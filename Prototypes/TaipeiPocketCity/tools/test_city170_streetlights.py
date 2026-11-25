"""Focused safety checks for roadside and path lamp placement."""

import gzip
import hashlib
import json
from pathlib import Path
import runpy
from tempfile import TemporaryDirectory
import unittest

from shapely import LineString, Point, STRtree


placement = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/build-city170-streetlights.py"))


class StreetlightPlacement(unittest.TestCase):
    def test_road_support_uses_curb_offset_and_road_facing_direction(self):
        road = STRtree([LineString([(0, -100), (0, 100)])])
        empty = STRtree([])
        infer = placement["street_context"]
        self.assertEqual(infer(Point(5, 0), 800, road, [4], empty), ("road", 180))
        self.assertEqual(infer(Point(-5, 0), 800, road, [4], empty), ("road", 0))
        self.assertIsNone(infer(Point(2, 0), 800, road, [4], empty))
        self.assertIsNone(infer(Point(11, 0), 800, road, [4], empty))

    def test_path_lamp_requires_a_nearby_walkway_and_matching_scale(self):
        path = STRtree([LineString([(4, -20), (4, 20)])])
        empty = STRtree([])
        infer = placement["street_context"]
        self.assertEqual(infer(Point(7, 1), 350, empty, [], path), ("path", 0))
        self.assertIsNone(infer(Point(7, 1), 800, empty, [], path))
        self.assertIsNone(infer(Point(12, 0), 350, empty, [], path))

    def test_path_does_not_exempt_points_in_travel_lanes(self):
        ways = STRtree([LineString([(0, -30), (0, 30)])])
        self.assertIsNone(placement["street_context"](Point(1, 0), 350, ways, [4], ways))

    def test_only_public_surface_streets_count_as_support(self):
        check = placement["public_grade"]
        self.assertTrue(check({"access": "public"}))
        self.assertFalse(check({"access": "private"}))
        self.assertFalse(check({"foot": "no"}))
        self.assertFalse(check({"layer": "-1"}))
        self.assertFalse(check({"bridge": "yes"}))

    def test_original_way_tags_restore_access_and_grade_lost_from_packs(self):
        with TemporaryDirectory() as temporary:
            data = Path(temporary)
            packs = data / "city170"
            packs.mkdir()
            features = [
                {"id": f"walk/way/{ident}", "properties": {"kind": "walk", "category": "footway", "width": 2.2},
                 "geometry": {"type": "LineString", "coordinates": [[121.535, latitude], [121.536, latitude]]}}
                for ident, latitude in enumerate((25.033, 25.034, 25.035), 1)
            ]
            (packs / "p1.json.gz").write_bytes(gzip.compress(json.dumps({"features": {"features": features}}).encode()))
            raw = json.dumps({"elements": [
                {"type": "way", "id": 1, "tags": {"foot": "no"}},
                {"type": "way", "id": 2, "tags": {"location": "underground"}},
                {"type": "way", "id": 3, "tags": {"foot": "yes"}},
            ]}).encode()
            osm = data / "osm.json.gz"
            osm.write_bytes(gzip.compress(raw))
            (packs / "index.json").write_text(json.dumps({"source": {"provenance": {
                "taipeiExtractUncompressedSHA256": hashlib.sha256(raw).hexdigest(),
            }}}))
            _, _, _, paths, shadows = placement["map_geometry"](data, osm)
            for latitude, expected in ((25.033, (0, 0)), (25.034, (0, 1)), (25.035, (1, 0))):
                sample = placement["F"]["project"](Point(121.5355, latitude))
                self.assertEqual((len(paths.query(sample, predicate="dwithin", distance=1)),
                                  len(shadows.query(sample, predicate="intersects"))), expected)


if __name__ == "__main__":
    unittest.main()
