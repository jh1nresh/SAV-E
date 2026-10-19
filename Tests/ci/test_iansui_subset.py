#!/usr/bin/env python3
"""Iansui subset gates: <=1.5 MB and 100% MOE 4808 coverage."""

import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "SAV-E/Resources/DisplayFont/Iansui-SavvySubset.ttf"
EDU = ROOT / "scripts/doodle-fonts/edu-standard-4808.txt"
DISPLAY_FONT = ROOT / "SAV-E/Resources/DisplayFont"
MAX_BYTES = 1_500_000


def load_edu_4808(path: Path) -> list[str]:
    chars: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        chars.append(line.split()[0][0])
    return chars


def _u16(data: bytes, offset: int) -> int:
    return struct.unpack_from(">H", data, offset)[0]


def _u32(data: bytes, offset: int) -> int:
    return struct.unpack_from(">I", data, offset)[0]


def cmap_codepoints(path: Path) -> set[int]:
    data = path.read_bytes()
    table_count = _u16(data, 4)
    cmap_offset = None
    for index in range(table_count):
        rec = 12 + index * 16
        tag = data[rec:rec + 4]
        if tag == b"cmap":
            cmap_offset = _u32(data, rec + 8)
            break
    if cmap_offset is None:
        raise AssertionError("font has no cmap table")
    num_tables = _u16(data, cmap_offset + 2)
    codes: set[int] = set()
    for index in range(num_tables):
        rec = cmap_offset + 4 + index * 8
        sub_offset = cmap_offset + _u32(data, rec + 4)
        fmt = _u16(data, sub_offset)
        if fmt == 4:
            seg_count = _u16(data, sub_offset + 6) // 2
            end_off = sub_offset + 14
            start_off = end_off + 2 * seg_count + 2
            delta_off = start_off + 2 * seg_count
            range_off = delta_off + 2 * seg_count
            for seg in range(seg_count):
                end = _u16(data, end_off + 2 * seg)
                start = _u16(data, start_off + 2 * seg)
                delta = struct.unpack_from(">h", data, delta_off + 2 * seg)[0]
                range_ptr = _u16(data, range_off + 2 * seg)
                for code in range(start, end + 1):
                    if range_ptr == 0:
                        glyph = (code + delta) & 0xFFFF
                    else:
                        glyph_off = range_off + 2 * seg + range_ptr + 2 * (code - start)
                        glyph = _u16(data, glyph_off)
                        if glyph:
                            glyph = (glyph + delta) & 0xFFFF
                    if glyph:
                        codes.add(code)
        elif fmt == 12:
            n_groups = _u32(data, sub_offset + 12)
            base = sub_offset + 16
            for group in range(n_groups):
                start = _u32(data, base + group * 12)
                end = _u32(data, base + group * 12 + 4)
                codes.update(range(start, end + 1))
    return codes


class IansuiSubsetTests(unittest.TestCase):
    def test_file_is_at_most_1_5_mb(self):
        self.assertTrue(FONT.is_file(), FONT)
        self.assertLessEqual(FONT.stat().st_size, MAX_BYTES, FONT.stat().st_size)

    def test_moe_4808_coverage_is_complete(self):
        needed = load_edu_4808(EDU)
        self.assertEqual(len(needed), 4808)
        present = cmap_codepoints(FONT)
        missing = [ch for ch in needed if ord(ch) not in present]
        self.assertEqual(missing, [], f"missing {len(missing)} of 4808")

    def test_ascii_and_bundle_exclude_charset_text(self):
        present = cmap_codepoints(FONT)
        missing_ascii = [chr(code) for code in range(0x20, 0x7F) if code not in present]
        self.assertEqual(missing_ascii, [])
        bundled_txt = sorted(p.name for p in DISPLAY_FONT.glob("*.txt"))
        self.assertEqual(bundled_txt, [])


if __name__ == "__main__":
    unittest.main()
