"""Exercise the real macOS parity CLI, including its Swift compilation and gate."""

import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Prototypes/AtlasPostcard/Scripts/VisualParity.swift"
TARGET = ROOT / "Prototypes/AtlasPostcard/Reference/ProductionTargets/friends.png"


def write_blank_png(path: Path):
    def chunk(kind, content):
        return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind + content))

    width, height = 402, 874
    rows = (b"\0" + b"\xff\xff\xff" * width) * height
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "AppKit parity CLI requires macOS/Xcode")
class VisualParityCLITests(unittest.TestCase):
    def compare(self, actual, diff):
        return subprocess.run(
            ["xcrun", "swift", str(SCRIPT), "--target", str(TARGET),
             "--actual", str(actual), "--diff", str(diff), "--threshold", "0.90"],
            capture_output=True, text=True, timeout=60,
        )

    def test_identical_image_passes_real_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.compare(TARGET, Path(tmp) / "diff.png")
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertTrue(report["passed"])
            self.assertAlmostEqual(report["composite"], 1.0)
            self.assertEqual(report["threshold"], 0.90)
            self.assertEqual(report["mask"], "")

    def test_blank_image_still_fails_point_nine_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            actual = Path(tmp) / "blank.png"
            write_blank_png(actual)
            result = self.compare(actual, Path(tmp) / "diff.png")
            self.assertEqual(result.returncode, 1, result.stderr)
            report = json.loads(result.stdout)
            self.assertFalse(report["passed"])
            self.assertLess(report["composite"], 0.90)


if __name__ == "__main__":
    unittest.main()
