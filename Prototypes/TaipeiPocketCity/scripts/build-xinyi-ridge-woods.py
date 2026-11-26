"""Build Xinyi's illustrated forest relief and understated hiking paths from archived local data.

Run from TaipeiPocketCity with unpacked data/:
    uv run --python 3.12 --with shapely==2.2.0 --with pillow==13.0.0 scripts/build-xinyi-ridge-woods.py

The OSM cliff, exposed rock, viewpoint and summit inventory is pinned in
xinyi-ridge-sites.geojson. Crown locations/sizes illustrate mapped woodland;
individual municipal tree inventories and the existing illustrated groves are kept separate.
"""
import gzip
import json
import math
from pathlib import Path
import random

import numpy as np
from PIL import Image, ImageFilter
import shapely
from shapely.affinity import affine_transform
from shapely.geometry import Point, box, shape

CITY = Path(__file__).resolve().parents[1]
ASSETS, DATA = CITY/'assets', CITY/'data'
LON, LAT = 121.55, 25.01
EAST, NORTH = 111320*math.cos(math.radians(25.03)), 110574
RADIUS = 6.5
SIZE = 1536


def read(path):
    with (gzip.open if path.suffix == '.gz' else open)(path) as src:
        return json.load(src)


def local(g):
    return affine_transform(g, [EAST,0,0,NORTH,-LON*EAST,-LAT*NORTH])


def point_lonlat(x,y):
    return x/EAST+LON, y/NORTH+LAT


def degree_point(p):
    return [round(v,6) for v in point_lonlat(*p)]


class Terrain:
    def __init__(self):
        self.tiles = {}
        self.urls = {}
        for key in read(DATA/'street-atlas.json')['tiles']:
            self.urls[key] = DATA/'terrain/street-atlas'/('14-'+key.replace('/','-')+'.png')
        for key in read(DATA/'city-streets/index.json')['terrainTiles']:
            self.urls[key] = DATA/'city-streets/terrain'/('14-'+key.replace('/','-')+'.png')
        for x,y in read(CITY/'cities/map-tiles/index.json')['tiles']:
            self.urls[f'{x}/{y}'] = CITY/'cities/map-tiles'/f'{x}-{y}.png'
        self.urls['13724/7014'] = ASSETS/'taipei-songyan-factory-terrain.png'

    def sample(self,lon,lat):
        # Bilinear sample of the z14 Terrarium pixel centres, including tile edges.
        xx=(np.asarray(lon)+180)/360*16384*256-.5
        yy=(1-np.arcsinh(np.tan(np.radians(lat)))/np.pi)*.5*16384*256-.5
        xx,yy=np.broadcast_arrays(xx,yy)
        px,py=np.floor(xx).astype(int),np.floor(yy).astype(int)
        result=np.zeros(xx.shape)
        for dx,dy in ((0,0),(1,0),(0,1),(1,1)):
            i,j=px+dx,py+dy
            tileids=(i//256)*16384+(j//256)
            for tile in np.unique(tileids):
                key=f'{tile//16384}/{tile%16384}'
                if key not in self.tiles:
                    rgb=np.asarray(Image.open(self.urls[key]).convert('RGB'),dtype=float)
                    self.tiles[key]=rgb[:,:,0]*256+rgb[:,:,1]+rgb[:,:,2]/256-32768
                m=tileids==tile
                weight=(1-abs(xx-i))*(1-abs(yy-j))
                result[m]+=weight[m]*self.tiles[key][j[m]%256,i[m]%256]
        return result


def landscape():
    district=next(local(shape(f['geometry'])) for f in read(DATA/'districts.geojson')['features']
                  if f['properties']['name']=='信義區')
    forest=[local(shapely.make_valid(shape(f['geometry']))).intersection(district)
            for f in read(DATA/'city170-landscape.json.gz')['features']
            if f['properties'].get('kind')=='forest' and f['properties'].get('category') in ('wood','forest')
            and local(box(*f['bbox'])).intersects(district)]
    wood=shapely.union_all(forest)
    entries=read(DATA/'city170/index.json')['packs']
    near=[e for e in entries if local(box(*e['bounds'])).intersects(wood)]
    owners={key for e in near for key in [e['id'],*e.get('deps',[])]}
    near_wood=wood.buffer(12)
    blocked,structures,old_crowns,paths=[],[],[],[]
    grade=json.loads((CITY/'city170-grade-ids.js').read_text().split('export default ',1)[1].split(';',1)[0])
    excluded={f'{key}/{id}' for key,ids in grade.items() for id in ids}
    for e in entries:
        if e['id'] not in owners:continue
        p=read(DATA/'city170'/e['url'])
        for f in p['features']['features']:
            t=f['properties'];kind=t['kind']
            if kind not in ('building','water','road','walk','pitch'):continue
            g=local(shapely.make_valid(shape(f['geometry'])))
            if not g.intersects(near_wood):continue
            if kind in ('road','walk'):
                width=float(t.get('width',5.4 if kind=='road' else 1.8))
                blocked.append(g.buffer(max(width/2,1.0),quad_segs=3))
                name=t.get('name','')
                if kind=='walk' and name and any(n in name for n in ('步道','登山','石階','獅山','虎山','象山','豹山','九五峰')):
                    ground=f['id'] not in excluded and not float(t.get('layer',0)) and all(t.get(k,'no')=='no' for k in ('bridge','indoor','tunnel'))
                    if ground:paths.append((f['id'],name,g))
            else:
                blocked.append(g)
                structures.append(g)
    for e in near:
        for r in read(DATA/'city170-nature'/e['url']):
            p=local(Point(r[:2]))
            if near_wood.intersects(p):old_crowns.append(p)
        for rows in read(DATA/'city170-prepared'/(e['id'][1:]+'.json.gz')).values():
            for f in rows:
                if f['properties'].get('kind')=='grove-tree':
                    p=local(shape(f['geometry']))
                    if near_wood.intersects(p):old_crowns.append(p)
    exclusion=shapely.union_all(blocked)
    rocks=[]
    for f in read(Path(__file__).with_name('xinyi-ridge-sites.geojson'))['features']:
        g=local(shape(f['geometry']))
        rocks.append(g.buffer(7 if f['properties'].get('natural')=='cliff' else 4))
    bare=shapely.union_all(rocks)
    return wood,exclusion,bare,old_crowns,paths,shapely.union_all(structures)


def understory(inside, metres_x, metres_y):
    """A continuous relief field of overlapping stands and leaf masses, not individual tree records."""
    rng=np.random.default_rng(27109)
    rows,cols=np.nonzero(inside)
    height=np.zeros(inside.shape,dtype=np.float32)
    area=len(rows)*metres_x*metres_y
    # The broad masses fill the valleys between smaller, overlapping crowns.
    # Uniform random centres and variable, rotated shoulders avoid a planting grid.
    for density,low,high,lift in [(840,20,38,9.5),(85,6,14,12.0)]:
        for index in rng.choice(len(rows),round(area/density),replace=True):
            y,x=rows[index]+rng.random()-.5,cols[index]+rng.random()-.5
            r=rng.uniform(low,high);ratio=rng.uniform(.62,.97);angle=rng.uniform(0,np.pi)
            dx,dy=r/metres_x,r/metres_y
            x0,x1=max(0,math.floor(x-dx)-1),min(SIZE,math.ceil(x+dx)+2)
            y0,y1=max(0,math.floor(y-dy)-1),min(SIZE,math.ceil(y+dy)+2)
            ew=(np.arange(x0,x1)-x)[None,:]*metres_x/r
            ns=(np.arange(y0,y1)-y)[:,None]*metres_y/r
            a,b=math.cos(angle),math.sin(angle)
            u,v=ew*a+ns*b,(ns*a-ew*b)/ratio
            # Bend the shoulder slightly; a stand has no circular outline.
            u=u+.16*v*v
            surface=lift*rng.uniform(.72,1.20)*np.maximum(1-u*u-v*v,0)**.72
            patch=height[y0:y1,x0:x1]
            np.maximum(patch,surface,out=patch)
    # Half-pixel softening keeps these low plants subordinate to the raised crowns.
    smooth=Image.fromarray(np.uint8(np.clip(height*16,0,255))).filter(ImageFilter.GaussianBlur(.57))
    height=np.asarray(smooth,dtype=np.float32)/16
    gy,gx=np.gradient(height,metres_y,metres_x)
    light=np.clip((gx*.73+gy*.58)/np.sqrt(1+gx*gx+gy*gy),-.78,.78)
    return light, np.clip(height/13,0,1)


def write_relief(mask,terrain):
    west,south,east,north=mask.bounds
    # Pixel centres and image corners share the same local projection. The
    # Mercator/geographic row discrepancy here is below one fifth of a pixel.
    x=west+(np.arange(SIZE)+.5)*(east-west)/SIZE
    y=north-(np.arange(SIZE)+.5)*(north-south)/SIZE
    xx,yy=np.meshgrid(x,y)
    dem=terrain.sample(xx/EAST+LON,yy/NORTH+LAT)
    gy,gx=np.gradient(dem,(north-south)/SIZE,(east-west)/SIZE)
    # Leave every pixel whose bilinear footprint could reach a path, clearing,
    # rock or building transparent. Centre-only and inclusive fill rasterization
    # both close metre-wide trail holes, even when the source polygons are exact.
    mx,my=(east-west)/SIZE,(north-south)/SIZE
    support=math.hypot(mx,my)+.12
    clear=mask.buffer(-support)
    shapely.prepare(clear)
    inside=shapely.contains_xy(clear,xx,yy)
    # Feather further inside the forest; the shared transparent apron stays clear.
    edge=np.asarray(Image.fromarray(inside.astype('uint8')*255).filter(ImageFilter.GaussianBlur(1.5)),dtype=float)/255
    coverage=np.where(inside,np.clip((edge-.36)/.64,0,1),0)
    relief,crowns=understory(inside,mx,my)
    # Low broadleaves share the slope's northwestern light. Shadowed folds
    # stay cool; patches on exposed shoulders have warmer olive highlights.
    lighting=np.clip((.77+.9*gx+.62*gy)/np.sqrt(1+gx*gx+gy*gy),-.65,1.3)
    slope=np.clip((lighting+.35)/1.55,0,1)
    tone=np.clip(.17+.39*slope+.23*crowns+.49*relief,0,1)
    shade=np.array([52,83,66]);light=np.array([160,180,111])
    rgb=shade+(light-shade)*tone[:,:,None]
    rgb[:,:,0]+=np.clip(gx,-.8,.8)*3
    rgb[:,:,2]-=crowns*2.7
    alpha=255*coverage*np.clip((dem-46)/30,0,1)
    rgba=np.dstack([np.clip(rgb,0,255),alpha]).astype('uint8')
    rgba[rgba[:,:,3]==0]=0
    image=Image.fromarray(rgba)
    image.quantize(colors=240,method=Image.Quantize.FASTOCTREE).save(ASSETS/'xinyi-ridge-relief.png',optimize=True)
    return [degree_point(q) for q in [(west,north),(east,north),(east,south),(west,south)]]


def main():
    wood,obstacles,rocks,existing,paths,structures=landscape()
    terrain=Terrain()
    safe=wood.difference(obstacles).difference(rocks)
    corners=write_relief(safe,terrain)
    interior=safe.buffer(-RADIUS)
    shapely.prepare(interior)
    existing=shapely.STRtree(existing)
    rng=random.Random(8901);candidates=[]
    w,s,e,n=interior.bounds
    for iy in range(math.floor(s/19),math.ceil(n/19)):
        for ix in range(math.floor(w/19),math.ceil(e/19)):
            x=(ix+rng.uniform(.1,.9))*19;y=(iy+rng.uniform(.1,.9))*19
            h=rng.randint(85,135);order=rng.getrandbits(32);p=Point(x,y)
            if not interior.contains(p) or len(existing.query(p,predicate='dwithin',distance=10)):continue
            candidates.append((order,x,y,h))
    candidates.sort()
    x=np.array([c[1] for c in candidates]);y=np.array([c[2] for c in candidates])
    lon,lat=x/EAST+LON,y/NORTH+LAT
    z=terrain.sample(lon,lat);zx=terrain.sample(lon+8/EAST,lat);zy=terrain.sample(lon,lat+8/NORTH)
    crowns=[]
    for i,(order,x,y,h) in enumerate(candidates):
        if z[i]<58 or math.hypot(zx[i]-z[i],zy[i]-z[i])/8>1.18:continue
        crowns.append([round(x,1),round(y,1),round(float(z[i]),1),h/10,(order%360)])
    # Split only at real forest boundaries; town pavements keep their established street styling.
    trails=[];trail_area=wood.buffer(5).difference(structures.buffer(.7))
    for id,name,g in paths:
        for line in shapely.get_parts(g.intersection(trail_area)):
            if line.geom_type=='LineString' and line.length>3:
                elev=terrain.sample(*point_lonlat(*line.interpolate(.5,normalized=True).coords[0]))
                if float(elev)>=55:
                    trails.append({'type':'Feature','properties':{'id':id,'name':name},
                                   'geometry':{'type':'LineString','coordinates':[degree_point(p) for p in line.simplify(.35).coords]}})
    data={'version':1,'origin':[LON,LAT],'corners':corners,'crowns':crowns,'trails':trails}
    encoded=json.dumps(data,separators=(',',':'),ensure_ascii=False).encode()
    (ASSETS/'xinyi-ridge-woods.json.gz').write_bytes(gzip.compress(encoded,compresslevel=9,mtime=0))
    print(json.dumps({'forestKm2':round(wood.area/1e6,3),'rootCount':len(crowns),'trails':len(trails),
                      'heightRange':[min(r[2] for r in crowns),max(r[2] for r in crowns)],'tiles':sorted(terrain.tiles)},ensure_ascii=False))


if __name__=='__main__':
    main()
