"""Full-frame Map parity reports unmasked coverage, not a dummy mask."""

from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMPOSE = ROOT / "Prototypes/AtlasPostcard/Scripts/compose-map-similarity.py"
RUNNER = ROOT / "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh"


def load_compose():
    spec = importlib.util.spec_from_file_location("compose_map_similarity", COMPOSE)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class MapParityUnmaskedTests(unittest.TestCase):
    def test_no_mask_report_omits_map_masked_and_mask_reason(self):
        compose = load_compose()
        mock, live = compose.panel_captions(no_mask=True)
        self.assertEqual(mock, "Doodle mock")
        self.assertEqual(live, "Live Map")
        self.assertNotIn("map masked", mock)
        self.assertNotIn("map masked", live)

        report = compose.build_similarity_report(
            status="PASS",
            threshold="0.90",
            payload={
                "composite": 0.94,
                "edgeF1": 0.9,
                "appearanceSimilarity": 0.95,
                "passed": True,
                "ignoredTopRows": 48,
                "ignoreRects": [],
                "ignoreMask": None,
            },
            mask=(0, 0, 0, 0),
            mask_image=None,
            no_mask=True,
            side_by_side="side-by-side.png",
        )
        self.assertEqual(report["mask"], {"coverage": "no-map-mask"})
        self.assertEqual(report["ignoredTopRows"], 48)
        self.assertEqual(report["ignoreRects"], [])
        self.assertIsNone(report["ignoreMask"])
        self.assertNotIn("maskReason", report)
        self.assertEqual(report["threshold"], 0.90)
        self.assertNotIn("map masked", json.dumps(report))

    def test_masked_report_still_explains_rectangle_or_image(self):
        compose = load_compose()
        mock, live = compose.panel_captions(no_mask=False)
        self.assertIn("map masked", mock)
        self.assertIn("map masked", live)
        report = compose.build_similarity_report(
            status="FAIL",
            threshold="0.90",
            payload={"composite": 0.5, "passed": False},
            mask=(0, 48, 402, 642),
            mask_image=None,
            no_mask=False,
            side_by_side="side-by-side.png",
        )
        self.assertEqual(report["mask"]["width"], 402)
        self.assertIn("maskReason", report)
        self.assertEqual(report["threshold"], 0.90)

    def test_runner_uses_explicit_no_mask_and_keeps_point_nine(self):
        script = RUNNER.read_text()
        self.assertIn("--no-mask", script)
        self.assertNotIn('--mask "0,0,0,0"', script)
        self.assertIn('THRESHOLD="0.90"', script)
        self.assertIn("full frame, no map-mask.png", script)
        self.assertIn("gate_failed=1", script)
