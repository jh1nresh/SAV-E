import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ios_ui_retry", ROOT / "scripts/ios_ui_retry.py")
retry = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(retry)


LOG = """
Test Case '-[SAVEUITests.SAVEScreenshotRailTests testCaptureFiveTabLanding]' started.
Test Case '-[SAVEUITests.SAVEScreenshotRailTests testCaptureFiveTabLanding]' passed (8.2 seconds).
Test Case '-[SAVEScreenshotRailTests testHomeListProgressiveSearch]' started.
Test Case '-[SAVEScreenshotRailTests testHomeListProgressiveSearch]' failed (12.0 seconds).
Test Case '-[SAVEScreenshotRailTests testHomeListProgressiveSearch]' started.
Test Case '-[SAVEScreenshotRailTests testHomeListProgressiveSearch]' failed (11.4 seconds).
"""


class RetryHelperTests(unittest.TestCase):
    def test_failed_ids_use_last_result_and_only_testing_shape(self):
        self.assertEqual(
            retry.failed_ids(LOG),
            ["SAVEUITests/SAVEScreenshotRailTests/testHomeListProgressiveSearch"],
        )
        self.assertEqual(
            retry.parse_results(LOG)[
                "SAVEUITests/SAVEScreenshotRailTests/testCaptureFiveTabLanding"
            ],
            "passed",
        )

    def test_same_failure_twice_is_deterministic(self):
        first = ["SAVEUITests/SAVEScreenshotRailTests/testHomeListProgressiveSearch"]
        second = first + ["SAVEUITests/SAVEOnboardingCarouselTests/testExample"]
        self.assertEqual(retry.deterministic_failures(first, second), first)
        self.assertEqual(retry.deterministic_failures(first, ["other"]), [])

    def test_cli_fail_fast_and_failed_tests(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            log = root / "attempt.log"
            log.write_text(LOG)
            previous = root / "prev.txt"
            current = root / "curr.txt"
            self.assertEqual(retry.main(["failed-tests", str(log)]), 0)
            current.write_text(
                retry.only_testing_lines(retry.failed_ids(LOG))
            )
            previous.write_text(current.read_text())
            self.assertEqual(retry.main(["fail-fast", str(previous), str(current)]), 2)
            previous.write_text("-only-testing:SAVEUITests/Other/testFlake\n")
            self.assertEqual(retry.main(["fail-fast", str(previous), str(current)]), 0)


if __name__ == "__main__":
    unittest.main()
