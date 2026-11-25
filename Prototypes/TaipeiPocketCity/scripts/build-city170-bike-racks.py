"""Build ground-level bike-rack illustrations from the frozen Taipei OSM atlas.

Usage: python build-city170-bike-racks.py TAIPEI.osm.json.gz RESTORED_DATA OUTPUT_JS
Each accepted source gets one illustrative rack segment. A source point stays
fixed, while a line or area can supply an eligible position within its geometry.
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
from shapely import Point, STRtree, points
from shapely.affinity import rotate, translate
from shapely.geometry import LineString, Polygon, box, shape

R = runpy.run_path(str(Path(__file__).with_name('build-city170-riverside-pavilions.py')))
P, W, F, H, read, project = (R[k] for k in ('P','W','F','H','read','project'))
MODELS = {
    'wall_loops': ('bike-wheel-rack', .81, .29),
    'rack': ('bike-wheel-rack', .81, .29),
    'stands': ('bike-frame-stand', .46, .12),
}


def eligible(t):
    return (
        t.get('bicycle_parking') in MODELS
        and not H['off_ground'](t)
        and t.get('access') in H['OPEN_ACCESS']
        and t.get('covered') in {None,'no'}
        and t.get('parking') in {None,'surface','street_side'}
        and t.get('location') in {None,'outdoor','outdoors','surface','ground'}
        and not t.get('fixme')
        and all(t.get(key) in {None,'no'} for key in ('disused','abandoned','construction'))
        and all(t.get(key) in {None,'0','ground','1F','1樓'} for key in ('floor','addr:floor'))
    )


def elements(source):
    with gzip.open(source,'rb') as f:
        yield from ijson.items(f,'elements.item',use_float=True)


def osm_sites(source,city):
    records = [e for e in elements(source) if e['type'] in {'node','way'}
               and e.get('tags',{}).get('amenity') == 'bicycle_parking']
    wanted = {n for e in records if e['type']=='way' for n in e['nodes']}
    nodes, rentals = {}, []
    for e in elements(source):
        if e['type'] != 'node':
            continue
        if e['id'] in wanted:
            nodes[e['id']] = (e['lon'],e['lat'])
        if e.get('tags',{}).get('amenity') == 'bicycle_rental':
            p = Point(e['lon'],e['lat'])
            if city.covers(p):
                rentals.append(project(p).buffer(.46))
    sites = []
    for e in records:
        if e['type']=='node':
            g = Point(e['lon'],e['lat'])
        elif all(n in nodes for n in e['nodes']) and len(e['nodes']) >= 2:
            coords = [nodes[n] for n in e['nodes']]
            g = Polygon(coords) if len(coords)>3 and coords[0]==coords[-1] else LineString(coords)
        else:
            continue
        if g.is_valid and not g.is_empty and city.intersects(g):
            sites.append((f"{e['type']}/{e['id']}",e['tags'],project(g),city.covers(g)))
    return sorted(sites,key=lambda e:e[0]), rentals


def primary_axis(geom):
    coords = list(geom.coords) if geom.geom_type=='LineString' else list(geom.minimum_rotated_rectangle.exterior.coords)
    dx,dy = max(((b[0]-a[0],b[1]-a[1]) for a,b in zip(coords,coords[1:])),
                key=lambda d:d[0]**2+d[1]**2)
    return round(math.degrees(math.atan2(dy,dx))) % 180


def anchors(geom):
    if geom.geom_type=='Point':
        yield geom
    elif geom.geom_type=='LineString':
        for fraction in (.5,.3,.7,.15,.85):
            yield geom.interpolate(fraction,normalized=True)
    else:
        inside=geom.representative_point()
        yield inside
        for _,x,y in P['OFFSETS']:
            if x==y==0:
                continue
            p=Point(inside.x+x,inside.y+y)
            if geom.covers(p):
                yield p


def outdoor_indexes(data,rentals):
    trails, paths, fixed = R['walkways'](data)
    runs = {}
    for file in sorted((data/'city170-life').glob('p*.json.gz')):
        runs.update(read(file)['paths'])
    animated = [project(LineString(r['points'])).buffer(1.30)
                for r in runs.values() if r['people'] and len(r['points'])>=2]
    fixed += animated + list(paths.geometries) + P['known_props']() + rentals
    rows = [r for file in sorted((data/'city170-nature').glob('p*.json.gz')) for r in read(file)]
    x,y = F['FORWARD'].transform([r[0] for r in rows],[r[1] for r in rows])
    return trails,(W['obstacle_tree'](data),W['legacy_trunks'](data),STRtree(fixed)),STRtree(points(x,y))


def build(source,data):
    index=read(data/'city170/index.json')
    digest=index['source']['provenance']['taipeiExtractUncompressedSHA256']
    with gzip.open(source,'rb') as f:
        if hashlib.file_digest(f,'sha256').hexdigest()!=digest:
            raise ValueError('Wrong Taipei OSM snapshot')
    city=shape(read(data/'city170-boundary.json'))
    sites,rentals=osm_sites(source,city)
    documented=[(name,t,g) for name,t,g,in_city in sites if in_city and eligible(t)]
    trails,conflicts,trees=outdoor_indexes(data,rentals)
    terrain=F['Survey'](data)
    covered=H['survey_cover'](terrain,data)
    cells=read(data/'city170/grid.json.gz')['features']
    districts=read(data/'districts.geojson')['features']
    grid=STRtree([shape(r['geometry']) for r in cells])
    admins=STRtree([shape(r['geometry']) for r in districts])
    zones=STRtree([g for _,_,g,_ in sites if g.geom_type=='Polygon'])
    selected,skipped,found,placed=defaultdict(dict),Counter(),Counter(),[]
    by_kind=Counter()

    for name,t,g in sorted(documented,key=lambda r:(r[2].geom_type=='Point',r[0])):
        if g.geom_type=='Point' and len(zones.query(g,predicate='within')):
            skipped['in-mapped-parking-area'] += 1
            continue
        kind,w,d=MODELS[t['bicycle_parking']]
        for anchor in anchors(g):
            lon,lat=F['REVERSE'].transform(anchor.x,anchor.y)
            ll=Point(round(lon,8),round(lat,8))
            center=project(ll)
            angle=R['heading'](trails,center) if g.geom_type=='Point' else primary_axis(g)
            if angle is None:
                continue
            rectangle=box(-w-.035,-d-.035,w+.035,d+.035)
            footprint=translate(rotate(rectangle,angle,origin=(0,0)),center.x,center.y)
            if g.geom_type=='Polygon' and not g.covers(footprint):
                continue
            if g.geom_type=='LineString' and (g.length < 2*w or footprint.difference(g.buffer(d+.15)).area > .02):
                continue
            if any(len(o.query(footprint,predicate='intersects')) for o in conflicts):
                continue
            if len(trees.query(footprint,predicate='dwithin',distance=.32)):
                continue
            if any(footprint.distance(p)<.22 for p in placed):
                continue
            if covered(ll,center,math.hypot(w,d)+.06):
                continue
            heights=[terrain.ground(p) for p in [center,*map(Point,footprint.exterior.coords[:-1])]]
            if any(z is None for z in heights) or max(heights)-min(heights)>.13:
                continue
            cell,admin=grid.query(ll,predicate='within'),admins.query(ll,predicate='within')
            if len(cell)!=1 or len(admin)!=1:
                continue
            pack=cells[cell[0]]['properties']['pack']
            selected[pack]['bike-parking/'+name]=[ll.x,ll.y,kind,1,angle,0]
            found[districts[admin[0]]['properties']['name']]+=1
            by_kind[kind]+=1
            placed.append(footprint)
            break
        else:
            skipped['no-supported-ground-footprint'] += 1
    receipt=dict(osmSHA256=digest,mappedSites=len(sites),documentedOutdoorSites=len(documented),
                 illustratedSites=len(placed),districts=found,kinds=by_kind,exclusions=skipped)
    return receipt,selected


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for field in ('source','data','output'):
        parser.add_argument(field,type=Path)
    args=parser.parse_args()
    receipt,rows=build(args.source,args.data)
    def encode(value):
        return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'))
    args.output.write_text('// OpenStreetMap contributors · ODbL. Generated by scripts/build-city170-bike-racks.py.\n'
                           f'export const bikeRackSnapshot={encode(receipt)};\n'
                           f'export default {encode(rows)};\n',encoding='utf-8')
    print(encode(receipt))
