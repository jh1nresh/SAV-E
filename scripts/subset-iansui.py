#!/usr/bin/env python3
"""Subset Iansui Regular to Savvy title CJK (OFL 1.1).

Keeps:
- fixed UI title strings used by SaveDisplayTitle
- Taiwan MOE 常用國字標準字體表 (4808)
- CJK / fullwidth punctuation used next to titles

Charset tables live in scripts/doodle-fonts/ so DisplayFont ships only
fonts and OFL licenses. Missing glyphs fall through to PingFang TC via
kCTFontCascadeListAttribute. Do not change the shipped Iansui size
unless the founder asks.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

# Titles and city-switcher copy that must render in Iansui, not fallback.
UI_STRINGS = (
    "朋友護照收藏地圖首頁附近你的私人地點圖鑑"
    "想去的地方全部存下這附近還沒有存過地方"
    "天壇北京台北臺北東京上海香港深圳京都大阪首爾"
    "蘇州南京青島杭州成都重慶廈門高雄台中臺中"
    "Savvy Passport Friends Home Map Paywall"
)

PUNCTUATION = (
    "，。、．·・「」『』（）【】—–…：；？！—-–—／"
    "·•‧℃°％—–-_/|&'\"“”‘’"
)


def load_edu_4808(path: Path) -> str:
    chars: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        ch = line.split()[0]
        if ch:
            chars.append(ch[0])
    if len(chars) < 4800:
        raise SystemExit(f"{path} has {len(chars)} characters; expected 4808")
    return "".join(chars)


def charset(edu_path: Path) -> str:
    return "".join(dict.fromkeys(UI_STRINGS + PUNCTUATION + load_edu_4808(edu_path)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    repo = Path(__file__).resolve().parents[1]
    fonts = repo / "SAV-E/Resources/DisplayFont"
    tables = repo / "scripts/doodle-fonts"
    parser.add_argument(
        "--src",
        type=Path,
        help="Upstream Iansui-Regular.ttf (v1.020). Not committed; download from GitHub releases.",
    )
    parser.add_argument("--edu", type=Path, default=tables / "edu-standard-4808.txt")
    parser.add_argument("--out", type=Path, default=fonts / "Iansui-SavvySubset.ttf")
    parser.add_argument(
        "--charset-out",
        type=Path,
        default=None,
        help="Optional charset dump. Defaults to a temp file so DisplayFont stays font-only.",
    )
    args = parser.parse_args()
    if args.src is None:
        parser.error(" --src Iansui-Regular.ttf is required (download v1.020 from ButTaiwan/iansui)")

    text = charset(args.edu)
    cleanup = False
    if args.charset_out is not None:
        charset_path = args.charset_out
        charset_path.parent.mkdir(parents=True, exist_ok=True)
        charset_path.write_text(text + "\n", encoding="utf-8")
    else:
        tmp = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8")
        tmp.write(text + "\n")
        tmp.close()
        charset_path = Path(tmp.name)
        cleanup = True

    # Handwritten Iansui outlines dominate size. Drop hinting, vertical
    # metrics, and GSUB/GPOS so 4808 glyphs stay as small as a TTF allows.
    cmd = [
        sys.executable, "-m", "fontTools.subset",
        str(args.src),
        f"--text-file={charset_path}",
        f"--output-file={args.out}",
        "--no-hinting",
        "--no-glyph-names",
        "--symbol-cmap",
        "--legacy-cmap",
        "--notdef-glyph",
        "--notdef-outline",
        "--name-legacy",
        "--layout-features=",
        "--drop-tables+=FFTM,DSIG,LTSH,hdmx,VDMX,PCLT,gasp,BASE,GDEF,GPOS,GSUB,vhea,vmtx,JSTF,MATH",
    ]
    try:
        subprocess.check_call(cmd)
    finally:
        if cleanup:
            charset_path.unlink(missing_ok=True)
    size = args.out.stat().st_size
    print(f"wrote {args.out} ({size} bytes, {len(text)} chars)")
    if size > 1_500_000:
        print(
            f"warning: subset is {size} bytes; spec target is <= 1.5 MB. "
            "glyf outlines for 4808 handwritten glyphs do not compress further "
            "in TTF. Missing glyphs still cascade to PingFang TC.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
