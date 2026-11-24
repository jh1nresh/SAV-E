"""Index existing illustrated pedestrian routes and scenery by intersecting neighbourhood packs."""
from collections import defaultdict
import gzip,json,hashlib,math
from pathlib import Path
from pyproj import Transformer
from shapely.geometry import LineString,box
from shapely.strtree import STRtree

root=Path('data')
out=root/'city170-life'
out.mkdir(exist_ok=True)
def read(file):
    return json.loads(gzip.decompress(file.read_bytes()) if file.suffix=='.gz' else file.read_bytes())
def key(row):
    return hashlib.blake2s(json.dumps(row,sort_keys=True).encode(),digest_size=10).hexdigest()
packs=read(root/'city170/index.json')['packs']
boxes=[box(*p['bounds']) for p in packs]
tree=STRtree(boxes)
to_grid=Transformer.from_crs(4326,3826,always_xy=True).transform
items={p['id']:{'paths':{},'objects':{}} for p in packs}
extra=read(root/'street-pocket-city.json.gz')['districts']
for file in sorted(root.glob('street-*-district.json'))+sorted((root/'city-streets').glob('*-district.json.gz')):
    records=read(file)
    district=file.name.removeprefix('street-').split('.')[0]
    for record in [records,extra.get(district,{})]:
        for obj in record.get('objects',[]):
            x,y=to_grid(*obj[:2])
            pack=f'p{math.floor(x/1360)}_{math.floor(y/1360)}'
            if pack in items: items[pack]['objects'][key(obj)]=obj
        for path in record.get('paths',[]):
            if len(path['points'])<2:continue
            ident=key(path)
            for hit in tree.query(LineString(path['points']),predicate='intersects'):
                items[packs[hit]['id']]['paths'][ident]=path
for pack,contents in items.items():
    (out/(pack+'.json.gz')).write_bytes(gzip.compress(json.dumps(contents,separators=(',',':')).encode(),mtime=0))
