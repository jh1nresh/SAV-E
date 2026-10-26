#!/usr/bin/env python3
"""Copy xcresult attachments to imagerenderer/ using suggested names.

Simulator tests cannot write the host SAVE_GATE5_EVIDENCE_DIR, so CI
renames XCTAttachments after `xcresulttool export attachments`.
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


def clean_name(suggested: str, fallback: str) -> str:
    name = suggested or fallback
    if "_0_" in name and name.endswith(".png"):
        return f"{name.split('_0_', 1)[0]}.png"
    return name


def export_named(manifest_path: Path, attachments_dir: Path, dest_dir: Path) -> list[str]:
    dest_dir.mkdir(parents=True, exist_ok=True)
    written: list[str] = []
    payload = json.loads(manifest_path.read_text())
    for suite in payload:
        for attachment in suite.get("attachments", []):
            exported = attachment.get("exportedFileName")
            if not exported:
                continue
            source = attachments_dir / exported
            if not source.is_file():
                continue
            name = clean_name(
                attachment.get("suggestedHumanReadableName") or "",
                exported,
            )
            target = dest_dir / name
            shutil.copy2(source, target)
            written.append(name)
    return written


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--attachments", required=True)
    parser.add_argument("--dest", required=True)
    args = parser.parse_args()
    written = export_named(
        Path(args.manifest),
        Path(args.attachments),
        Path(args.dest),
    )
    if not written:
        raise SystemExit("no named gate-5 stills exported from xcattachments")
    print("\n".join(sorted(written)))


if __name__ == "__main__":
    main()
