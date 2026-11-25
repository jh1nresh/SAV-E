"""Place illustrative pavilions at matched Taipei riverside inventory points.

Usage: python build-city170-riverside-pavilions.py PAVILIONS.csv REST-SITES.csv RESTORED_DATA OUTPUT_JS
Requires numpy, pyproj, shapely, ijson and Pillow, as used by the existing atlas builders.
"""
import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import runpy

from shapely import Point, STRtree, points
from shapely.affinity import rotate, translate
from shapely.geometry import box, shape

P = runpy.run_path(str(Path(__file__).with_name('build-city170-playgrounds.py')))
W, F, H, read, project = (P[k] for k in ('W', 'F', 'H', 'read', 'project'))
SOURCE = ('https://data.gov.tw/dataset/121649', 'https://data.gov.tw/dataset/143897')
SHA256 = (
    'adfd75e5fa8e27d635a884e3a5e3d0f90b16569bb8f9d45c1f6a763f028b73b8',
    'feac674f4c2010054f3d5036071f43dd7ffecf683633ac6d7aae6fe4cee9a2b2',
)
MODELS = {
    '高灘地休憩涼亭': ('river-pavilion', 2.05, 1.55, 1.55, 1.05),
    '堤頂休憩涼亭': ('river-canopy', 1.55, 1.15, 1.22, .78),
    '自行車道堤頂休憩涼亭': ('river-canopy', 1.55, 1.15, 1.22, .78),
}


def read_source(path, checksum):
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != checksum:
        raise ValueError(f'Unexpected riverside inventory: {path.name}')
    return list(csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))))


def site_key(row, type_field):
    return float(row['Longitude']), float(row['Latitude']), row[type_field]


def walkways(data):
    lines, corridors, fixed, seen = [], [], [], set()
    for filename in sorted((data/'city170').glob('p*.json.gz')):
        for f in read(filename)['features']['features']:
            ident, kind, geometry = f['id'], f['properties']['kind'], f['geometry']
            if ident in seen or kind not in {'walk', 'pitch', 'park'} or H['off_ground'](f['properties']):
                continue
            seen.add(ident)
            if kind == 'walk':
                line = project(shape(geometry))
                corridors.append(line.buffer(f['properties']['width']/2))
                if line.geom_type == 'LineString' and line.length >= 2:
                    lines.append(line)
            elif (kind == 'pitch' or f['properties']['category'] == 'playground') and 'Polygon' in geometry['type']:
                fixed.append(project(shape(geometry)))
    return STRtree(lines), STRtree(corridors), fixed


def heading(trails, center):
    if not len(trails.geometries):
        return None
    line = trails.geometries[trails.nearest(center)]
    if line.distance(center) > 30:
        return None
    u = line.project(center)
    a, b = (line.interpolate(d) for d in (max(0., u-2), min(line.length, u+2)))
    if a.distance(b) < 1:
        return None
    return round(math.degrees(math.atan2(b.y-a.y, b.x-a.x))) % 180


def build(inventory, rest_sites, data):
    rows, rest = (read_source(path, digest) for path, digest in zip((inventory, rest_sites), SHA256))
    refs = Counter(site_key(r, 'Type') for r in rest if r['Type'] in MODELS)
    eligible = [r for r in rows if r['形式'] in MODELS]
    keys = Counter(site_key(r, '形式') for r in eligible)
    cells = read(data/'city170/grid.json.gz')['features']
    cell_index = STRtree([shape(row['geometry']) for row in cells])
    districts = read(data/'districts.geojson')['features']
    district_index = STRtree([shape(row['geometry']) for row in districts])
    trails, corridors, fixed = walkways(data)
    survey = F['Survey'](data)
    covered = H['survey_cover'](survey, data)
    obstacles = W['obstacle_tree'](data)
    known = STRtree(fixed + P['known_props']())
    older_trees = W['legacy_trunks'](data)
    vegetation = [r for path in sorted((data/'city170-nature').glob('p*.json.gz')) for r in read(path)]
    tx, ty = F['FORWARD'].transform([r[0] for r in vegetation], [r[1] for r in vegetation])
    trees = STRtree(points(tx,ty))
    counters, areas, rivers, parks = Counter(), Counter(), Counter(), Counter()
    result = defaultdict(dict)
    placed = []

    for row in sorted(eligible, key=lambda r: int(r['項次'])):
        x, y, declared = key = site_key(row, '形式')
        if refs[key] != 1 or keys[key] != 1:
            counters['unconfirmed-position'] += 1
            continue
        ll = Point(x,y)
        cell = cell_index.query(ll, predicate='within')
        district = district_index.query(ll, predicate='within')
        if len(cell) != 1 or len(district) != 1:
            counters['outside-grid-or-city'] += 1
            continue
        center = project(ll)
        angle = heading(trails, center)
        if angle is None:
            counters['unclear-walkway'] += 1
            continue
        kind, width, depth, leg_x, leg_y = MODELS[declared]
        # A handful of narrow levee sites can fit the compact cut of the same illustration.
        for scale in (1., .79):
            def positioned(geom):
                return translate(rotate(geom, angle, origin=(0,0)), center.x, center.y)
            roof = positioned(box(-width*scale, -depth*scale, width*scale, depth*scale)).buffer(.05)
            legs = [positioned(Point(u*leg_x*scale, v*leg_y*scale)) for u in (-1,1) for v in (-1,1)]
            if len(obstacles.query(roof, predicate='intersects')):
                reason = 'mapped-building-water-or-road'
                continue
            if covered(ll, center, math.hypot(width,depth)*scale+.06):
                reason = 'surveyed-structure'
                continue
            if len(known.query(roof, predicate='intersects')) or any(roof.intersects(other) for other in placed):
                reason = 'existing-object'
                continue
            if len(older_trees.query(roof, predicate='intersects')) or len(trees.query(roof, predicate='dwithin', distance=.35)):
                reason = 'tree-trunk'
                continue
            if any(len(corridors.query(leg, predicate='dwithin', distance=.20)) for leg in legs):
                reason = 'posts-in-walkway'
                continue
            heights = [survey.ground(p) for p in [center,*legs]]
            if any(z is None for z in heights) or max(heights)-min(heights) > .26:
                reason = 'unclear-ground'
                continue
            break
        else:
            counters[reason] += 1
            continue
        placed.append(roof)
        pack = cells[cell[0]]['properties']['pack']
        zid = int(row['項次'])
        result[pack][f'riverside-pavilion/{zid}'] = [x,y,kind,scale,angle,0]
        areas[districts[district[0]]['properties']['name']] += 1
        rivers[row['河系']] += 1
        parks[row['河濱公園']] += 1
    receipt = dict(source=SOURCE, sha256=SHA256, inventoryRows=len(rows), restSiteRows=len(rest),
                   candidatePavilions=len(eligible), pavilions=len(placed), districts=areas, rivers=rivers,
                   parks=parks, exclusions=counters)
    return receipt, result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('inventory','rest_sites','data','output'):
        parser.add_argument(field,type=Path)
    args = parser.parse_args()
    receipt, rows = build(args.inventory,args.rest_sites,args.data)
    def encode(value):
        return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'))
    args.output.write_text('// 臺北市政府工務局水利工程處 · 政府資料開放授權條款-第1版\n'
                           '// Generated by scripts/build-city170-riverside-pavilions.py.\n'
                           f'export const riversidePavilionSnapshot={encode(receipt)};\n'
                           f'export default {encode(rows)};\n',encoding='utf-8')
    print(encode(receipt))
