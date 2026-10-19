#!/usr/bin/env python3
"""Subset Iansui Regular to Savvy title CJK (OFL 1.1).

Keeps every Taiwan MOE 常用國字標準字體表 (4808) character, plus ASCII
0x20–0x7E and CJK / typographic punctuation. Drops rare hanzi, kana,
hinting, and unused OpenType tables.

iOS UIAppFonts / CTFontManager only register TTF and OTF, not WOFF2, so
the shipped file stays a TTF. Size comes from:
1. a tight cmap subset
2. quadratic outline simplification (max error 64/1000 em)
3. UPEM 500 so more glyf deltas pack as short vectors

Target: Iansui-SavvySubset.ttf <= 1.5 MB with 100% 4808 coverage.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.qu2cuPen import Qu2CuPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem

ASCII = "".join(chr(code) for code in range(0x20, 0x7F))
CJK_PUNCT = (
    "，。、．·・「」『』（）【】《》〔〕"
    "—–…：；？！／％°℃•‧‘’“”"
)
SIMPLIFY_ERROR = 64.0
TARGET_UPEM = 500
MAX_BYTES = 1_500_000


def load_edu_4808(path: Path) -> str:
    chars: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        ch = line.split()[0]
        if ch:
            chars.append(ch[0])
    if len(chars) != 4808:
        raise SystemExit(f"{path} has {len(chars)} characters; expected 4808")
    return "".join(chars)


def charset(edu_path: Path) -> str:
    return "".join(dict.fromkeys(ASCII + CJK_PUNCT + load_edu_4808(edu_path)))


def subset_source(src: Path, text: str) -> TTFont:
    font = TTFont(src)
    options = Options()
    options.hinting = False
    options.glyph_names = False
    options.legacy_kern = False
    options.layout_features = []
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = False
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.drop_tables += [
        "FFTM", "DSIG", "LTSH", "hdmx", "VDMX", "PCLT", "gasp",
        "BASE", "GDEF", "GPOS", "GSUB", "vhea", "vmtx", "JSTF", "MATH",
    ]
    subsetter = Subsetter(options=options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    return font


def simplify_outlines(font: TTFont, max_err: float) -> None:
    glyph_set = font.getGlyphSet()
    glyf = font["glyf"]
    replay_set = {name: glyph_set[name] for name in font.getGlyphOrder()}
    for name in font.getGlyphOrder():
        try:
            cubic = RecordingPen()
            glyph_set[name].draw(Qu2CuPen(cubic, max_err=max_err, all_cubic=True))
            dest = TTGlyphPen(replay_set)
            cubic.replay(Cu2QuPen(dest, max_err=max_err))
            glyf[name] = dest.glyph()
        except Exception:
            continue
    for name in font.getGlyphOrder():
        glyph = glyf[name]
        if glyph.numberOfContours > 0:
            try:
                glyph.recalcBounds(glyf)
            except Exception:
                continue


def cmap_codepoints(font: TTFont) -> set[int]:
    codes: set[int] = set()
    for table in font["cmap"].tables:
        codes.update(table.cmap)
    return codes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    repo = Path(__file__).resolve().parents[1]
    fonts = repo / "SAV-E/Resources/DisplayFont"
    tables = repo / "scripts/doodle-fonts"
    parser.add_argument(
        "--src",
        type=Path,
        help="Upstream Iansui-Regular.ttf (v1.020). Download from ButTaiwan/iansui.",
    )
    parser.add_argument("--edu", type=Path, default=tables / "edu-standard-4808.txt")
    parser.add_argument("--out", type=Path, default=fonts / "Iansui-SavvySubset.ttf")
    args = parser.parse_args()
    if args.src is None:
        parser.error("--src Iansui-Regular.ttf is required")

    text = charset(args.edu)
    needed = {ord(ch) for ch in load_edu_4808(args.edu)}
    font = subset_source(args.src, text)
    simplify_outlines(font, SIMPLIFY_ERROR)
    scale_upem(font, TARGET_UPEM)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    font.save(args.out)

    saved = TTFont(args.out)
    present = cmap_codepoints(saved)
    missing = sorted(needed - present)
    size = args.out.stat().st_size
    print(
        f"wrote {args.out} ({size} bytes, {len(text)} chars, "
        f"{len(saved.getGlyphOrder())} glyphs, UPEM {saved['head'].unitsPerEm})"
    )
    if missing:
        raise SystemExit(f"4808 coverage incomplete: missing {len(missing)} codepoints")
    if size > MAX_BYTES:
        raise SystemExit(
            f"subset is {size} bytes; founder gate is <= {MAX_BYTES}. "
            "Do not drop 4808 coverage to shrink further."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
