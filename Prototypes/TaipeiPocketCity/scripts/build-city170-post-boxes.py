"""Place documented, freestanding Chunghwa Post boxes in the Taipei scenery.

Usage: build-city170-post-boxes.py BOXES.csv SPECIAL.csv TAIPEI_OSM.json.gz DATA OUTPUT.js
"""

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import runpy

from shapely import Point, STRtree
from shapely.geometry import shape

HERE = Path(__file__).resolve().parent
B = runpy.run_path(str(HERE / 'build-city170-pedestrian-bins.py'))
F, H, L, W, read = (B[key] for key in ('F', 'H', 'L', 'W', 'read'))
SOURCE = 'https://data.gov.tw/dataset/7964'
SPECIAL_SOURCE = 'https://data.gov.tw/dataset/52781'
SHA256 = '2d4ba3db8d3cf219955cc196d2f5f9a629dd22645adc0a8b66db23569cfde07c'
SPECIAL_SHA256 = '4b576cac0204f69df773bedcbb92a7de84ee6fd9dd22367c766bb9bd7110d54c'
RADIUS = B['RADIUS']
TYPES = {('1', '限時信筒'): 'post-box-express', ('3', '普通信筒'): 'post-box-ordinary'}
SLOTS = {('1', '單口'): 1, ('2', '雙口'): 2, ('3', '四口'): 4}
INDOOR = re.compile(r'室內|地下室|地下[一二三四0-9]樓|地下一層|樓內|大廳內|[2-9２-９二三四五六七八九]樓')


def rows(source, digest, fields):
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError(f'Unexpected postal snapshot: {source.name}')
    reader = csv.DictReader(io.StringIO(raw.decode('utf-8-sig')))
    if not set(fields).issubset(reader.fieldnames or ()):
        raise ValueError(f'Unexpected postal fields: {source.name}')
    return list(reader)


def point_from_row(row, fields):
    try:
        lon, lat = (round(float(row[field]), 7) for field in fields)
    except (TypeError, ValueError):
        return None
    return (lon, lat) if 121.4 < lon < 121.7 and 24.9 < lat < 25.25 else None


def read_sources(source, special_source):
    inventory = [row for row in rows(source, SHA256, (
        '縣市', '鄉鎮市區', '類別代號', '類別', '信筒樣式代號', '信筒樣式', 'x座標', 'y座標',
        '路名', '地址描述', '備註',
    )) if row['縣市'] in ('臺北市', '台北市')]
    excluded, by_point = Counter(), defaultdict(list)
    for row in inventory:
        point = point_from_row(row, ('x座標', 'y座標'))
        if point is None:
            excluded['invalid-coordinate'] += 1
            continue
        by_point[point].append(row)
    special = []
    for row in rows(special_source, SPECIAL_SHA256, ('地址', '經度', '緯度')):
        if row['地址'].startswith(('臺北市', '台北市')):
            point = point_from_row(row, ('經度', '緯度'))
            if point is None:
                raise ValueError('Unusable Taipei specialty box location')
            special.append(F['project'](Point(point)))
    return len(inventory), by_point, STRtree(special), excluded


def existing_furniture(data):
    def records(filename):
        module = (HERE.parent / filename).read_text(encoding='utf-8')
        return json.loads(module.split('export default ', 1)[1].strip().removesuffix(';')).values()

    masks = list(B['scenery_obstacles'](data).geometries)
    for pack in records('city170-pedestrian-bin-points.js'):
        masks.extend(F['project'](Point(x, y)).buffer(.43) for x, y, *_ in pack.values())
    for pack in records('city170-bench-points.js'):
        masks.extend(F['project'](Point(x, y)).buffer(.91) for _, x, y, *_ in pack)
    for name, radius in [('city170-hydrant-points.js', .46), ('city170-park-water-points.js', .46)]:
        for pack in records(name):
            masks.extend(F['project'](Point(x/1e7, y/1e7)).buffer(radius) for _, x, y, *_ in pack)
    for pack in records('city170-bus-shelter-points.js'):
        masks.extend(F['project'](Point(x/1e7, y/1e7)).buffer((w*w + d*d)**.5 / 2)
                     for _, x, y, _, _, w, d in pack)
    return STRtree(masks)


def build(source, special_source, osm, data):
    inventory, groups, special, excluded = read_sources(source, special_source)
    sites = sorted(groups)
    positions = [F['project'](Point(pair)) for pair in sites]
    nearby = STRtree(positions)
    cells = read(data / 'city170/grid.json.gz')['features']
    districts = read(data / 'districts.geojson')['features']
    grid = STRtree([shape(f['geometry']) for f in cells])
    areas = STRtree([shape(f['geometry']) for f in districts])
    obstacles, roads, widths, paths, shadows = L['map_geometry'](data, osm)
    clearance = (obstacles, W['obstacle_tree'](data), L['tree_trunks'](data),
                 W['legacy_trunks'](data), existing_furniture(data))
    survey = F['Survey'](data)
    covered = H['survey_cover'](survey, data)
    by_district, by_kind, packs = Counter(), Counter(), defaultdict(dict)
    for pair, point in zip(sites, positions, strict=True):
        records = groups[pair]
        if len(records) != 1 or len(nearby.query(point, predicate='dwithin', distance=2*RADIUS)) != 1:
            excluded['co-located-records'] += len(records)
            continue
        row = records[0]
        kind = TYPES.get((row['類別代號'], row['類別']))
        slots = SLOTS.get((row['信筒樣式代號'], row['信筒樣式']))
        if not kind or not slots:
            excluded['unsupported-box-style'] += 1
            continue
        if len(special.query(point, predicate='dwithin', distance=7)):
            excluded['near-specialty-box'] += 1
            continue
        if INDOOR.search(' '.join(row[field] for field in ('路名', '地址描述', '備註'))):
            excluded['indoor-or-upper-level-note'] += 1
            continue
        district, ll = row['鄉鎮市區'], Point(pair)
        here, cell = areas.query(ll, predicate='within'), grid.query(ll, predicate='within')
        if len(here) != 1 or len(cell) != 1 or districts[here[0]]['properties']['name'] != district:
            excluded['outside-source-district-or-grid'] += 1
            continue
        angle = B['direction'](point, roads, widths, paths)
        if angle is None or len(shadows.query(point, predicate='dwithin', distance=RADIUS)):
            excluded['no-clear-surface-path-or-sidewalk'] += 1
            continue
        if any(len(index.query(point, predicate='dwithin', distance=RADIUS)) for index in clearance) or covered(ll, point, RADIUS):
            excluded['intersecting-structure-tree-or-furniture'] += 1
            continue
        ground = [survey.ground(Point(point.x+x, point.y+y)) for x, y in
                  ((0, 0), (-RADIUS, 0), (RADIUS, 0), (0, -RADIUS), (0, RADIUS))]
        if any(g is None for g in ground) or max(ground)-min(ground) > .15:
            excluded['unproven-ground'] += 1
            continue
        lon, lat = pair
        pack = cells[cell[0]]['properties']['pack']
        packs[pack][f'post-box/{round(lon*1e7)}/{round(lat*1e7)}'] = [lon, lat, kind, 1, angle, slots]
        by_district[district] += 1
        by_kind[kind] += 1
    return dict(source=SOURCE, sha256=SHA256, specialtySource=SPECIAL_SOURCE, specialtySHA256=SPECIAL_SHA256,
                retrieved='2026-11-25', inventory=inventory, total=sum(by_district.values()),
                districts=by_district, types=by_kind, exclusions=excluded), packs


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ('source', 'special_source', 'osm', 'data', 'output'):
        parser.add_argument(arg, type=Path)
    args = parser.parse_args()
    receipt, packs = build(args.source, args.special_source, args.osm, args.data)

    def encode(value):
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))

    args.output.write_text('// Chunghwa Post · Government Open Data License 1.0.\n'
                           + 'export const postBoxSnapshot='+encode(receipt)+';\n'
                           + 'export default '+encode(packs)+';\n', encoding='utf-8')
    print(encode(receipt))
