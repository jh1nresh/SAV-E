#!/usr/bin/env python3
"""Decide whether a completed CI run may call rerun-failed-jobs.

Only the required `backend / validate` job, and only when that job failed
because npm audit could not reach the registry. Test failures, builds,
vulnerability findings, ios* jobs, and cancelled runs must never rerun.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

BACKEND_JOB = "backend / validate"
MAX_RUN_ATTEMPT = 3
# Only exhausted terminal failures. Intermediate
# `transient npm audit failure (timeout` lines are retries the process
# moved past and must not trigger a rerun.
TERMINAL_TIMEOUT_RE = re.compile(
    r"npm audit timed out talking to the registry|npm audit timed out after \d+"
)
TERMINAL_NON_TIMEOUT_RE = re.compile(
    r"npm audit failed \(|npm audit found production vulnerabilities"
)
FINDING_RE = re.compile(
    r"npm audit found production vulnerabilities|found \d+ (?:high|critical) severity",
    re.I,
)
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


def has_cancelled(payload, run_conclusion=None):
    if run_conclusion == "cancelled":
        return True
    return any(job.get("conclusion") == "cancelled" for job in load_jobs(payload))


def audit_section(log: str) -> str:
    """Return only the final `npm run audit:production` section.

    `validate` runs `audit:self-test` first. That invocation prints
    synthetic timeout markers via `scripts/audit-production.mjs --self-test`.
    A later TypeScript/build failure must not inherit those markers.
    """
    last = log.rfind("audit:production")
    if last < 0:
        return ""
    line_start = log.rfind("\n", 0, last) + 1
    return log[line_start:]


def last_audit_decision(section: str):
    for line in reversed(section.splitlines()):
        text = line.strip()
        if not text:
            continue
        if TERMINAL_NON_TIMEOUT_RE.search(text):
            return "other"
        if TERMINAL_TIMEOUT_RE.search(text):
            return "timeout"
    return None


def has_timeout(log: str) -> bool:
    return last_audit_decision(audit_section(log)) == "timeout"


def parse_audit_reports(text: str):
    reports = []
    decoder = json.JSONDecoder()
    index = 0
    while index < len(text):
        start = text.find("{", index)
        if start < 0:
            break
        try:
            obj, end = decoder.raw_decode(text, start)
        except json.JSONDecodeError:
            index = start + 1
            continue
        if isinstance(obj, dict):
            reports.append(obj)
        index = end
    return reports


def high_critical_count(report):
    vulns = (report.get("metadata") or {}).get("vulnerabilities") or {}
    try:
        return int(vulns.get("high") or 0) + int(vulns.get("critical") or 0)
    except (TypeError, ValueError):
        return 0


def has_vulnerability_findings(log: str) -> bool:
    section = audit_section(log)
    if FINDING_RE.search(section):
        return True
    return any(high_critical_count(report) > 0 for report in parse_audit_reports(section))


def has_test_failure(log: str) -> bool:
    if TEST_NOT_OK_RE.search(log):
        return True
    match = TEST_FAIL_COUNT_RE.search(log)
    return bool(match and int(match.group(1)) > 0)


def backend_validate_job_id(jobs_payload, run_conclusion=None):
    if has_cancelled(jobs_payload, run_conclusion):
        return None
    failed = failed_jobs(jobs_payload)
    if any(str(job.get("name") or "").startswith("ios") for job in failed):
        return None
    match = [job for job in failed if job.get("name") == BACKEND_JOB]
    if len(failed) != 1 or len(match) != 1:
        return None
    return match[0].get("id")


def should_rerun(jobs_payload, backend_log: str, run_attempt: int, run_conclusion=None):
    if run_conclusion == "cancelled" or has_cancelled(jobs_payload, run_conclusion):
        return False, "cancelled run; never rerun"

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

    return True, f"matched npm audit network timeout, attempt {run_attempt}"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs-json", required=True)
    parser.add_argument("--backend-log")
    parser.add_argument("--run-attempt", type=int)
    parser.add_argument("--run-conclusion")
    parser.add_argument(
        "--print-backend-job-id",
        action="store_true",
        help="Print the failed backend / validate job id when it is the only failure.",
    )
    args = parser.parse_args(argv)

    jobs = json.loads(Path(args.jobs_json).read_text())
    if args.print_backend_job_id:
        job_id = backend_validate_job_id(jobs, args.run_conclusion)
        if job_id is None:
            return 2
        print(job_id)
        return 0

    if args.backend_log is None or args.run_attempt is None:
        parser.error("--backend-log and --run-attempt are required unless --print-backend-job-id")

    log = Path(args.backend_log).read_text(errors="replace")
    rerun, reason = should_rerun(jobs, log, args.run_attempt, args.run_conclusion)
    print(reason)
    return 0 if rerun else 2


if __name__ == "__main__":
    sys.exit(main())
