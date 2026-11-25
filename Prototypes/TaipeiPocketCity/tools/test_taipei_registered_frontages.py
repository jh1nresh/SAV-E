"""Regression tests for corroborating a Taipei ground-floor shop in the registry."""

from io import StringIO
from pathlib import Path
import runpy
import unittest

from shapely import Point


builder = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/build-taipei-registered-frontages.py"))
registry_index = builder["registry_index"]
registered_ground = builder["registered_ground"]


class TaipeiRegisteredGround(unittest.TestCase):
    def rows(self, *records):
        return registry_index(StringIO(
            "商業名稱,商業地址,營業地址（財政資訊中心匯入）\n" + "\n".join(",".join(row) for row in records)
        ))

    def test_both_addresses_agree_on_ground_at_the_same_door(self):
        rows = self.rows(("巷口咖啡", "台北市中山區錦州街１８號一樓", "臺北市中山區測試里錦州街18號1樓"))
        self.assertTrue(registered_ground(rows["巷口咖啡", "中山區", "錦州街", "18"]))
        self.assertNotIn(("巷口咖啡分店", "中山區", "錦州街", "18"), rows)

    def test_other_door_floor_district_or_unspecified_level_does_not_supply_evidence(self):
        address = "臺北市中山區錦州街18號1樓"
        for other in (
            "臺北市中山區錦州街18之1號1樓", "臺北市中山區錦州街18號2樓",
            "臺北市中山區錦州街18號", "臺北市松山區錦州街18號1樓",
        ):
            with self.subTest(other=other):
                rows = self.rows(("巷口咖啡", address, other))
                self.assertFalse(registered_ground(rows["巷口咖啡", "中山區", "錦州街", "18"]))

    def test_duplicate_identity_rejected_even_when_both_rows_match(self):
        address = "臺北市中山區錦州街18號1樓"
        record = ("巷口咖啡", address, address)
        rows = self.rows(record, record)
        self.assertFalse(registered_ground(rows["巷口咖啡", "中山區", "錦州街", "18"]))
        self.assertFalse(registered_ground(()))

    def test_repeated_municipal_point_is_one_location_but_a_different_door_is_ambiguous(self):
        first = (9, Point(2, 3), {})
        repeated = (11, Point(2.01, 3), {})
        distinct = (13, Point(5, 2), {})
        select = builder["unique_municipal_plate"]
        self.assertEqual(select([repeated, first]), first)
        self.assertIsNone(select([repeated, first, distinct]))
        self.assertIsNone(select([]))


if __name__ == "__main__":
    unittest.main()
