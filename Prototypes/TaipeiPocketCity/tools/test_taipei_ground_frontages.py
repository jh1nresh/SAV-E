import importlib
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

from shapely.geometry import LineString, Point, box
from shapely.strtree import STRtree

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
batch = importlib.import_module("build-taipei-ground-frontages")
F = batch.F


class StreetBayTests(unittest.TestCase):
    def candidate(self, walls, *, road_x=7, neighbor=False):
        origin = F["project"](Point(121.52, 25.05))
        def xy(x, y):
            return origin.x + x, origin.y + y
        def line(x, start, end):
            return LineString([xy(x,start),xy(x,end)])
        segments = [line(x,start,end) for x,start,end in walls]
        bucket = F["SurveyWalls"]("test", segments, [2.0]*len(segments), [8.0]*len(segments), STRtree(segments))
        survey = Mock()
        survey.buckets.return_value = [bucket]
        survey.exposure.return_value = 3.0
        road = F["MapFeature"]("road/way/1", {"streetKey":"路", "name":"路", "width":4}, line(road_x,-25,25))
        other = F["MapFeature"]("building/way/2", {}, box(*xy(3,-9),*xy(4,9)))
        streets = F["Streets"]([other] if neighbor else [],[road])
        store = F["MapFeature"]("poi/node/2",dict(name="樣本商店",category="tea",categoryLabel="茶店",
                               detail="路1號1樓", source="fixture",url=""),Point(121.52,25.05))
        return batch.shop_bay(survey,streets,origin,store,None,"路")

    def test_reject_ambiguous_occluded_and_wrong_side(self):
        self.assertIsNotNone(self.candidate([(1,-3,3)]))
        self.assertIsNone(self.candidate([(1,-3,3),(2,-3,3)]))
        self.assertIsNone(self.candidate([(1,-3,3)],neighbor=True))
        self.assertIsNone(self.candidate([(1,-3,3)],road_x=-4))
        self.assertIsNone(self.candidate([(1,1,5)]))

    def test_nearby_cross_source_branch_label_and_address_variants(self):
        def shop(ident, name, source):
            return F["MapFeature"](ident, {"name":name, "source":source}, None)
        def address(road, number):
            return batch.A["Address"](road, number, "")
        for name, alias, road, sub in [
                ("麥當勞-台北麟光", "麥當勞", "和平東路3段406巷", "8-2"),
                ("北海漁村 台北杭州店", "北海漁村", "杭州南路1段", "8-1")]:
            store = shop("inspection/example", name, "衛生局")
            other = shop("poi/node/2", alias, "OpenStreetMap")
            plate = address(road, "8")
            def blocked(peer, where, peer_plate):
                return batch.nearby_identity_conflict(store, Point(0, 0), plate, [(peer, Point(where, 0), peer_plate)])
            self.assertTrue(blocked(other, 8.32, address(road, sub)))
            self.assertFalse(blocked(other, 13, address(road, sub)))
            self.assertFalse(blocked(other, 5, address(road, "9")))
            self.assertFalse(blocked(other, 5, address("另一條街", sub)))
            self.assertFalse(blocked(shop("poi/node/3", alias+"別家分店", "OpenStreetMap"), 5, address(road, sub)))
            self.assertFalse(blocked(shop("poi/node/3", "怡客咖啡", "OpenStreetMap"), 5, address(road, sub)))

    def test_upper_floor_protection_even_if_address_mentions_ground_entrance(self):
        store = F["MapFeature"]("poi/node/42", {"detail":"街1號2樓"}, Point(121.52,25.05))
        self.assertEqual(F["floor_status"](store, {"entrance":"main"}),"upper-or-unknown-floor")
        self.assertFalse(batch.explicit_floor(batch.A["Address"]("街","1",""),{}))


if __name__ == "__main__":
    unittest.main()
