#!/usr/bin/env python3
"""DisplayFont ships fonts and OFL licenses only — no charset .txt."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DISPLAY_FONT = ROOT / "SAV-E/Resources/DisplayFont"
EDU = ROOT / "scripts/doodle-fonts/edu-standard-4808.txt"
FONT = DISPLAY_FONT / "Iansui-SavvySubset.ttf"


class DisplayFontBundleTests(unittest.TestCase):
    def test_bundle_excludes_charset_text(self):
        self.assertTrue(FONT.is_file(), FONT)
        self.assertEqual(FONT.stat().st_size, 3_475_528)
        bundled_txt = sorted(p.name for p in DISPLAY_FONT.glob("*.txt"))
        self.assertEqual(bundled_txt, [])
        self.assertTrue(EDU.is_file(), EDU)
        self.assertFalse((DISPLAY_FONT / "iansui-savvy-charset.txt").exists())
        self.assertFalse((DISPLAY_FONT / "edu-standard-4808.txt").exists())


if __name__ == "__main__":
    unittest.main()
