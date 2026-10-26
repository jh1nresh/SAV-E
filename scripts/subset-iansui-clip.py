#!/usr/bin/env python3
"""Subset Iansui to Clip state-title glyphs (OFL 1.1).

Does not cover user list names — those fall back to the system font.
Rebuild from Iansui-SavvySubset.ttf (already OFL-subset) or upstream Regular.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont

CLIP_TITLE_TEXT = (
    "這個連結已失效連不上網路暫時忙不過來讀不懂用分享打開正在內容朋友"
    "存好了免費額度已滿已經在你的沒有進去"
    "Savvy Passport"
    "，。、．·・「」『』（）？！"
)


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    fonts = repo / "SAV-E/Resources/DisplayFont"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--src",
        type=Path,
        default=fonts / "Iansui-SavvySubset.ttf",
        help="Source TTF (Clip-title subset or Iansui Regular).",
    )
    parser.add_argument("--out", type=Path, default=fonts / "Iansui-ClipTitles.ttf")
    args = parser.parse_args()

    opts = Options()
    opts.notdef_outline = True
    opts.recommended_glyphs = True
    font = TTFont(args.src)
    subsetter = Subsetter(options=opts)
    subsetter.populate(text=CLIP_TITLE_TEXT)
    subsetter.subset(font)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    font.save(args.out)
    print(f"wrote {args.out} ({args.out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
