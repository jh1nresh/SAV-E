import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("selection", ROOT / "scripts/select-ios-tests.py")
selection = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(selection)


class CoverageTests(unittest.TestCase):
    def test_full_matches_frozen_baseline_without_plan_extras(self):
        full = selection.select([], full=True)
        actual = set(full["tests"] + [selection.TRIP_SHEET])
        baseline = set(json.loads((ROOT / "Tests/ci/full-ui-baseline.json").read_text()))
        self.assertEqual(actual, baseline | {selection.RAIL + "testHomeListProgressiveSearch"})
        self.assertIn(selection.RAIL + "testUnplacedLabelFullScreenAtDeviceWidth", full["tests"])
        self.assertIn(selection.RAIL + "testUnplacedLabelFullScreenAtDeviceWidth", selection.select([])["tests"])
        self.assertTrue(full["trip"])
        self.assertTrue(full["units"])
        plan_only = (
            selection.RAIL + "testPlanChatDraftAndConversationSurviveTabChange",
            selection.RAIL + "testPlanTabDraftsFromSavedMapStamps",
            selection.RAIL + "testPlanCandidateCanBeConfirmedSavedAndOpened",
        )
        plan = selection.select(["SAV-E/Views/Plan/SavePlanView.swift"])
        for test in plan_only:
            self.assertIn(test, plan["tests"])
            self.assertNotIn(test, full["tests"])

    def test_selected_tests_exist_in_real_xctest_sources(self):
        catalog = list(dict.fromkeys(
            selection.FULL + sum(selection.TESTS.values(), []) + [selection.TRIP_SHEET]
        ))
        for test in catalog:
            _, test_class, *method = test.split("/")
            source = (ROOT / f"Tests/SAVEUITests/{test_class}.swift").read_text()
            self.assertRegex(source, rf"class {test_class}\b")
            if method:
                self.assertRegex(source, rf"func {method[0]}\(")

    def test_known_map_change_keeps_parity_and_related_navigation(self):
        plan = selection.select(["SAV-E/Views/Map/SaveMapDrawerPanel.swift"])
        self.assertEqual(plan["profile"], "map")
        self.assertIn(selection.RAIL + "testCaptureAtlasProductionParity", plan["tests"])
        self.assertIn(selection.RAIL + "testCaptureFiveTabLanding", plan["tests"])
        self.assertIn(selection.RAIL + "testMapSearchDrawerResizesThroughThreeStages", plan["tests"])
        self.assertIn(selection.RAIL + "testTripMapMarkerDetailReturnsToScopedTabs", plan["tests"])
        self.assertFalse(plan["trip"])
        self.assertLess(len(plan["tests"]), len(selection.FULL))

    def test_every_ui_route_keeps_parity_and_five_tab_home(self):
        parity = selection.RAIL + "testCaptureAtlasProductionParity"
        five_tab = selection.RAIL + "testCaptureFiveTabLanding"
        for path in (*selection.SURFACES,):
            plan = selection.select([path])
            with self.subTest(path=path):
                self.assertTrue(plan["ui"])
                self.assertIn(parity, plan["tests"])
                self.assertIn(five_tab, plan["tests"])
        self.assertIn(five_tab, selection.select([], full=True)["tests"])

    def test_onboarding_keeps_entire_carousel_class_and_replay(self):
        plan = selection.select(["SAV-E/Views/Onboarding/OnboardingView.swift"])
        self.assertIn(selection.ONBOARDING, plan["tests"])
        self.assertIn(selection.RAIL + "testPassportTutorialReplaysWithoutAddingPlaces", plan["tests"])
        self.assertFalse(plan["trip"])

    def test_plan_keeps_confirmation_persistence_and_trip_sheets(self):
        plan = selection.select(["SAV-E/Views/Plan/SavePlanView.swift"])
        self.assertTrue(plan["trip"])
        self.assertIn(selection.RAIL + "testPlanCandidateCanBeConfirmedSavedAndOpened", plan["tests"])
        self.assertIn(selection.RAIL + "testAnalyzedMapLinkPersistsAsTripStopAfterRelaunch", plan["tests"])

    def test_multiple_surfaces_union_without_duplicates(self):
        plan = selection.select(list(selection.SURFACES))
        for tests in selection.TESTS.values():
            self.assertTrue(set(tests) <= set(plan["tests"]))
        self.assertEqual(len(plan["tests"]), len(set(plan["tests"])))

    def test_shared_unknown_ci_and_test_harness_force_full(self):
        for path in (
            "SAV-E/App/ContentView.swift", "SAV-E/Extensions/Color+Theme.swift",
            "SAV-E/Services/SaveAIService.swift", "SAV-E/Views/Shared/New.swift",
            "SAV-E/Views/Map/New.swift", "SAV-E.xcodeproj/project.pbxproj",
            "Tests/SAVEUITests/SAVEScreenshotRailTests.swift", "project.yml",
            ".github/workflows/ci.yml", ".github/workflows/ios.yml",
            "scripts/select-ios-tests.py", "unknown.json",
        ):
            with self.subTest(path=path):
                self.assertEqual(selection.select([path])["profile"], "full")
                self.assertEqual(selection.select([*selection.SURFACES, path])["profile"], "full")
        self.assertEqual(selection.select([])["profile"], "full")

    def test_docs_and_backend_keep_existing_non_ios_route(self):
        plan = selection.select(["README.md", "docs/a.txt", "backend/server.js"])
        self.assertFalse(plan["run"])
        self.assertFalse(plan["ui"])

    def test_unit_only_keeps_build_and_unit_without_ui(self):
        plan = selection.select(["Tests/SocialPlacePipelineTests/TripTests.swift", "docs/a.md"])
        self.assertTrue(plan["run"])
        self.assertFalse(plan["ui"])
        self.assertFalse(plan["trip"])

    def test_cli_diff_and_rename_cannot_hide_shared_path(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, text=True).strip()
            git("init", "-q")
            git("config", "user.name", "CI fixture")
            git("config", "user.email", "ci@example.invalid")
            source = root / "SAV-E/Views/Shared/Old.swift"
            source.parent.mkdir(parents=True)
            source.write_text("shared fixture\n")
            git("add", ".")
            git("commit", "-qm", "base")
            base = git("rev-parse", "HEAD")
            target = root / "SAV-E/Views/Map/SaveMapDrawerPanel.swift"
            target.parent.mkdir(parents=True)
            source.rename(target)
            git("add", "-A")
            git("commit", "-qm", "move")
            env = dict(os.environ, GITHUB_EVENT_NAME="pull_request", PR_BASE_SHA=base,
                       GITHUB_OUTPUT=str(root / "outputs"), GITHUB_STEP_SUMMARY=str(root / "summary"))
            env.pop("SAVE_UI_TEST_FOCUS", None)
            subprocess.run(["python3", str(ROOT / "scripts/select-ios-tests.py"),
                            "--output-dir", str(root)], cwd=root, env=env,
                           check=True, capture_output=True)
            plan = json.loads((root / "ios-test-selection.json").read_text())
            self.assertEqual(plan["profile"], "full")
            self.assertIn("SAV-E/Views/Shared/Old.swift", plan["changed_paths"])
            self.assertIn("run=true", (root / "outputs").read_text())

    def test_non_pr_and_bad_base_run_full(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for event in ("push", "workflow_dispatch", "pull_request"):
                env = dict(os.environ, GITHUB_EVENT_NAME=event, PR_BASE_SHA="bad",
                           GITHUB_OUTPUT=str(root / "outputs"), GITHUB_STEP_SUMMARY=str(root / "summary"))
                env.pop("SAVE_UI_TEST_FOCUS", None)
                subprocess.run(["python3", str(ROOT / "scripts/select-ios-tests.py"),
                                "--output-dir", str(root)], cwd=ROOT, env=env,
                               check=True, capture_output=True)
                self.assertEqual(json.loads((root / "ios-test-selection.json").read_text())["profile"], "full")

    def test_tile_town_home_focus_is_a_subset_of_full_without_trip_or_units(self):
        spec = selection.FOCUS_PROFILES["tile-town-home"]
        self.assertTrue(set(spec["tests"]) <= set(selection.FULL))
        self.assertFalse(spec["trip"])
        self.assertFalse(spec["units"])
        for name in (
            "testCaptureAtlasProductionParity",
            "testCaptureFiveTabLanding",
            "testAtlasHomeAndSavesRenderPersistedPlaceData",
            "testCaptureMultipleResultsExcludeOlderClues",
            "testCaptureAtlasTripsAndLiveMaps",
            "testFriendsComingSoon",
            "testHomeListProgressiveSearch",
        ):
            self.assertIn(selection.RAIL + name, spec["tests"])
        self.assertNotIn(selection.TRIP_SHEET, spec["tests"])
        self.assertNotIn(selection.RAIL + "testAnalyzedMapLinkPersistsAsTripStopAfterRelaunch", spec["tests"])

    def test_cli_honors_save_ui_test_focus_off_main(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            env = dict(os.environ, GITHUB_EVENT_NAME="pull_request", PR_BASE_SHA="bad",
                       GITHUB_REF="refs/pull/279/merge",
                       SAVE_UI_TEST_FOCUS="tile-town-home",
                       GITHUB_OUTPUT=str(root / "outputs"), GITHUB_STEP_SUMMARY=str(root / "summary"))
            subprocess.run(["python3", str(ROOT / "scripts/select-ios-tests.py"),
                            "--output-dir", str(root)], cwd=ROOT, env=env,
                           check=True, capture_output=True)
            plan = json.loads((root / "ios-test-selection.json").read_text())
            self.assertEqual(plan["profile"], "focus:tile-town-home")
            self.assertEqual(plan["tests"], selection.FOCUS_PROFILES["tile-town-home"]["tests"])
            self.assertTrue(plan["run"])
            self.assertTrue(plan["ui"])
            self.assertFalse(plan["trip"])
            self.assertFalse(plan["units"])
            self.assertIn("units=false", (root / "outputs").read_text())
            args = (root / "ios-ui-args.txt").read_text()
            self.assertIn("-only-testing:SAVEUITests/SAVEScreenshotRailTests/testHomeListProgressiveSearch", args)
            self.assertNotIn("testTripStopEditorSurfaceIsReachable", args)

    def test_cli_ignores_focus_on_main_push(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            env = dict(os.environ, GITHUB_EVENT_NAME="push",
                       GITHUB_REF="refs/heads/main",
                       SAVE_UI_TEST_FOCUS="tile-town-home",
                       GITHUB_OUTPUT=str(root / "outputs"), GITHUB_STEP_SUMMARY=str(root / "summary"))
            subprocess.run(["python3", str(ROOT / "scripts/select-ios-tests.py"),
                            "--output-dir", str(root)], cwd=ROOT, env=env,
                           check=True, capture_output=True)
            plan = json.loads((root / "ios-test-selection.json").read_text())
            self.assertEqual(plan["profile"], "full")
            self.assertTrue(plan["units"])
            self.assertTrue(plan["trip"])
            self.assertEqual(plan["tests"], selection.FULL)

    def test_workflow_focus_omits_single_test_iteration_flag(self):
        ios_workflow = (ROOT / ".github/workflows/ios.yml").read_text()
        ci_workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertRegex(ios_workflow, r"(?m)^  ios:\s*$")
        self.assertNotRegex(ci_workflow, r"(?m)^  ios:\s*$")
        self.assertRegex(ci_workflow, r"(?m)^  ios-fast:\s*$")
        self.assertIn("run-visual-parity.sh", ios_workflow)
        self.assertIn("--threshold 0.90", ios_workflow)
        self.assertIn("xcrun simctl io booted screenshot", ios_workflow)
        self.assertNotIn("run-visual-parity.sh", ci_workflow)
        self.assertIn("SAVE_UI_TEST_FOCUS", ios_workflow)
        self.assertIn("Must specify -test-iterations with more than 1 iteration", ios_workflow)
        self.assertIn("iteration_args=(-test-iterations 3 -retry-tests-on-failure)", ios_workflow)
        self.assertIn("iteration_args=()", ios_workflow)
        self.assertNotRegex(ios_workflow, r"(?m)^\s+-test-iterations 1\s")
        self.assertIn("test-without-building", ios_workflow)
        self.assertIn("save-ios-test-products-", ios_workflow)
        self.assertIn("save-ios-test-products.tar", ios_workflow)
        self.assertIn("ios-products-${{ github.run_id }}", ios_workflow)
        self.assertIn("scripts/run-ios-xcodebuild-retry.sh", ios_workflow)
        retry_script = (ROOT / "scripts/run-ios-xcodebuild-retry.sh").read_text()
        self.assertIn("retry-selectors", retry_script)
        self.assertIn("ios_ui_retry.py\" coverage", retry_script)
        self.assertIn("original_selectors", retry_script)
        self.assertIn("save-parity-venv", ios_workflow)
        self.assertIn("python3 -m venv", ios_workflow)
        self.assertIn("pip install Pillow", ios_workflow)
        self.assertNotIn("pip install --user Pillow", ios_workflow)
        self.assertNotIn("--break-system-packages", ios_workflow)
        self.assertIn("actions: write", ios_workflow)
        self.assertIn("github.head_ref || github.ref_name", ios_workflow)
        self.assertIn("github.ref != 'refs/heads/main'", ios_workflow)
        self.assertNotIn(
            "cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            ios_workflow,
        )
        self.assertNotIn("Build without booting a simulator", ios_workflow)
        self.assertRegex(ios_workflow, r"(?m)^    timeout-minutes: 100\s*$")
        self.assertIn("timeout-minutes: 60", ios_workflow)

    def test_unknown_focus_fails_loudly(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            env = dict(os.environ, GITHUB_EVENT_NAME="pull_request", PR_BASE_SHA="bad",
                       GITHUB_REF="refs/pull/279/merge",
                       SAVE_UI_TEST_FOCUS="does-not-exist",
                       GITHUB_OUTPUT=str(root / "outputs"), GITHUB_STEP_SUMMARY=str(root / "summary"))
            completed = subprocess.run(["python3", str(ROOT / "scripts/select-ios-tests.py"),
                                        "--output-dir", str(root)], cwd=ROOT, env=env,
                                       capture_output=True, text=True)
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("unknown SAVE_UI_TEST_FOCUS", completed.stderr + completed.stdout)


if __name__ == "__main__":
    unittest.main()
