import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class Gate5NamedExportTests(unittest.TestCase):
    def test_clean_name_strips_xcresult_suffix(self):
        spec = ROOT / "scripts/export-gate5-named-stills.py"
        ns: dict[str, object] = {}
        exec(spec.read_text(), ns)
        clean_name = ns["clean_name"]
        self.assertEqual(
            clean_name(
                "light-coralCardHero_0_38EFF560-47AE-449F-A9DD-F3BB0B6ED6A6.png",
                "fallback.png",
            ),
            "light-coralCardHero.png",
        )
        self.assertEqual(clean_name("", "raw.png"), "raw.png")

    def test_export_named_copies_manifest_attachments(self):
        spec = ROOT / "scripts/export-gate5-named-stills.py"
        ns: dict[str, object] = {}
        exec(spec.read_text(), ns)
        export_named = ns["export_named"]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            attachments = root / "xcattachments"
            dest = root / "imagerenderer"
            attachments.mkdir()
            sample = attachments / "ABC.png"
            sample.write_bytes(b"png")
            manifest = attachments / "manifest.json"
            manifest.write_text(json.dumps([{
                "attachments": [{
                    "exportedFileName": "ABC.png",
                    "suggestedHumanReadableName": "zh-Hant-photoBadge_0_DEADBEEF.png",
                }]
            }]))
            written = export_named(manifest, attachments, dest)
            self.assertEqual(written, ["zh-Hant-photoBadge.png"])
            self.assertTrue((dest / "zh-Hant-photoBadge.png").is_file())
            self.assertEqual((dest / "zh-Hant-photoBadge.png").read_bytes(), b"png")


if __name__ == "__main__":
    unittest.main()
