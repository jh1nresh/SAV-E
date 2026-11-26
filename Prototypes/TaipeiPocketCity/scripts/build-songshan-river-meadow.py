"""Illustrate the two mapped grasslands at Guanshan Riverside Park from the restored city170 atlas.

Run with: python build-songshan-river-meadow.py DATA OUTPUT.json.gz (Shapely 2).
The drawn clumps describe grass cover. Their positions and sizes aren't an inventory of plants.
"""
import argparse
import gzip
import json
import math
import random
from pathlib import Path

from shapely.affinity import affine_transform
from shapely.geometry import Point, Polygon, box, mapping, shape
from shapely.ops import unary_union

GRASS = ('forest/way/1097615014', 'forest/way/1097615015')
PARK = 'park/way/468371626'
RIVER = 'water/relation/3298928'
REGION = (121.56915, 25.06143, 121.56967, 25.06222)
ORIGIN = (121.5694, 25.0618)
MX, MY = 100907.4, 110773.3  # local ground metres per degree at the plots


def read(path):
    with gzip.open(path, 'rt') if path.suffix == '.gz' else path.open() as stream:
        return json.load(stream)


def metres(geometry):
    return affine_transform(geometry, (MX, 0, 0, MY, -ORIGIN[0]*MX, -ORIGIN[1]*MY))


def feature(kind, identity, geometry, **properties):
    ll = affine_transform(geometry, (1/MX, 0, 0, 1/MY, *ORIGIN))
    return {'type': 'Feature', 'properties': {'kind': kind, 'sourceId': identity, **properties},
            'geometry': mapping(ll)}


def district_paving(area):
    # The displayed district streets include kerb rounding at intersections.
    # Decode the display geometry at its stored microdegree precision.
    packed = read(Path(__file__).resolve().parents[1]/'assets/songshan-street-ground.json.gz')
    masks = []
    for kind in ('road', 'walk', 'path'):
        for row in packed[kind]:
            rings = []
            for values in row:
                x, y = 121550000, 25000000
                ring = []
                for dx, dy in zip(values[::2], values[1::2]):
                    x, y = x+dx, y+dy
                    ring.append((x/1e6, y/1e6))
                rings.append(ring)
            poly = Polygon(rings[0], rings[1:])
            if area.intersects(poly):
                masks.append(metres(poly))
    return masks


def build(data):
    index = read(data/'city170/index.json')
    area = box(*REGION)
    ids = set()
    for pack in index['packs']:
        if area.intersects(box(*pack['bounds'])):
            ids.update([pack['id'], *pack['deps']])
    records = {}
    for pack in sorted(ids):
        records.update((f['id'], f) for f in read(data/f'city170/{pack}.json.gz')['features']['features'])
    park = metres(shape(records[PARK]['geometry']))
    river = metres(shape(records[RIVER]['geometry']))
    district = metres(shape(next(f['geometry'] for f in read(data/'districts.geojson')['features']
                                 if f['properties']['name'] == '松山區')))
    masks = [river, *district_paving(area)]
    for record in records.values():
        props = record['properties']
        kind = props.get('kind')
        if kind not in ('road', 'walk', 'pitch', 'water', 'building'):
            continue
        geometry = shape(record['geometry'])
        if not area.intersects(geometry):
            continue
        mask = metres(geometry)
        if kind in ('road', 'walk'):
            mask = mask.buffer(props['width']/2)
        masks.append(mask)
    obstacles = unary_union(masks)
    features = []
    for identity in GRASS:
        record = records[identity]
        if record['properties'].get('category') != 'grassland':
            raise ValueError(f'{identity} is no longer mapped grassland')
        land = metres(shape(record['geometry']))
        if not district.covers(land) or not park.covers(land):
            raise ValueError(f'{identity} is outside Songshan / Guanshan Riverside Park')
        land = land.difference(obstacles)
        features.append(feature('grassland', identity, land))
        # A fixed inset accounts for the footprint of the largest illustrated clump.
        # Leave gaps along the path, between clumps and around the triangular tips.
        interior = land.buffer(-1.6)
        rng = random.Random(int(identity.split('/')[-1]))
        roots = []
        west, south, east, north = interior.bounds
        for _ in range(math.ceil(land.area*1.7)):
            x, y = rng.uniform(west,east), rng.uniform(south,north)
            position = Point(x,y)
            # Vary spacing in broad patches along the long axis of the bank.
            spacing = 2.15 + .75*(1 + math.sin(.12*y-.05*x))
            if not interior.covers(position) or any(position.distance(p)<spacing for p in roots):
                continue
            roots.append(position)
            features.append(feature('clump', identity, position, form=rng.randrange(3),
                                    scale=round(rng.uniform(.66,1.0),2)))
    return {'type':'FeatureCollection','park':PARK,'river':RIVER,'source':'© OpenStreetMap contributors',
            'features':features}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('data', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.write_bytes(gzip.compress(json.dumps(build(args.data), separators=(',',':')).encode(), mtime=0))
