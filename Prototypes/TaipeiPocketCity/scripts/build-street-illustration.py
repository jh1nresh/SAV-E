"""Build the Hybrid map backdrop from the local LOD1 survey and terrain data.

Run from the preview root with:
    uv run --no-project --with numpy --with shapely --with pillow python scripts/build-street-illustration.py
"""
import gzip, json, math
from functools import lru_cache
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageChops, ImageFilter
from shapely import MultiPoint
from shapely.geometry import shape
from shapely.ops import unary_union

data=Path('data')
manifest=json.loads((data/'street-atlas.json').read_text())
west,north,east,south=manifest['materialBounds']
def merc(lng,lat):
    return (lng+180)/360,(1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2
def geographic(x,y):
    return x*360-180,math.degrees(math.atan(math.sinh(math.pi*(1-2*y))))
area=unary_union([shape(f['geometry']) for f in json.loads((data/'districts.geojson').read_text())['features']
                   if f['properties']['name'] in ('信義區','大安區','松山區','中山區')])
size=1024
zoom=15
scale=2**zoom
xmin,xmax=int(west*scale),int(east*scale)
ymin,ymax=int(north*scale),int(south*scale)
width,height=(xmax-xmin+1)*size,(ymax-ymin+1)*size

@lru_cache
def terrain_tile(x,y):
    path=data/'terrain'/'street-atlas'/f'14-{x}-{y}.png'
    if not path.exists():return None
    rgb=np.asarray(Image.open(path).convert('RGB'),dtype=np.float32)
    return rgb[:,:,0]*256+rgb[:,:,1]+rgb[:,:,2]/256-32768

def ground_at(x,y):
    tx,ty=x*2**14,y*2**14
    ix,iy=int(tx),int(ty)
    values=terrain_tile(ix,iy)
    if values is None:return None
    return float(values[int((ty-iy)*256),int((tx-ix)*256)])

def pixel(x,y):
    return ((x*scale-xmin)*size,(y*scale-ymin)*size)
district=Image.new('L',(width,height))
pen=ImageDraw.Draw(district)
for polygon in getattr(area,'geoms',[area]):
    pen.polygon([pixel(*merc(x,y)) for x,y in polygon.exterior.coords],fill=255)
mask=Image.new('L',(width,height))
ink=ImageDraw.Draw(mask)
models=0
shadows=0
w,s,e,n=area.bounds
q=np.array([.36,-.31],dtype=np.float64)
index=json.loads((data/'survey-index.json').read_text())['levels']['200']
for tile in index:
    tw,ts,te,tn=tile['box']
    if te<w-.001 or tn<s-.001 or tw>e+.001 or ts>n+.001:continue
    v=np.frombuffer(gzip.decompress((data/'200'/f"{tile['id']}.bin.gz").read_bytes()), dtype='<f4').reshape(-1,6)
    breaks=np.r_[0,np.flatnonzero(np.any(v[1:,3:]!=v[:-1,3:],axis=1))+1,len(v)]
    for a,b in zip(breaks[:-1],breaks[1:]):
        h=float(v[a,4])
        if h<4 or b-a<6:continue
        coords=np.unique(v[a:b,:2],axis=0)
        if len(coords)<3:continue
        outline=MultiPoint(coords).convex_hull
        if outline.geom_type!='Polygon' or outline.area<5:continue
        center=outline.centroid
        ground=ground_at(tile['mx']+center.x*tile['m'],tile['my']-center.y*tile['m'])
        if ground is None:continue
        exposed_height=float(v[a:b,2].max())-ground
        if exposed_height<3.1:continue
        xy=np.asarray(outline.exterior.coords)
        cast=xy+min(h,exposed_height,72)*q
        outline_cast=MultiPoint(np.concatenate((xy,cast))).convex_hull.difference(outline)
        for part in getattr(outline_cast,'geoms',[outline_cast]):
            if part.geom_type!='Polygon' or part.is_empty:continue
            ring=[pixel(tile['mx']+x*tile['m'],tile['my']-y*tile['m']) for x,y in part.exterior.coords]
            ink.polygon(ring,fill=255)
        models+=1
# Soften a single raster pixel for clean rotated and scaled edges.
shadow=ImageChops.multiply(mask.filter(ImageFilter.GaussianBlur(.35)),district).point(lambda v: round(v*.30))
for ix in range(xmin,xmax+1):
    for iy in range(ymin,ymax+1):
        x,y=(ix-xmin)*size,(iy-ymin)*size
        alpha=shadow.crop((x,y,x+size,y+size))
        tile=Image.new('RGBA',(size,size),(48,62,113,0))
        tile.putalpha(alpha)
        path=data/'shadows'/str(ix)
        path.mkdir(exist_ok=True,parents=True)
        tile.save(path/f'{iy}.png',optimize=True)
        if alpha.getbbox():shadows+=1
# Include map coverage bounds as tile-aligned values inside the source options.
lon0,lat0=geographic(xmin/scale,(ymax+1)/scale)
lon1,lat1=geographic((xmax+1)/scale,ymin/scale)
info={'bounds':[lon0,lat0,lon1,lat1],'zoom':zoom}
(data/'street-shadows.json').write_text(json.dumps(info,separators=(',',':'))+'\n')

# The existing alpha coverage remains the red channel. Green marks façades
# near mapped shops rather than coloring every ground floor in the district.
original=Image.open(data/'street-atlas-material-mask.png').convert('L')
w,h=original.size
shops=Image.new('L',(w,h))
windows=ImageDraw.Draw(shops)
total=0
for scene in ('101','daan-district','xinyi-district','songshan-district','zhongshan-district','xinyi-link','yongchun','songshan'):
    for place in json.loads((data/f'street-{scene}.json').read_text())['places']:
        if place['kind'] not in ('餐廳','咖啡','麵包','書店','超商','超市','茶飲','熟食','選物','商店'):continue
        x,y=merc(*place['point'])
        x=(x-west)/(east-west)*(w-1)
        y=(y-north)/(south-north)*(h-1)
        windows.ellipse((x-2.9,y-2.9,x+2.9,y+2.9),fill=255)
        total+=1
Image.merge('RGB',(original,shops.filter(ImageFilter.GaussianBlur(.48)),Image.new('L',original.size))).save(data/'street-hybrid-material-mask.png',optimize=True)
print('Shadow footprints:',models,'non-empty tiles:',shadows,'raw tiles:',(xmax-xmin+1)*(ymax-ymin+1),'shops:',total)
