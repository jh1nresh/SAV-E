import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "require_save_release_ci", ROOT / "scripts/require-save-release-ci.py"
)
require_ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(require_ci)


def job(name: str, status: str = "completed", conclusion: str | None = "success") -> dict:
    return {"name": name, "status": status, "conclusion": conclusion}


class ReleaseReadinessTests(unittest.TestCase):
    def test_reusable_and_direct_job_names_count(self):
        results = require_ci.evaluate_jobs(
            [
                job("backend / validate"),
                job("save-contracts"),
                job("evidence-rubric / validate"),
                job("ios-build"),
            ]
        )
        self.assertTrue(require_ci.all_succeeded(results))
        self.assertEqual(require_ci.blocking_failures(results), [])

    def test_failed_required_job_blocks_receipt(self):
        results = require_ci.evaluate_jobs(
            [
                job("backend / validate"),
                job("save-contracts", conclusion="failure"),
                job("evidence-rubric / validate"),
            ]
        )
        self.assertFalse(require_ci.all_succeeded(results))
        self.assertEqual(require_ci.blocking_failures(results), ["save-contracts"])

    def test_pending_or_missing_jobs_are_not_success(self):
        pending = require_ci.evaluate_jobs(
            [
                job("backend / validate"),
                job("save-contracts", status="in_progress", conclusion=None),
                job("evidence-rubric / validate"),
            ]
        )
        self.assertEqual(pending["save-contracts"], require_ci.PENDING)
        self.assertFalse(require_ci.all_succeeded(pending))
        self.assertEqual(require_ci.blocking_failures(pending), [])

        missing = require_ci.evaluate_jobs([job("backend / validate")])
        self.assertEqual(missing["save-contracts"], require_ci.MISSING)
        self.assertEqual(missing["evidence-rubric"], require_ci.MISSING)
        self.assertFalse(require_ci.all_succeeded(missing))

    def test_failed_or_skipped_sibling_blocks_a_successful_job(self):
        failed = require_ci.evaluate_jobs(
            [
                job("backend / setup", conclusion="failure"),
                job("backend / validate"),
                job("save-contracts"),
                job("evidence-rubric / validate"),
            ]
        )
        self.assertEqual(failed["backend"], require_ci.FAILED)
        self.assertFalse(require_ci.all_succeeded(failed))

        skipped = require_ci.evaluate_jobs(
            [
                job("backend / validate"),
                job("save-contracts", conclusion="skipped"),
                job("evidence-rubric / validate"),
            ]
        )
        self.assertEqual(skipped["save-contracts"], require_ci.FAILED)
        self.assertFalse(require_ci.all_succeeded(skipped))

    def test_ios_workflow_verifies_ci_jobs_before_writing_receipt(self):
        workflow = (ROOT / ".github/workflows/ios.yml").read_text()
        readiness = workflow.split("release-readiness:")[1]
        require_at = readiness.find("require-save-release-ci.py")
        write_at = readiness.find("write-save-release-readiness.py")
        self.assertGreater(require_at, 0)
        self.assertGreater(write_at, require_at)
        self.assertIn("actions: read", readiness)
        verifier = (ROOT / "scripts/require-save-release-ci.py").read_text()
        self.assertIn('"backend"', verifier)
        self.assertIn('"save-contracts"', verifier)
        self.assertIn('"evidence-rubric"', verifier)

    def test_receipt_writer_still_records_the_three_ci_gates(self):
        writer = (ROOT / "scripts/write-save-release-readiness.py").read_text()
        self.assertIn('"backendCI": "passed"', writer)
        self.assertIn('"saveRnContractCI": "passed"', writer)
        self.assertIn('"evidenceRubricCI": "passed"', writer)


if __name__ == "__main__":
    unittest.main()
