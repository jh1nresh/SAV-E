"""Build Pocket City road surfaces from unpacked Taipei GIS and 170 m cell data.

From TaipeiPocketCity, using the ground geometry from the accepted Songyan scene:
    uv run --python 3.12 --with shapely==2.2.0 scripts/build-xinyi-street-ground.py \
        --verify-xinyi --out assets/xinyi-street-ground.json.gz

For another district, pass --district and --district-ground. For example:
    uv run --python 3.12 --with shapely==2.2.0 scripts/build-xinyi-street-ground.py \
        --district 萬華區 --district-ground data/city-streets/wanhua-district.json.gz \
        --out path/to/wanhua-street-ground.json.gz

The optional scene replaces ground within its surveyed plot. --receipt records
the inputs read, their SHA-256 digests, library versions and both output hashes.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import re
import zlib

import shapely
from shapely import make_valid, set_precision, union_all
from shapely.affinity import affine_transform
from shapely.geometry import Polygon, box, shape


CITY = Path(__file__).resolve().parents[1]
DISTRICT = '信義區'
# The renderer decodes coordinates relative to this fixed Taiwanese origin (microdegrees).
ORIGIN = (121550000, 25000000)
LON, LAT = 121.57, 25.03
EAST = 111320 * math.cos(math.radians(LAT))
NORTH = 110574
SONGYAN_GROUND_SHA = '2aad78e25bc97bd4ffe74cf97ffe1dc7d1315e08375f65b5325529cdceddff73'
XINYI_GIS_SHA = '0bf1ca133cf2c580f4ff988359d7bfb37368b787dbfa5c8d102f05e54f339aa8'
XINYI_GEOMETRY_SHA = '8d3969c4301791eb41cd3d6f8819995874d566c446d4b8bd14c2ff88ba381c12'
UNPAVED = {'dirt', 'gravel', 'ground', 'unpaved', 'compacted', 'earth', 'woodchips'}


def json_bytes(value):
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False).encode()


def metres(geometry):
    return affine_transform(geometry, [EAST, 0, 0, NORTH, -LON * EAST, -LAT * NORTH])


def area_only(geometry):
    if geometry.is_empty:
        return Polygon()
    if geometry.geom_type in ('Polygon', 'MultiPolygon'):
        return geometry
    return union_all([area_only(part) for part in getattr(geometry, 'geoms', ())
                      if part.geom_type in ('Polygon', 'MultiPolygon', 'GeometryCollection')])


def clean(geometry):
    return set_precision(area_only(make_valid(geometry)), .03)


def merge(parts):
    return clean(union_all([clean(part) for part in parts], grid_size=.03))


class Inputs:
    def __init__(self, city):
        self.city = city
        self.hashes = {}

    def read(self, path, label=None):
        payload = path.read_bytes()
        key = label if label else path.relative_to(self.city).as_posix()
        self.hashes[key] = hashlib.sha256(payload).hexdigest()
        return gzip.decompress(payload) if path.suffix == '.gz' else payload

    def json(self, path, label=None):
        return json.loads(self.read(path, label))


def source_geometry(inputs, district, district_name, index, off_ground):
    """A cell references the owning pack even when the full way crosses a pack border."""
    refs, owners = set(), set()
    packs, cells, paving = {}, [], []
    for entry in index['packs']:
        if not metres(box(*entry['bounds'])).intersects(district):
            continue
        pack = inputs.json(inputs.city / 'data/city170' / entry['url'])
        selected = [cell for cell in pack['cells'] if district_name in cell['districts']]
        if not selected:
            continue
        packs[entry['id']] = pack
        owners.add(entry['id'])
        prepared = inputs.json(inputs.city / 'data/city170-prepared' / (entry['id'][1:] + '.json.gz'))
        for cell in selected:
            refs.update(cell['refs'])
            owners.update(cell['deps'])
            cells.append(cell)
            for feature in prepared[cell['id']]:
                if feature['properties']['kind'] == 'skill-paving':
                    paving.append(metres(shape(feature['geometry'])))

    parts = defaultdict(list)
    excluded = Counter()
    for entry in index['packs']:
        if entry['id'] not in owners:
            continue
        pack = packs.get(entry['id']) or inputs.json(inputs.city / 'data/city170' / entry['url'])
        for feature in pack['features']['features']:
            tags = feature['properties']
            kind = tags['kind']
            if feature['id'] not in refs or kind not in ('road', 'walk', 'water', 'building'):
                continue
            geometry = metres(shape(feature['geometry']))
            if not geometry.intersects(district):
                continue
            if kind in ('building', 'water'):
                parts[kind].append(geometry)
                continue
            separated = any(str(tags.get(key, 'no')) != 'no' for key in ('bridge', 'tunnel', 'indoor'))
            if separated or float(tags.get('layer', 0)) != 0 or feature['id'] in off_ground:
                excluded[kind] += 1
                continue
            if kind == 'road' and tags.get('category') in ('motorway', 'motorway_link'):
                continue
            width = max(1, min(float(tags.get('width', 5.4 if kind == 'road' else 1.8)), 24))
            if kind == 'road' and tags.get('name') == '菸廠路':
                # The archive assigns the class default (5 m) to all four ways;
                # OSM records their separate one-, two- and four-lane sections.
                width = max(width, float(tags.get('lanes', 1)) * 2.9)
            trail = tags.get('surface') in UNPAVED or tags.get('category') in ('path', 'bridleway', 'track')
            surface = 'path' if kind == 'walk' and trail else kind
            parts[surface].append(geometry.buffer(width / 2, quad_segs=3))
    return parts, paving, cells, dict(excluded)


def read_plot(inputs, path, district_name):
    raw = inputs.read(path, 'authored-scene').decode()
    if path.suffix.lower() == '.html':
        # Parse just the static JSON object. Never run JavaScript from an input.
        match = re.search(r'^const SCENE\s*=\s*', raw, re.MULTILINE)
        if not match:
            raise ValueError('No static SCENE object in the exported HTML')
        scene, _ = json.JSONDecoder().raw_decode(raw, match.end())
    else:
        scene = json.loads(raw)
    source = {key: scene[key] for key in ('meta', 'corners', 'roads', 'walk', 'paths')}
    digest = hashlib.sha256(json.dumps(source, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()
    if district_name == DISTRICT and digest != SONGYAN_GROUND_SHA:
        raise ValueError(f'Songyan ground differs from the accepted export: {digest}')
    meta = scene['meta']
    angle = math.radians(meta['rotation'])
    cos, sin = math.cos(angle), math.sin(angle)
    east = 111320 * math.cos(math.radians(meta['lat']))

    def point(xy):
        x, y = xy
        lon = meta['lon'] + (x*cos - y*sin) / east
        lat = meta['lat'] + (x*sin + y*cos) / NORTH
        return (lon-LON)*EAST, (lat-LAT)*NORTH

    def forms(rows):
        return merge([Polygon([point(xy) for xy in rings[0]],
                              [[point(xy) for xy in hole] for hole in rings[1:]]) for rings in rows])

    return Polygon([point(xy) for xy in scene['corners']]), forms(scene['roads']), forms(scene['walk'] + scene['paths']), digest


def delta_ring(points):
    previous = (0, 0)
    encoded = []
    for x, y in points:
        current = (round(x), round(y))
        if current != previous:
            encoded.extend([current[0]-previous[0], current[1]-previous[1]])
            previous = current
    return encoded


def grid_ring(points):
    return [(round((x/EAST+LON)*1e6)-ORIGIN[0], round((y/NORTH+LAT)*1e6)-ORIGIN[1]) for x, y in points]


def integer_polygons(surface):
    """Repair collapsed slivers on the integer grid before delta-encoding GeoJSON rings."""
    polygons = []
    for part in getattr(surface, 'geoms', (surface,)):
        if part.geom_type != 'Polygon' or part.area <= .08:
            continue
        exterior = grid_ring(part.exterior.coords)
        holes = [grid_ring(h.coords) for h in part.interiors if Polygon(h).area > .25]
        integer = set_precision(make_valid(Polygon(exterior, holes)), 1)
        stack = [integer]
        while stack:
            geom = stack.pop()
            if geom.geom_type == 'Polygon' and geom.area >= 1:
                polygons.append([delta_ring(geom.exterior.coords)] + [delta_ring(h.coords) for h in geom.interiors])
            elif hasattr(geom, 'geoms'):
                stack.extend(reversed(geom.geoms))
    return polygons


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--city', type=Path, default=CITY, help='TaipeiPocketCity root with unpacked data/')
    parser.add_argument('--district', default=DISTRICT, help='official administrative name')
    parser.add_argument('--district-ground', type=Path, help='existing prepared district streets JSON or .json.gz')
    parser.add_argument('--scene', type=Path, help='authored Pocket City scene JSON or static HTML export')
    parser.add_argument('--verify-xinyi', action='store_true', help='require the frozen GIS and geometry hashes before writing')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, help='optional output for SHA-256 and coverage receipt')
    args = parser.parse_args()
    if args.district == DISTRICT and not args.scene:
        args.scene = Path(__file__).with_name('songyan-street-plot.json.gz')
    if args.district != DISTRICT and not args.district_ground:
        parser.error('Choose the matching --district-ground when building a different district')
    if args.verify_xinyi and args.district != DISTRICT:
        parser.error('--verify-xinyi is specific to the frozen Xinyi asset')
    inputs = Inputs(args.city)
    data = args.city / 'data'
    boundary = next(f for f in inputs.json(data/'districts.geojson')['features'] if f['properties']['name'] == args.district)
    district = clean(metres(shape(boundary['geometry'])))
    existing = inputs.json(args.district_ground or data/'street-xinyi-district.json', 'district-ground')
    road_feature = next(f for f in existing['ground']['features'] if f['properties']['kind'] == 'road')
    old_road = clean(metres(shape(road_feature['geometry'])))
    grade_data = inputs.read(args.city/'city170-grade-ids.js').decode().split('export default ', 1)[1].split(';', 1)[0]
    off_ground = {f'{key}/{value}' for key, values in json.loads(grade_data).items() for value in values}
    index = inputs.json(data/'city170/index.json')
    parts, paving, cells, excluded = source_geometry(inputs, district, args.district, index, off_ground)
    base = merge(parts['road'])
    obstacles = merge(parts['water'] + parts['building'])
    road = merge([base, old_road.intersection(base.buffer(3))]).difference(obstacles)
    walk = merge([merge(paving), merge(parts['walk'])]).difference(obstacles)
    path = merge(parts['path']).difference(obstacles)
    plot_digest = None
    if args.scene:
        plot, plot_roads, plot_walks, plot_digest = read_plot(inputs, args.scene, args.district)
        road = merge([road.difference(plot), plot_roads.difference(obstacles)])
        walk = merge([walk.difference(plot), plot_walks.difference(obstacles)])
    road = road.intersection(district)
    walk = walk.intersection(district).difference(road)
    path = path.intersection(district).difference(road)
    walk = walk.difference(path)
    # Remove sub-decimetre extraction seams before taking kerbs. An administrative
    # boundary cuts the paint extent, but it does not create a physical kerb.
    road = clean(road.buffer(.08, join_style=2).buffer(-.08, join_style=2).simplify(.10))
    kerbs = road.boundary.difference(district.boundary.buffer(.32))
    surfaces = {'road': road, 'walk': walk, 'path': path}
    rows = {kind: integer_polygons(clean(surface.simplify(.15))) for kind, surface in surfaces.items()}
    rows['kerb'] = [delta_ring(grid_ring(line.coords)) for line in getattr(kerbs, 'geoms', (kerbs,))
                    if line.geom_type == 'LineString' and line.length > .4]
    encoded = json_bytes(rows)
    gis_inputs = {k: v for k, v in sorted(inputs.hashes.items()) if k != 'authored-scene'}
    gis_digest = hashlib.sha256(json_bytes(gis_inputs)).hexdigest()
    geometry_digest = hashlib.sha256(encoded).hexdigest()
    if args.verify_xinyi and (gis_digest != XINYI_GIS_SHA or geometry_digest != XINYI_GEOMETRY_SHA):
        raise ValueError(f'Xinyi verification failed. GIS {gis_digest}, geometry {geometry_digest}')
    packed = gzip.compress(encoded, compresslevel=9, mtime=0)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(packed)
    receipt = {'district': args.district, 'districtCells': len(cells), 'excludedGrade': excluded,
               'segments': {k: len(parts[k]) for k in surfaces}, 'authoredGroundSHA256': plot_digest,
               'gisSHA256': gis_digest, 'geometrySHA256': geometry_digest, 'gzipSHA256': hashlib.sha256(packed).hexdigest(),
               'shapely': shapely.__version__, 'geos': shapely.geos_version_string, 'zlib': zlib.ZLIB_RUNTIME_VERSION}
    print(json.dumps(receipt, ensure_ascii=False))
    if args.receipt:
        receipt['inputsSHA256'] = dict(sorted(inputs.hashes.items()))
        args.receipt.write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n')


if __name__ == '__main__':
    main()
