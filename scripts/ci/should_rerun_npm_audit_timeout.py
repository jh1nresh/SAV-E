#!/usr/bin/env python3
"""Decide whether a completed CI run may call rerun-failed-jobs.

Only the required `backend / validate` job, and only when that job failed
because npm audit could not reach the registry. Test failures, vulnerability
findings, and any iOS job failure must never rerun.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

BACKEND_JOB = "backend / validate"
MAX_RUN_ATTEMPT = 3
TIMEOUT_MARKERS = (
    "npm audit timed out talking to the registry",
    "npm audit timed out after",
    "transient npm audit failure (timeout",
)
FINDING_RE = re.compile(r"found \d+ (?:high|critical) severity", re.I)
TEST_FAIL_COUNT_RE = re.compile(r"^# fail (\d+)\s*$", re.M)
TEST_NOT_OK_RE = re.compile(r"^not ok \d+", re.M)


def load_jobs(payload):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        return payload.get("jobs") or []
    raise TypeError("jobs payload must be an object or list")


def failed_jobs(payload):
    return [job for job in load_jobs(payload) if job.get("conclusion") == "failure"]


def audit_section(log: str) -> str:
    for marker in ("audit:production", "scripts/audit-production.mjs"):
        index = log.find(marker)
        if index >= 0:
            return log[index:]
    return ""


def has_timeout(log: str) -> bool:
    section = audit_section(log) or log
    return any(marker in section for marker in TIMEOUT_MARKERS)


def has_vulnerability_findings(log: str) -> bool:
    return bool(FINDING_RE.search(audit_section(log)))


def has_test_failure(log: str) -> bool:
    if TEST_NOT_OK_RE.search(log):
        return True
    match = TEST_FAIL_COUNT_RE.search(log)
    return bool(match and int(match.group(1)) > 0)


def backend_validate_job_id(jobs_payload):
    failed = failed_jobs(jobs_payload)
    if any(str(job.get("name") or "").startswith("ios") for job in failed):
        return None
    match = [job for job in failed if job.get("name") == BACKEND_JOB]
    if len(failed) != 1 or len(match) != 1:
        return None
    return match[0].get("id")


def should_rerun(jobs_payload, backend_log: str, run_attempt: int):
    if run_attempt >= MAX_RUN_ATTEMPT:
        return False, f"run_attempt {run_attempt} is not < {MAX_RUN_ATTEMPT}"

    failed = failed_jobs(jobs_payload)
    if any(str(job.get("name") or "").startswith("ios") for job in failed):
        return False, "ios job failed; never rerun ios"

    names = [job.get("name") for job in failed]
    if names != [BACKEND_JOB]:
        return False, f"failed jobs {names} are not only {BACKEND_JOB}"

    if has_test_failure(backend_log):
        return False, "test failure; never rerun"

    if has_vulnerability_findings(backend_log):
        return False, "npm audit vulnerability findings; never rerun"

    if not has_timeout(backend_log):
        return False, "no npm audit network timeout marker"

    return True, "npm audit network timeout"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs-json", required=True)
    parser.add_argument("--backend-log")
    parser.add_argument("--run-attempt", type=int)
    parser.add_argument(
        "--print-backend-job-id",
        action="store_true",
        help="Print the failed backend / validate job id when it is the only failure.",
    )
    args = parser.parse_args(argv)

    jobs = json.loads(Path(args.jobs_json).read_text())
    if args.print_backend_job_id:
        job_id = backend_validate_job_id(jobs)
        if job_id is None:
            return 2
        print(job_id)
        return 0

    if args.backend_log is None or args.run_attempt is None:
        parser.error("--backend-log and --run-attempt are required unless --print-backend-job-id")

    log = Path(args.backend_log).read_text(errors="replace")
    rerun, reason = should_rerun(jobs, log, args.run_attempt)
    print(reason)
    return 0 if rerun else 2


if __name__ == "__main__":
    sys.exit(main())
