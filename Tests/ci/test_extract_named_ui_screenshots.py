import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/extract-named-ui-screenshots.py"


class ExtractNamedUIScreenshotsTests(unittest.TestCase):
    def test_copies_expected_manifest_names_and_fails_on_missing(self):
        with tempfile.TemporaryDirectory() as raw, tempfile.TemporaryDirectory() as out:
            export = Path(raw)
            dest = Path(out)
            (export / "shot-a.png").write_bytes(b"png-a")
            (export / "shot-b.png").write_bytes(b"png-b")
            (export / "manifest.json").write_text(json.dumps([
                {
                    "attachments": [
                        {
                            "exportedFileName": "shot-a.png",
                            "suggestedHumanReadableName": "t3-home-light_0_1.png",
                        },
                        {
                            "exportedFileName": "shot-b.png",
                            "suggestedHumanReadableName": "t3-home-dark",
                        },
                    ]
                }
            ]))

            missing = subprocess.run(
                [
                    sys.executable, str(SCRIPT), str(export), str(dest),
                    "--expect", "t3-home-light", "--expect", "t3-missing",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(missing.returncode, 1)
            self.assertIn("t3-missing", missing.stderr)

            ok = subprocess.run(
                [
                    sys.executable, str(SCRIPT), str(export), str(dest),
                    "--also-prefix", "t3-main",
                    "--expect", "t3-home-light", "--expect", "t3-home-dark",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(ok.returncode, 0, ok.stderr)
            self.assertEqual((dest / "t3-home-light.png").read_bytes(), b"png-a")
            self.assertEqual((dest / "t3-home-dark.png").read_bytes(), b"png-b")
            self.assertEqual((dest / "t3-main-home-light.png").read_bytes(), b"png-a")
            self.assertEqual((dest / "t3-main-home-dark.png").read_bytes(), b"png-b")
