"""Illustrate Taipei park exercise equipment at reconciled inventory sites.

Usage: python build-city170-park-fitness.py FIXED.json MECHANICAL.json RESTORED_DATA OUTPUT_JS
Requires the same geospatial packages and frozen atlas as build-city170-playgrounds.py.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import runpy
import unicodedata

from shapely import Point, STRtree, points
from shapely.geometry import LineString, shape

HERE = Path(__file__).resolve().parent
P = runpy.run_path(str(HERE / 'build-city170-playgrounds.py'))
W, F, H, read, project = (P[k] for k in ('W', 'F', 'H', 'read', 'project'))
SOURCE = 'https://data.gov.tw/dataset/136476'
CHECKSUM = {
    'fixed': '84f1a06ec33728d0a6ccbada67f84ce92aa43e14424037ce327954f3cd31aef0',
    'mechanical': 'd5d75d4647132026c30ea16980d8526d97913edfa74604640200d621aa7155c8',
}
TYPES = [
    ('水平吊梯', 'fitness-ladder', 1.27),
    ('雙槓', 'fitness-parallel', 1.04),
    ('單槓', 'fitness-pullup', .98),
    ('扭腰器', 'fitness-twister', .98),
    ('腹肌板', 'fitness-bench', .95),
    ('大轉輪', 'fitness-wheel', .89),
    ('滑雪器', 'fitness-ski', .88),
    ('漫步機', 'fitness-walker', .87),
    ('划船器', 'fitness-rower', .87),
    ('上肢牽引器', 'fitness-pull', .83),
    ('伸腰伸背器', 'fitness-back', .69),
    ('肩關節康復器', 'fitness-shoulder', .65),
]
SEARCH_RADIUS = 6
SEPARATION = .20
PEDESTRIAN_SWEEP = 1.30  # Umbrella radius and offset at the largest rendered scale shared with scenery.
OFFSETS = [(x, y) for distance, x, y in P['OFFSETS'] if distance <= SEARCH_RADIUS**2]


def normalized_name(text):
    return ''.join(unicodedata.normalize('NFKC', text).replace('臺', '台').split())


def site_inventory(paths):
    sites = defaultdict(Counter)
    records = {}
    for key, file in paths.items():
        raw = file.read_bytes()
        if hashlib.sha256(raw).hexdigest() != CHECKSUM[key]:
            raise ValueError(f'Unexpected Taipei {key} exercise equipment inventory')
        data = json.loads(raw.decode('utf-8-sig'))
        records[key] = len(data)
        for row in data:
            name = normalized_name(row['公園名稱'])
            district = row['行政區'].split('(')[0].removesuffix('區') + '區'
            try:
                x, y = float(row['X坐標']), float(row['Y坐標'])
            except (ValueError, TypeError):
                continue
            if not name or not (math.isfinite(x) and math.isfinite(y)):
                continue
            count = {kind: int(row.get(field+'數量', '0')) for field, kind, _ in TYPES}
            # Both sources can repeat the same device counts at the same site.
            site = sites[district, name, x, y]
            for kind, value in count.items():
                if value > site[kind]:
                    site[kind] = value
    return records, sites


def mapped_parks(data):
    parks = {}
    for file in sorted((data / 'city170').glob('p*.json.gz')):
        for feature in read(file)['features']['features']:
            ident, prop, raw = feature['id'], feature['properties'], feature['geometry']
            if (ident in parks or (prop['kind'], prop['category']) != ('park', 'park')
                or 'Polygon' not in raw['type'] or not prop.get('name')
                or prop.get('access') not in H['OPEN_ACCESS'] or H['off_ground'](prop)):
                continue
            polygon = project(shape(raw))
            if polygon.is_valid and not polygon.is_empty:
                parks[ident] = (normalized_name(prop['name']), polygon)
    return parks


def angle_of(area):
    coords = list(area.minimum_rotated_rectangle.exterior.coords)
    dx, dy = max(((b[0]-a[0], b[1]-a[1]) for a,b in zip(coords,coords[1:])),
                 key=lambda edge: edge[0]**2+edge[1]**2)
    return round(math.degrees(math.atan2(dy, dx))) % 180


def placement_indexes(data):
    playgrounds, walkways_and_pitches = P['mapped_areas'](data)
    routes = {}
    for file in sorted((data/'city170-life').glob('p*.json.gz')):
        routes.update(read(file)['paths'])
    animated_walkways = [project(LineString(path['points'])).buffer(PEDESTRIAN_SWEEP)
                         for path in routes.values() if path['people'] and len(path['points']) >= 2]
    walk_index = STRtree(walkways_and_pitches + animated_walkways + list(playgrounds.values()) + P['known_props']())
    inventory = [r for file in sorted((data/'city170-nature').glob('p*.json.gz')) for r in read(file)]
    tx, ty = F['FORWARD'].transform([r[0] for r in inventory], [r[1] for r in inventory])
    tree_index = STRtree(points(tx, ty))
    return (W['obstacle_tree'](data), W['legacy_trunks'](data), walk_index), tree_index


def candidates(site, area, radius, districts, grid, indexes, survey, placed):
    district, _, x, y = site
    district_rows, district_tree = districts
    cell_rows, cell_tree = grid
    obstacles, tree_index = indexes
    terrain, covered = survey
    for ox, oy in OFFSETS:
        lonlat = F['REVERSE'].transform(x + ox, y + oy)
        ll = Point(*(round(v, 8) for v in lonlat))
        point = project(ll)
        if not area.contains(point) or area.boundary.distance(point) < radius:
            continue
        if any(len(index.query(point, predicate='dwithin', distance=radius)) for index in obstacles):
            continue
        if len(tree_index.query(point, predicate='dwithin', distance=radius+.26)):
            continue
        if any(point.distance(other) < radius+margin+SEPARATION for other, margin in placed):
            continue
        if covered(ll, point, radius) or not P['flat_ground'](terrain, point, radius):
            continue
        cell, administrative = (index.query(ll, predicate='within') for index in (cell_tree, district_tree))
        if len(cell) != 1 or len(administrative) != 1:
            continue
        if district_rows[administrative[0]]['properties']['name'] != district:
            continue
        yield point, ll, cell_rows[cell[0]]['properties']['pack']


def build(paths, data):
    records, sites = site_inventory(paths)
    park_rows = list(mapped_parks(data).items())
    parks = STRtree([area for _, (_, area) in park_rows])
    grid_rows = read(data/'city170/grid.json.gz')['features']
    district_rows = read(data/'districts.geojson')['features']
    grid = grid_rows, STRtree([shape(f['geometry']) for f in grid_rows])
    districts = district_rows, STRtree([shape(f['geometry']) for f in district_rows])
    indexes = placement_indexes(data)
    terrain = F['Survey'](data)
    survey = terrain, H['survey_cover'](terrain, data)
    output, by_kind, by_district, missed = defaultdict(dict), Counter(), Counter(), Counter()
    placed, park_ids, included_sites = [], set(), set()

    for site, counts in sorted(sites.items()):
        district, name, x, y = site
        if not counts:
            missed['no-modeled-type'] += 1
            continue
        matches = [i for i in parks.query(Point(x,y), predicate='within') if park_rows[i][1][0] == name]
        if len(matches) != 1:
            missed['without-one-named-park'] += 1
            continue
        ident, (_, area) = park_rows[matches[0]]
        angle = angle_of(area)
        for _, kind, radius in TYPES:
            for _ in range(counts[kind]):
                placement = next(candidates(site, area, radius, districts, grid, indexes, survey, placed), None)
                if placement is None:
                    missed['equipment-without-clear-position'] += 1
                    continue
                point, ll, pack = placement
                placed.append((point,radius))
                number = len(placed)
                output[pack][f'fitness/{ident}/{number}'] = [ll.x,ll.y,kind,1,angle,(number-1)%4]
                by_kind[kind] += 1
                by_district[district] += 1
                park_ids.add(ident)
                included_sites.add(site)
    receipt = dict(source=SOURCE, sha256=CHECKSUM, records=records, uniqueSites=len(sites),
                   renderedSites=len(included_sites), mappedParks=len(park_ids), maxOffsetMetres=SEARCH_RADIUS,
                   equipment=by_kind, districts=by_district, exclusions=missed)
    return receipt, output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('fixed', 'mechanical', 'data', 'output'):
        parser.add_argument(field, type=Path)
    args = parser.parse_args()
    receipt, rows = build({'fixed': args.fixed, 'mechanical': args.mechanical}, args.data)
    def encode(value):
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    args.output.write_text('// 臺北市公園路燈工程管理處 · 政府資料開放授權條款-第1版\n'
                           '// Generated by scripts/build-city170-park-fitness.py.\n'
                           f'export const fitnessSnapshot={encode(receipt)};\n'
                           f'export default {encode(rows)};\n', encoding='utf-8')
    print(encode(receipt))
