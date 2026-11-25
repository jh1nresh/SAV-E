"""Clip each surveyed storefront's threshold to documented arcade paving on its own street.

Usage: python build-taipei-arcade-floors.py RESTORED_DATA FINISHGFL97_ZIP OUTPUT_GZ
Dependencies: Node, pyshp, pyproj, Shapely 2. Official project footprints describe
2002–2016 works, not current column positions or materials. Joints are illustrative.
Download: https://data.gov.tw/dataset/128426 (Taipei City Construction Management Office).
"""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import subprocess

import shapefile
from pyproj import Transformer
from shapely import STRtree, get_parts, make_valid, set_precision
from shapely.geometry import LineString, MultiLineString, Polygon, shape, mapping
from shapely.ops import transform, unary_union

WEB = Path(__file__).resolve().parents[1]
OFFICIAL = '5f7130cfc5e17b274c5b81706478333b8d396e70ab03f777b51088e05e766160'
to_grid = Transformer.from_crs(4326, 3826, always_xy=True).transform
to_geo = Transformer.from_crs(3826, 4326, always_xy=True).transform


def name(s):
    return ''.join(s.split()).replace('台','臺')


def load_works(archive):
    if hashlib.sha256(archive.read_bytes()).hexdigest() != OFFICIAL:
        raise ValueError('Unexpected Taipei arcade works edition')
    works, streets, identifiers = [], [], []
    with shapefile.Reader(str(archive), encoding='cp950') as records:
        for record in records.iterShapeRecords():
            road = record.record['GFL_ROAD'].strip()
            for k,part in enumerate(get_parts(make_valid(shape(record.shape.__geo_interface__)))):
                if road and part.geom_type == 'Polygon' and part.area > 1:
                    works.append(part)
                    streets.append(road)
                    identifiers.append(f'{record.record["MAP_COOR_I"]}/{k}')
    return works, streets, identifiers


def geometry(row, works, streets, index, obstacles):
    x, y = to_grid(*row['center'])
    # Convert the geographic outward direction to local grid north at this shop.
    a = math.radians(row['angle'])
    lon, lat = row['center']
    ex, ey = to_grid(lon + math.cos(a)/100890, lat + math.sin(a)/110780)
    size = math.hypot(ex-x, ey-y)
    nx, ny = (ex-x)/size, (ey-y)/size
    def xy(along, depth):
        return x - ny*along + nx*depth, y + nx*along + ny*depth
    half = min(9, row['width'])/2
    # Only illustrate the visible bay outside this known wall, to a maximum of 3 m.
    bay = Polygon([xy(-half,.2), xy(half,.2), xy(half,3), xy(-half,3)])
    road = name(row['street'])
    def same_road(label):
        # Municipal records may name two streets, but a parent road does not assign
        # its project to a lane with the same prefix.
        return road in {name(s) for s in label.replace('、',' ').replace('，',' ').split()}
    for i in index.query(bay,predicate='intersects'):
        if not same_road(streets[i]):
            continue
        floor = works[i]
        blocked = obstacles.query(floor, predicate='intersects')
        if len(blocked):
            floor = floor.difference(unary_union(obstacles.geometries.take(blocked)))
        for j, piece in enumerate(get_parts(floor)):
            if piece.geom_type != 'Polygon':
                continue
            overlap = piece.intersection(bay)
            if overlap.area < 2 or overlap.distance(LineString([xy(-half,.2),xy(half,.2)])) > .45:
                continue
            # Carry the paving to the edge of the continuous municipal section.
            # Changes in ownership or width of the pictured shop are not paving edges.
            yield (int(i),j), piece, (x,y,nx,ny)


def paving_joints(piece, axes):
    x,y,nx,ny = axes
    corners = list(piece.exterior.coords)
    along = [-(px-x)*ny+(py-y)*nx for px,py in corners]
    depth = [(px-x)*nx+(py-y)*ny for px,py in corners]
    a,b,c,d = min(along)-1,max(along)+1,min(depth)-1,max(depth)+1
    def xy(s,t):
        return x-ny*s+nx*t,y+nx*s+ny*t
    lines = [LineString([xy(i*.8,c),xy(i*.8,d)]) for i in range(math.ceil(a/.8),math.ceil(b/.8))]
    lines += [LineString([xy(a,i*.65),xy(b,i*.65)]) for i in range(math.ceil(c/.65),math.ceil(d/.65))]
    segments = [part for line in lines for part in get_parts(line.intersection(piece))
                if part.geom_type=='LineString' and part.length>.05]
    return MultiLineString(segments)


def carriageways(data):
    roads = {}
    for pack in sorted((data/'city170').glob('p*.json.gz')):
        for f in json.loads(gzip.decompress(pack.read_bytes()))['features']['features']:
            p = f['properties']
            if p['kind'] != 'road' or f['id'] in roads or p.get('offGround') or p.get('bridge','no') != 'no' or p.get('tunnel','no') != 'no' or str(p.get('layer',0)) != '0':
                continue
            try:
                width = float(p.get('width',5.4))
            except (TypeError, ValueError):
                width = 5.4
            roads[f['id']] = transform(to_grid,shape(f['geometry'])).buffer(max(1,min(24,width))/2+.45)
    return STRtree(list(roads.values()))


def build(data, archive):
    # Use the renderer's real matched rows, including municipal-address recoveries.
    js = """import {readFileSync} from 'node:fs';import {gunzipSync} from 'node:zlib';
const [url,base]=process.argv.slice(1);const {completeFrontagePack}=await import(url);
const {packs}=JSON.parse(readFileSync(base+'/city170/index.json'));
process.stdout.write(JSON.stringify(packs.flatMap(({id})=>completeFrontagePack(id,
 JSON.parse(gunzipSync(readFileSync(base+'/city170-frontages/'+id+'.json.gz')))))));"""
    rows = json.loads(subprocess.check_output(['node','--input-type=module','-e',js,
                      (WEB/'taipei-frontage-pack.js').as_uri(), str(data)]))
    works, streets, identifiers = load_works(archive)
    index, obstacles = STRtree(works), carriageways(data)
    sections = {}
    for row in sorted(rows, key=lambda r:r['id']):
        for key,piece,axes in geometry(row,works,streets,index,obstacles):
            section = sections.setdefault(key, (piece,axes,[]))
            section[2].append(row['id'])
    features, covered = [], []
    for key,(area,axes,stores) in sorted(sections.items()):
        overlaps = [other for other in covered if area.intersects(other)]
        remaining = area.difference(unary_union(overlaps)) if overlaps else area
        for floor in get_parts(remaining):
            if floor.geom_type!='Polygon' or floor.area<.1:
                continue
            for kind,geom in [('floor',floor),('joints',paving_joints(floor,axes))]:
                geo = set_precision(transform(to_geo,geom),.0000001)
                if not geo.is_empty:
                    features.append(dict(type='Feature',properties={'kind':kind,'section':f'{identifiers[key[0]]}/{key[1]}'},geometry=mapping(geo)))
        covered.append(area)
    evidence = {f'{identifiers[i]}/{j}':ids for (i,j),(_,_,ids) in sections.items()}
    return dict(type='FeatureCollection',source='臺北市建築管理工程處 · 臺北市騎樓整平工程完成路段表',
                sourceURL='https://data.gov.tw/dataset/128426',sourceSHA256=OFFICIAL,sectionShops=evidence,features=features)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('data','archive','output'):
        p.add_argument(key,type=Path)
    args = p.parse_args()
    atlas = build(args.data, args.archive)
    args.output.write_bytes(gzip.compress(json.dumps(atlas,separators=(',',':')).encode(),mtime=0))
    print(len({shop for shops in atlas['sectionShops'].values() for shop in shops}),'corroborating shops;',len(atlas['features']),'features')
