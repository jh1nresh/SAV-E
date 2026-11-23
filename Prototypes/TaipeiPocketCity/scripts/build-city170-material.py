"""Add mapped campuses and street businesses to Taipei's existing façade material mask."""
import gzip
import json
import math
from pathlib import Path
from PIL import Image,ImageDraw,ImageChops

data=Path('data')
bounds=json.loads((data/'city-streets/index.json').read_text())['materialBounds']
west,north,east,south=bounds
original=Image.open(data/'city-streets/material-mask.png').convert('RGB')
w,h=original.size

def pixel(coordinates):
    lon,lat=coordinates[:2]
    x=(lon+180)/360
    y=(1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2
    return ((x-west)/(east-west)*(w-1),(y-north)/(south-north)*(h-1))

campuses=Image.new('L',original.size,0)
school_draw=ImageDraw.Draw(campuses)
for f in json.load(gzip.open(data/'city170/schools.json.gz'))['features']:
    g=f['geometry']
    if g['type'] not in ('Polygon','MultiPolygon'): continue
    for rings in ([g['coordinates']] if g['type']=='Polygon' else g['coordinates']):
        for i,ring in enumerate(rings):
            school_draw.polygon([pixel(p) for p in ring],fill=30 if i==0 else 0)

red,shops,landmarks=original.split()
draw=ImageDraw.Draw(shops)
for path in sorted((data/'city170').glob('p*.json.gz')):
    for f in json.load(gzip.open(path))['features']['features']:
        p=f['properties']
        if p['kind']!='poi' or p.get('vendor') or p.get('category') not in (
            'restaurant','fast_food','cafe','bakery','clothes','convenience','books','supermarket',
            'hairdresser','gift','ice_cream','tea','confectionery','beverages','shoes','optician','florist'
        ): continue
        if p.get('level') not in (None,'0'): continue
        x,y=pixel(f['geometry']['coordinates'])
        draw.ellipse((x-1.0,y-.8,x+1.0,y+.8),fill=240)
Image.merge('RGB',(red,shops,ImageChops.lighter(landmarks,campuses))).save(data/'city170-material.png')
