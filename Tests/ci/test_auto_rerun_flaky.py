import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "should_rerun_npm_audit_timeout",
    ROOT / "scripts/ci/should_rerun_npm_audit_timeout.py",
)
rerun = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rerun)


# Shortened from https://github.com/jh1nresh/SAV-E/actions/runs/39714110358
# job 119612025701. Tests passed; npm audit then hit 5 local 45s timeouts.
TIMEOUT_LOG = """
> save-backend@0.1.0 test
ok 640 - documented founder SQL fallbacks pin search_path to public
1..640
# tests 640
# pass 640
# fail 0
> save-backend@0.1.0 audit:production
> node scripts/audit-production.mjs
transient npm audit failure (timeout 45000ms, attempt 1/5); retrying in 2000ms
transient npm audit failure (timeout 45000ms, attempt 2/5); retrying in 4000ms
npm audit timed out after 45000ms (attempt 5/5)
"""

NEW_MARKER_LOG = """
> save-backend@0.1.0 audit:production
> node scripts/audit-production.mjs
transient npm audit failure (ETIMEDOUT, attempt 1/3); retrying in 2000ms
npm audit timed out talking to the registry (timeout 90000ms, attempt 3/3)
"""

TEST_FAIL_LOG = """
not ok 12 - entitlements reject a stale token
# fail 1
> save-backend@0.1.0 audit:production
"""

FINDINGS_LOG = """
> save-backend@0.1.0 audit:production
> node scripts/audit-production.mjs
found 2 high severity vulnerabilities
npm audit found production vulnerabilities (attempt 1/3)
"""


def jobs(*names, extra=None):
    payload = {
        "jobs": [
            {"name": "ios-build", "conclusion": "success"},
            {"name": "ios-fast", "conclusion": "success"},
            {"name": "save-contracts", "conclusion": "success"},
            {"name": "evidence-rubric / validate", "conclusion": "success"},
            {"name": "backend / validate", "conclusion": "success"},
        ]
    }
    failed = set(names)
    for job in payload["jobs"]:
        if job["name"] in failed:
            job["conclusion"] = "failure"
    if extra:
        payload["jobs"].extend(extra)
    return payload


class AutoRerunFlakyTests(unittest.TestCase):
    def test_example_run_39714110358_is_a_timeout_rerun(self):
        ok, reason = rerun.should_rerun(jobs("backend / validate"), TIMEOUT_LOG, 1)
        self.assertTrue(ok)
        self.assertIn("npm audit network timeout", reason)

    def test_new_marker_is_a_timeout_rerun(self):
        ok, reason = rerun.should_rerun(jobs("backend / validate"), NEW_MARKER_LOG, 2)
        self.assertTrue(ok)
        self.assertIn("npm audit network timeout", reason)

    def test_attempt_3_does_not_rerun(self):
        ok, reason = rerun.should_rerun(jobs("backend / validate"), TIMEOUT_LOG, 3)
        self.assertFalse(ok)
        self.assertIn("run_attempt", reason)

    def test_ios_failure_never_reruns(self):
        ok, reason = rerun.should_rerun(
            jobs("backend / validate", "ios-fast"), TIMEOUT_LOG, 1
        )
        self.assertFalse(ok)
        self.assertIn("ios", reason)

    def test_other_failed_jobs_never_rerun(self):
        ok, reason = rerun.should_rerun(
            jobs("backend / validate", "save-contracts"), TIMEOUT_LOG, 1
        )
        self.assertFalse(ok)
        self.assertIn("failed jobs", reason)

    def test_test_failures_never_rerun(self):
        ok, reason = rerun.should_rerun(jobs("backend / validate"), TEST_FAIL_LOG, 1)
        self.assertFalse(ok)
        self.assertIn("test failure", reason)

    def test_vulnerability_findings_never_rerun(self):
        ok, reason = rerun.should_rerun(jobs("backend / validate"), FINDINGS_LOG, 1)
        self.assertFalse(ok)
        self.assertIn("vulnerability", reason)

    def test_timeout_plus_findings_never_reruns(self):
        log = FINDINGS_LOG + "\nnpm audit timed out talking to the registry\n"
        ok, reason = rerun.should_rerun(jobs("backend / validate"), log, 1)
        self.assertFalse(ok)
        self.assertIn("vulnerability", reason)

    def test_backend_job_id_only_when_sole_failure(self):
        payload = jobs("backend / validate")
        payload["jobs"][4]["id"] = 119612025701
        self.assertEqual(rerun.backend_validate_job_id(payload), 119612025701)
        self.assertIsNone(rerun.backend_validate_job_id(jobs("backend / validate", "ios-build")))
        self.assertIsNone(rerun.backend_validate_job_id(jobs()))

    def test_cli_exit_codes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            jobs_path = root / "jobs.json"
            log_path = root / "backend.log"
            jobs_path.write_text(json.dumps(jobs("backend / validate")))
            log_path.write_text(TIMEOUT_LOG)
            self.assertEqual(
                rerun.main(
                    [
                        "--jobs-json",
                        str(jobs_path),
                        "--backend-log",
                        str(log_path),
                        "--run-attempt",
                        "1",
                    ]
                ),
                0,
            )
            log_path.write_text(FINDINGS_LOG)
            self.assertEqual(
                rerun.main(
                    [
                        "--jobs-json",
                        str(jobs_path),
                        "--backend-log",
                        str(log_path),
                        "--run-attempt",
                        "1",
                    ]
                ),
                2,
            )
            payload = jobs("backend / validate")
            payload["jobs"][4]["id"] = 119612025701
            jobs_path.write_text(json.dumps(payload))
            self.assertEqual(
                rerun.main(["--jobs-json", str(jobs_path), "--print-backend-job-id"]),
                0,
            )


if __name__ == "__main__":
    unittest.main()
