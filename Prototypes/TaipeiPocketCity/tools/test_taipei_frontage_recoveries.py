"""Regressions for evidence required before a shop may be drawn on a surveyed wall."""
from pathlib import Path
import runpy
import unittest
from types import SimpleNamespace as NS
from shapely.geometry import LineString, Point, box

module = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/build-city170-frontage-recoveries.py"))
MapFeature = module["F"]["MapFeature"]


class RecoveredFrontages(unittest.TestCase):
    def test_ground_and_exact_doorplate(self):
        self.assertEqual(module["address"]({"detail": "臺北市內湖區舊宗路一段135號1樓"}, "內湖區"),
                         module["address"]({"addr:street":"舊宗路1段", "addr:housenumber":"135"}, "內湖區"))
        self.assertNotEqual(module["address"]({"detail": "舊宗路一段135之1號1樓"}, "內湖區"),
                            module["address"]({"addr:street":"舊宗路1段", "addr:housenumber":"135"}, "內湖區"))
        self.assertFalse(module["explicit_ground"]({"level":"1"}))
        self.assertFalse(module["explicit_ground"]({}))
        self.assertTrue(module["explicit_ground"]({"level":"0"}))

    def test_do_not_select_one_of_two_unmarked_or_private_entrances(self):
        store = MapFeature("poi/way/1", {"detail":""}, Point(0, 0))
        nodes = {i:(Point(i,0), {"entrance":"yes"}) for i in (1,2)}
        choose = module["unique_entry"]
        self.assertIsNone(choose([1,2], nodes, store))
        nodes[2][1]["entrance"] = "main"
        self.assertEqual(choose([1,2], nodes, store)[0], 2)
        nodes[2][1]["access"] = "private"
        self.assertIsNone(choose([2], nodes, store))

    def test_a_missing_survey_wall_cannot_resolve_two_plausible_fronts(self):
        footprint=box(0,0,10,10)
        edges=[LineString([a,b]) for a,b in zip(footprint.exterior.coords,footprint.exterior.coords[1:])]
        def match(store, point, tags, building, inside, district):
            index=next(i for i,edge in enumerate(edges) if edge.distance(point)<.01)
            return (NS(edge=edges[index],edge_number=index),None) if index<2 else (None,"not facing")
        survey=NS(snap=lambda *_:self.fail("ambiguous OSM geometry must be rejected before consulting survey coverage"))
        result=module["exposed_front"](NS(find_wall=match),survey,None,NS(geometry=footprint),{},"大安區",None)
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
