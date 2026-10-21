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

    args = parser.parse_args(argv)
    if args.command == "failed-tests":
        text = args.log.read_text(errors="replace")
        ids = failed_ids(text)
        sys.stdout.write(only_testing_lines(ids))
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
