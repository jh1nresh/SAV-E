"""Illustrate mapped trail guideposts next to documented outdoor Taipei paths.

Usage: python build-city170-trail-signs.py TAIPEI.osm.json.gz RESTORED_DATA OUTPUT_JS
Plate appearance and placement within the nearby walkable verge are illustrative.
"""

import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import re
import runpy

from shapely import Point, STRtree
from shapely.geometry import LineString, shape

B = runpy.run_path(str(Path(__file__).with_name('build-city170-bike-racks.py')))
R, P, W, F, H, read, project = (B[k] for k in ('R','P','W','F','H','read','project'))
MAX_OFFSET = 2.25
SIGN_RADIUS = .64


def guidepost(tags):
    return (
        tags.get('tourism') == 'information' and tags.get('information') == 'guidepost'
        and tags.get('hiking') != 'no' and tags.get('highway') in {None, 'trailhead'}
        and tags.get('access') in H['OPEN_ACCESS'] and not H['off_ground'](tags)
        and not tags.get('fixme') and tags.get('location') in {None, 'outdoor', 'outdoors', 'ground'}
        and all(tags.get(key) in {None, 'no'} for key in ('disused', 'abandoned', 'construction'))
    )


def hiking_way(tags):
    if (tags.get('highway') not in {'path', 'footway', 'steps'}
        or tags.get('access') not in H['OPEN_ACCESS'] or tags.get('foot') not in H['OPEN_ACCESS']
        or H['off_ground'](tags) or tags.get('footway') in {'sidewalk','crossing'}):
        return False
    name=tags.get('name','')
    return bool(tags.get('sac_scale') or tags.get('hiking')=='yes'
                or (re.search(r'步道|古道|山徑|大縱走',name) and '自行車' not in name))


def scan(source, city):
    candidates, trail_ids = [], set()
    for row in B['elements'](source):
        tags=row.get('tags',{})
        if row['type']=='way' and hiking_way(tags):
            trail_ids.add(row['id'])
        elif row['type']=='node' and tags.get('information')=='guidepost':
            ll=Point(row['lon'],row['lat'])
            if city.covers(ll):
                candidates.append((row['id'],tags,ll))
    return candidates,trail_ids


def map_trails(data, ids):
    written={}
    for file in sorted((data/'city170').glob('p*.json.gz')):
        for row in read(file)['features']['features']:
            name=row['id']
            if not name.startswith('walk/way/') or name in written or row['geometry']['type']!='LineString':
                continue
            if int(name.rsplit('/',1)[1]) in ids and not H['off_ground'](row['properties']):
                written[name]=project(shape(row['geometry']))
    return STRtree(list(written.values()))


def offsets(center, trail):
    yield center
    at=trail.project(center)
    a,b=(trail.interpolate(x) for x in (max(0,at-1.4),min(trail.length,at+1.4)))
    length=a.distance(b)
    if length<.7:
        return
    x,y=(b.x-a.x)/length,(b.y-a.y)/length
    for radius in (.55,1.,1.4,1.8,2.2):
        for sign in (1,-1):
            for tangent in (0,.32,-.32):
                p=Point(center.x-sign*radius*y+tangent*x,center.y+sign*radius*x+tangent*y)
                if center.distance(p)>MAX_OFFSET:
                    continue
                if trail.distance(center)>.25 and LineString([center,p]).crosses(trail):
                    continue
                yield p


def build(source,data):
    digest=read(data/'city170/index.json')['source']['provenance']['taipeiExtractUncompressedSHA256']
    with gzip.open(source,'rb') as f:
        if hashlib.file_digest(f,'sha256').hexdigest()!=digest:
            raise ValueError('Wrong Taipei OSM snapshot')
    city=shape(read(data/'city170-boundary.json'))
    source_rows,ways=scan(source,city)
    hiking=map_trails(data,ways)
    _,conflicts,trees=B['outdoor_indexes'](data,[])
    terrain=F['Survey'](data)
    covered=H['survey_cover'](terrain,data)
    by_id=read(data/'city170/grid.json.gz')['features']
    districts=read(data/'districts.geojson')['features']
    grid=STRtree([shape(row['geometry']) for row in by_id])
    admins=STRtree([shape(row['geometry']) for row in districts])
    out,skips,district_counts=defaultdict(dict),Counter(),Counter()
    placed=[]
    reviewed=0
    shifted=0
    maximum=0
    for ident,tags,original in sorted(source_rows,key=lambda r:r[0]):
        if not guidepost(tags):
            skips['other-or-non-ground-guidepost']+=1
            continue
        anchor=project(original)
        if not len(hiking.geometries):
            skips['no-documented-trail-nearby']+=1
            continue
        path=hiking.geometries[hiking.nearest(anchor)]
        if path.distance(anchor)>8:
            skips['no-documented-trail-nearby']+=1
            continue
        reviewed+=1
        anchor_admin=admins.query(original,predicate='within')
        if len(anchor_admin)!=1:
            skips['ambiguous-district']+=1
            continue
        district=anchor_admin[0]
        path_axis=B['primary_axis'](LineString([path.interpolate(max(0,path.project(anchor)-1.4)),
                                               path.interpolate(min(path.length,path.project(anchor)+1.4))]))
        for candidate in offsets(anchor,path):
            lon,lat=F['REVERSE'].transform(candidate.x,candidate.y)
            ll=Point(round(lon,8),round(lat,8))
            center=project(ll)
            distance=anchor.distance(center)
            if distance>MAX_OFFSET or path.distance(center)>8:
                continue
            if any(len(tree.query(center,predicate='dwithin',distance=SIGN_RADIUS)) for tree in conflicts):
                continue
            if len(trees.query(center,predicate='dwithin',distance=SIGN_RADIUS+.35)):
                continue
            if any(center.distance(p)<1.4 for p in placed):
                continue
            if covered(ll,center,SIGN_RADIUS) or not P['flat_ground'](terrain,center,.20):
                continue
            cell=grid.query(ll,predicate='within')
            if len(cell)!=1 or not shape(districts[district]['geometry']).covers(ll):
                continue
            pack=by_id[cell[0]]['properties']['pack']
            out[pack][f'trail-sign/node/{ident}']=[ll.x,ll.y,'trail-guidepost',1,path_axis,0]
            district_counts[districts[district]['properties']['name']]+=1
            placed.append(center)
            shifted+=int(distance>.015)
            maximum=max(maximum,distance)
            break
        else:
            skips['no-clear-trailside-location']+=1
    receipt=dict(osmSHA256=digest,sourceGuideposts=len(source_rows),recognizedTrailGuideposts=reviewed,
                 illustrated=len(placed),shiftedWithinVerge=shifted,maxOffsetMetres=round(maximum,3),
                 districts=district_counts,exclusions=skips)
    return receipt,out


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for field in ('source','data','output'):
        parser.add_argument(field,type=Path)
    args=parser.parse_args()
    receipt,rows=build(args.source,args.data)
    def encode(value):
        return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'))
    args.output.write_text('// OpenStreetMap contributors · ODbL. Generated by scripts/build-city170-trail-signs.py.\n'
                           f'export const trailSignSnapshot={encode(receipt)};\n'
                           f'export default {encode(rows)};\n',encoding='utf-8')
    print(encode(receipt))
