from pathlib import Path
import json
import runpy
import unittest
from types import SimpleNamespace

import numpy as np
from shapely import LineString, Point, STRtree, box

ROOT = Path(__file__).resolve().parents[1]
M = runpy.run_path(str(ROOT / "scripts/build-taipei-survey-frontages.py"))


class SurveyStoreTests(unittest.TestCase):
    def test_roof_triangle_union_excludes_low_skirt_and_separates_disconnected_buildings(self):
        def triangle(coords, z=20):
            return [[x, y, z, 10, 10, 0.5] for x, y in coords]

        tris = np.array(
            [
                triangle([(0, 0), (4, 0), (4, 6)]),
                triangle([(0, 0), (4, 6), (0, 6)]),
                triangle([(8, 0), (12, 0), (12, 6)]),
                triangle([(0, 0), (18, 0), (18, 6)], 10),
            ]
        )
        roofs = M["roof_components"](tris, {"id": "sample", "mx": 0.837, "my": 0.428, "m": 2.755e-8})
        self.assertEqual(len(roofs), 2)
        self.assertTrue(all(r.base == 10 and r.top == 20 for r in roofs))
        self.assertTrue(roofs[0].polygon.disjoint(roofs[1].polygon))

    def test_other_street_endpoint_nearby_does_not_establish_a_parallel_facade(self):
        edge = LineString([(0, 0), (5, 0)])
        self.assertTrue(M["parallel_to_road"](edge, LineString([(-4, -3), (11, -3)]), Point(2, -3)))
        self.assertFalse(M["parallel_to_road"](edge, LineString([(7, -3), (7, 4)]), Point(7, -3)))

    def test_corridor_ending_inside_a_neighbour_fails_even_without_crossing_another_wall(self):
        footprint = box(-6, -12, 6, -1)
        tree = STRtree([footprint])
        layer = object.__new__(M["SurveyFootprints"])
        layer.survey = SimpleNamespace(extents=tree)
        for base, blocked in [(0, True), (8, False)]:
            roof = M["Roof"](footprint, "sample", base, 20)
            layer.tile = lambda _: ([roof], tree)
            self.assertEqual(layer.blocks_corridor(Point(0, -2), Point(0, -4), 2), blocked)

    def test_real_business_and_separate_municipal_address(self):
        text = (ROOT / "taipei-survey-frontages.js").read_text()
        rows = json.loads(text.split("=", 1)[1].strip().removesuffix(";"))
        self.assertEqual(len({r["id"] for r in rows}), len(rows))
        record = next(r for r in rows if r["id"] == "poi/node/11406970597")
        self.assertEqual(
            (record["name"], record["addressNode"], record["street"]),
            ("建春行電器", "node/10907753518", "西園路二段"),
        )
        self.assertEqual(record["pack"], "p220_2036")
        self.assertEqual(record["surveyTile"], "1500_13846")
        self.assertIsNone(record["buildingId"])
        self.assertGreater(record["surveyTop"] - record["groundZ"], 2.4)

    def test_street_corridor_must_clear_both_neighbour_and_conflicting_footprint(self):
        start, road = Point(0, 0), Point(0, -6)
        solver = SimpleNamespace(exposure=lambda *args: 3)

        def corridor(mask, own=0):
            streets = SimpleNamespace(footprints=STRtree([mask]), buildings=[SimpleNamespace(geometry=mask)])
            return M["clear_corridor"](solver, streets, [], start, (0, -1), road, 0, 8, own)

        self.assertEqual(corridor(box(-3, -0.8, 3, 5)), 3)
        self.assertIsNone(corridor(box(-3, -0.8, 3, 5), None))
        self.assertIsNone(corridor(box(-3, -3, 3, 5)))
        self.assertIsNone(corridor(box(-3, -3, 3, -2)))

    def test_segments_must_be_continuous_and_grounded_in_the_same_survey_building(self):
        edge = LineString([(0, 0), (8, 0)])
        roof = SimpleNamespace(base=3, top=14)

        def span(segments, heights):
            lines = [LineString([(x, 0), (xx, 0)]) for x, xx in segments]
            bucket = SimpleNamespace(tree=STRtree(lines), segments=lines, base=[3] * len(lines), top=heights)
            return M["measured_span"](edge, 1, 5, bucket, roof)

        self.assertTrue(span([(0, 3), (3.02, 8)], [14, 14]))
        self.assertFalse(span([(0, 2.7), (3.02, 8)], [14, 14]))
        self.assertFalse(span([(0, 3), (3.02, 8)], [14, 18]))

    def test_entrance_alone_does_not_prove_ground_floor(self):
        store = SimpleNamespace(properties={"detail": "忠孝東路8號"})
        address = M["A"]["split_address"]("忠孝東路8號", "信義區")
        self.assertFalse(M["same_address_floor"](store, {"entrance": "main"}, "信義區", address))
        self.assertTrue(
            M["same_address_floor"](store, {"addr:full": "臺北市信義區忠孝東路8號1樓"}, "信義區", address)
        )
        self.assertFalse(
            M["same_address_floor"](store, {"addr:full": "臺北市信義區忠孝東路9號1樓"}, "信義區", address)
        )


if __name__ == "__main__":
    unittest.main()
