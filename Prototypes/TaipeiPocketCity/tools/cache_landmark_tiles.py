"""Freeze OpenFreeMap and Terrarium tiles for the immediate surroundings of each landmark."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import math
from pathlib import Path
import subprocess
from urllib.parse import urlsplit

ROOT=Path(__file__).resolve().parents[1]/'cities'
parser=argparse.ArgumentParser()
parser.add_argument('--resolve',action='append',default=[],help='Optional curl HOST:443:IP overrides for local DNS outages')
args=parser.parse_args()
options=[arg for value in args.resolve for arg in ['--resolve',value]]
def fetch(url):
    return subprocess.check_output(['curl','--fail','--silent','--show-error','--compressed','--max-time','30',*options,url])
def tile(lon,lat):
    return int((lon+180)/360*16384),int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)*8192)
folder=ROOT/'map-tiles';folder.mkdir(exist_ok=True)
manifest=folder/'index.json'
info=json.loads(fetch('https://tiles.openfreemap.org/planet'))
source=info['tiles'][0]
if manifest.exists():
    # Keep a coherent snapshot while adding counties to an existing release.
    source=json.loads(manifest.read_text())['vectorTemplate']
keys=set()
for path in ROOT.glob('*/metadata.json'):
    west,south,east,north=json.loads(path.read_text())['bounds']
    x0,y0=tile(west-.002,north+.002);x1,y1=tile(east+.002,south-.002)
    keys.update((x,y) for x in range(x0,x1+1) for y in range(y0,y1+1))
def cache(key):
    x,y=key
    for ext,url in [('pbf',source.format(z=14,x=x,y=y)),('png',f'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/14/{x}/{y}.png')]:
        dest=folder/f'{x}-{y}.{ext}'
        if dest.is_file():continue
        raw=fetch(url)
        if (ext=='png' and raw[:8]!=b'\x89PNG\r\n\x1a\n') or (ext=='pbf' and raw[:1]!=b'\x1a'):
            raise ValueError(f'Invalid {ext} tile {x}/{y}')
        dest.write_bytes(raw)
with ThreadPoolExecutor(4) as pool:list(pool.map(cache,sorted(keys)))
manifest.write_text(json.dumps(dict(vectorTemplate=source,attribution=info['attribution'],tiles=[list(v) for v in sorted(keys)]),ensure_ascii=False,indent=2)+'\n')
print(f'{len(keys)} vector / elevation tile pairs')
