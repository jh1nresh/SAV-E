from collections import Counter
import gzip
import hashlib
import json
import os
from pathlib import Path
import runpy
import unittest

from shapely import union_all
from shapely.geometry import box, LineString, shape

build=runpy.run_path(str(Path(__file__).resolve().parents[1]/"scripts/build-city170-airfield.py"))


class CivilApron(unittest.TestCase):
    def test_clips_and_deduplicates_ground_geometry(self):
        site=box(300000,2700000,300100,2700100)
        road=box(300045,2699990,300055,2700110)
        line=LineString([(299980,2700050),(300120,2700050)])
        data=build["render_surfaces"](site,[line,line],road)
        items=[(row["properties"]["surface"],build["projected"](shape(row["geometry"]))) for row in data["features"]]
        self.assertEqual(Counter(k for k,_ in items),{"apron":2,"taxiway":2})
        covered=union_all([geom for kind,geom in items if kind=="apron"])
        self.assertAlmostEqual(covered.area,9000,delta=13)
        self.assertLess(covered.intersection(road).area,10)
        for kind,geom in items:
            if kind=="taxiway":
                self.assertTrue(covered.buffer(.15).covers(geom))
                self.assertLess(geom.length,44)
        for tags in [{"indoor":"yes"},{"layer":"1"},{"level":"-1"},{"bridge":"yes"},{"military":"yes"}]:
            self.assertFalse(build["ground"](tags))

    @unittest.skipUnless(os.getenv("POCKET_AIRFIELD_ASSET"),"set POCKET_AIRFIELD_ASSET to the generated bundle")
    def test_actual_output_omits_airside_area_beyond_the_civil_passenger_apron(self):
        file=Path(os.environ["POCKET_AIRFIELD_ASSET"])
        raw=file.read_bytes()
        geo=json.loads(gzip.decompress(raw))
        self.assertEqual(set(geo),{"type","features"})
        excluded=box(1803*170,16313*170,1804*170,16314*170)
        parts=[]
        for feature in geo["features"]:
            self.assertEqual(set(feature),{"type","properties","geometry"})
            self.assertEqual(set(feature["properties"]),{"surface"})
            self.assertIn(feature["properties"]["surface"],{"apron","taxiway"})
            geom=build["projected"](shape(feature["geometry"]))
            self.assertTrue(geom.is_valid and geom.disjoint(excluded))
            parts.append((feature["properties"]["surface"],geom))
        fill=union_all([p for k,p in parts if k=="apron"])
        self.assertTrue(65000 < fill.area < 77000)
        for kind,p in parts:
            if kind=="taxiway":
                self.assertTrue(fill.buffer(.2).covers(p))
        print("Coverage",Counter(k for k,_ in parts),"pavement",round(fill.area),"m²",
              hashlib.sha256(raw).hexdigest())


if __name__=="__main__":
    unittest.main()
