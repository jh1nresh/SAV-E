"""Assign one illustrated crown to each shared 16m lattice position across tile edges."""
from pathlib import Path
import gzip,json,math
from pyproj import Transformer

def unique_groves(folder):
    project=Transformer.from_crs(4326,3826,always_xy=True)
    def rows(cells):
        for cell,features in cells.items():
            for i,f in enumerate(features):
                if f['properties']['kind']=='grove-tree':
                    yield cell,i,f['geometry']['coordinates']
    packs=sorted(Path(folder).glob('*.json.gz'))
    selected={}
    for path in packs:
        cells=json.load(gzip.open(path))
        for cell,i,coords in rows(cells):
            x,y=project.transform(*coords)
            key=math.floor(x/16),math.floor(y/16)
            candidate=((x%16-8)**2+(y%16-8)**2,cell,i)
            if key not in selected or selected[key]>candidate:
                selected[key]=candidate
    keep={(cell,i) for _,cell,i in selected.values()}
    for path in packs:
        cells=json.load(gzip.open(path))
        if not any((cell,i) not in keep for cell,i,_ in rows(cells)):continue
        for cell,features in cells.items():
            cells[cell]=[f for i,f in enumerate(features) if f['properties']['kind']!='grove-tree' or (cell,i) in keep]
        temp=path.with_suffix('.new')
        temp.write_bytes(gzip.compress(json.dumps(cells,separators=(',',':'),allow_nan=False).encode(),compresslevel=4,mtime=0))
        temp.replace(path)
    return len(selected)
