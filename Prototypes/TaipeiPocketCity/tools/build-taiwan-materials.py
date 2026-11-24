"""Attach sparse OSM building tags to the signed OSM IDs in the published street shards.
Run with Python 3.11+, pyosmium and Shapely 2. Reuses the street extractor's boundary rules.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import runpy

import osmium
from shapely.geometry import Polygon

ROOT=Path(__file__).resolve().parents[1]/'taiwan'
FIELDS=('building','building:use','building:material','building:colour','roof:shape','roof:material',
        'roof:colour','building:levels','roof:levels','amenity','shop','tourism','office','historic','leisure')
EMPTY={'','yes','no','unknown','undefined','unspecified','other'}
TILES_PER_GROUP=8


def sparse(tags):
    flat=[]
    for i,key in enumerate(FIELDS):
        raw=tags.get(key)
        if not raw and key.endswith(':colour'):
            raw=tags.get(key.replace(':colour',':color'))
        if not raw:continue
        value=raw.strip().lower()
        if value in EMPTY or len(value)>80 or any(ord(ch)<32 for ch in value):continue
        if key.endswith(':levels'):
            try:
                number=float(value)
            except ValueError:
                continue
            if not 0<=number<=180:continue
            value=int(number) if number.is_integer() else number
        flat.extend([i,value])
    return tuple(flat)


def decoded(line,x,y):
    points=[]
    for i in range(0,len(line),2):
        x+=line[i];y+=line[i+1];points.append((x/100000,y/100000))
    return points


def build(pbf,out):
    street=json.loads((ROOT/'streets/index.json').read_text())
    with pbf.open('rb') as f:
        if hashlib.file_digest(f,'sha256').hexdigest()!=street['sha256']:
            raise ValueError('PBF does not match the published street snapshot')
    tools=runpy.run_path(str(Path(__file__).with_name('build-taiwan-streets.py')))
    counties=tools['Counties']()
    profiles={}
    paths=[pbf]
    for info in street['supplements'].values():
        f=ROOT/'scenery'/info['file']
        if hashlib.sha256(f.read_bytes()).hexdigest()!=info['sha256']:raise ValueError(f)
        paths.append(f)
    for path in paths:
        for feature in osmium.FileProcessor(str(path),osmium.osm.WAY|osmium.osm.RELATION).with_filter(
                osmium.filter.KeyFilter(*FIELDS,'roof:color','building:color')):
            values=sparse(feature.tags)
            if values:
                profiles[feature.id if feature.is_way() else -feature.id]=values
    groups=defaultdict(dict)
    stats=defaultdict(Counter)
    seen=set()
    for tile in street['tiles']:
        tx,ty=map(int,tile.split('-'))
        coarse=f'{tx//TILES_PER_GROUP}-{ty//TILES_PER_GROUP}'
        rows=json.loads(gzip.decompress((ROOT/'streets'/(tile+'.json.gz')).read_bytes()))
        for row in rows:
            if row[0]!=1:continue
            _,ident,part,_,rings,*_=row
            profile=profiles.get(ident)
            if profile is None:continue
            groups[coarse][ident]=profile
            fp=(ident,part)
            if fp in seen:continue
            seen.add(fp)
            # On county boundaries use a point guaranteed to lie in the quantized building.
            counties.at((tx+.5)/32,(ty+.5)/32)
            county=counties.grid[tx,ty][0]
            if not county:
                loops=[decoded(line,tx*3125,ty*3125) for line in rings]
                point=Polygon(loops[0],loops[1:]).representative_point()
                county=counties.at(point.x,point.y)
            bucket=stats[county or '邊界未歸屬']
            bucket['tagged']+=1
            for i in profile[::2]:bucket[FIELDS[i]]+=1
    out.mkdir(parents=True,exist_ok=True)
    sizes={}
    for group,items in sorted(groups.items()):
        dictionary={p:i for i,p in enumerate(sorted(set(items.values())))}
        rows=[];previous=0
        for ident,profile in sorted(items.items()):
            rows.extend((ident-previous,dictionary[profile]))
            previous=ident
        raw=tools['json_line']({'profiles':list(dictionary),'rows':rows}).encode()
        content=gzip.compress(raw,compresslevel=9,mtime=0)
        (out/(group+'.json.gz')).write_bytes(content)
        sizes[group]=len(content)
    listing={'version':1,'osm':street['osm'],'sha256':street['sha256'],'license':street['license'],
             'fields':FIELDS,'tilesPerGroup':TILES_PER_GROUP,'tiles':sorted(groups),
             'compressedBytes':sum(sizes.values()),'largestShardBytes':max(sizes.values()),
             'footprints':sum(c['footprints'] for c in street['counties'].values()),'taggedFootprints':len(seen),
             'counties':{name:{'footprints':street['counties'].get(name,{}).get('footprints',0),**stats[name]}
                         for name in sorted(set(stats)|set(street['counties']))}}
    (out/'index.json').write_text(tools['json_line'](listing)+'\n')
    print(f"{len(sizes)} material packs, {len(seen)} tagged footprints of {listing['footprints']}, {sum(sizes.values())} bytes")


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('pbf',type=Path);p.add_argument('--output',type=Path,default=ROOT/'materials')
    args=p.parse_args()
    build(args.pbf,args.output)
