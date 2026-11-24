"""Generalize actual mapped landscape for the city scale before street packs load."""
from pathlib import Path
import gzip
import json
from shapely.geometry import shape,mapping

folder=Path('data/city170')
features=[]
for pack in sorted(folder.glob('p*.json.gz')):
    for f in json.load(gzip.open(pack))['features']['features']:
        if f['properties']['kind'] in ('park','pitch','forest','water'):
            geometry=shape(f['geometry']).simplify(.000025,preserve_topology=True)
            if geometry.is_empty:
                continue
            features.append({**f,'geometry':mapping(geometry),'bbox':list(geometry.bounds)})
raw=json.dumps({'type':'FeatureCollection','features':features},ensure_ascii=False,separators=(',',':')).encode()
Path('data/city170-landscape.json.gz').write_bytes(gzip.compress(raw,mtime=0))
print(len(features))
