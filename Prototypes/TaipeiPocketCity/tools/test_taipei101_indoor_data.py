import json
from pathlib import Path
import runpy
import unittest

from shapely.geometry import Point, shape

ROOT = Path(__file__).resolve().parents[1]
build = runpy.run_path(str(ROOT / "scripts/build-taipei101-indoor.py"))


class Taipei101IndoorData(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        module = (ROOT / "taipei101-indoor-data.js").read_text()
        cls.venue = json.loads(module.split("export const taipei101Indoor=", 1)[1].strip().removesuffix(";"))
        cls.levels = {r["label"]: r["features"]["features"] for r in cls.venue["levels"]}
        cls.by_id = {feature["id"]: feature for features in cls.levels.values() for feature in features}

    def test_level_offsets_keep_basement_and_ground_and_refuse_conflicting_public_labels(self):
        actual = build["floor_labels"]
        self.assertEqual(actual({"level": "-1"}), {-1})
        self.assertEqual(actual({"level": "0"}), {1})
        self.assertEqual(actual({"level": "0;1", "level:ref": "1F;2F"}), {1, 2})
        self.assertEqual(actual({"layer": "-1"}), set())
        self.assertEqual(actual({"level": "1", "addr:floor": "1"}), set())

    def test_actual_store_pins_and_unassigned_conflicts(self):
        self.assertEqual(list(self.levels), ["B1", "1F", "6F"])
        restaurant = self.by_id["node/5492157852"]
        self.assertEqual(restaurant["geometry"]["coordinates"], [121.5647547, 25.0343149])
        self.assertEqual(restaurant["properties"]["level"], "B1")
        self.assertIn("/tw/food/", restaurant["properties"]["floorSourceUrl"])
        other = self.by_id["node/7004289008"]
        self.assertEqual(other["properties"]["name"], "Sawadee")
        self.assertEqual(other["properties"]["source"], "OpenStreetMap")
        self.assertNotIn("floorSourceUrl", other["properties"])
        for ident in (4825642721, 7845660511, 12237139465, 13354180106):
            self.assertNotIn(f"node/{ident}", self.by_id)

    def test_real_mall_outline_contains_each_exposed_location(self):
        outline = shape(self.venue["footprint"])
        self.assertEqual(self.venue["id"], "way/64566862")
        self.assertFalse(outline.covers(Point(121.5655, 25.0330)))
        self.assertEqual(len(self.venue["entrances"]["features"]), 3)
        self.assertEqual(
            {f["id"] for f in self.venue["unassignedCorridors"]["features"]},
            {"way/310909471", "way/1339487708"},
        )
        for row in self.venue["entrances"]["features"]:
            self.assertLess(outline.boundary.distance(shape(row["geometry"])), 0.00000001)
            self.assertIsNone(row["properties"]["level"])
        for row in self.venue["unassignedCorridors"]["features"]:
            self.assertTrue(outline.covers(shape(row["geometry"])))
            self.assertIsNone(row["properties"]["level"])
        for row in self.by_id.values():
            self.assertTrue(outline.covers(shape(row["geometry"])))
            self.assertEqual(row["geometry"]["type"], "Point")
        facility = self.by_id["node/13354111405"]
        self.assertEqual(facility["properties"]["kind"], "facility")
        self.assertEqual(facility["properties"]["detail"], "1F員工出入口")

    def test_official_multifloor_tenant_does_not_inherit_a_single_point(self):
        facts = build["official_tenants"](ROOT / "taipei101-directory.js")
        self.assertNotIn("zara", facts)
        self.assertEqual(facts["凱林鐵板燒"][0], "B1")


if __name__ == "__main__":
    unittest.main()
