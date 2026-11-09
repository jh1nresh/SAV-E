#!/usr/bin/env python3
"""Fail unless CI backend, contracts, and evidence-rubric succeeded for a SHA."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


REQUIRED_JOBS = ("backend", "save-contracts", "evidence-rubric")
SUCCESS = "success"
PENDING = "pending"
FAILED = "failed"
MISSING = "missing"
RANK = {MISSING: 0, SUCCESS: 1, PENDING: 2, FAILED: 3}
CI_WORKFLOW_FILE = "ci.yml"
CI_WORKFLOW_PATH = ".github/workflows/ci.yml"
CI_NOT_FOUND = "CI not found"
MAX_RUN_PAGES = 50


def job_key(name: str) -> str | None:
    for required in REQUIRED_JOBS:
        if name == required or name.startswith(f"{required} /"):
            return required
    return None


def classify_job(job: dict) -> str:
    status = job.get("status") or ""
    conclusion = job.get("conclusion")
    if status != "completed":
        return PENDING
    if conclusion == "success":
        return SUCCESS
    return FAILED


def evaluate_jobs(jobs: list[dict]) -> dict[str, str]:
    results = {name: MISSING for name in REQUIRED_JOBS}
    for job in jobs:
        key = job_key(str(job.get("name") or ""))
        if key is None:
            continue
        state = classify_job(job)
        if RANK[state] > RANK[results[key]]:
            results[key] = state
    return results


def all_succeeded(results: dict[str, str]) -> bool:
    return all(results[name] == SUCCESS for name in REQUIRED_JOBS)


def blocking_failures(results: dict[str, str]) -> list[str]:
    return [name for name in REQUIRED_JOBS if results[name] == FAILED]


def format_results(results: dict[str, str]) -> str:
    return ", ".join(f"{name}={results[name]}" for name in REQUIRED_JOBS)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Require CI backend, contracts, and evidence-rubric for a commit."
    )
    parser.add_argument("--commit", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--timeout-seconds", type=int, default=780)
    parser.add_argument("--poll-seconds", type=int, default=20)
    return parser.parse_args()


def api_get(url: str, token: str) -> dict:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "save-release-readiness",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"GitHub API {error.code} for {url}: {detail}") from error


def ci_workflow_runs_url(
    repository: str, commit: str, *, page: int = 1, per_page: int = 100
) -> str:
    query = urllib.parse.urlencode(
        {"head_sha": commit, "per_page": per_page, "page": page}
    )
    return (
        f"https://api.github.com/repos/{repository}/actions/workflows/"
        f"{CI_WORKFLOW_FILE}/runs?{query}"
    )


def run_recency_key(run: dict) -> tuple:
    return (str(run.get("created_at") or ""), int(run.get("id") or 0))


def is_ci_run_for_commit(run: dict, commit: str) -> bool:
    if str(run.get("head_sha") or "") != commit:
        return False
    path = run.get("path")
    if path not in (None, "", CI_WORKFLOW_PATH):
        return False
    return True


def describe_ci_run(run: dict | None) -> str:
    if run is None:
        return CI_NOT_FOUND
    conclusion = run.get("conclusion") or "none"
    return (
        f"CI run {run.get('id')} status={run.get('status') or 'unknown'} "
        f"conclusion={conclusion}"
    )


def latest_ci_run(
    repository: str, commit: str, token: str, *, per_page: int = 100
) -> dict | None:
    """Return the newest CI workflow run for commit, or None if none exist.

    Queries the CI workflow runs API directly so other workflows (for
    example Auto-rerun flaky) cannot crowd the first page of the generic
    /actions/runs list. Paginates until a short page. Does not filter by
    status or conclusion: in-progress and failed runs are returned so the
    caller can wait or block.
    """
    selected: dict | None = None
    page = 1
    while True:
        payload = api_get(
            ci_workflow_runs_url(
                repository, commit, page=page, per_page=per_page
            ),
            token,
        )
        page_runs = list(payload.get("workflow_runs") or [])
        for run in page_runs:
            if not is_ci_run_for_commit(run, commit):
                continue
            if selected is None or run_recency_key(run) > run_recency_key(selected):
                selected = run
        if len(page_runs) < per_page:
            break
        page += 1
        if page > MAX_RUN_PAGES:
            break
    return selected


def list_jobs(repository: str, run_id: int, token: str) -> list[dict]:
    payload = api_get(
        f"https://api.github.com/repos/{repository}/actions/runs/{run_id}/jobs?per_page=100",
        token,
    )
    return list(payload.get("jobs") or [])


def main() -> None:
    args = parse_args()
    if args.timeout_seconds < 1 or args.poll_seconds < 1:
        raise SystemExit("timeout and poll seconds must be positive")
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token:
        raise SystemExit("GITHUB_TOKEN is required to read CI job results")

    deadline = time.monotonic() + args.timeout_seconds
    while True:
        run = latest_ci_run(args.repository, args.commit, token)
        jobs = list_jobs(args.repository, int(run["id"]), token) if run else []
        results = evaluate_jobs(jobs)
        if all_succeeded(results):
            print(f"CI jobs passed for {args.commit}: {format_results(results)}")
            return
        failed = blocking_failures(results)
        if failed:
            raise SystemExit(
                "release-readiness cannot claim CI passed: "
                f"{format_results(results)}"
            )
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise SystemExit(
                "timed out waiting for backend, save-contracts, and "
                f"evidence-rubric: {format_results(results)}"
            )
        print(
            f"waiting for CI jobs ({describe_ci_run(run)}; "
            f"{format_results(results)}); {int(remaining)}s left",
            file=sys.stderr,
        )
        time.sleep(min(args.poll_seconds, remaining))


if __name__ == "__main__":
    main()
