#!/usr/bin/env python3
"""Partition execution only; select-ios-tests.py still owns the full coverage."""

import argparse
import os
from pathlib import Path

HOME = {
    "-only-testing:SAVEUITests/SAVEScreenshotRailTests/testHomeHintCountEvidence",
    "-only-testing:SAVEUITests/SAVEScreenshotRailTests/testHomeTPEAEvidence",
}


def partition(lines):
    selected = [line.strip() for line in lines if line.strip()]
    if any(not line.startswith("-only-testing:") for line in selected):
        raise ValueError("unexpected selector argument")
    if len(selected) != len(set(selected)):
        raise ValueError("duplicate selectors")
    return ([line for line in selected if line not in HOME],
            [line for line in selected if line in HOME])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True, type=Path)
    args = parser.parse_args()
    original = args.directory / "ios-ui-args.txt"
    core, home = partition(original.read_text().splitlines())
    for name, lines in (("core", core), ("home", home)):
        (args.directory / f"ios-ui-{name}-args.txt").write_text(
            "".join(line + "\n" for line in lines))
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as f:
            f.write(f"home={str(bool(home)).lower()}\n")


if __name__ == "__main__":
    main()
