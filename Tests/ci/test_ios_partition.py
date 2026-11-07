import importlib.util
import os
import re
import subprocess
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


partition = load("partition", "partition-ios-ui-tests.py")
selection = load("selection", "select-ios-tests.py")


class PartitionTests(unittest.TestCase):
    def test_full_selection_preserved_exactly_once(self):
        lines = ["-only-testing:" + test for test in selection.select([], full=True)["tests"]]
        core, home = partition.partition(lines)
        self.assertEqual(home, [])
        self.assertEqual(core, lines)
        self.assertTrue(any("testFreeCapE4Screenshots" in x for x in core))

    def test_empty_and_focused_selection_do_not_add_tests(self):
        self.assertEqual(partition.partition([]), ([], []))
        lines = ["-only-testing:SAVEUITests/SAVEOnboardingCarouselTests"]
        self.assertEqual(partition.partition(lines), (lines, []))

    def test_duplicate_or_unexpected_arguments_fail_closed(self):
        with self.assertRaises(ValueError):
            partition.partition(["-only-testing:A", "-only-testing:A"])
        with self.assertRaises(ValueError):
            partition.partition(["-skip-testing:A"])

    def test_supplemental_work_cannot_be_non_gating(self):
        workflow = (ROOT / ".github/workflows/ios.yml").read_text()
        core = workflow.split("\n  ios-tests:\n", 1)[1].split("\n  ios-supplemental:\n", 1)[0]
        self.assertIn("needs: [ios-build]", core)
        self.assertNotIn("needs.ios-supplemental", core)
        self.assertIn("--threshold 0.90", core)
        self.assertIn('ios-ui-core-args.txt', core)
        ios = workflow.split("\n  ios:\n", 1)[1].split("\n  release-readiness:\n", 1)[0]
        self.assertIn("needs: [ios-build, ios-tests, ios-supplemental]", ios)
        self.assertIn("if: ${{ !cancelled() }}", ios)
        self.assertIn("SUPPLEMENTAL_RESULT: ${{ needs.ios-supplemental.result }}", ios)
        supplemental = workflow.split("\n  ios-supplemental:\n", 1)[1].split("\n  ios:\n", 1)[0]
        self.assertIn("fail-fast: false", supplemental)
        for width in (375, 390, 430):
            self.assertIn(f"lane: width-{width}", supplemental)
            for surface in ("Map", "Friends", "Passport"):
                self.assertIn(f"test{surface}Width{width}", supplemental)
                self.assertIn(f"Capture {surface} width evidence", supplemental)
        self.assertIn("lane: home-evidence", supplemental)
        self.assertIn("for surface in map friends passport", supplemental)
        self.assertIn('ios-ui-home-args.txt', supplemental)
        self.assertNotIn('continue-on-error', supplemental)
        self.assertIn('needs: [ios]', workflow.split("\n  release-readiness:\n", 1)[1])


    def test_required_gate_rejects_any_incomplete_lane(self):
        workflow = (ROOT / ".github/workflows/ios.yml").read_text()
        gate = workflow.split("\n  ios:\n", 1)[1].split("\n  release-readiness:\n", 1)[0]
        script = gate.split("        run: |\n", 1)[1]
        script = "\n".join(line[10:] for line in script.splitlines() if line.startswith("          "))
        results = re.findall(r"^          (\w+): ", gate, re.MULTILINE)
        self.assertEqual(set(results), {"BUILD_RESULT", "TEST_RESULT", "SUPPLEMENTAL_RESULT"})
        passed = dict(os.environ, **{name: "success" for name in results})
        self.assertEqual(subprocess.run(["bash", "-e", "-c", script], env=passed,
                                        capture_output=True).returncode, 0)
        for name in results:
            for status in ("failure", "cancelled", "skipped", "abandoned", ""):
                with self.subTest(lane=name, status=status):
                    env = dict(passed, **{name: status})
                    result = subprocess.run(["bash", "-e", "-c", script], env=env,
                                            capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("::error::Required iOS lane did not succeed", result.stdout)
