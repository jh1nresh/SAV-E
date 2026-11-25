"""Index mapped above-ground Taipei hydrants with a clear street-level position.

Usage: python build-city170-hydrants.py taipei.json.gz restored-data city170-hydrant-points.js
Uses the existing Taipei OSM extract, districts, 170 m cells, terrain and survey mesh.
"""
import argparse
from collections import Counter, defaultdict
from functools import lru_cache
import gzip
import hashlib
import json
import math
from pathlib import Path
import runpy

import ijson
import numpy as np
from shapely import Point, STRtree
from shapely.geometry import shape

HERE = Path(__file__).resolve().parent
F = runpy.run_path(str(HERE / 'build-city170-frontages.py'))
off_ground = runpy.run_path(str(HERE / 'build-city170-grade.py'))['above_or_below_ground']
read = F['load_json']
OPEN_ACCESS = {None, 'yes', 'public', 'permissive', 'designated'}


def eligible(tags):
    return (tags.get('emergency') == 'fire_hydrant' and tags.get('fire_hydrant:type') == 'pillar'
            and not off_ground(tags) and tags.get('access') in OPEN_ACCESS
            and tags.get('location') in {None, 'outdoor', 'outdoors', 'surface', 'ground'}
            and all(tags.get(k) in {None, '0', 'ground', 'ground_floor', '1樓', '1F', '1f'}
                    for k in ('floor', 'addr:floor'))
            and tags.get('fire_hydrant:type:zh') in {None, '地上式消防栓'}
            and not tags.get('fixme') and tags.get('disused', 'no') == 'no'
            and tags.get('abandoned', 'no') == 'no')


def ground_street(tags):
    return (tags.get('highway') in {'residential', 'unclassified', 'service', 'tertiary', 'secondary',
                                     'primary', 'living_street', 'pedestrian', 'footway', 'path', 'steps'}
            and not off_ground(tags) and tags.get('access') in OPEN_ACCESS
            and tags.get('foot') in OPEN_ACCESS and tags.get('service') not in {'driveway', 'parking_aisle'})


def footprint_hits(triangles, x, y, clearance=.30):
    # This XY projection also covers sloped roofs and open-sided elevated structures.
    a, b, c = triangles[:, 0], triangles[:, 1], triangles[:, 2]
    ab, bc, ca = b - a, c - b, a - c
    signed_area = ab[:, 0] * (-ca[:, 1]) - ab[:, 1] * (-ca[:, 0])
    def side(start, edge):
        return edge[:, 0] * (y - start[:, 1]) - edge[:, 1] * (x - start[:, 0])
    e1, e2, e3 = side(a, ab), side(b, bc), side(c, ca)
    inside = (((e1 >= -.002) & (e2 >= -.002) & (e3 >= -.002)) |
              ((e1 <= .002) & (e2 <= .002) & (e3 <= .002)))
    if np.any((np.abs(signed_area) > .025) & inside):
        return True
    # A pillar's flange extends beyond the source point. Reject overlapping
    # edges as well, including vertical mesh walls whose projection is a line.
    for start, edge in ((a, ab), (b, bc), (c, ca)):
        dx, dy = x - start[:, 0], y - start[:, 1]
        denom = np.sum(edge * edge, axis=1)
        t = np.clip((dx * edge[:, 0] + dy * edge[:, 1]) / np.maximum(denom, 1e-12), 0, 1)
        if np.any((dx - t * edge[:, 0]) ** 2 + (dy - t * edge[:, 1]) ** 2 <= clearance ** 2):
            return True
    return False


def survey_cover(survey, root):
    @lru_cache(maxsize=48)
    def triangles(index):
        tile = survey.tiles[index]
        with gzip.open(root / '200' / (tile['id'] + '.bin.gz'), 'rb') as stream:
            rows = np.frombuffer(stream.read(), dtype='<f4').reshape(-1, 3, 6)
        return rows[:, :, :2].astype('float64')

    def covered(ll, point, clearance=.30):
        mx = (ll.x + 180) / 360
        my = (1 - math.asinh(math.tan(math.radians(ll.y))) / math.pi) / 2
        for idx in survey.extents.query(point, predicate='dwithin', distance=clearance+.02):
            tile = survey.tiles[idx]
            if footprint_hits(triangles(int(idx)), (mx - tile['mx']) / tile['m'], (tile['my'] - my) / tile['m'], clearance):
                return True
        return False
    return covered


def build(source, data):
    index = read(data / 'city170/index.json')
    digest = index['source']['provenance']['taipeiExtractUncompressedSHA256']
    with gzip.open(source, 'rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != digest:
            raise ValueError('Wrong Taipei OSM snapshot')
    grid = read(data / 'city170/grid.json.gz')['features']
    cells = STRtree([shape(f['geometry']) for f in grid])
    ds = read(data / 'districts.geojson')['features']
    districts = STRtree([shape(f['geometry']) for f in ds])
    masks, ways, seen = [], {}, set()
    for path in sorted((data / 'city170').glob('p*.json.gz')):
        for f in read(path)['features']['features']:
            k, kind = f['id'], f['properties']['kind']
            if k in seen:
                continue
            seen.add(k)
            if kind in {'building', 'water', 'school'} and f['geometry']['type'] in {'Polygon', 'MultiPolygon'}:
                masks.append(shape(f['geometry']))
            elif kind in {'road', 'walk'} and '/way/' in k:
                ways[int(k.rsplit('/', 1)[1])] = f
    sources, road_ids, counts = [], set(), Counter()
    with gzip.open(source, 'rb') as stream:
        for row in ijson.items(stream, 'elements.item', use_float=True):
            tags = row.get('tags', {})
            if row['type'] == 'way' and row['id'] in ways and ground_street(tags):
                road_ids.add(row['id'])
            if row['type'] != 'node' or tags.get('emergency') != 'fire_hydrant':
                continue
            counts['source-hydrants'] += 1
            if eligible(tags):
                sources.append((row['id'], Point(row['lon'], row['lat'])))
    excluded = STRtree(masks)
    streets = STRtree([F['project'](shape(ways[n]['geometry'])) for n in sorted(road_ids)])
    survey = F['Survey'](data)
    covered = survey_cover(survey, data)
    tentative = []
    for ident, ll in sorted(sources):
        district = districts.query(ll, predicate='intersects')
        cell = cells.query(ll, predicate='intersects')
        if not len(district) or not len(cell):
            continue
        counts['city-eligible-pillar'] += 1
        point = F['project'](ll)
        if len(excluded.query(ll, predicate='dwithin', distance=.0000031)):
            counts['inside-osm-mask'] += 1
            continue
        if not len(streets.query(point, predicate='dwithin', distance=14)):
            counts['without-public-ground-street'] += 1
            continue
        if covered(ll, point):
            counts['inside-survey-mesh'] += 1
            continue
        if survey.ground(point) is None:
            counts['no-ground-sample'] += 1
            continue
        tentative.append((ident, ll, point, min(grid[i]['id'] for i in cell),
                          min(ds[i]['properties']['name'] for i in district)))
    groups, by_district = defaultdict(list), Counter()
    close = STRtree([r[2] for r in tentative])
    for ident, ll, point, cell, district in tentative:
        if len(close.query(point, predicate='dwithin', distance=1.1)) != 1:
            counts['overlapping-nodes'] += 1
            continue
        groups[cell].append([ident, round(ll.x * 1e7), round(ll.y * 1e7)])
        by_district[district] += 1
    return dict(sorted(groups.items())), counts, by_district


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ('source', 'data', 'output'):
        parser.add_argument(arg, type=Path)
    args = parser.parse_args()
    groups, counts, districts = build(args.source, args.data)
    args.output.write_text('// OpenStreetMap contributors · ODbL. Source node, longitude E7, latitude E7 in each 170 m cell.\n'
                           '// Generated with build-city170-hydrants.py.\nexport default {\n' +
                           ',\n'.join(json.dumps(k) + ':' + json.dumps(v, separators=(',', ':')) for k, v in groups.items()) + '\n};\n')
    print(json.dumps({'nodes': sum(districts.values()), 'cells': len(groups), 'districts': districts,
                      'screen': counts}, ensure_ascii=False, sort_keys=True))
