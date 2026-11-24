"""Prepare every Taipei cell with the installed Pocket City kit, retaining close-range paint."""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from contextlib import redirect_stdout
import gzip
import hashlib
import importlib.util
import io
import json
import math
import multiprocessing
import os
from glob import glob
from pathlib import Path
import sys
import tempfile

from city170_groves import unique_groves
import ijson
from pyproj import Transformer
from shapely import make_valid
from shapely.geometry import Point, box, mapping, shape
from shapely.ops import transform, unary_union
from shapely.strtree import STRtree

def encode(data):
    return json.dumps(data, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode()

def stream_index(path):
    nodes, ways, records, boxes = {}, {}, [], []
    def add(record, bounds):
        records.append(encode(record))
        boxes.append(bounds)
    def vertices(coords):
        return [{'lon':lon, 'lat':lat} for lon,lat in coords]
    def envelope(coords):
        xs, ys = zip(*coords)
        return box(min(xs), min(ys), max(xs), max(ys))
    with gzip.open(path, 'rb') as stream:
        for row in ijson.items(stream, 'elements.item', use_float=True):
            tags = row.get('tags', {})
            if row['type'] == 'node':
                pos = row['lon'], row['lat']
                nodes[row['id']] = pos
                if tags.keys() & {'natural','highway','amenity','shop','tourism','railway','entrance','barrier','public_transport','man_made'}:
                    add(row, Point(pos))
            elif row['type'] == 'way':
                coords = [nodes[i] for i in row['nodes']]
                if len(coords) < 2:
                    continue
                ways[row['id']] = coords
                if tags:
                    add({'type':'way','id':row['id'],'tags':tags,'geometry':vertices(coords)},envelope(coords))
            elif row['type'] == 'relation':
                members = [m for m in row['members'] if m['type']=='way' and m['ref'] in ways]
                if members:
                    add({'type':'relation','id':row['id'],'tags':tags,'members':[
                        {'role':m['role'],'geometry':vertices(ways[m['ref']])} for m in members
                    ]},envelope([p for m in members for p in ways[m['ref']]]))
    return records, STRtree(boxes)

def jobs():
    to_local=Transformer.from_crs(4326,3826,always_xy=True).transform
    to_geo=Transformer.from_crs(3826,4326,always_xy=True).transform
    districts=json.loads(Path('data/districts.geojson').read_bytes())['features']
    area=unary_union([make_valid(transform(to_local, shape(d['geometry']))) for d in districts])
    w,s,e,n=area.bounds
    for i in range(math.floor(w/170), math.ceil(e/170)):
        for j in range(math.floor(s/170), math.ceil(n/170)):
            part=area.intersection(box(i*170,j*170,(i+1)*170,(j+1)*170))
            if part.area>0:
                yield i,j,to_geo((i+.5)*170,(j+.5)*170),transform(to_geo,part)

def prepare(job):
    i,j,(lon,lat),boundary=job
    work=Path(SCRATCH)/str(os.getpid())
    osm,plot,scene=[work.with_suffix('.'+ext) for ext in ('osm','plot','scene')]
    dx=140/(111320*math.cos(math.radians(lat)))
    dy=140/110574
    selected=TREE.query(box(lon-dx,lat-dy,lon+dx,lat+dy))
    osm.write_bytes(b'{"elements":['+b','.join(RECORDS[k] for k in sorted(selected))+b']}')
    # Context beyond the exact cell lets adjacent cells derive the same complete crossings.
    plot.write_bytes(encode({'lat':lat,'lon':lon,'rotation':0,'size':218,'place':f'{i}_{j}'}))
    sys.argv=[str(PREP),'--osm',str(osm),'--plot',str(plot),'--out',str(scene),'--drive','right']
    log=io.StringIO()
    with redirect_stdout(log):
        PREPARE()
    result=json.loads(scene.read_bytes())
    _,paint,_,crossings=ADAPTER.adapt_scene(result,boundary,(i,j),continuous_crossings=True)
    # A city-anchored lattice thins illustrative crowns without restarting a row at each cell.
    seen=set()
    east=111320*math.cos(math.radians(lat))
    for x,y,species,_ in result['trees']:
        if not 0 <= species < len(result['species']) or result['species'][species] not in ('Woodland','Garden tree','Park tree'):
            continue
        point=Point(lon+x/east,lat+y/110574)
        mx,my=TO_METRES(point.x,point.y)
        gx,gy=math.floor(mx/16),math.floor(my/16)
        site=(gx*16+8,gy*16+8)
        if math.dist((mx,my),site)>3.9 or (gx,gy) in seen or not boundary.covers(point):
            continue
        if EXISTING.query(Point(mx,my),predicate='dwithin',distance=8).size:
            continue
        seen.add((gx,gy))
        paint.append({'type':'Feature','geometry':mapping(point),'properties':{
            'kind':'grove-tree','variant':(gx*17+gy*7)%4}})

    return i,j,paint,{'buildings':len(result['buildings']),'trees':len(result['trees']),
                      'routes':len(result['routes']),'crossings':crossings,'walkWarnings':int('walk fix skipped' in log.getvalue())}

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('osm',type=Path)
    parser.add_argument('skill',type=Path)
    parser.add_argument('--workers',type=int,default=6)
    args=parser.parse_args()
    PREP=args.skill/'scripts/prep.py'
    sys.path.insert(0,str(PREP.parent))
    source=PREP.read_text()
    guard='if not wide.is_empty and wide.area > 300:'
    assert source.count(guard)==1
    namespace={'__name__':'pocket_city_prep','__file__':str(PREP)}
    exec(compile(source.replace(guard,guard[:-1]+' and not wide.intersection(SQ.buffer(-2)).is_empty:'),str(PREP),'exec'),namespace)
    PREPARE=namespace['main']
    spec=importlib.util.spec_from_file_location('street_adapter',Path(__file__).with_name('rebuild-pocket-city-streets.py'))
    ADAPTER=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ADAPTER)
    ADAPTER.EXPAND_SURFACES=False
    ADAPTER.CELL_SIZE=170
    TO_METRES=Transformer.from_crs(4326,3826,always_xy=True).transform
    existing=[]
    for filename in glob('data/street-*.json')+glob('data/city-streets/*-district.json.gz'):
        payload=ADAPTER.read(Path(filename))
        if isinstance(payload,dict):
            existing.extend(Point(*TO_METRES(x,y)) for x,y,kind,*_ in payload.get('objects',[]) if kind=='tree')
    for filename in glob('data/city170/p*.json.gz'):
        for feature in ADAPTER.read(Path(filename))['features']['features']:
            if feature['properties']['kind']=='tree':
                existing.append(Point(*TO_METRES(*feature['geometry']['coordinates'])))
    EXISTING=STRtree(existing)
    RECORDS,TREE=stream_index(args.osm)
    all_jobs=list(jobs())
    all_jobs.sort(key=lambda job:(job[0]//8,job[1]//8))
    print('Indexed',len(RECORDS),'elements.',len(all_jobs),'cells.',flush=True)
    cells={}
    pack_count=0
    previous=None
    totals=Counter()
    out=Path('data/city170-prepared')
    out.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as SCRATCH, ProcessPoolExecutor(args.workers,mp_context=multiprocessing.get_context('fork')) as pool:
        for count,(i,j,paint,stats) in enumerate(pool.map(prepare,all_jobs,chunksize=6),1):
            key=f'{i//8}_{j//8}'
            if previous is not None and previous!=key:
                (Path(SCRATCH)/(previous+'.json.gz')).write_bytes(gzip.compress(encode(cells),compresslevel=4,mtime=0))
                cells.clear()
                pack_count+=1
            previous=key
            cells[f'{i}_{j}']=paint
            totals.update(stats)
            if count%500==0:
                print(count,flush=True)
        (Path(SCRATCH)/(previous+'.json.gz')).write_bytes(gzip.compress(encode(cells),compresslevel=4,mtime=0))
        pack_count+=1
        totals['groveCrowns']=unique_groves(SCRATCH)
        for staged in Path(SCRATCH).glob('*.json.gz'):
            staged.replace(out/staged.name)
    receipt={'cells':len(all_jobs),'packs':pack_count,'cellSize':170,'prepSHA256':hashlib.sha256(PREP.read_bytes()).hexdigest(),'counts':totals}
    (out/'receipt.json').write_bytes(encode(receipt))
    print(receipt)
