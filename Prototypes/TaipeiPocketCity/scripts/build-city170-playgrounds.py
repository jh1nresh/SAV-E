"""Join Taipei's playground inventory to mapped playground boundaries.

Usage: python build-city170-playgrounds.py FACILITY.json RESTORED_DATA OUTPUT_JS
Retains only bounded matches; fittings inside the mapped playground are illustrative.
Uses the same packages as build-city170-park-water.py.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import runpy

from shapely import Point, STRtree, points
from shapely.geometry import shape

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'https://data.gov.tw/dataset/136476'
SHA256 = '390e29b13a6e4146c48032f39c746a0fd38b5c30ed40fc1101342b885104b61b'
W = runpy.run_path(str(ROOT / 'scripts/build-city170-park-water.py'))
F, H, read, project = W['F'], W['H'], W['read'], W['project']
EQUIPMENT = [
    ('組合遊具數量', 'play-tower', 2.02), ('磨石滑梯數量', 'play-slide', 1.96),
    ('鞦韆數量', 'play-swing', 1.94), ('戲沙坑數量', 'play-sand', 1.53),
    ('攀爬組數量', 'play-climb', 1.34), ('搖搖樂數量', 'play-rider', .54),
]
# The source has site points and counts. Search no further than 10 m from each
# site point and keep the whole illustrated object inside the mapped play area.
OFFSETS = sorted((x*x+y*y, x, y) for x in range(-10, 11) for y in range(-10, 11) if x*x+y*y <= 100)


def mapped_areas(data):
    module = (ROOT / 'city170-grade-ids.js').read_text(encoding='utf-8')
    grade = json.loads(module.split('export default ', 1)[1].strip().removesuffix(';'))
    off_ground = {f'{key}/{ident}' for key, ids in grade.items() for ident in ids}
    playgrounds, conflicts, seen = {}, [], set()
    for file in sorted((data / 'city170').glob('p*.json.gz')):
        for feature in read(file)['features']['features']:
            ident, prop, geometry = feature['id'], feature['properties'], feature['geometry']
            if ident in seen or ident in off_ground or H['off_ground'](prop):
                continue
            seen.add(ident)
            if 'Polygon' in geometry['type']:
                if (prop['kind'], prop['category']) == ('park', 'playground'):
                    playgrounds[ident] = project(shape(geometry))
                elif prop['kind'] == 'pitch':
                    conflicts.append(project(shape(geometry)))
            elif prop['kind'] == 'walk':
                conflicts.append(project(shape(geometry)).buffer(prop['width'] / 2))
    return playgrounds, conflicts


def known_props():
    geometries = []
    for filename, radius in [
        ('city170-park-water-points.js', .46), ('city170-bench-points.js', .94),
        ('city170-hydrant-points.js', .30), ('city170-bus-shelter-points.js', 2.25),
    ]:
        module = (ROOT / filename).read_text(encoding='utf-8')
        for rows in json.loads(module.split('export default ', 1)[1].strip().removesuffix(';')).values():
            for _, lon, lat, *_ in rows:
                # Benches retain degree coordinates; the other modules store E7 integers.
                if abs(lon) > 180:
                    lon, lat = lon / 1e7, lat / 1e7
                geometries.append(project(Point(lon, lat)).buffer(radius))
    return geometries


def flat_ground(survey, center, radius):
    samples = [survey.ground(Point(center.x + x*radius, center.y + y*radius))
               for x, y in [(0,0), (-1,0), (1,0), (0,-1), (0,1)]]
    return all(value is not None for value in samples) and max(samples) - min(samples) < .48


def build(source, data):
    payload = source.read_bytes()
    if hashlib.sha256(payload).hexdigest() != SHA256:
        raise ValueError('Unexpected Taipei playground inventory file')
    raw = json.loads(payload.decode('utf-8-sig'))
    rows = sorted({tuple(sorted(row.items())): row for row in raw}.values(),
                  key=lambda row: (row['行政區'], row['公園名稱'], row['X坐標'], row['Y坐標']))
    grid = read(data / 'city170/grid.json.gz')['features']
    grid_tree = STRtree([shape(f['geometry']) for f in grid])
    districts = read(data / 'districts.geojson')['features']
    district_tree = STRtree([shape(f['geometry']) for f in districts])
    playgrounds, conflicts = mapped_areas(data)
    play_ids = list(playgrounds)
    play_tree = STRtree(list(playgrounds.values()))
    obstacles = W['obstacle_tree'](data)
    older_trees = W['legacy_trunks'](data)
    conflicts = STRtree(conflicts + known_props())
    surveyed_trees = [r for f in sorted((data / 'city170-nature').glob('p*.json.gz')) for r in read(f)]
    tx, ty = F['FORWARD'].transform([r[0] for r in surveyed_trees], [r[1] for r in surveyed_trees])
    trees = STRtree(points(tx, ty))
    survey = F['Survey'](data)
    covered = H['survey_cover'](survey, data)
    output, by_district, missing = defaultdict(dict), Counter(), Counter()
    allocations, counts, sites = [], Counter(), set()
    for row in rows:
        if not any(row[k].isdigit() and int(row[k]) for k, _, _ in EQUIPMENT):
            missing['no-modeled-type'] += 1
            continue
        try:
            anchor = Point(float(row['X坐標']), float(row['Y坐標']))
        except (ValueError, TypeError):
            missing['invalid-site'] += 1
            continue
        matches = play_tree.query(anchor, predicate='within')
        if len(matches) != 1:
            missing['without-one-mapped-outline'] += 1
            continue
        area_id = play_ids[matches[0]]
        area = playgrounds[area_id]
        coords = list(area.minimum_rotated_rectangle.exterior.coords)
        dx, dy = max(((b[0]-a[0], b[1]-a[1]) for a, b in zip(coords, coords[1:])),
                     key=lambda e: e[0]**2+e[1]**2)
        angle = round(math.degrees(math.atan2(dy, dx))) % 180
        district_name = row['行政區'].split('(')[0].removesuffix('區') + '區'
        for field, kind, radius in EQUIPMENT:
            count = int(row[field]) if row[field].isdigit() else 0
            for _ in range(count):
                for _, x, y in OFFSETS:
                    cx, cy = anchor.x+x, anchor.y+y
                    ll = Point(*[round(v, 8) for v in F['REVERSE'].transform(cx, cy)])
                    point = project(ll)
                    if not area.contains(point) or area.boundary.distance(point) < radius:
                        continue
                    if any(len(index.query(point, predicate='dwithin', distance=radius))
                           for index in (obstacles, older_trees, conflicts)):
                        continue
                    if len(trees.query(point, predicate='dwithin', distance=radius+.26)):
                        continue
                    if any(point.distance(existing) < radius+margin for existing, margin in allocations):
                        continue
                    if covered(ll, point, radius) or not flat_ground(survey, point, radius):
                        continue
                    cell = grid_tree.query(ll, predicate='within')
                    districts_here = district_tree.query(ll, predicate='within')
                    if len(cell) != 1 or len(districts_here) != 1:
                        continue
                    if districts[districts_here[0]]['properties']['name'] != district_name:
                        continue
                    allocations.append((point, radius))
                    pack = grid[cell[0]]['properties']['pack']
                    key = 'playground/' + area_id + '/' + str(len(allocations))
                    output[pack][key] = [ll.x,ll.y,kind,1,angle,len(allocations) % 4]
                    by_district[district_name] += 1
                    counts[kind] += 1
                    sites.add(area_id)
                    break
                else:
                    missing['does-not-fit'] += 1
    receipt = dict(source=SOURCE, sha256=SHA256, records=len(raw), uniqueRecords=len(rows),
                   mappedPlaygrounds=len(sites), equipment=counts, districts=by_district, exclusions=missing)
    return receipt, output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('source', 'data', 'output'):
        parser.add_argument(field, type=Path)
    args = parser.parse_args()
    receipt, rows = build(args.source, args.data)
    def encode(obj):
        return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    args.output.write_text('// 臺北市公園路燈工程管理處 · 政府資料開放授權條款-第1版\n'
                           '// Generated by scripts/build-city170-playgrounds.py.\n'
                           f'export const playgroundSnapshot={encode(receipt)};\n'
                           f'export default {encode(rows)};\n', encoding='utf-8')
    print(encode(receipt))
