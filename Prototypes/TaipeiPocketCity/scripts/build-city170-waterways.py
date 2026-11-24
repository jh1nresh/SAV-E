"""Build street-scale open waterways using the Taipei extract used by build-city170.py.

Usage: python build-city170-waterways.py taipei.json.gz /path/to/data output.json.gz
Requires ijson and shapely. One clipped feature per public OSM way.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

import ijson
from shapely import make_valid
from shapely.geometry import LineString, MultiLineString, mapping, shape
from shapely.ops import unary_union


def elements(path):
    with gzip.open(path, 'rb') as stream:
        yield from ijson.items(stream, 'elements.item', use_float=True)


def build(osm, data):
    index = json.loads((data / 'city170/index.json').read_bytes())
    expected = index['source']['provenance']['taipeiExtractUncompressedSHA256']
    with gzip.open(osm, 'rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:
            raise ValueError('Use the Taipei extract recorded in the 170 m atlas')
    districts = json.loads((data / 'districts.geojson').read_bytes())['features']
    boundary = unary_union([make_valid(shape(f['geometry'])) for f in districts])
    # Use the detailed water polygons, not their simplified overview copies.
    waters = []
    for path in sorted((data / 'city170').glob('p*.json.gz')):
        for f in json.loads(gzip.decompress(path.read_bytes()))['features']['features']:
            if f['properties']['kind'] == 'water':
                waters.append(make_valid(shape(f['geometry'])))
    surface = boundary.difference(unary_union(waters))
    ways = []
    for row in elements(osm):
        tags = row.get('tags', {})
        kind = tags.get('waterway')
        if row['type'] != 'way' or kind not in ('stream', 'river', 'canal', 'ditch', 'drain'):
            continue
        if any(tags.get(k, 'no') not in ('no', 'false', '0') for k in ('covered', 'tunnel', 'indoor', 'bridge', 'area')):
            continue
        if (tags.get('layer', '0') != '0' or tags.get('level','0') != '0'
                or tags.get('man_made') == 'pipeline'
                or tags.get('location') in ('underground', 'underwater', 'indoor')):
            continue
        ways.append((row['id'], row['nodes'], kind, tags.get('intermittent') == 'yes'))
    needed = {node for _, refs, _, _ in ways for node in refs}
    coords = {r['id']: (r['lon'], r['lat']) for r in elements(osm) if r['type']=='node' and r['id'] in needed}
    lines = []
    for identity, refs, kind, seasonal in ways:
        if len(refs) < 2:
            continue
        cut = LineString([coords[n] for n in refs]).intersection(surface)
        parts = [g for g in getattr(cut, 'geoms', (cut,)) if g.geom_type == 'LineString' and g.length > .000003]
        if not parts:
            continue
        geom = parts[0] if len(parts)==1 else MultiLineString(parts)
        lines.append(dict(type='Feature', id=f'waterway/way/{identity}', bbox=geom.bounds, geometry=mapping(geom),
                          properties=dict(kind='waterway', category=kind, seasonal=seasonal)))
    return dict(type='FeatureCollection', sourceSHA256=expected, features=lines)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ('osm', 'data', 'output'):
        parser.add_argument(arg, type=Path)
    args = parser.parse_args()
    result = build(args.osm, args.data)
    args.output.write_bytes(gzip.compress(json.dumps(result, separators=(',', ':')).encode(), mtime=0))
    print(len(result['features']), 'open waterway features')
