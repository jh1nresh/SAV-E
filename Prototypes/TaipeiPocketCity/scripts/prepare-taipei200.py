"""Run the installed Pocket City preparer for each 200 m Taipei plot.

Run in TaipeiPocketCity with --work pointing outside the public map. Original
per-cell scene files are retained for detail authoring and resumable builds.
Use the same frozen OSM extract as the published survey atlas.
"""
import argparse
from concurrent.futures import ProcessPoolExecutor
from contextlib import redirect_stdout
import gzip
import hashlib
import io
import json
import math
import multiprocessing
import os
from pathlib import Path
import runpy
import sys
import tempfile

from pyproj import Transformer
from shapely import make_valid
from shapely.geometry import box, shape
from shapely.ops import transform, unary_union

HERE = Path(__file__).resolve().parent
OLD = runpy.run_path(str(HERE/'prepare-city170.py'))
encode = OLD['encode']
SIZE = 200


def cells():
    project = Transformer.from_crs(4326,3826,always_xy=True).transform
    geo = Transformer.from_crs(3826,4326,always_xy=True).transform
    districts = json.loads(Path('data/districts.geojson').read_bytes())['features']
    areas = [(row['properties']['name'],make_valid(transform(project,shape(row['geometry'])))) for row in districts]
    city = unary_union([area for _,area in areas])
    west,south,east,north = city.bounds
    for x in range(math.floor(west/SIZE),math.ceil(east/SIZE)):
        for y in range(math.floor(south/SIZE),math.ceil(north/SIZE)):
            square = box(x*SIZE,y*SIZE,(x+1)*SIZE,(y+1)*SIZE)
            footprint = city.intersection(square)
            if footprint.area < 1e-6:
                continue
            names = [name for name,area in areas if area.intersects(square) and area.intersection(square).area > 1e-6]
            point = geo((x+.5)*SIZE,(y+.5)*SIZE)
            north_point = geo((x+.5)*SIZE,(y+1)*SIZE)
            east_offset = (north_point[0]-point[0])*math.cos(math.radians(point[1]))
            # Kit local +y is true north rotated counterclockwise by rotation.
            angle = -math.degrees(math.atan2(east_offset,north_point[1]-point[1]))
            yield [x,y,point,angle,names,transform(geo,footprint).bounds]


def prepare(cell):
    x,y,(lon,lat),rotation,names,bounds = cell
    key = f'{x}_{y}'
    final = WORK/'scenes'/f'{key}.json.gz'
    if final.exists():
        return
    worker = SCRATCH/str(os.getpid())
    osm,plot,scene = (worker.with_suffix('.'+ext) for ext in ('osm','plot','scene'))
    margin = 170 + HALO
    dx = margin/(111320*math.cos(math.radians(lat)))
    dy = margin/110574
    hits = INDEX.query(box(lon-dx,lat-dy,lon+dx,lat+dy))
    osm.write_bytes(b'{"elements":['+b','.join(RECORDS[k] for k in sorted(hits) if k not in SKIP)+b']}')
    plot.write_bytes(encode({'lat':lat,'lon':lon,'rotation':rotation,'size':SIZE + 2*HALO,'place':'、'.join(names)}))
    sys.argv = [str(PREP),'--drive','right','--osm',str(osm),'--plot',str(plot),'--out',str(scene)]
    with redirect_stdout(io.StringIO()):
        RUN()
    payload = scene.read_bytes()
    if HALO:
        source = json.loads(payload)
        payload = encode({k: source[k] for k in ('meta', 'markings', 'centerlines', 'walk', 'paths')})
    temp = final.with_suffix('.partial')
    temp.write_bytes(gzip.compress(payload,compresslevel=3,mtime=0))
    temp.replace(final)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--osm',type=Path,required=True)
    parser.add_argument('--skill',type=Path,required=True)
    parser.add_argument('--work',type=Path,required=True)
    parser.add_argument('--workers',type=int,default=4)
    parser.add_argument('--paint-halo', action='store_true', help='Retain street paint with 25 m of context beyond each edge.')
    args=parser.parse_args()
    HALO = 25 if args.paint_halo else 0
    WORK=args.work.resolve()
    (WORK/'scenes').mkdir(parents=True,exist_ok=True)
    PREP=args.skill/'scripts/prep.py'
    sys.path.insert(0,str(PREP.parent))
    script=PREP.read_text()
    # Same edge case as prepare-city170.py: a buffered water polygon can be
    # large while its inner boat placement area is empty.
    guard='if not wide.is_empty and wide.area > 300:'
    assert script.count(guard)==1
    safe=script.replace(guard,guard[:-1]+' and not wide.intersection(SQ.buffer(-2)).is_empty:')
    ns={'__name__':'pocket_city_prep','__file__':str(PREP)}
    exec(compile(safe,str(PREP),'exec'),ns)
    RUN=ns['main']
    jobs=list(cells())
    jobs.sort(key=lambda cell:(not bool(set(cell[4])&{'信義區','松山區'}),cell[0]//8,cell[1]//8,cell[0],cell[1]))
    with gzip.open(args.osm,'rb') as contents:
        digest=hashlib.file_digest(contents,'sha256').hexdigest()
    expected=json.loads(Path('data/city170/index.json').read_bytes())['source']['provenance']['taipeiExtractUncompressedSHA256']
    assert digest==expected, 'The OSM extract differs from the frozen survey atlas.'
    grade_path = Path('city170-grade-ids.js')
    grade_rule = HERE/'build-city170-grade.py'
    grade_digest = hashlib.sha256(grade_path.read_bytes() + grade_rule.read_bytes()).hexdigest() if HALO else None
    inputs=encode({'crs':'EPSG:3826','size':SIZE,'cells':jobs,'paintHalo':HALO,'paintGradeSHA256':grade_digest,'osmSHA256':digest,
                   'prepSHA256':hashlib.sha256(safe.encode()).hexdigest(),
                   'generatorSHA256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()})
    manifest=WORK/'input.json'
    if manifest.exists() and manifest.read_bytes()!=inputs:
        raise ValueError('Use a new work directory for a different input or generator.')
    manifest.write_bytes(inputs)
    pending=[cell for cell in jobs if not (WORK/'scenes'/f'{cell[0]}_{cell[1]}.json.gz').exists()]
    print(f'{len(jobs)} cells in twelve districts, {len(pending)} to prepare',flush=True)
    if pending:
        RECORDS,INDEX=OLD['stream_index'](args.osm)
        SKIP = set()
        if HALO:
            above_or_below = runpy.run_path(str(grade_rule))['above_or_below_ground']
            grade = json.loads(grade_path.read_text().split('export default ')[1].rstrip(';\n'))
            excluded = {(key.split('/')[1], ident) for key, ids in grade.items()
                        if key.split('/')[0] in ('road','walk') for ident in ids}
            for k, raw in enumerate(RECORDS):
                row = json.loads(raw)
                tags = row.get('tags', {})
                if ((row['type'], row['id']) in excluded
                        or (('highway' in tags or 'area:highway' in tags or tags.get('place') == 'square')
                            and above_or_below(tags))):
                    SKIP.add(k)
        print(f'{len(RECORDS)} indexed source elements',flush=True)
        with tempfile.TemporaryDirectory(dir=WORK) as scratch:
            SCRATCH=Path(scratch)
            with ProcessPoolExecutor(args.workers,mp_context=multiprocessing.get_context('fork')) as pool:
                for n,_ in enumerate(pool.map(prepare,pending,chunksize=4),1):
                    if n%200==0:print(f'{n}/{len(pending)}',flush=True)
    print('All cell scenes written.',flush=True)
