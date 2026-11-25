"""Build illustrated water bands inside the frozen Taipei fountain-water polygons.

Usage: python build-city170-fountains.py TAIPEI.osm.json.gz RESTORED_DATA OUTPUT_JS
The bands and strokes illustrate water surfaces; they do not model plumbing.
"""

import argparse
from collections import Counter
import gzip
import hashlib
import json
import math
from pathlib import Path
import runpy

import numpy as np
from shapely import STRtree, get_parts, transform
from shapely.geometry import LineString, mapping, shape

B = runpy.run_path(str(Path(__file__).with_name('build-city170-bike-racks.py')))
F, H, read, project = (B[k] for k in ('F','H','read','project'))
# Songshan's courtyard is already authored; the Dajia basin is in renovation.
EXCLUDED = {1390847382:'existing-songshan-detail',484330232:'dajia-construction'}


def basin_tags(tags):
    return tags.get('amenity')=='fountain' and tags.get('natural')=='water'


def outdoor(tags):
    return (
        not H['off_ground'](tags) and tags.get('access') in H['OPEN_ACCESS']
        and tags.get('fountain') in {None,'decorative'}
        and tags.get('playground')!='splash_pad'
        and tags.get('historic')!='ruins'
        and tags.get('operational_status') not in {'out_of_order','closed','dry'}
        and all(tags.get(k) in {None,'no'} for k in ('disused','abandoned','construction','covered','demolished'))
    )


def parts(geometry, kind):
    return [g for g in get_parts(geometry) if g.geom_type==kind and not g.is_empty]


def line_glints(surface):
    # Use the basin's long axis, so small formal and narrow pools read differently.
    corners=list(surface.minimum_rotated_rectangle.exterior.coords)
    dx,dy=max(((b[0]-a[0],b[1]-a[1]) for a,b in zip(corners,corners[1:])),
              key=lambda d:d[0]**2+d[1]**2)
    span=math.hypot(dx,dy)
    u,v=dx/span,dy/span
    center=surface.representative_point()
    step=max(.43,min(1.42,math.sqrt(surface.area)*.15))
    extent=max(.42,min(3.5,span*.34))
    for index,offset in enumerate((-1.45,-.32,.72,1.63)):
        across=offset*step
        along=(index%2-.5)*extent*.35
        x,y=center.x-u*along-v*across,center.y-v*along+u*across
        pts=[]
        for i in range(13):
            f=(i-6)/12
            delta=math.sin(f*math.tau)*.115
            pts.append((x+f*extent*u-delta*v,y+f*extent*v+delta*u))
        clipped=LineString(pts).intersection(surface.buffer(-.055))
        for stroke in parts(clipped,'LineString'):
            if stroke.length>=.29:
                yield stroke


def prepare_polygon(original, water):
    # Guard against a stale or generalized source ID before sketching on top.
    if original.intersection(water).area/max(original.area,water.area)<.96:
        return None
    basin=original.intersection(water).buffer(-.065)
    if basin.geom_type!='Polygon' or basin.area<2:
        return None
    step=max(.17,min(.57,math.sqrt(basin.area)*.053))
    inside=basin.buffer(-step)
    if inside.geom_type!='Polygon' or inside.area<.34:
        return None
    deep=inside.buffer(-step*.58)
    return basin,inside,deep


def build(source,data):
    digest=read(data/'city170/index.json')['source']['provenance']['taipeiExtractUncompressedSHA256']
    with gzip.open(source,'rb') as f:
        if hashlib.file_digest(f,'sha256').hexdigest()!=digest:
            raise ValueError('Wrong Taipei OSM snapshot')
    ways=[r for r in B['elements'](source) if r['type']=='way' and basin_tags(r.get('tags',{}))
          and len(r['nodes'])>=4 and r['nodes'][0]==r['nodes'][-1]]
    wanted={n for r in ways for n in r['nodes']}
    nodes={r['id']:(r['lon'],r['lat']) for r in B['elements'](source) if r['type']=='node' and r['id'] in wanted}
    want_atlas={f"water/way/{r['id']}" for r in ways}
    atlas={}
    for path in sorted((data/'city170').glob('p*.json.gz')):
        for f in read(path)['features']['features']:
            if f['id'] in want_atlas and f['properties']['kind']=='water':
                atlas.setdefault(f['id'],f)
    districts=read(data/'districts.geojson')['features']
    district_index=STRtree([shape(f['geometry']) for f in districts])
    city=shape(read(data/'city170-boundary.json'))
    features, counts, skips = [], Counter(), Counter()
    city_candidates=0

    for row in sorted(ways,key=lambda r:r['id']):
        if any(i not in nodes for i in row['nodes']):
            continue
        coords=[nodes[i] for i in row['nodes']]
        orig=shape({'type':'Polygon','coordinates':[coords]})
        if not orig.is_valid or orig.area<=0 or not city.covers(orig):
            continue
        city_candidates+=1
        osm=row['id']
        if osm in EXCLUDED:
            skips[EXCLUDED[osm]]+=1
            continue
        if not outdoor(row['tags']):
            skips['unsupported-fountain-type']+=1
            continue
        key=f'water/way/{osm}'
        entry=atlas.get(key)
        if entry is None:
            skips['no-matching-atlas-water']+=1
            continue
        ground=prepare_polygon(project(orig),project(shape(entry['geometry'])))
        center=orig.representative_point()
        admin=district_index.query(center,predicate='within')
        if ground is None or len(admin)!=1:
            skips['narrow-or-unaligned-basin']+=1
            continue
        basin, inside, deep=ground

        def record(geometry, role):
            raw=transform(geometry,F['REVERSE'].transform,interleaved=False)
            raw=transform(raw,lambda coordinates:np.round(coordinates,8))
            features.append({'type':'Feature','id':f'{key}/{role}/{len(features)}',
                             'geometry':mapping(raw),
                             'properties':{'osm':osm,'role':role}})

        record(basin,'shallows')
        record(inside,'surface')
        if deep.geom_type=='Polygon' and deep.area>.28:
            record(deep,'depth')
        for stroke in line_glints(inside):
            record(stroke,'glint')
        counts[districts[admin[0]]['properties']['name']]+=1
    receipt=dict(osmSHA256=digest,sourceBasins=city_candidates,illustrated=sum(counts.values()),
                 districts=counts,excluded=skips)
    return receipt, {'type':'FeatureCollection','features':features}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for field in ('source','data','output'):
        parser.add_argument(field,type=Path)
    args=parser.parse_args()
    receipt,value=build(args.source,args.data)
    def encode(obj):
        return json.dumps(obj,ensure_ascii=False,separators=(',',':'))
    args.output.write_text('// OpenStreetMap contributors · ODbL. Generated by scripts/build-city170-fountains.py.\n'
                           f'export const fountainSnapshot={encode(receipt)};\n'
                           f'export default {encode(value)};\n',encoding='utf-8')
    print(encode(receipt))
