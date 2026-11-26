"""Place missing Pocket City walks on the published 200 m paving in Xinyi and Songshan.

Run in TaipeiPocketCity with the full 200 m scenes produced by prepare-taipei200.py:
  uv run --python 3.12 --with pyproj --with shapely python scripts/build-taipei200-walks.py /path/to/work
"""
import argparse
from collections import defaultdict
import gzip
import json
import math
from pathlib import Path

from pyproj import Transformer
from shapely import STRtree, line_merge, union_all
from shapely.affinity import affine_transform
from shapely.geometry import LineString, Polygon, box, shape
from shapely.ops import transform

DISTRICTS = {'松山區', '信義區'}
PROJECT = Transformer.from_crs(4326,3826,always_xy=True).transform
GEO = Transformer.from_crs(3826,4326,always_xy=True).transform


def read(path):
    path = Path(path)
    content = path.read_bytes()
    return json.loads(gzip.decompress(content) if path.suffix == '.gz' else content)


def lines(geometry):
    if geometry.is_empty:
        return
    if geometry.geom_type == 'LineString':
        yield geometry
    elif hasattr(geometry, 'geoms'):
        for part in geometry.geoms:
            yield from lines(part)


def near(index, route, metres=0):
    hits = index.query(route, predicate='dwithin', distance=metres)
    return union_all(index.geometries[hits])


def pavement(parts, center):
    lon, lat = center
    east = 20*111320*math.cos(math.radians(lat))
    def ring(deltas):
        x = y = 0
        for dx, dy in zip(deltas[::2], deltas[1::2]):
            x += dx
            y += dy
            yield lon+x/east,lat+y/(20*110574)
    return transform(PROJECT,Polygon(list(ring(parts[0])),[list(ring(r)) for r in parts[1:]]))


def kit_paths(scene):
    meta = scene['meta']
    angle = math.radians(meta['rotation'])
    s, c = math.sin(angle), math.cos(angle)
    east = 111320*math.cos(math.radians(meta['lat']))
    affine = [c/east,-s/east,s/110574,c/110574,meta['lon'],meta['lat']]
    for route in scene['routes']:
        if route['kind'] == 'ped' and len(route['p']) >= 2:
            yield transform(PROJECT,affine_transform(LineString(route['p']),affine))


def build(work):
    street_index = read('assets/taipei200/index.json')
    source = read(work/'input.json')
    if source.get('paintHalo', 0) or source['osmSHA256'] != street_index['sourceOSM'] or source['prepSHA256'] != street_index['kitPrep'] or source['size'] != 200:
        raise ValueError('Expected the original 200 m scene build for the current map.')
    paving, prepared = [], []
    for p in street_index['packs']:
        for key,(_,center,names,groups) in read('assets/taipei200/'+p['id']+'.json.gz').items():
            if DISTRICTS.isdisjoint(names) or not groups[2]:
                continue
            paving.extend(pavement(poly,center) for poly in groups[2])
            prepared.extend(kit_paths(read(work/'scenes'/(key+'.json.gz'))))
    surfaces, routes = STRtree(paving), STRtree(prepared)
    boundary = union_all([transform(PROJECT,shape(f['geometry'])) for f in read('data/districts.geojson')['features']
                          if f['properties']['name'] in DISTRICTS])
    box_geo = transform(GEO,boundary.buffer(180)).envelope
    exclusions = json.loads(Path('city170-grade-ids.js').read_text().split('export default ')[1].rstrip(';\n'))
    off_ground = set(exclusions['walk/way'])
    packs = read('data/city170/index.json')['packs']
    pack_boxes = [box(*p['bounds']) for p in packs]
    pack_index = STRtree(pack_boxes)
    existing, ways = [], {}
    additions = read('data/street-pocket-city.json.gz')['districts']
    def include(paths):
        existing.extend(transform(PROJECT,LineString(p['points'])) for p in paths if len(p['points']) >= 2)
    for key in ('101','songshan','yongchun','xinyi-link'):
        include(read('data/street-'+key+'.json')['paths'])
        include(additions.get(key,{}).get('paths',[]))
    markets = json.loads(Path('taipei-market-stalls-data.js').read_text().split('export default ')[1].rstrip(';\n'))
    for market in markets.values():
        include(market['paths'].values())
    for p in packs:
        # A long source way can be owned by a pack beyond the district bounds.
        features = read('data/city170/'+p['id']+'.json.gz')['features']['features']
        include(read('data/city170-life/'+p['id']+'.json.gz')['paths'].values())
        for f in features:
            a = f['properties']
            if a['kind'] != 'walk' or a['category'] not in ('footway','pedestrian') or f['geometry']['type'] != 'LineString':
                continue
            if not f['id'].startswith('walk/way/'):
                continue
            way = int(f['id'].split('/')[-1])
            if way in off_ground or str(a.get('layer','0')) != '0' or any(a.get(k,'no') != 'no' for k in ('bridge','tunnel','indoor')):
                continue
            line = shape(f['geometry'])
            if box_geo.intersects(line):
                ways[way] = transform(PROJECT,line)
    # The single-scene 101 illustration supplies its own walkers on its rotated square.
    single_ground = Path('taipei101-single-ground-data.js').read_text()
    corners = json.loads(single_ground.split('export const coordinates=')[1].split(';')[0])
    boundary = boundary.difference(transform(PROJECT, Polygon(corners)).buffer(.1))
    old = STRtree(existing)
    by_pack = defaultdict(list)
    accepted = []
    for way,line in sorted(ways.items()):
        if way in {557896961, 1471704252, 1471704270}:
            continue  # Songshan's three authored park routes already have their own actors.
        street = line.intersection(boundary)
        if street.is_empty:
            continue
        reference = near(routes,street,1.25)
        if reference.is_empty:
            continue
        # Join only the centimetre-scale rounding seam, then inset for a figure's feet.
        surface = near(surfaces,street,1).buffer(.04).buffer(-.39)
        eligible = street.intersection(surface).intersection(reference.buffer(1.25))
        legacy = near(old,street,36)
        if not legacy.is_empty:
            eligible = eligible.difference(legacy.buffer(20))
        for path in lines(line_merge(eligible)):
            if path.length < 20 or (not legacy.is_empty and path.interpolate(.5,normalized=True).distance(legacy)<35):
                continue
            # Guard against two OSM ways covering the same sidewalk.
            if any(other.distance(path.interpolate(.5,normalized=True))<6 for other in accepted):
                continue
            accepted.append(path)
            points = [[round(x,7),round(y,7)] for x,y in transform(GEO,path).coords]
            coords = LineString(points)
            # Key by position along this way, independently of other packs or streets.
            offset = round(line.project(path.interpolate(.5, normalized=True)) * 10)
            key = f'{way}/{offset}'
            row = [key,points, min(4,math.ceil(path.length/48))]
            for i in sorted(pack_index.query(coords,predicate='intersects')):
                by_pack[packs[i]['id']].append(row)
    return by_pack


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('work',type=Path)
    parser.add_argument('--out',type=Path,default=Path('taipei200-walks-data.js'))
    args = parser.parse_args()
    packs = build(args.work)
    args.out.write_text('// Generated by scripts/build-taipei200-walks.py from the public Taipei street atlas.\nexport default '+
                        json.dumps(dict(sorted(packs.items())),ensure_ascii=False,separators=(',',':'))+';\n')
    print('walks',len({r[0] for rows in packs.values() for r in rows}),'pack memberships',sum(map(len,packs.values())))
