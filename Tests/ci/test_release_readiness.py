import importlib.util
from pathlib import Path
from urllib.parse import parse_qs, urlparse
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


SHA = "32ef5f957067eee05daa7daae6587ac84876f91a"
REPO = "jh1nresh/SAV-E"


def ci_run(
    run_id: int,
    *,
    sha: str = SHA,
    path: str = ".github/workflows/ci.yml",
    status: str = "completed",
    conclusion: str | None = "success",
    created_at: str = "2026-10-23T23:48:12Z",
) -> dict:
    return {
        "id": run_id,
        "head_sha": sha,
        "path": path,
        "status": status,
        "conclusion": conclusion,
        "created_at": created_at,
    }


class LatestCIRunTests(unittest.TestCase):
    def setUp(self):
        self._api_get = require_ci.api_get
        self.urls: list[str] = []

    def tearDown(self):
        require_ci.api_get = self._api_get

    def fake_api(self, handler):
        def wrapper(url: str, token: str):
            self.assertEqual(token, "test-token")
            self.urls.append(url)
            return handler(url)

        require_ci.api_get = wrapper

    def assert_queries_ci_workflow(self, url: str, *, sha: str = SHA):
        parsed = urlparse(url)
        self.assertTrue(
            parsed.path.endswith(f"/repos/{REPO}/actions/workflows/ci.yml/runs"),
            url,
        )
        self.assertNotIn("/actions/runs?", url)
        query = parse_qs(parsed.query)
        self.assertEqual(query.get("head_sha"), [sha])

    def test_returns_ci_run_when_other_workflows_flood_generic_list(self):
        target = ci_run(40041681337)
        # More than 20 Auto-rerun flaky rows for the same SHA — the live
        # failure mode of the generic /actions/runs?per_page=20 list.
        other_workflow_runs = [
            ci_run(
                40057000000 + index,
                path=".github/workflows/auto-rerun-flaky.yml",
                created_at=f"2026-10-24T03:{index:02d}:00Z",
            )
            for index in range(25)
        ]

        def handler(url: str):
            self.assert_queries_ci_workflow(url)
            if "/actions/workflows/ci.yml/runs" in url:
                return {"workflow_runs": [target]}
            return {"workflow_runs": other_workflow_runs}

        self.fake_api(handler)
        found = require_ci.latest_ci_run(REPO, SHA, "test-token")
        self.assertIsNotNone(found)
        self.assertEqual(found["id"], target["id"])
        self.assertEqual(found["path"], require_ci.CI_WORKFLOW_PATH)
        self.assertTrue(self.urls)
        self.assert_queries_ci_workflow(self.urls[0])

    def test_no_run_is_clear_not_found(self):
        self.fake_api(lambda url: {"workflow_runs": []})
        found = require_ci.latest_ci_run(REPO, SHA, "test-token")
        self.assertIsNone(found)
        self.assertEqual(require_ci.describe_ci_run(found), require_ci.CI_NOT_FOUND)
        self.assertEqual(require_ci.describe_ci_run(found), "CI not found")
        self.assert_queries_ci_workflow(self.urls[0])

    def test_multiple_runs_for_sha_use_the_latest(self):
        older = ci_run(10, created_at="2026-10-20T09:00:00Z")
        newest = ci_run(5, created_at="2026-10-24T01:00:00Z")
        same_time_older = ci_run(20, created_at="2026-10-24T01:00:00Z")
        pages = {
            1: [older, newest],
            2: [same_time_older],
        }

        def handler(url: str):
            self.assert_queries_ci_workflow(url)
            query = parse_qs(urlparse(url).query)
            page = int(query.get("page", ["1"])[0])
            return {"workflow_runs": pages.get(page, [])}

        self.fake_api(handler)
        found = require_ci.latest_ci_run(REPO, SHA, "test-token", per_page=2)
        self.assertEqual(found["id"], same_time_older["id"])
        self.assertGreaterEqual(len(self.urls), 2)

    def test_in_progress_run_is_returned(self):
        pending = ci_run(88, status="in_progress", conclusion=None)
        self.fake_api(lambda url: {"workflow_runs": [pending]})
        found = require_ci.latest_ci_run(REPO, SHA, "test-token")
        self.assertEqual(found["id"], 88)
        self.assertEqual(found["status"], "in_progress")
        self.assertIsNone(found["conclusion"])
        self.assertIn("status=in_progress", require_ci.describe_ci_run(found))
        self.assertIn("conclusion=none", require_ci.describe_ci_run(found))

    def test_failed_run_is_returned(self):
        failed = ci_run(77, conclusion="failure")
        self.fake_api(lambda url: {"workflow_runs": [failed]})
        found = require_ci.latest_ci_run(REPO, SHA, "test-token")
        self.assertEqual(found["id"], 77)
        self.assertEqual(found["conclusion"], "failure")
        self.assertIn("conclusion=failure", require_ci.describe_ci_run(found))

    def test_paginates_past_a_full_first_page_to_reach_latest(self):
        first_page = [
            ci_run(1000 + index, created_at=f"2026-10-20T00:00:{index:02d}Z")
            for index in range(2)
        ]
        latest = ci_run(2000, created_at="2026-10-24T00:00:00Z")

        def handler(url: str):
            self.assert_queries_ci_workflow(url)
            query = parse_qs(urlparse(url).query)
            page = int(query.get("page", ["1"])[0])
            if page == 1:
                return {"workflow_runs": first_page}
            if page == 2:
                return {"workflow_runs": [latest]}
            return {"workflow_runs": []}

        self.fake_api(handler)
        found = require_ci.latest_ci_run(REPO, SHA, "test-token", per_page=2)
        self.assertEqual(found["id"], 2000)
        self.assertEqual(len(self.urls), 2)

    def test_ignores_other_sha_or_workflow_rows_on_the_ci_endpoint(self):
        other_sha = ci_run(1, sha="a" * 40)
        other_workflow = ci_run(
            2, path=".github/workflows/auto-rerun-flaky.yml"
        )
        target = ci_run(3)
        self.fake_api(
            lambda url: {"workflow_runs": [other_sha, other_workflow, target]}
        )
        found = require_ci.latest_ci_run(REPO, SHA, "test-token")
        self.assertEqual(found["id"], 3)


if __name__ == "__main__":
    unittest.main()
