"""Index mapped outdoor bench nodes into the existing 170 m Taipei grid (OSM, ODbL).

Usage: python build-city170-benches.py taipei.json.gz restored-data city170-bench-points.js
Requires ijson and shapely. The gzip input must match the public atlas snapshot.
"""
import argparse
import collections
import gzip
import hashlib
import importlib
import json
import math
from pathlib import Path

import ijson
from shapely import LineString, Point, Polygon, STRtree, polygonize
from shapely.geometry import shape

off_ground = importlib.import_module('build-city170-grade').above_or_below_ground
access_allowed = {'', 'public', 'yes', 'permissive', 'designated'}
compass = 'N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW'.split()


def eligible(tags):
    return (tags.get('amenity') == 'bench' and not off_ground(tags)
            and tags.get('access', '') in access_allowed
            and tags.get('foot', '') in access_allowed
            and tags.get('location', '') in {'', 'surface', 'outdoor', 'outdoors', 'ground'}
            and tags.get('tourism') != 'artwork' and not tags.get('building')
            and tags.get('bench:type', '') not in {'swing', 'log'})


def facing(value):
    if value.upper() in compass:
        return compass.index(value.upper()) * 22.5
    try:
        number = float(value)
        return number % 360 if math.isfinite(number) and 0 <= number <= 360 else None
    except ValueError:
        return None


def material_class(tag):
    parts = set(tag.lower().split(';'))
    if 'wood' in parts:
        return 'wood'
    if parts & {'stone', 'concrete', 'granite', 'marble'}:
        return 'stone'
    if parts & {'metal', 'iron', 'steel', 'stainless_steel'}:
        return 'metal'
    return 'other'


def raw(source):
    with gzip.open(source, 'rb') as stream:
        yield from ijson.items(stream, 'elements.item', use_float=True)


def build(source, data):
    index = json.loads((data / 'city170/index.json').read_bytes())
    provenance = index['source']['provenance']
    with gzip.open(source, 'rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != provenance['taipeiExtractUncompressedSHA256']:
            raise ValueError('Wrong Taipei OSM snapshot')

    grid = json.loads(gzip.decompress((data / 'city170/grid.json.gz').read_bytes()))['features']
    cells = STRtree([shape(f['geometry']) for f in grid])
    district_rows = json.loads((data / 'districts.geojson').read_bytes())['features']
    districts = STRtree([shape(f['geometry']) for f in district_rows])
    masks = []
    for path in sorted((data / 'city170').glob('p*.json.gz')):
        for f in json.loads(gzip.decompress(path.read_bytes()))['features']['features']:
            if f['properties']['kind'] in {'building', 'water', 'school'} and f['geometry']['type'] in {'MultiPolygon', 'Polygon'}:
                masks.append(shape(f['geometry']))

    # A node often omits the access or indoor condition on its enclosing area.
    candidates, restricted, shell_members, ways = {}, [], set(), {}
    restricted_relations = []
    for r in raw(source):
        t = r.get('tags', {})
        if r['type'] == 'node' and eligible(t):
            candidates[r['id']] = (Point(r['lon'], r['lat']), t)
        if r['type'] in {'way', 'relation'}:
            blocked = (t.get('access', '') not in access_allowed or t.get('foot', '') not in access_allowed
                       or t.get('landuse') in {'military', 'construction'}
                       or t.get('indoor', 'no') != 'no')
            if r['type'] == 'way':
                if blocked and r['nodes'][0] == r['nodes'][-1] and len(r['nodes']) >= 4:
                    restricted.append(r['nodes'])
            elif blocked and t.get('type') == 'multipolygon':
                restricted_relations.append([m['ref'] for m in r.get('members', []) if m['type'] == 'way'
                                             and m.get('role', '') in ('outer', '')])
    for relation in restricted_relations:
        shell_members.update(relation)
    if shell_members:
        for row in raw(source):
            if row['type'] == 'way' and row['id'] in shell_members:
                ways[row['id']] = row['nodes']
    needed = {ref for line in [*restricted, *ways.values()] for ref in line}
    nodes = {}
    for r in raw(source):
        if r['type'] == 'node' and r['id'] in needed:
            nodes[r['id']] = (r['lon'], r['lat'])
    for refs in restricted:
        if all(ref in nodes for ref in refs):
            masks.append(Polygon([nodes[ref] for ref in refs]))
    # Keep all outer rings of access-restricted multipolygons. Excluding a courtyard
    # conservatively is preferable to placing a schematic seat in a private facility.
    for relation in restricted_relations:
        segments = [LineString([nodes[n] for n in ways[w]]) for w in relation
                    if w in ways and len(ways[w]) >= 2 and all(n in nodes for n in ways[w])]
        masks.extend(polygonize(segments).geoms)

    authored = []
    for path in sorted(data.glob('street-*.json')):
        payload = json.loads(path.read_bytes())
        if isinstance(payload, dict):
            authored.extend(row[:2] for row in payload.get('objects', []) if row[2] == 'bench')
    excluded = STRtree(masks)
    groups = collections.defaultdict(list)
    district_counts = collections.Counter()
    for osm_id, (pt, tags) in sorted(candidates.items()):
        cell = cells.query(pt, predicate='intersects')
        district = districts.query(pt, predicate='intersects')
        if not len(cell) or not len(district) or len(excluded.query(pt, predicate='intersects')):
            continue
        if any(math.hypot((pt.x - x) * 100800, (pt.y - y) * 110574) < 5 for x, y in authored):
            continue
        key = min(grid[i]['id'] for i in cell)
        groups[key].append([osm_id, pt.x, pt.y, facing(tags.get('direction', '')),
                            material_class(tags.get('material', '')), int(tags.get('backrest') == 'yes')])
        district_counts[min(district_rows[i]['properties']['name'] for i in district)] += 1
    return dict(sorted(groups.items())), district_counts


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ('source', 'data', 'output'):
        parser.add_argument(arg, type=Path)
    args = parser.parse_args()
    groups, counts = build(args.source, args.data)
    args.output.write_text('// OpenStreetMap contributors · ODbL. Generated by build-city170-benches.py.\n'
                           '// Each 170 m cell holds [OSM node, lon, lat, facing degrees or null, material, mapped backrest].\n'
                           'export default {\n' + ',\n'.join(json.dumps(k) + ':' + json.dumps(v, separators=(',', ':'))
                                                          for k, v in groups.items()) + '\n};\n')
    print(json.dumps({'nodes': sum(counts.values()), 'cells': len(groups), 'districts': counts},
                     sort_keys=True, ensure_ascii=False))
