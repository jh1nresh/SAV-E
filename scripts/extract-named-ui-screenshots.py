#!/usr/bin/env python3
"""Copy named XCTAttachment screenshots out of an xcresult export."""

import argparse
import json
import shutil
import sys
from pathlib import Path


def stable_name(human: str) -> str:
    stable = human.split("_0_", 1)[0]
    if stable.lower().endswith(".png"):
        stable = stable[:-4]
    return stable


def collect(export_dir: Path, expected: list[str]) -> dict[str, Path]:
    wanted = set(expected)
    found: dict[str, Path] = {}
    manifest_path = export_dir / "manifest.json"
    if manifest_path.exists():
        for test in json.loads(manifest_path.read_text()):
            for att in test.get("attachments", []):
                human = att.get("suggestedHumanReadableName") or att.get(
                    "exportedFileName", ""
                )
                name = stable_name(human)
                exported = export_dir / att["exportedFileName"]
                if name in wanted and exported.exists():
                    found[name] = exported
        return found
    for png in export_dir.glob("*.png"):
        name = stable_name(png.stem)
        if name in wanted:
            found[name] = png
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export_dir", type=Path)
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("--expect", action="append", required=True)
    parser.add_argument(
        "--also-prefix",
        action="append",
        default=[],
        help="Also copy each t3-* shot as {prefix}-<rest>, e.g. t3-main",
    )
    args = parser.parse_args()
    found = collect(args.export_dir, args.expect)
    missing = [name for name in args.expect if name not in found]
    if missing:
        print("error: missing screenshots: " + ", ".join(missing), file=sys.stderr)
        return 1
    args.out_dir.mkdir(parents=True, exist_ok=True)
    for name in args.expect:
        dest = args.out_dir / f"{name}.png"
        shutil.copyfile(found[name], dest)
        print(f"{dest} ({dest.stat().st_size} bytes)")
        rest = name[3:] if name.startswith("t3-") else name
        for prefix in args.also_prefix:
            alias = args.out_dir / f"{prefix}-{rest}.png"
            shutil.copyfile(found[name], alias)
            print(f"{alias} ({alias.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
