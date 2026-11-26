"""Extract mapped road bridge decks with a connected, painted approach at both ends.

From TaipeiPocketCity, pass the frozen gzip from extract-taipei-osm.py:
  uv run --python 3.12 --with ijson --with shapely==2.2.0 --with mapbox-vector-tile==2.2.0 \
    scripts/build-taipei-road-bridges.py taipei.json.gz

city170 owns unsimplified road lines and their cartographic widths. OSM node IDs
distinguish a true approach from a road that merely passes under a flyover.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import runpy

import ijson
from shapely import STRtree, union_all
from shapely.geometry import LineString, Point, shape

CITY = Path(__file__).resolve().parents[1]
GROUND = runpy.run_path(str(CITY / 'scripts/build-xinyi-street-ground.py'))
off_ground = runpy.run_path(str(CITY / 'scripts/build-city170-grade.py'))['above_or_below_ground']
OFF = {'0', 'no', 'false'}
NON_ROAD = {'track', 'raceway', 'escape', 'construction', 'proposed'}
BRIDGES = {'yes', 'viaduct', 'cantilever', 'arch', 'beam', 'suspension', 'movable', 'truss'}


def read(path):
    return json.loads(gzip.decompress(path.read_bytes()))


def atlas_roads(data):
    roads = {}
    for pack in sorted((data / 'city170').glob('p*.json.gz')):
        for f in read(pack)['features']['features']:
            if f['properties']['kind'] == 'road' and f['geometry']['type'] == 'LineString':
                roads[int(f['id'].split('/')[-1])] = f
    return roads


def drivable(tags):
    return (tags.get('highway') not in NON_ROAD and 'highway' in tags
            and 'railway' not in tags and tags.get('area', 'no') in OFF
            and tags.get('motor_vehicle') != 'no' and tags.get('vehicle') != 'no')


def raised(tags):
    try:
        layer = int(tags.get('layer', '0'))
    except ValueError:
        return False
    return (layer > 0 and tags.get('bridge') in BRIDGES and drivable(tags)
            and tags.get('tunnel', 'no') in OFF and tags.get('indoor', 'no') in OFF
            and tags.get('location') not in ('underground', 'underwater'))


def continuation(bridge, approach):
    """Both lines point out from the shared node. Test their initial bearings."""
    def direction(points):
        line = GROUND['metres'](LineString(points))
        start = line.coords[0]
        end = line.interpolate(min(5, line.length)).coords[0]
        dx, dy = end[0]-start[0], end[1]-start[1]
        length = math.hypot(dx, dy)
        return (dx/length, dy/length) if length else (0, 0)
    a, b = direction(bridge), direction(approach)
    return a[0]*b[0] + a[1]*b[1] < -.5


def load_topology(source, roads):
    ways, junctions = {}, defaultdict(list)
    with gzip.open(source, 'rb') as stream:
        for row in ijson.items(stream, 'elements.item', use_float=True):
            if row['type'] != 'way' or row['id'] not in roads:
                continue
            refs, tags, ident = row['nodes'], row.get('tags', {}), row['id']
            if len(refs) != len(roads[ident]['geometry']['coordinates']):
                raise ValueError(f'Raw geometry and source nodes differ for way {ident}')
            ways[ident] = (tags, refs)
            for i, ref in enumerate(refs):
                junctions[ref].append((ident, i))
    return ways, junctions


def pavement(assets):
    polygons = [GROUND['packed_polygon'](row) for path in sorted(assets.glob('*-street-ground.json.gz'))
                for row in read(path)['road']]
    if not polygons:
        raise ValueError('Missing district road surfaces')
    return STRtree(polygons)


def on_paint(tree, xy):
    ox, oy = GROUND['ORIGIN']
    point = Point(xy[0]*1e6-ox, xy[1]*1e6-oy)
    return bool(len(tree.query(point, predicate='covered_by')))


def joins_paint(approach, paint):
    # Check both the joint and the first few metres continuing away from it.
    line = LineString(approach)
    distance = GROUND['metres'](line).length
    if distance < 2:
        return False
    sample = line.interpolate(min(4, distance)/distance, normalized=True)
    return on_paint(paint, approach[0]) and on_paint(paint, sample.coords[0])


def tied_end(ident, index, ways, roads, junctions, paint):
    refs = ways[ident][1]
    bridge = roads[ident]['geometry']['coordinates']
    if index == -1:
        bridge = bridge[::-1]
    joined = [(way, i) for way, i in junctions[refs[index]] if way != ident]
    # A junction on another bridge or tunnel is not a proven landing.
    if any(off_ground(ways[way][0]) for way, _ in joined):
        return False
    for way, i in joined:
        tags = ways[way][0]
        # Motorway approaches are absent from the ground painter; a crossing road
        # could otherwise supply both paint samples under the elevated highway.
        if not drivable(tags) or tags['highway'] in ('motorway', 'motorway_link'):
            continue
        path = roads[way]['geometry']['coordinates']
        for approach in (path[i:], path[:i+1][::-1]):
            if len(approach) > 1 and continuation(bridge, approach) and joins_paint(approach, paint):
                return True
    return False


def build(source, city):
    data = city/'data'
    with gzip.open(source, 'rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    index = json.loads((data/'city170/index.json').read_bytes())
    if digest != index['source']['provenance']['taipeiExtractUncompressedSHA256']:
        raise ValueError('Use the exact Taipei OSM extract recorded in the city170 manifest')
    roads = atlas_roads(data)
    ways, junctions = load_topology(source, roads)
    paint = pavement(city/'assets')
    districts = json.loads((data/'districts.geojson').read_bytes())['features']
    boundary = union_all([shape(d['geometry']) for d in districts])
    reasons, spans = Counter(), []
    for ident, (tags, refs) in sorted(ways.items()):
        if not raised(tags):
            continue
        f = roads[ident]
        coords = f['geometry']['coordinates']
        line = LineString(coords)
        if not line.is_simple or line.is_ring or not boundary.covers(line):
            reasons['outside city or non-simple'] += 1
            continue
        if not all(tied_end(ident, i, ways, roads, junctions, paint) for i in (0, -1)):
            reasons['unverified approach'] += 1
            continue
        if any(any(w != ident for w, _ in junctions[ref]) for ref in refs[1:-1]):
            reasons['road junction inside span'] += 1
            continue
        props = f['properties']
        spans.append(dict(id=f['id'], name=props.get('name', ''), width=props['width'],
                          line=coords, box=list(line.bounds)))
    identify = runpy.run_path(str(CITY/'scripts/bridge-vector-paint.py'))['certify']
    grades = {span['id']: int(ways[int(span['id'].split('/')[-1])][0]['layer']) for span in spans}
    return identify(spans, grades, city/'cities/map-tiles/taipei-bundled', GROUND['metres'], reasons), reasons


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--city', type=Path, default=CITY)
    parser.add_argument('--out', type=Path, default=CITY/'assets/taipei-road-bridges.json.gz')
    args = parser.parse_args()
    spans, reasons = build(args.source, args.city)
    content = json.dumps(spans, ensure_ascii=False, separators=(',', ':')).encode()
    with args.out.open('wb') as stream:
        with gzip.GzipFile(filename='', fileobj=stream, mode='wb', mtime=0) as encoded:
            encoded.write(content)
    print(f'{len(spans)} spans, exclusions {dict(reasons)}, SHA-256 {hashlib.sha256(content).hexdigest()}')
