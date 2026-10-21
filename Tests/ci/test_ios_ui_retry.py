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

    def test_abort_after_one_failure_keeps_unrun_selected_tests(self):
        selected = [
            "SAVEUITests/SAVEScreenshotRailTests/testCaptureFiveTabLanding",
            "SAVEUITests/SAVEScreenshotRailTests/testHomeListProgressiveSearch",
            "SAVEUITests/SAVEScreenshotRailTests/testFriendsComingSoon",
        ]
        abort_log = (
            "Test Case '-[SAVEUITests.SAVEScreenshotRailTests "
            "testCaptureFiveTabLanding]' failed (1.0 seconds).\n"
        )
        self.assertEqual(retry.failed_ids(abort_log), [selected[0]])
        self.assertEqual(retry.never_executed(selected, abort_log), selected[1:])
        self.assertEqual(retry.unsatisfied(selected, abort_log), selected)
        self.assertEqual(retry.retry_selectors(selected, abort_log), selected)

    def test_coverage_requires_every_selected_test_to_run_and_pass(self):
        selected = [
            "SAVEUITests/SAVEScreenshotRailTests/testCaptureFiveTabLanding",
            "SAVEUITests/SAVEScreenshotRailTests/testFriendsComingSoon",
        ]
        passed_one = (
            "Test Case '-[SAVEUITests.SAVEScreenshotRailTests "
            "testCaptureFiveTabLanding]' passed (8.2 seconds).\n"
        )
        self.assertEqual(retry.never_executed(selected, passed_one), [selected[1]])
        self.assertEqual(retry.unsatisfied(selected, passed_one), [selected[1]])
        self.assertEqual(retry.retry_selectors(selected, passed_one), [selected[1]])
        both = passed_one + (
            "Test Case '-[SAVEUITests.SAVEScreenshotRailTests "
            "testFriendsComingSoon]' passed (4.0 seconds).\n"
        )
        self.assertEqual(retry.never_executed(selected, both), [])
        self.assertEqual(retry.unsatisfied(selected, both), [])
        self.assertEqual(retry.retry_selectors(selected, both), [])

    def test_class_selector_is_unfinished_until_the_suite_reports(self):
        selected = ["SAVEUITests/SAVEOnboardingCarouselTests"]
        mid_class = (
            "Test Suite 'SAVEOnboardingCarouselTests' started.\n"
            "Test Case '-[SAVEUITests.SAVEOnboardingCarouselTests "
            "testCarouselAdvances]' failed (2.0 seconds).\n"
        )
        self.assertEqual(retry.never_executed(selected, mid_class), selected)
        self.assertEqual(retry.retry_selectors(selected, mid_class), selected)
        finished = mid_class + "Test Suite 'SAVEOnboardingCarouselTests' failed.\n"
        self.assertEqual(retry.never_executed(selected, finished), [])
        self.assertEqual(
            retry.retry_selectors(selected, finished),
            ["SAVEUITests/SAVEOnboardingCarouselTests/testCarouselAdvances"],
        )

    def test_cli_coverage_fails_when_a_selected_test_never_ran(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            selected = root / "selected.txt"
            selected.write_text(
                retry.only_testing_lines(
                    [
                        "SAVEUITests/SAVEScreenshotRailTests/testCaptureFiveTabLanding",
                        "SAVEUITests/SAVEScreenshotRailTests/testFriendsComingSoon",
                    ]
                )
            )
            log = root / "combined.log"
            log.write_text(
                "Test Case '-[SAVEUITests.SAVEScreenshotRailTests "
                "testCaptureFiveTabLanding]' passed (8.2 seconds).\n"
            )
            self.assertEqual(retry.main(["coverage", str(selected), str(log)]), 2)
            self.assertEqual(
                retry.main(["retry-selectors", str(selected), str(log)]), 0
            )
            log.write_text(
                log.read_text()
                + "Test Case '-[SAVEUITests.SAVEScreenshotRailTests "
                "testFriendsComingSoon]' passed (4.0 seconds).\n"
            )
            self.assertEqual(retry.main(["coverage", str(selected), str(log)]), 0)

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
