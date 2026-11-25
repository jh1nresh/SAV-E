"""Focused tests for the local-footprint fallback used by the survey edge scan."""

from pathlib import Path
import runpy
from types import SimpleNamespace
import unittest

from shapely import LineString, Point, Polygon, STRtree


builder = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/build-taipei-edge-frontages.py"))
locally_supported = builder["locally_supported"]


class LocalFootprint(unittest.TestCase):
    def test_a_second_tenant_disqualifies_single_storey_ground_evidence(self):
        square = Polygon([(0, 0), (8, 0), (8, 8), (0, 8)])
        building = SimpleNamespace(id="building/way/1", properties={"building": "retail"}, geometry=square)
        streets = SimpleNamespace(footprints=STRtree([square]), buildings=[building])
        shop, other = [SimpleNamespace(id=f"poi/node/{i}") for i in (1, 2)]
        pin, second = Point(2, .5), Point(6, 7)
        tags = {"way/1": {"building:levels": "1"}}
        eligible = builder["single_storey_tenant"]
        self.assertTrue(eligible(streets, pin, shop, tags, STRtree([pin]), [shop]))
        self.assertFalse(eligible(streets, pin, shop, tags, STRtree([pin, second]), [shop, other]))

    def test_nearby_spelling_conflicts_are_held_without_merging_pins(self):
        aliases = builder["has_nearby_alias"]
        for names in (("8% ice cafe", "8% Cafe"), ("緑原品", "綠原品")):
            shops = [SimpleNamespace(id=str(i), properties={"name": name}) for i, name in enumerate(names)]
            pin = Point(0, 0)
            self.assertTrue(aliases(shops[0], pin, STRtree([pin, Point(4, 1)]), shops))
            self.assertFalse(aliases(shops[0], pin, STRtree([pin, Point(9, 1)]), shops))

    def test_full_wall_must_follow_the_owning_footprint(self):
        square = Polygon([(0, 0), (8, 0), (8, 8), (0, 8)])
        self.assertTrue(locally_supported(square, LineString([(1, -.1), (4, -.1)]), Point(2, 1), Point(2.5, -.1)))
        self.assertFalse(locally_supported(square, LineString([(1, -.1), (4, -.7)]), Point(2, 1), Point(2.5, -.1)))

    def test_shop_to_wall_must_stay_in_the_owning_footprint(self):
        cutout = Polygon([(0, 0), (6, 0), (6, 6), (4, 6), (4, 2), (2, 2), (2, 6), (0, 6)])
        wall = LineString([(4, 3), (4, 5)])
        self.assertFalse(locally_supported(cutout, wall, Point(1, 4), Point(4, 4)))


if __name__ == "__main__":
    unittest.main()
