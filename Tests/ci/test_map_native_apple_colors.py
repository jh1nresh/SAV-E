"""HoP 298-1: product Map keeps native Apple MapKit colors."""

from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
MAP = ROOT / "SAV-E/Views/Map/SaveDoodleMapView.swift"
HOME = ROOT / "SAV-E/Views/Home/SaveDoodleHomeView.swift"

# Acceptance: ZERO `.saturation(`, `.colorMultiply(`, `.muted`, and
# paper-texture overlay on the product Map surface.
FORBIDDEN = (
    r"\.saturation\(",
    r"\.colorMultiply\(",
    r"emphasis:\s*\.muted",
    r"\.blendMode\(\.multiply\)",
    r"PaperGrain",
    r"paper-grain",
    r"paper multiply",
    r"paper-texture",
)


def mini_map_source(home: str) -> str:
    start = home.find("struct SaveDoodleMiniMap")
    if start < 0:
        raise AssertionError("SaveDoodleMiniMap is missing from SaveDoodleHomeView.swift")
    end = home.find("enum SaveDoodleOfficialSticker", start)
    if end < 0:
        raise AssertionError("SaveDoodleOfficialSticker marker is missing after SaveDoodleMiniMap")
    return home[start:end]


class NativeAppleMapColorTests(unittest.TestCase):
    def test_map_and_mini_map_have_no_paper_wash(self):
        map_src = MAP.read_text()
        mini_src = mini_map_source(HOME.read_text())
        for name, source in (
            ("SaveDoodleMapView", map_src),
            ("SaveDoodleMiniMap", mini_src),
        ):
            for pattern in FORBIDDEN:
                self.assertIsNone(
                    re.search(pattern, source),
                    f"{name} HoP 298-1 forbids {pattern}",
                )
            washed = source.replace("SaveAtlasPalette.muted", "")
            self.assertNotIn(".muted", washed, f"{name} HoP 298-1 forbids .muted")
            self.assertIn(".mapStyle(.standard(emphasis: .automatic))", source)

    def test_ios_job_wall_stays_at_160_for_verify_ci_test_selection(self):
        # Run 40014623058: lock expected 100 vs ios.yml job 160.
        ios_workflow = (ROOT / ".github/workflows/ios.yml").read_text()
        self.assertRegex(ios_workflow, r"(?m)^    timeout-minutes: 160\s*$")
        self.assertIn("timeout-minutes: 100", ios_workflow)
        self.assertIn("name: Verify CI test selection", ios_workflow)
