import importlib.util
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
        self.assertEqual(set(home), partition.HOME)
        self.assertFalse(set(core) & set(home))
        self.assertCountEqual(core + home, lines)
        self.assertTrue(any("testMapSavedUnsavedVisitedTaipeiFixture" in x for x in core))

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
        ios = workflow.split("\n  ios:\n", 1)[1].split("\n  ios-supplemental:\n", 1)[0]
        self.assertIn("needs: [ios-build, ios-supplemental]", ios)
        self.assertIn("SUPPLEMENTAL_RESULT: ${{ needs.ios-supplemental.result }}", ios)
        self.assertIn('[[ "$SUPPLEMENTAL_RESULT" == success ]]', ios)
        self.assertIn("--threshold 0.90", ios)
        self.assertIn('ios-ui-core-args.txt', ios)
        supplemental = workflow.split("\n  ios-supplemental:\n", 1)[1].split("\n  release-readiness:\n", 1)[0]
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
