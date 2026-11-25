"""Place Taipei's documented pedestrian bins in the 170 m scenery packs.

Usage: build-city170-pedestrian-bins.py BINS.csv TAIPEI_OSM.json.gz RESTORED_DATA OUTPUT.js
Source: Taipei Department of Environmental Protection, 2026-10-21.
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

from shapely import LineString, Point, STRtree
from shapely.geometry import shape

HERE = Path(__file__).resolve().parent
L = runpy.run_path(str(HERE / 'build-city170-streetlights.py'))
F, H, W, read = (L[key] for key in ('F', 'H', 'W', 'read'))
P = runpy.run_path(str(HERE / 'build-city170-riverside-pavilions.py'))
SOURCE = 'https://data.taipei/dataset/detail?id=a835f3ba-7f50-4b0d-91a6-9df128632d1c'
SHA256 = 'a5dc928c93b99794d31eaf513bc4f82a953937488aece61d004ed0ee5faf91d1'
RADIUS = .43


def read_source(source):
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SHA256:
        raise ValueError('Unexpected Taipei pedestrian bin snapshot')
    reader = csv.DictReader(io.StringIO(raw.decode('cp950')))
    if not {'行政區', '經度', '緯度'}.issubset(reader.fieldnames or ()):
        raise ValueError('Unexpected pedestrian bin fields')
    sites, skipped = [], Counter()
    for row in reader:
        try:
            lon, lat = (round(float(row[field]), 7) for field in ('經度', '緯度'))
        except (TypeError, ValueError):
            skipped['invalid-coordinate'] += 1
            continue
        if not (121.4 < lon < 121.7 and 24.9 < lat < 25.25):
            skipped['invalid-coordinate'] += 1
            continue
        sites.append((row['行政區'], lon, lat))
    return sites, skipped, len(sites) + skipped['invalid-coordinate']


def direction(point, roads, widths, paths):
    nearest = None
    for i in roads.query(point, predicate='dwithin', distance=26):
        line = roads.geometries[i]
        edge = line.distance(point) - widths[i] - .35
        if edge < RADIUS:
            return None
        if edge <= 7:
            road_point = line.interpolate(line.project(point))
            target = Point(2*point.x-road_point.x, 2*point.y-road_point.y)
            if nearest is None or edge < nearest[0]:
                nearest = (edge, target)
    if len(paths.geometries):
        line = paths.geometries[paths.nearest(point)]
        distance = line.distance(point)
        if distance < 1.1:
            return None
        if distance <= 4:
            nearest = (distance, line.interpolate(line.project(point)))
    if nearest is None:
        return None
    target = nearest[1]
    return round(math.degrees(math.atan2(target.y-point.y, target.x-point.x))) % 360


def scenery_obstacles(data):
    _, pedestrian_corridors, restricted_areas = P['walkways'](data)
    masks = list(pedestrian_corridors.geometries) + restricted_areas + P['P']['known_props']()
    walking_routes = {}
    for pack in sorted((data / 'city170-life').glob('p*.json.gz')):
        walking_routes.update(read(pack)['paths'])
    masks.extend(F['project'](LineString(route['points'])).buffer(1.30)
                 for route in walking_routes.values() if route['people'] and len(route['points']) >= 2)
    for filename, radius in [('city170-bike-rack-points.js', .87), ('city170-trail-sign-points.js', .45),
                             ('city170-riverside-pavilion-points.js', 3.0)]:
        module = (HERE.parent / filename).read_text(encoding='utf-8')
        for rows in json.loads(module.split('export default ', 1)[1].strip().removesuffix(';')).values():
            masks.extend(F['project'](Point(lon, lat)).buffer(radius) for lon, lat, *_ in rows.values())
    lights = read(HERE.parent / 'assets/taipei-streetlights.json.gz')['packs']
    masks.extend(F['project'](Point(x/1e7, y/1e7)).buffer(height*.0004)
                 for rows in lights.values() for x, y, height, *_ in rows)
    return STRtree(masks)


def build(source, osm, data):
    coordinates, skipped, inventory = read_source(source)
    sites = sorted(set(coordinates))
    skipped['duplicate'] = len(coordinates) - len(sites)
    cells = read(data / 'city170/grid.json.gz')['features']
    districts = read(data / 'districts.geojson')['features']
    grid = STRtree([shape(f['geometry']) for f in cells])
    areas = STRtree([shape(f['geometry']) for f in districts])
    obstacles, roads, widths, paths, shadows = L['map_geometry'](data, osm)
    mapped_streets = W['obstacle_tree'](data)
    trees = L['tree_trunks'](data)
    legacy = W['legacy_trunks'](data)
    furniture = scenery_obstacles(data)
    survey = F['Survey'](data)
    covered = H['survey_cover'](survey, data)
    points = [F['project'](Point(lon, lat)) for _, lon, lat in sites]
    by_position = STRtree(points)
    by_district, packs = Counter(), defaultdict(dict)
    for (district, lon, lat), point in zip(sites, points, strict=True):
        ll = Point(lon, lat)
        here, cell = areas.query(ll, predicate='within'), grid.query(ll, predicate='within')
        if len(here) != 1 or len(cell) != 1 or districts[here[0]]['properties']['name'] != district:
            skipped['outside-source-district-or-grid'] += 1
            continue
        if len(by_position.query(point, predicate='dwithin', distance=2*RADIUS)) != 1:
            skipped['ambiguous-nearby-bin'] += 1
            continue
        angle = direction(point, roads, widths, paths)
        if angle is None or len(shadows.query(point, predicate='dwithin', distance=RADIUS)):
            skipped['no-clear-surface-path-or-sidewalk'] += 1
            continue
        if any(len(index.query(point, predicate='dwithin', distance=RADIUS))
               for index in (obstacles, mapped_streets, trees, legacy, furniture)) or covered(ll, point, RADIUS):
            skipped['intersecting-structure-tree-or-furniture'] += 1
            continue
        ground = [survey.ground(Point(point.x+x, point.y+y)) for x,y in
                  ((0,0), (-RADIUS,0), (RADIUS,0), (0,-RADIUS), (0,RADIUS))]
        if any(g is None for g in ground) or max(ground)-min(ground) > .15:
            skipped['unproven-ground'] += 1
            continue
        pack = cells[cell[0]]['properties']['pack']
        packs[pack][f'pedestrian-bin/{round(lon*1e7)}/{round(lat*1e7)}'] = [lon, lat, 'pedestrian-bin', 1, angle, 0]
        by_district[district] += 1
    return dict(source=SOURCE, sha256=SHA256, snapshot='2026-10-21', inventory=inventory,
                total=sum(by_district.values()), districts=by_district, exclusions=skipped), packs


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('source', 'osm', 'data', 'output'):
        parser.add_argument(field, type=Path)
    args = parser.parse_args()
    receipt, packs = build(args.source, args.osm, args.data)
    def encode(value):
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    args.output.write_text('// Taipei Department of Environmental Protection · Government Open Data License 1.0.\n'
                           + 'export const pedestrianBinSnapshot='+encode(receipt)+';\n'
                           + 'export default '+encode(packs)+';\n', encoding='utf-8')
    print(encode(receipt))
