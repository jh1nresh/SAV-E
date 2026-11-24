"""Run the installed Pocket City prep on every unique 220 m atlas cell.

Run from this preview directory. Pass the skill root, a work directory and the
folders containing the previously fetched OSM API 0.6 JSON snapshots.
"""
import argparse
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from contextlib import redirect_stdout
from hashlib import sha256
import gzip
import io
import json
import math
import multiprocessing
import os
from pathlib import Path
import sys

from shapely import make_valid
from shapely.geometry import LineString, Point, Polygon, box, mapping, shape
from shapely.ops import transform, unary_union, substring
from shapely.strtree import STRtree

DISTRICTS = ('xinyi', 'daan', 'songshan', 'zhongshan')
ROOT = Path('data')
PREVIEWS = {
    'minsheng': (121.56128, 25.05866),
    'songjiang': (121.5332, 25.0521),
}
CELL_SIZE = 220
SOUTH = 111195


def read(path):
    return json.loads(gzip.decompress(path.read_bytes()) if path.suffix=='.gz' else path.read_bytes())


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')))


def write_runtime_assets(folder, summary, districts):
    def compress(name, data):
        payload=json.dumps(data,ensure_ascii=False,separators=(',',':')).encode()
        (folder/name).write_bytes(gzip.compress(payload,compresslevel=6,mtime=0))
    street_life={key:{name:value[name] for name in ('paths','objects')} for key,value in districts.items()}
    paint={'type':'FeatureCollection','features':[feature for value in districts.values() for feature in value['ground']]}
    compress('street-pocket-city.json.gz',{'summary':summary,'districts':street_life})
    compress('street-pocket-city-paint.json.gz',paint)

def index_map(folders):
    nodes, ways, relations = {}, {}, {}
    sources = {'node': nodes, 'way': ways, 'relation': relations}
    for path in sorted(path for folder in folders for pattern in ('*.json','*.json.gz') for path in folder.glob(pattern)):
        for item in read(path)['elements']:
            if item['type'] == 'relation' and item.get('tags', {}).get('type') != 'multipolygon':
                continue
            source = sources[item['type']]
            if item.get('version', 0) >= source.get(item['id'], {}).get('version', 0):
                source[item['id']] = item

    def record_bounds(rows):
        return box(min(r['lon'] for r in rows), min(r['lat'] for r in rows),
                   max(r['lon'] for r in rows), max(r['lat'] for r in rows))

    elements = []
    bounds = []
    geometries = {}
    member_ids={m['ref'] for relation in relations.values() for m in relation['members'] if m['type']=='way'}
    for key, row in ways.items():
        if key not in member_ids and not row.get('tags'):
            continue
        if not all(n in nodes for n in row['nodes']):
            continue
        vertices = [{k: nodes[n][k] for k in ('lon', 'lat')} for n in row['nodes']]
        if len(vertices) < 2:
            continue
        geometries[key] = vertices
        if not row.get('tags'):
            continue
        elements.append({'id': key, 'type': 'way', 'tags': row['tags'], 'geometry': vertices})
        bounds.append(record_bounds(vertices))
    for key, row in relations.items():
        members = [{'role': m['role'], 'geometry': geometries[m['ref']]}
                   for m in row['members'] if m['type'] == 'way' and m['ref'] in geometries]
        if not members:
            continue
        elements.append({'id': key, 'type': 'relation', 'tags': row['tags'], 'members': members})
        bounds.append(record_bounds([p for m in members for p in m['geometry']]))
    for row in nodes.values():
        if not row.get('tags'):
            continue
        elements.append({k: row[k] for k in ('id', 'type', 'lon', 'lat', 'tags')})
        bounds.append(Point(row['lon'], row['lat']))
    return elements, STRtree(bounds)


def parts(geometry, kind):
    if geometry.geom_type == kind:
        return [] if geometry.is_empty else [geometry]
    return [part for part in getattr(geometry, 'geoms', ()) if part.geom_type == kind and not part.is_empty]


def polygons(rows):
    return unary_union([Polygon(r[0], r[1:]).buffer(0) for r in rows if r and len(r[0]) >= 3])


def adapt_scene(scene, owner, cell_xy, continuous_crossings=False):
    lon, lat = scene['meta']['lon'], scene['meta']['lat']
    kx, ky = 111320*math.cos(math.radians(lat)), 110574

    def local(x, y):
        return (x-lon)*kx, (y-lat)*ky

    def geo(x, y):
        return round(x/kx+lon, 8), round(y/ky+lat, 8)

    clip = transform(local, owner)
    roads = polygons(scene['roads'])
    paved = polygons(scene['paths']+scene['walk'])
    buildings = unary_union([Polygon(b['ring']).buffer(0) for b in scene['buildings'] if len(b['ring']) >= 3])
    water = polygons(scene['water'])
    dry = clip.difference(water).difference(buildings.buffer(.35))
    crossings, crosswalks = [], []
    crossing_ground=roads.difference(water).difference(buildings.buffer(.35)) if continuous_crossings else dry.intersection(roads)
    for marking in scene['markings']:
        if len(marking) < 2:
            continue
        for line in parts(LineString(marking).intersection(crossing_ground), 'LineString'):
            if not 3.0 < line.length < 36 or any(z.distance(line.centroid) < 3 for z in crossings):
                continue
            first, last = line.coords[0], line.coords[-1]
            dx, dy = (last[0]-first[0])/line.length, (last[1]-first[1])/line.length
            crossings.append(line)
            for i in range(1, int(line.length/.92)):
                p = line.interpolate(i*.92)
                stripe = Polygon([(p.x+u*dx-v*dy, p.y+u*dy+v*dx)
                                  for u,v in [(-.20,-1.30),(.20,-1.30),(.20,1.30),(-.20,1.30)]])
                crosswalks.append(stripe.intersection(dry).intersection(roads))

    crossing_areas = unary_union([g.buffer(1.3, cap_style='flat') for g in crossings])
    walkable = dry.intersection(paved.union(crossing_areas))
    candidates = []
    for route in scene['routes']:
        if route['kind'] != 'ped' or len(route['p']) < 2:
            continue
        for line in parts(LineString(route['p']).intersection(walkable), 'LineString'):
            if 19 < line.length < 300:
                candidates.append(line)
    paths, used = [], []
    for line in sorted(candidates, key=lambda g: -g.length):
        midpoint = line.interpolate(.5, normalized=True)
        if any(midpoint.distance(p) < 13 for p in used):
            continue
        used.append(midpoint)
        paths.append({'points': list(transform(geo, line.simplify(.12)).coords),
                      'people': 2 if line.length > 52 else 1})
        if len(paths) >= 5:
            break

    lanes = []
    usable_road = roads.intersection(dry).difference(crossing_areas.buffer(1.0)).buffer(-.45)
    for marking in scene['centerlines']:
        for line in parts(LineString(marking['p']).intersection(usable_road), 'LineString'):
            if line.length < 12:
                continue
            first, last = line.coords[0], line.coords[-1]
            # Use a shared east/north phase so adjacent cells don't restart an entire dash.
            direction = 0 if abs(first[0]-last[0]) >= abs(first[1]-last[1]) else 1
            sign = 1 if last[direction] >= first[direction] else -1
            origin = cell_xy[direction]*CELL_SIZE+first[direction]
            axis_fraction=max(.58,abs(last[direction]-first[direction])/line.length)
            step=7.4/axis_fraction
            phase=((-sign*origin)%7.4)/axis_fraction
            for start in range(int((line.length-phase)/step)+1):
                begin = phase+start*step
                end = min(begin+2.3, line.length)
                if end-begin < .38:
                    continue
                lanes.append(substring(line, begin, end).buffer(.10,cap_style='flat'))

    land = dry.difference(roads).difference(paved) if EXPAND_SURFACES else None
    surfaces = [('crossing', unary_union(crosswalks)), ('lane', unary_union(lanes)),
                ('walk' if EXPAND_SURFACES else 'skill-paving', paved.intersection(dry).difference(roads))]
    if EXPAND_SURFACES:
        forest = polygons([row['r'] for row in scene['lawns'] if row['kind'] == 'wood'])
        green = polygons([row['r'] for row in scene['lawns'] if row['kind'] != 'wood'])
        surfaces.extend([
            ('wood', forest.intersection(land)), ('grass', green.difference(forest).intersection(land)),
            ('water', water.intersection(clip)), ('road', roads.intersection(dry)),
            ('road-edge',roads.buffer(.23).difference(roads).intersection(land)),
        ])
    features = []
    for kind, surface in surfaces:
        if surface.is_empty:
            continue
        geometry = transform(geo, unary_union(parts(surface.simplify(.07), 'Polygon')))
        if not geometry.is_valid:
            geometry = unary_union(parts(make_valid(geometry), 'Polygon'))
        if geometry.is_empty:
            continue
        features.append({'type':'Feature','geometry':mapping(geometry),'properties':{'kind':kind}})

    trees = []
    park = unary_union([Polygon(v['r'][0],v['r'][1:]).buffer(0) for v in scene['lawns'] if v['r']])
    clear_land = dry.difference(roads.buffer(1.2)).difference(paved.buffer(.25))
    for i,(x,y,species,_) in enumerate(scene['trees']):
        p=Point(x,y)
        if not clear_land.covers(p) or not park.covers(p):
            continue
        trees.append([*geo(x,y),'tree',round(.69+((i*7+abs(cell_xy[0]))%11)*.035,2),(i*137)%360,(i+2)%6])
        if len(trees) >= 14:
            break
    return paths, features, trees, len(crossings)


def render_cell(job):
    ident, (i,j), lon, lat, owners, preview = job
    margin = 172
    sx = 111320*math.cos(math.radians(lat))
    nearby = box(lon-margin/sx, lat-margin/110574, lon+margin/sx, lat+margin/110574)
    hits = ELEMENT_INDEX.query(nearby)
    file = WORK/f'worker-{os.getpid()}'
    osm, plot, result = (file.with_suffix(suffix) for suffix in ('.osm.json','.plot.json','.scene.json'))
    write(osm, {'elements':[ELEMENTS[k] for k in sorted(hits)]})
    write(plot, {'lat':lat,'lon':lon,'size':220,'rotation':0,'place':preview or ident})
    sys.argv = [str(PREP), '--osm',str(osm),'--plot',str(plot),'--out',str(result),'--drive','right']
    with redirect_stdout(io.StringIO()):
        PREPARE()
    scene = read(result)
    if SAVE_SCENES:
        (SAVE_SCENES/f'{ident.replace(":", "_")}.json.gz').write_bytes(
            gzip.compress(result.read_bytes(), compresslevel=4, mtime=0))
    if preview:
        write(WORK/f'{preview}-scene.json', scene)
    return ident, {key:adapt_scene(scene, area,(i,j)) for key,area in owners.items()}, {
        'buildings':len(scene['buildings']), 'empty':not any(scene[k] for k in ('buildings','roads','walk','paths','trees','water'))
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skill', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--osm', type=Path, nargs='+', required=True)
    parser.add_argument('--jobs', type=int, default=6)
    parser.add_argument('--save-scenes', action='store_true', help='Keep every original Pocket City scene for rendering.')
    parser.add_argument('--grid-root', type=Path, default=ROOT)
    parser.add_argument('--districts', nargs='+', default=DISTRICTS)
    parser.add_argument('--expand-surfaces', action='store_true', help='Include full ground colors in per-district data.')
    args = parser.parse_args()
    global ELEMENTS, ELEMENT_INDEX, PREPARE, WORK, PREP, SAVE_SCENES, EXPAND_SURFACES
    EXPAND_SURFACES=args.expand_surfaces
    WORK = args.work.resolve()
    WORK.mkdir(parents=True, exist_ok=True)
    SAVE_SCENES=WORK/'scenes' if args.save_scenes else None
    if SAVE_SCENES:
        SAVE_SCENES.mkdir(exist_ok=True)
    PREP = args.skill/'scripts/prep.py'
    source = PREP.read_text()
    # A shore can be in the buffered input without containing any interior
    # water for boats, which gives infinite coordinates. Guard only that case.
    guard = 'if not wide.is_empty and wide.area > 300:'
    assert source.count(guard) == 1
    safe_source = source.replace(guard, 'if not wide.is_empty and wide.area > 300 and not wide.intersection(SQ.buffer(-2)).is_empty:')
    sys.path.insert(0, str(PREP.parent))
    namespace = {'__name__':'pocket_city_prep','__file__':str(PREP)}
    exec(compile(safe_source,str(PREP),'exec'),namespace)
    PREPARE = namespace['main']

    coverage = defaultdict(dict)
    origin = None
    for key in args.districts:
        payload = read(args.grid_root/f'street-{key}-district.json')
        assert payload['cellSize'] == CELL_SIZE
        origin = origin or payload['origin']
        assert payload['origin'] == origin
        for cell in payload['cells']:
            area = shape(cell['geometry'])
            assert area.is_valid
            coverage[cell['id']][f'{key}-district'] = area
    sx = SOUTH*math.cos(math.radians(origin[1]))
    previews = {
        f'{math.floor((lon-origin[0])*sx/CELL_SIZE)}:{math.floor((lat-origin[1])*SOUTH/CELL_SIZE)}':key
        for key,(lon,lat) in PREVIEWS.items()
    }
    jobs = []
    # Existing saved centroids and render ownership use this origin across all districts.
    for ident,owners in sorted(coverage.items(),key=lambda x:x[0] not in previews):
        i,j = map(int,ident.split(':'))
        lon = origin[0]+(i+.5)*CELL_SIZE/sx
        lat = origin[1]+(j+.5)*CELL_SIZE/SOUTH
        jobs.append((ident,(i,j),lon,lat,owners,previews.get(ident)))
    ELEMENTS,ELEMENT_INDEX=index_map(args.osm)
    print('Indexed',len(ELEMENTS),'OSM elements for',len(jobs),'unique cells',flush=True)
    districts = defaultdict(lambda:{'paths':[],'ground':[],'objects':[]})
    # Keep each approved tree and space additional foliage across the complete grid.
    tree_bins=defaultdict(list)
    def add_tree(row):
        x,y = row[:2]
        p = (x*sx,y*SOUTH)
        i,j = (math.floor(v/7) for v in p)
        for a in (-1,0,1):
            for b in (-1,0,1):
                if any(math.dist(p,q)<6.6 for q in tree_bins[i+a,j+b]):
                    return False
        tree_bins[i,j].append(p)
        return True
    for key in args.districts:
        for row in read(args.grid_root/f'street-{key}-district.json')['objects']:
            if row[2]=='tree':
                add_tree(row)
    tiles = {}
    crossings = 0
    with ProcessPoolExecutor(max_workers=args.jobs,mp_context=multiprocessing.get_context('fork')) as pool:
        for ident,outputs,summary in pool.map(render_cell,jobs,chunksize=2):
            tiles[ident] = summary
            for key,(walk,paint,trees,cross) in outputs.items():
                result=districts[key]
                result['paths'].extend(walk)
                result['ground'].extend(paint)
                result['objects'].extend(row for row in trees if add_tree(row))
                crossings += cross
            if len(tiles)%100 == 0:
                print('Prepared',len(tiles),'of',len(jobs),flush=True)
    assert set(tiles) == set(coverage)
    summary = {
        'cells':len(tiles),'districtPieces':sum(map(len,coverage.values())),
        'emptyCells':sum(t['empty'] for t in tiles.values()),'crossings':crossings,
        'walks':{k:len(v['paths']) for k,v in districts.items()},
        'surfaces':{k:len(v['ground']) for k,v in districts.items()},
        'trees':{k:len(v['objects']) for k,v in districts.items()},
        'origin':origin,'size':CELL_SIZE,'prepSHA256':sha256(source.encode()).hexdigest(),
    }
    write(WORK/'receipt.json',summary)
    write(WORK/'cells.json',tiles)
    if EXPAND_SURFACES:
        payloads = WORK/'districts'
        payloads.mkdir(exist_ok=True)
        for key, data in districts.items():
            write(payloads/f'{key}.json', data)
    else:
        write_runtime_assets(WORK, summary, districts)
    print(json.dumps(summary,ensure_ascii=False),flush=True)


if __name__=='__main__':
    main()
