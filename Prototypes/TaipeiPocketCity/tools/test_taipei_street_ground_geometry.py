"""Check the shipped polygons; unpacked city170 packs additionally enable a citywide GIS audit.

    uv run --python 3.12 --with shapely==2.2.0 tools/test_taipei_street_ground_geometry.py
"""
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import unittest

import shapely
from shapely.affinity import affine_transform
from shapely.geometry import LineString, Point, Polygon, shape

CITY = Path(__file__).resolve().parents[1]
DATA = Path(os.environ.get('POCKET_TAIPEI_DATA', CITY/'data'))
SLUGS = ('xinyi', 'songshan', 'daan', 'zhongshan', 'datong', 'wanhua', 'zhongzheng',
         'shilin', 'beitou', 'neihu', 'nangang', 'wenshan')
EAST = 111320 * math.cos(math.radians(25.03))
NORTH = 110574


def json_gz(path):
    with gzip.open(path) as src:
        return json.load(src)


def point(lon, lat):
    return Point((lon-121.55)*EAST, (lat-25)*NORTH)


def decode_ring(deltas):
    x = y = 0
    for dx, dy in zip(deltas[::2], deltas[1::2]):
        x, y = x+dx, y+dy
        yield x*EAST/1e6, y*NORTH/1e6


class DistrictGround(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.surfaces = {}
        for slug in SLUGS:
            data = json_gz(CITY/'assets'/f'{slug}-street-ground.json.gz')
            cls.surfaces[slug] = {}
            for kind in ('road', 'walk', 'path'):
                polygons = [Polygon(list(decode_ring(r[0])), [list(decode_ring(h)) for h in r[1:]])
                            for r in data[kind]]
                cls.surfaces[slug][kind] = shapely.union_all(polygons)

    def test_assets_match_the_gis_build_receipts(self):
        receipts = json.loads((CITY/'scripts/taipei-street-ground-receipts.json').read_text())['districts']
        self.assertEqual(set(SLUGS), set(receipts))
        for slug, receipt in receipts.items():
            packed = (CITY/'assets'/f'{slug}-street-ground.json.gz').read_bytes()
            self.assertEqual(hashlib.sha256(packed).hexdigest(), receipt['gzipSHA256'], slug)
            self.assertEqual(hashlib.sha256(gzip.decompress(packed)).hexdigest(), receipt['geometrySHA256'], slug)

    def test_precision_repair_keeps_buildings_and_open_lots_off_the_road(self):
        # Before the floating-precision offset, an 8 cm closing filled entire
        # city blocks, including these known buildings and neighboring open lots.
        for slug, lon, lat in (
            ('daan', 121.5330786, 25.0239191),      # 中央公教大樓
            ('xinyi', 121.5784487, 25.0376489),     # OSM building 588109994
            ('songshan', 121.5599368, 25.0635408),  # OSM building 449085158
            ('xinyi', 121.5808021, 25.0394150),     # Open ground off 大道路96巷
            ('songshan', 121.5595912, 25.0638961),  # Open ground north of 民權東路四段
        ):
            self.assertFalse(self.surfaces[slug]['road'].covers(point(lon, lat)), slug)

    def test_named_streets_cross_real_district_edges(self):
        # Six metres of GIS centreline across each official border.
        fixtures = [
            ('daan', 'xinyi', (121.5628698,25.0135046), (121.5629172,25.0134719)),         # 和平東路三段
            ('songshan', 'zhongshan', (121.5438829,25.0475678), (121.5439402,25.0475823)), # 八德路二段
            ('zhongshan', 'datong', (121.5207708,25.0576612), (121.5208298,25.0576686)),   # 民生西路
            ('wanhua', 'datong', (121.5064889,25.0488337), (121.5065041,25.0488862)),     # 昆明街
            ('daan', 'zhongzheng', (121.5328468,25.0161182), (121.5328883,25.0161571)),   # 羅斯福路三段316巷
            ('shilin', 'beitou', (121.5627064,25.1692486), (121.5626469,25.1692486)),     # 中湖戰備道路
            ('shilin', 'neihu', (121.5534387,25.0923692), (121.5534602,25.0924198)),      # 劍南路
            ('xinyi', 'nangang', (121.5880163,25.0384529), (121.5879598,25.0384360)),     # 福德街251巷7弄
            ('zhongzheng', 'wenshan', (121.5362822,25.0109935), (121.5363156,25.0109486)),# 汀州路三段
        ]
        for a, b, start, end in fixtures:
            line = LineString([point(*start), point(*end)])
            search = line.buffer(1)
            streets = [self.surfaces[k]['road'].intersection(search) for k in (a,b)]
            self.assertTrue(all(road.intersection(line).length > .1 for road in streets), (a,b))
            self.assertLess(line.difference(shapely.union_all(streets)).length, .001, (a,b))

    def test_mountain_paths_and_bridge_decks(self):
        for slug, kind, lon, lat in (
            ('beitou','path',121.5191948,25.1286270),     # 軍艦岩親山步道, unpaved segment
            ('beitou','walk',121.5176112,25.1265732),     # Paved segment of the same walk
            ('wenshan','walk',121.5810462,24.9691865),    # 樟樹步道
            ('shilin','walk',121.5628672,25.1679279),     # 環七星山人車分道
            ('daan','path',121.5550320,25.0162144),        # 福州山步道
        ):
            self.assertTrue(self.surfaces[slug][kind].covers(point(lon,lat)), (slug,kind))
        for slug, lon, lat in (
            ('wanhua',121.4877024,25.0274187), ('datong',121.5074082,25.0634405), # 華翠大橋 / 台北大橋
            ('beitou',121.5480614,25.1501557), ('wenshan',121.5743655,24.9840919),# 紗帽橋 / 渡賢橋
        ):
            self.assertFalse(any(s.covers(point(lon,lat)) for s in self.surfaces[slug].values()), slug)

    @unittest.skipUnless((DATA/'city170/index.json').is_file(), 'requires the unpacked Taipei archive')
    def test_no_material_inside_mapped_buildings_or_water(self):
        interiors = []
        index = json.loads((DATA/'city170/index.json').read_text())
        for entry in index['packs']:
            for feature in json_gz(DATA/'city170'/entry['url'])['features']['features']:
                if feature['properties']['kind'] not in ('water', 'building'):
                    continue
                geometry = shapely.make_valid(shape(feature['geometry']))
                local = affine_transform(geometry, [EAST,0,0,NORTH,-121.55*EAST,-25*NORTH])
                # Polygon simplification and the 0.1 m output grid can shift
                # edges. A half-metre inset isolates actual interior intrusions.
                interiors.append(local.buffer(-.5))
        tree = shapely.STRtree(interiors)
        for slug, surfaces in self.surfaces.items():
            paint = shapely.union_all(list(surfaces.values()))
            for i in tree.query(paint, predicate='intersects'):
                self.assertLess(paint.intersection(interiors[i]).area, .01, (slug, i))


if __name__ == '__main__':
    unittest.main()
