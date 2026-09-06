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
        self.assertEqual(actual, baseline)
        self.assertTrue(full["trip"])
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
            ".github/workflows/ci.yml", "scripts/select-ios-tests.py", "unknown.json",
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
                subprocess.run(["python3", str(ROOT / "scripts/select-ios-tests.py"),
                                "--output-dir", str(root)], cwd=ROOT, env=env,
                               check=True, capture_output=True)
                self.assertEqual(json.loads((root / "ios-test-selection.json").read_text())["profile"], "full")


if __name__ == "__main__":
    unittest.main()
