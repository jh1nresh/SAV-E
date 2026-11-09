"""AppIcon.appiconset must cover iPad when TARGETED_DEVICE_FAMILY includes 2."""

from __future__ import annotations

import json
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ICONSET = ROOT / "SAV-E/Resources/Assets.xcassets/AppIcon.appiconset"
CONTENTS = ICONSET / "Contents.json"
MASTER = ICONSET / "SaveAppIcon.png"
IOS_WORKFLOW = ROOT / ".github/workflows/ios.yml"
PROJECT_YML = ROOT / "project.yml"

# iPad slots actool expects for a 1,2 family when the set is not the
# single-size 1024 universal format.
IPAD_REQUIRED = {
    ("20x20", "2x"),
    ("29x29", "2x"),
    ("40x40", "2x"),
    ("76x76", "2x"),
    ("83.5x83.5", "2x"),
}


def png_header(path: Path) -> tuple[int, int, int, bool]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"{path.name} is not a PNG")
    pos = 8
    width = height = color_type = None
    has_trns = False
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        if ctype == b"IHDR":
            width, height, _bit_depth, color_type = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"tRNS":
            has_trns = True
        elif ctype == b"IEND":
            break
        pos += 12 + length
    if width is None or color_type is None:
        raise AssertionError(f"{path.name} is missing IHDR")
    return width, height, color_type, has_trns


class AppIconTests(unittest.TestCase):
    def test_family_includes_ipad(self):
        self.assertIn('TARGETED_DEVICE_FAMILY: "1,2"', PROJECT_YML.read_text())

    def test_master_is_opaque_1024_rgb(self):
        self.assertTrue(MASTER.is_file(), MASTER)
        width, height, color_type, has_trns = png_header(MASTER)
        self.assertEqual((width, height), (1024, 1024))
        # 2 = RGB, no alpha channel. tRNS would still introduce transparency.
        self.assertEqual(color_type, 2)
        self.assertFalse(has_trns)

    def test_contents_covers_ipad_or_universal_1024(self):
        catalog = json.loads(CONTENTS.read_text())
        images = catalog["images"]
        universal = [
            image
            for image in images
            if image.get("idiom") == "universal"
            and image.get("platform") == "ios"
            and image.get("size") == "1024x1024"
        ]
        if universal:
            self.assertEqual(len(images), 1, "universal 1024 must be the only slot")
            self.assertEqual(universal[0].get("filename"), MASTER.name)
            return
        ipad = {
            (image.get("size"), image.get("scale"))
            for image in images
            if image.get("idiom") == "ipad"
        }
        missing = sorted(IPAD_REQUIRED - ipad)
        self.assertEqual(missing, [], f"missing iPad icon slots: {missing}")

    def test_ios_workflow_captures_booted_home_screen(self):
        workflow = IOS_WORKFLOW.read_text()
        self.assertIn("xcrun simctl install", workflow)
        self.assertIn("xcrun simctl io booted screenshot", workflow)
        self.assertIn("save-home-screen-icon-", workflow)


if __name__ == "__main__":
    unittest.main()
