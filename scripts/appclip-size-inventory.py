#!/usr/bin/env python3
"""List bytes the SAVEClip target is allowed to ship (Z1 / Z2)."""

from __future__ import annotations

import argparse
from pathlib import Path

CLIP_ROOT = Path("SAV-EClip")
CAVEAT = Path("SAV-E/Resources/DisplayFont/Caveat-SemiBold.ttf")
IANSUI = Path("SAV-E/Resources/DisplayFont/Iansui-SavvySubset.ttf")
IANSUI_CLIP = Path("SAV-E/Resources/DisplayFont/Iansui-ClipTitles.ttf")
MAIN_ASSETS = Path("SAV-E/Resources/Assets.xcassets")
THRESHOLD = 15 * 1024 * 1024


def byte_count(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    total = 0
    for child in path.rglob("*"):
        if child.is_file():
            total += child.stat().st_size
    return total


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, help="Write a markdown report")
    args = parser.parse_args()

    rows: list[tuple[str, int, str]] = []
    clip_assets = CLIP_ROOT / "Assets.xcassets"
    rows.append(("SAV-EClip/Assets.xcassets", byte_count(clip_assets), "Clip catalog only"))
    rows.append((str(CAVEAT), byte_count(CAVEAT), "English titles (shipped)"))
    rows.append((str(IANSUI_CLIP), byte_count(IANSUI_CLIP), "zh title glyphs (shipped)"))
    rows.append((str(IANSUI), byte_count(IANSUI), "NOT shipped — full main subset"))
    rows.append((str(MAIN_ASSETS), byte_count(MAIN_ASSETS), "NOT shipped (removed from SAVEClip)"))

    shipped = byte_count(clip_assets) + byte_count(CAVEAT) + byte_count(IANSUI_CLIP)
    lines = [
        "# App Clip size inventory",
        "",
        "Official App Thinning Size Report needs `xcodebuild -exportArchive` on",
        "macOS. Until that artifact exists, this is the source inventory plus",
        "the Debug `.app` measured on CI. Threshold: 15 MB uncompressed per variant.",
        "",
        "| Path | Bytes | Notes |",
        "| --- | ---: | --- |",
    ]
    for path, size, note in rows:
        lines.append(f"| `{path}` | {size:,} | {note} |")
    lines.extend(
        [
            "",
            f"Shipped source assets: **{shipped:,} bytes** "
            f"({shipped / (1024 * 1024):.2f} MB).",
            f"Iansui full subset avoided: **{byte_count(IANSUI):,} bytes**.",
            f"Iansui Clip-title subset shipped: **{byte_count(IANSUI_CLIP):,} bytes**.",
            "User list names fall back to the system font when a glyph is missing.",
            f"Main catalog avoided: **{byte_count(MAIN_ASSETS):,} bytes**.",
            f"Threshold: {THRESHOLD:,} bytes.",
            "",
            "Vector stickers are SwiftUI drawings (noodle bowl + plate, coffee +",
            "saucer, temple, duck, lantern, place/pin fallback), not extra rasters.",
            "Wordmark is Caveat 'Savvy' in forest at a fixed 34pt — not the elephant.",
            "",
        ]
    )
    report = "\n".join(lines)
    print(report)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
