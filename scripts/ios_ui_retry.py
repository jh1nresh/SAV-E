#!/usr/bin/env python3
"""Fail-fast helpers for the iOS UI retry loop.

A flake may take up to three attempts. A test that failed the previous
attempt and failed again is treated as deterministic: stop before a third
run burns the job wall. Infrastructure failures (no Test Case lines) are
not deterministic and may use the remaining attempts.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

TEST_CASE = re.compile(
    r"Test Case '-\[(?:(?P<bundle>[^.\]]+)\.)?(?P<class>[^\]\s]+) "
    r"(?P<method>[^\]]+)\]' (?P<result>passed|failed)"
)
SUITE_DONE = re.compile(
    r"Test Suite '(?P<name>[^']+)' (?P<result>passed|failed)"
)


def parse_results(text: str) -> dict[str, str]:
    """Map each `-only-testing` id to its last seen result in this log."""
    last: dict[str, str] = {}
    for match in TEST_CASE.finditer(text):
        bundle = match.group("bundle") or "SAVEUITests"
        class_name = match.group("class").split(".")[-1]
        ident = f"{bundle}/{class_name}/{match.group('method')}"
        last[ident] = match.group("result")
    return last


def failed_ids(text: str) -> list[str]:
    return sorted(ident for ident, result in parse_results(text).items() if result == "failed")


def deterministic_failures(previous: list[str], current: list[str]) -> list[str]:
    return sorted(set(previous) & set(current))


def _is_method(ident: str) -> bool:
    return ident.count("/") >= 2


def _covers(ident: str, executed: set[str]) -> bool:
    if ident in executed:
        return True
    prefix = ident + "/"
    return any(item.startswith(prefix) for item in executed)


def suite_finished(ident: str, text: str) -> bool:
    class_name = ident.split("/")[-1]
    for match in SUITE_DONE.finditer(text):
        name = match.group("name")
        if name == class_name or name.endswith("." + class_name):
            return True
    return False


def never_executed(selected: list[str], text: str) -> list[str]:
    """Original selectors that never emitted a Test Case result.

    A class-level selector also counts as unfinished when its Test Suite
    never reported passed/failed, so a mid-class abort cannot go green.
    """
    executed = set(parse_results(text))
    missing: list[str] = []
    for ident in selected:
        if _is_method(ident):
            if ident not in executed:
                missing.append(ident)
            continue
        if not _covers(ident, executed) or not suite_finished(ident, text):
            missing.append(ident)
    return missing


def unsatisfied(selected: list[str], text: str) -> list[str]:
    """Selected tests that did not run and pass across the combined log."""
    executed = parse_results(text)
    bad: list[str] = []
    for ident in selected:
        if _is_method(ident):
            if executed.get(ident) != "passed":
                bad.append(ident)
            continue
        methods = {
            key: result
            for key, result in executed.items()
            if key == ident or key.startswith(ident + "/")
        }
        if (
            not methods
            or not suite_finished(ident, text)
            or any(result != "passed" for result in methods.values())
        ):
            bad.append(ident)
    return bad


def retry_selectors(selected: list[str], text: str) -> list[str]:
    """Failed tests plus original selectors that never completed."""
    executed = parse_results(text)
    retry: list[str] = []
    seen: set[str] = set()
    for ident in selected:
        if ident in seen:
            continue
        if _is_method(ident):
            if executed.get(ident) != "passed":
                retry.append(ident)
                seen.add(ident)
            continue
        methods = {
            key: result
            for key, result in executed.items()
            if key == ident or key.startswith(ident + "/")
        }
        if not methods or not suite_finished(ident, text):
            retry.append(ident)
            seen.add(ident)
            continue
        for key, result in methods.items():
            if result != "passed" and key not in seen:
                retry.append(key)
                seen.add(key)
    return retry


def only_testing_lines(idents: list[str]) -> str:
    return "".join(f"-only-testing:{ident}\n" for ident in idents)


def _read_idents(path: Path) -> list[str]:
    idents: list[str] = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("-only-testing:"):
            line = line[len("-only-testing:") :]
        idents.append(line)
    return idents


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    failed = sub.add_parser("failed-tests", help="print failed -only-testing ids")
    failed.add_argument("log", type=Path)

    decide = sub.add_parser(
        "fail-fast",
        help="exit 2 when the same tests failed two consecutive attempts",
    )
    decide.add_argument("previous", type=Path)
    decide.add_argument("current", type=Path)

    coverage = sub.add_parser(
        "coverage",
        help="exit 2 when a selected test did not run and pass",
    )
    coverage.add_argument("selected", type=Path)
    coverage.add_argument("log", type=Path)

    retry = sub.add_parser(
        "retry-selectors",
        help="print failed and never-completed original selectors",
    )
    retry.add_argument("selected", type=Path)
    retry.add_argument("log", type=Path)

    args = parser.parse_args(argv)
    if args.command == "failed-tests":
        text = args.log.read_text(errors="replace")
        ids = failed_ids(text)
        sys.stdout.write(only_testing_lines(ids))
        return 0
    if args.command == "coverage":
        selected = _read_idents(args.selected)
        text = args.log.read_text(errors="replace")
        gaps = unsatisfied(selected, text)
        never = never_executed(selected, text)
        sys.stdout.write(only_testing_lines(gaps))
        if not gaps:
            return 0
        if never:
            print(
                "selected UI tests never executed: " + ", ".join(never),
                file=sys.stderr,
            )
        leftover = [ident for ident in gaps if ident not in never]
        if leftover:
            print(
                "selected UI tests did not pass: " + ", ".join(leftover),
                file=sys.stderr,
            )
        return 2
    if args.command == "retry-selectors":
        selected = _read_idents(args.selected)
        text = args.log.read_text(errors="replace")
        sys.stdout.write(only_testing_lines(retry_selectors(selected, text)))
        return 0
    previous = _read_idents(args.previous)
    current = _read_idents(args.current)
    stuck = deterministic_failures(previous, current)
    if not stuck:
        return 0
    print(
        "deterministic UI failure (failed two consecutive attempts): "
        + ", ".join(stuck),
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
