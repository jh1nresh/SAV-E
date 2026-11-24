"""Check street-side matching and the offline artwork produced by the arcade builder."""
from pathlib import Path
import gzip
import json
import runpy
import unittest

from shapely import STRtree
from shapely.geometry import box,shape
from shapely.ops import unary_union

WEB=Path(__file__).resolve().parents[1]
builder=runpy.run_path(str(WEB/'scripts/build-taipei-arcade-floors.py'))

class ArcadeFloors(unittest.TestCase):
    def test_paving_continues_past_shop_but_stops_at_cross_street(self):
        row={'center':(121.53,25.04),'width':4,'angle':0,'street':'長春路'}
        x,y=builder['to_grid'](*row['center'])
        section=box(x,y-20,x+3,y+20)
        road=box(x-4,y+6,x+6,y+12)
        def pieces(name):
            return [r[1] for r in builder['geometry'](row,[section],[name],STRtree([section]),STRtree([road]))]
        self.assertFalse(pieces('長春路一段'))
        floor,=pieces('長春路 松江路')
        self.assertAlmostEqual(floor.bounds[1],y-20)
        self.assertAlmostEqual(floor.bounds[3],y+6)
        self.assertEqual(floor.intersection(road).area,0)

    def test_shipped_artwork_has_measured_section_and_no_detached_joints(self):
        data=json.load(gzip.open(WEB/'assets/taipei-arcade-floors.json.gz'))
        self.assertEqual(data['sourceSHA256'],builder['OFFICIAL'])
        self.assertGreater(len(data['sectionShops']),0)
        floors={}
        for f in data['features']:
            key=f['properties']['section']
            self.assertTrue(data['sectionShops'][key])
            if f['properties']['kind']=='floor':
                floors.setdefault(key,[]).append(shape(f['geometry']))
        for f in data['features']:
            if f['properties']['kind']=='joints':
                # Rounded WGS84 intersections can move by about one centimetre.
                self.assertTrue(unary_union(floors[f['properties']['section']]).buffer(.00000015).covers(shape(f['geometry'])))
if __name__=='__main__':
    unittest.main()
