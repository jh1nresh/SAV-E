import importlib
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest

from shapely import LineString, Point, box

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
compact = importlib.import_module("build-taipei-compact-frontages")
F = compact.F


class CompactFrontageTests(unittest.TestCase):
    def choose(self, shift=0, blocked=False, width=3.8):
        origin = F["project"](Point(121.526,25.029))
        x, y = origin.x, origin.y
        building = F["MapFeature"]("building/way/1", {}, box(x-6,y-5,x,y+5))
        road = F["MapFeature"]("road/way/2", {"width":4,"name":"路"},
                               LineString([(x+8,y-10),(x+8,y+10)]))
        pin = Point(x-2,y)
        store = F["MapFeature"]("poi/node/3", {"name":"小店","category":"tea","categoryLabel":"茶",
                                "detail":"路1號1樓","source":"fixture","url":""},
                                Point(*F["REVERSE"].transform(pin.x,pin.y)))
        edge = LineString([(x,y-5),(x,y+5)])
        match = F["Match"](store,building,road,"大安區",edge,0,5,(1,0),"street-address",0)
        streets = F["Streets"]([building],[road])
        samples = []

        def snap(_, row, __):
            row.update(width=width, surveyTile="tile", surveyBase=2, surveyTop=8,
                       wall=[F["geographic"](Point(x+shift,y+dy)) for dy in (-width/2,width/2)])
            return Point(x+shift,y), None

        def corridor(a, b, ground):
            samples.append((a,b,ground))
            return blocked

        survey = SimpleNamespace(snap=snap, buckets=lambda point: [], exposure=lambda *args: 4)
        solver = SimpleNamespace(blocks_corridor=corridor)
        fitted = compact.variant(pin,match,survey,solver,streets,0,compact.Counter())
        return fitted, samples

    def test_short_strip_clears_entire_front_and_retains_identity(self):
        result, checked = self.choose()
        self.assertIsNotNone(result)
        _, row = result
        self.assertEqual(row["id"],"poi/node/3")
        self.assertEqual(row["buildingId"],"building/way/1")
        self.assertEqual(row["evidence"],"compact-measured-street-wall")
        self.assertEqual(row["groundZ"],4)
        self.assertEqual(len(checked),3)

    def test_other_facade_or_unusable_strip_never_becomes_a_storefront(self):
        self.assertIsNone(self.choose(shift=.8)[0])
        self.assertIsNone(self.choose(blocked=True)[0])
        self.assertIsNone(self.choose(width=2.3)[0])


if __name__ == "__main__":
    unittest.main()
