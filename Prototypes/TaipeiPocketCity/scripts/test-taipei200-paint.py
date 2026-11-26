"""Check surveyed street and river witnesses against the packed map artwork."""
import gzip
import json
import math
from pathlib import Path
import unittest

from pyproj import Transformer
from shapely.geometry import Point, Polygon
from shapely.ops import transform, unary_union

ROOT = Path(__file__).resolve().parents[1] / 'assets/taipei200'
PROJECT = Transformer.from_crs(4326, 3826, always_xy=True).transform


def paint_at(lon, lat, layer):
    point = Point(PROJECT(lon, lat))
    cell_x, cell_y = math.floor(point.x / 200), math.floor(point.y / 200)
    polygons = []
    packs = {}
    for x in range(cell_x - 1, cell_x + 2):
        for y in range(cell_y - 1, cell_y + 2):
            pack_id = f'{x // 8}_{y // 8}'
            if pack_id not in packs:
                packs[pack_id] = json.loads(gzip.decompress((ROOT / f'{pack_id}.json.gz').read_bytes()))
            row = packs[pack_id].get(f'{x}_{y}')
            if row is None:
                continue
            (ox, oy), groups = row[1], row[3]
            east = 20 * 111320 * math.cos(math.radians(oy))
            for parts in groups[layer]:
                rings = []
                for offsets in parts:
                    px = py = 0
                    coords = []
                    for dx, dy in zip(offsets[::2], offsets[1::2]):
                        px += dx
                        py += dy
                        coords.append((ox + px / east, oy + py / (20 * 110574)))
                    rings.append(coords)
                polygons.append(transform(PROJECT, Polygon(rings[0], rings[1:])))
    return point, unary_union(polygons)


class TaipeiStreetPaint(unittest.TestCase):
    def test_marked_crossings_on_tile_edges(self):
        # OSM N5588680260 and N3778174947 both sit within 10 cm of a boundary.
        for coords in [(121.5812702, 25.0442064), (121.5489656, 25.0515523)]:
            with self.subTest(coords=coords):
                point, markings = paint_at(*coords, 1)
                self.assertLess(markings.distance(point), 1.2)

    def test_river_and_apartment_interiors_are_clear(self):
        for coords in [(121.5695333, 25.0639474), (121.5715724, 25.0562558),
                       (121.5753281, 25.0402224), (121.5768374, 25.0502635)]:
            with self.subTest(coords=coords):
                point, paving = paint_at(*coords, 2)
                self.assertFalse(paving.covers(point))

    def test_elevated_road_dash_is_absent_from_ground(self):
        point, lanes = paint_at(121.5589324, 25.0452632, 0)
        self.assertGreater(lanes.distance(point), 1)


if __name__ == '__main__':
    unittest.main()
