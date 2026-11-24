import gzip
import hashlib
import importlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

from shapely.geometry import box, mapping

scripts = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(scripts))
benches = importlib.import_module('build-city170-benches')


class MappedBenches(unittest.TestCase):
    def test_only_supported_ground_tags_and_real_orientation(self):
        for extra in [{'access':'private'}, {'foot':'customers'}, {'level':'1'}, {'layer':'-1'},
                      {'location':'bridge'}, {'indoor':'yes'}, {'tourism':'artwork'}]:
            self.assertFalse(benches.eligible({'amenity':'bench', **extra}))
        self.assertTrue(benches.eligible({'amenity':'bench', 'access':'yes', 'level':'0'}))
        self.assertIsNone(benches.facing('several'))
        self.assertEqual(benches.facing('WNW'), 292.5)
        self.assertEqual(benches.facing('360'), 0)

    def test_city_grid_buildings_and_restricted_areas_clip_candidates(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory)
            pack = data / 'city170'
            pack.mkdir()
            def nodes(index,x,y,tag=None):
                return {'type':'node','id':index,'lon':x,'lat':y, 'tags':tag or {}}
            bench = {'amenity':'bench','backrest':'yes','material':'wood','direction':'S'}
            rows = [nodes(i,x,y,bench) for i,(x,y) in enumerate(
                [(1,1), (2,2), (4,4), (6,6), (12,12), (8,8)], start=1)]
            rows.extend(nodes(i+10,x,y) for i,(x,y) in enumerate([(3,3),(5,3),(5,5),(3,5)]))
            rows.extend([{'type':'way','id':20,'nodes':[10,11,12]}, {'type':'way','id':21,'nodes':[12,13,10]},
                         {'type':'relation','id':88,'tags':{'type':'multipolygon','access':'private'},
                          'members':[{'type':'way','ref':i,'role':'outer'} for i in (20,21)]}])
            raw = json.dumps({'elements':rows}).encode()
            source = data / 'source.gz'
            source.write_bytes(gzip.compress(raw))
            (pack/'index.json').write_text(json.dumps({'source':{'provenance':{
                'taipeiExtractUncompressedSHA256':hashlib.sha256(raw).hexdigest()}}}))
            grid = {'id':'0_0','properties':{'name':'區'}, 'geometry':mapping(box(0,0,10,10))}
            (pack/'grid.json.gz').write_bytes(gzip.compress(json.dumps({'features':[grid]}).encode()))
            (data/'districts.geojson').write_text(json.dumps({'features':[dict(grid,geometry=mapping(box(0,0,7,7)))]}))
            building = {'properties':{'kind':'building'},'geometry':mapping(box(1.8,1.8,2.2,2.2))}
            (pack/'p0.json.gz').write_bytes(gzip.compress(json.dumps({'features':{'features':[building]}}).encode()))
            (data/'street-sample.json').write_text(json.dumps({'objects':[[6,6,'bench']]}))
            cells, counts = benches.build(source,data)
            self.assertEqual(cells, {'0_0':[[1,1,1,180,'wood',1]]})
            self.assertEqual(counts, {'區':1})


if __name__ == '__main__':
    unittest.main()
