"""Place illustrated park drinking stations from the Taipei Water Department snapshot.

Usage: python build-city170-park-water.py SNAPSHOT.csv RESTORED_DATA OUTPUT_JS
Requires the Taipei survey pipeline's numpy, pyproj, shapely, ijson and Pillow.
"""

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import re
import runpy

from shapely import Point, STRtree, points
from shapely.geometry import shape

SOURCE = 'https://data.gov.tw/dataset/128640'
AS_OF = '2026-10-31'
SHA256 = 'b097a6c8deb4d1cb988d8e0e996d13d2e444b1c68fcbab2f3d38290107f48a25'
H = runpy.run_path(str(Path(__file__).with_name('build-city170-hydrants.py')))
F, read = H['F'], H['read']
project = F['project']
CLEARANCE = .46  # greater than the maximum corner distance of the drawn model


def obstacle_tree(data):
    root = Path(__file__).resolve().parents[1]
    grade_module = (root / 'city170-grade-ids.js').read_text(encoding='utf-8')
    grade = json.loads(grade_module.split('export default ', 1)[1].strip().removesuffix(';'))
    off_ground = {f'{key}/{ident}' for key, ids in grade.items() for ident in ids}
    obstacles, seen = [], set()
    for pack in sorted((data / 'city170').glob('p*.json.gz')):
        for feature in read(pack)['features']['features']:
            ident, prop, raw = feature['id'], feature['properties'], feature['geometry']
            if ident in seen:
                continue
            seen.add(ident)
            if prop['kind'] in {'building', 'school', 'water'} and 'Polygon' in raw['type']:
                obstacles.append(project(shape(raw)))
            elif prop['kind'] == 'road' and ident not in off_ground and not H['off_ground'](prop):
                # The measured or default width is already resolved by the street atlas.
                obstacles.append(project(shape(raw)).buffer(prop['width'] / 2))
    return STRtree(obstacles)


def legacy_trunks(data):
    objects = {}
    for pack in sorted((data / 'city170-life').glob('p*.json.gz')):
        objects.update(read(pack)['objects'])
    # Match the base trunk radius in StreetScenery, including older trees
    # that may still render when an inventory tile has not loaded.
    return STRtree([project(Point(x, y)).buffer(.28 * size)
                    for x, y, kind, size, *_ in objects.values() if kind == 'tree'])


def build(source, data):
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SHA256:
        raise ValueError('Unexpected Taipei Water Department snapshot')
    rows = list(csv.DictReader(io.StringIO(raw.decode('cp950'))))
    allowed = [r for r in rows if (r['市別'], r['場所別'], r['狀態']) == ('臺北市', '公園步道', '正常')]
    ids = [r['直飲臺編號'] for r in allowed]
    if len(ids) != len(set(ids)) or any(not re.fullmatch(r'[0-9]{4}[a-z]?', i) for i in ids):
        raise ValueError('Invalid or duplicate station numbers')
    grid = read(data / 'city170/grid.json.gz')['features']
    cells = STRtree([shape(f['geometry']) for f in grid])
    districts = read(data / 'districts.geojson')['features']
    districts_index = STRtree([shape(f['geometry']) for f in districts])
    obstacles = obstacle_tree(data)
    survey = F['Survey'](data)
    covered = H['survey_cover'](survey, data)
    trees = [r for pack in sorted((data / 'city170-nature').glob('p*.json.gz')) for r in read(pack)]
    tree_x, tree_y = F['FORWARD'].transform([r[0] for r in trees], [r[1] for r in trees])
    tree_index = STRtree(points(tree_x, tree_y))
    older_trees = legacy_trunks(data)
    output, counts, by_district, accepted = defaultdict(list), Counter(), Counter(), []
    for r in sorted(allowed, key=lambda row: row['直飲臺編號']):
        if re.search(r'室內|地下室|地下[0-9一二三四]+樓|廁所內|[2-9二三四]樓內', r['設置地點']):
            counts['indoor-note'] += 1
            continue
        try:
            lon, lat = float(r['經度']), float(r['緯度'])
        except (ValueError, TypeError):
            counts['invalid-point'] += 1
            continue
        if not math.isfinite(lon) or not math.isfinite(lat):
            counts['invalid-point'] += 1
            continue
        x, y = round(lon * 1e7), round(lat * 1e7)
        ll = Point(x / 1e7, y / 1e7)
        candidates = districts_index.query(ll, predicate='within')
        cell = cells.query(ll, predicate='within')
        district = r['行政區'].removesuffix('區') + '區'
        if len(candidates) != 1 or len(cell) != 1 or district != districts[candidates[0]]['properties']['name']:
            counts['outside-recorded-district-or-cell'] += 1
            continue
        pt = project(ll)
        if len(obstacles.query(pt, predicate='dwithin', distance=CLEARANCE)):
            counts['mapped-obstacle'] += 1
            continue
        if covered(ll, pt, CLEARANCE):
            counts['surveyed-structure'] += 1
            continue
        if len(tree_index.query(pt, predicate='dwithin', distance=.70)):
            counts['tree-trunk'] += 1
            continue
        if len(older_trees.query(pt, predicate='dwithin', distance=CLEARANCE)):
            counts['legacy-tree-trunk'] += 1
            continue
        if any(pt.distance(previous) < .90 for previous in accepted):
            counts['near-duplicate-site'] += 1
            continue
        accepted.append(pt)
        by_district[district] += 1
        output[grid[cell[0]]['id']].append([r['直飲臺編號'], x, y])
    receipt = dict(source=SOURCE, asOf=AS_OF, sha256=SHA256, records=len(rows), candidates=len(allowed),
                   exclusions=counts, districts=by_district)
    return receipt, output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv', type=Path)
    parser.add_argument('data', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    receipt, cells = build(args.csv, args.data)
    json_text = lambda value: json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    args.output.write_text('// 臺北自來水事業處 · 政府資料開放授權條款-第1版\n'
                           '// Generated by scripts/build-city170-park-water.py.\n'
                           f'export const snapshot={json_text(receipt)};\n'
                           f'export default {json_text(cells)};\n', encoding='utf-8')
    print(json_text(receipt))
