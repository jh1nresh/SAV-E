"""Rebuild the Pocket City elevation wash. Requires numpy, Pillow and pyshp.

Pass the official TWD97 geographic township ZIP from data.gov.tw/dataset/7441.
Source XYZ tiles are cached outside the repo; decode Terrarium at native resolution.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import math
from pathlib import Path
import shutil
import tempfile
import time
from urllib.request import Request, urlopen
from zipfile import ZipFile

import numpy as np
from PIL import Image, ImageDraw


TERRAIN = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium'
OUT = Path(__file__).resolve().parents[1] / 'taiwan' / 'relief'
TILE = 256
ZOOMS = {'taiwan': 10, 'penghu': 11, 'kinmen': 12, 'matsu': 12,
         'wuqiu': 14, 'lanyu': 13, 'ludao': 13, 'liuqiu': 13,
         'dongsha': 14, 'nansha': 14, 'eastern-islets': 12}


def xy(point, z):
    lon, lat = point[:2]
    size = TILE * 2**z
    return ((lon / 360 + .5) * size,
            (.5 - math.asinh(math.tan(math.radians(lat))) / (2 * math.pi)) * size)


def lnglat(x, y, z):
    size = TILE * 2**z
    return [360*x/size-180, math.degrees(math.atan(math.sinh(math.pi*(1-2*y/size))))]


def sheet_name(county, town, point):
    lon,lat=point[:2]
    if lon>122.5:
        return 'eastern-islets'
    if lat < 15:
        return 'nansha'
    if lat < 21:
        return 'dongsha'
    towns = {'烏坵鄉': 'wuqiu', '蘭嶼鄉': 'lanyu', '綠島鄉': 'ludao', '琉球鄉': 'liuqiu'}
    counties = {'澎湖縣': 'penghu', '金門縣': 'kinmen', '連江縣': 'matsu'}
    return towns.get(town, counties.get(county, 'taiwan'))


def read_boundaries(path):
    import shapefile
    groups = {}
    # Prefer the national township file, not an accompanying single-area revision.
    with ZipFile(path) as archive:
        name = next(n[:-4] for n in archive.namelist() if Path(n).name.startswith('TOWN_MOI_') and n.lower().endswith('.shp'))
        reader = shapefile.Reader(shp=io.BytesIO(archive.read(name+'.shp')), dbf=io.BytesIO(archive.read(name+'.dbf')), encoding='utf-8')
        for record in reader.iterShapeRecords():
            geom = record.shape.__geo_interface__
            polygons = [geom['coordinates']] if geom['type'] == 'Polygon' else geom['coordinates']
            for rings in polygons:
                group = sheet_name(record.record['COUNTYNAME'], record.record['TOWNNAME'], rings[0][0])
                groups.setdefault(group, []).append(rings)
    return groups, Path(name).name


def download_tile(key, cache):
    z, x, y = key
    path = cache / f'{z}-{x}-{y}.png'
    if path.exists():
        return path
    for attempt in range(3):
        try:
            request = Request(f'{TERRAIN}/{z}/{x}/{y}.png', headers={'User-Agent': 'Savvy-Pocket-City-relief/1'})
            with urlopen(request, timeout=18) as response:
                raw = response.read()
            with Image.open(io.BytesIO(raw)) as img:
                if img.size != (TILE, TILE):
                    raise ValueError(f'unexpected tile dimensions {key}')
                img.verify()
            with tempfile.NamedTemporaryFile(dir=cache,delete=False) as tmp:
                tmp.write(raw)
            Path(tmp.name).replace(path)
            return path
        except OSError:
            if attempt == 2:
                raise
            time.sleep(attempt+.25)


def build_mask(rings_list,z):
    xys = [[ [xy(p,z) for p in ring] for ring in polygon] for polygon in rings_list]
    bounds = [np.array(polygon[0]) for polygon in xys]
    lower = np.floor(np.min([b.min(axis=0) for b in bounds],axis=0)).astype(int)-2
    upper = np.ceil(np.max([b.max(axis=0) for b in bounds],axis=0)).astype(int)+3
    mask = Image.new('L',tuple(upper-lower))
    for polygon,extent in zip(xys,bounds):
        origin = np.floor(extent.min(axis=0)).astype(int)
        shape = np.ceil(extent.max(axis=0)).astype(int)-origin+1
        part = Image.new('L',tuple(shape))
        draw = ImageDraw.Draw(part)
        for i,ring in enumerate(polygon):
            draw.polygon([(x-origin[0],y-origin[1]) for x,y in ring],fill=0 if i else 255)
        # A township inside another township's hole must survive either draw order.
        mask.paste(255,tuple(origin-lower),part)
    return mask,tuple(map(int,lower))


def land_tiles(mask,origin,z):
    w,h=mask.size
    left,top=origin
    for y in range(top//TILE,(top+h-1)//TILE+1):
        for x in range(left//TILE,(left+w-1)//TILE+1):
            sx,sy=x*TILE-left,y*TILE-top
            region=(max(0,sx),max(0,sy),min(w,sx+TILE),min(h,sy+TILE))
            if mask.crop(region).getbbox():
                yield (z,x,y)


def elevations(keys,cache,origin,size):
    left,top=origin
    width,height=size
    result=np.zeros((height,width),dtype=np.float32)
    for z,x,y in keys:
        with Image.open(cache/f'{z}-{x}-{y}.png') as tile:
            rgb=np.asarray(tile.convert('RGB'),dtype=np.float32)
        meters=rgb[:,:,0]*256+rgb[:,:,1]+rgb[:,:,2]/256-32768
        sx,sy=x*TILE-left,y*TILE-top
        x0,y0=max(0,sx),max(0,sy)
        x1,y1=min(width,sx+TILE),min(height,sy+TILE)
        result[y0:y1,x0:x1]=meters[y0-sy:y1-sy,x0-sx:x1-sx]
    return result


def relief_image(heights,mask,origin,z):
    # Color encodes elevation, not a claimed survey of tree species or land use.
    levels=[0,80,350,850,1500,2400,3200,3950]
    palette=np.array([[211,219,161],[189,210,146],[149,190,131],[122,172,132],
                      [111,158,139],[130,159,146],[171,176,154],[210,202,173]])
    lat=lnglat(origin[0],origin[1]+heights.shape[0]/2,z)[1]
    meters_per_pixel=40075016.69*math.cos(math.radians(lat))/(TILE*2**z)
    dy,dx=np.gradient(heights,meters_per_pixel)
    # Northwest light, deliberately soft enough that ridges retain their green.
    slope=np.sqrt(dx*dx+dy*dy)
    relief=np.clip((dy-dx)*.67 -.14*slope,-.46,.40)
    surface=np.maximum(heights,0)
    # Fine 250 m contours only where the DEM actually crosses a level.
    distance_to_level=np.abs((surface+125)%250-125)
    contour=(surface>230)*np.clip(1-distance_to_level/np.maximum(3,slope*meters_per_pixel*.48),0,1)
    rgb=np.stack([np.interp(surface,levels,palette[:,i]) for i in range(3)],axis=2)
    rgb*=1+relief[:,:,None]*.72-contour[:,:,None]*.13
    alpha=np.asarray(mask,dtype=np.float32)/255
    # Muted lowlands allow underlying urban/woodland vectors to read through.
    alpha*=np.clip(.23+.57*surface/550+.25*slope,.23,1)
    rgba=np.dstack([np.clip(rgb,0,255),alpha*255]).astype('uint8')
    return Image.fromarray(rgba)


def verify_images(output,manifest):
    # Interior anchors and offshore controls catch shifted georeferencing and masks.
    interior={'taiwan':(120.9573,23.47),'eastern-islets':(123.474,25.748),'kinmen':(118.399,24.452),
              'penghu':(119.58,23.581),'wuqiu':(119.455,24.994),'matsu':(119.937,26.153),
              'liuqiu':(120.37,22.34),'ludao':(121.494,22.66),'lanyu':(121.55,22.04),
              'dongsha':(116.727,20.703),'nansha':(114.367,10.377)}
    for sheet in manifest['sheets']:
        name,z=sheet['name'],sheet['sourceZoom']
        origin=tuple(round(v) for v in xy(sheet['coordinates'][0],z))
        with Image.open(output/f'{name}.webp') as image:
            assert image.size==(sheet['width'],sheet['height']) and 'A' in image.getbands(),name
            def alpha(point):
                px,py=xy(point,z)
                return image.getpixel((math.floor(px)-origin[0],math.floor(py)-origin[1]))[-1]
            assert alpha(interior.pop(name))>0, name
            if name=='taiwan':
                assert alpha((121.7,23.3))==0, 'ocean near Hualien'
            if name=='kinmen':
                assert alpha((118.145,24.488))==0, 'outside the Kinmen mask'
    assert not interior, interior
    for point,low,high in [((120.9573,23.47),3300,4000),((121.2318,24.3832),3300,4000),((121.5656,24.1728),100,1400)]:
        x,y=(math.floor(v) for v in xy(point,9))
        with Image.open(output/'dem'/f'9-{x//TILE}-{y//TILE}.png') as tile:
            r,g,b=tile.convert('RGB').getpixel((x%TILE,y%TILE))
        assert low<r*256+g+b/256-32768<high,point


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--boundaries',type=Path)
    parser.add_argument('--verify',action='store_true',help='inspect encoded image pixels and DEM anchors offline')
    parser.add_argument('--cache',type=Path,default=Path(tempfile.gettempdir())/'pocket-city-taiwan-dem')
    parser.add_argument('--output',type=Path,default=OUT)
    args=parser.parse_args()
    if args.verify:
        source=(args.output/'index.js').read_text().split('export default ',1)[1].strip().removesuffix(';')
        verify_images(args.output,json.loads(source))
        print('Verified all island masks, two outside controls and three DEM anchors')
        return
    if not args.boundaries:
        parser.error('--boundaries is required for rebuilding')
    args.cache.mkdir(parents=True,exist_ok=True)
    args.output.mkdir(parents=True,exist_ok=True)
    groups,revision=read_boundaries(args.boundaries)
    sheets=[]
    dem=set()
    samples={'玉山':(120.9573,23.4700),'雪山':(121.2318,24.3832),'太魯閣峽谷':(121.5656,24.1728)}
    for name,polygons in sorted(groups.items()):
        z=ZOOMS[name]
        mask,origin=build_mask(polygons,z)
        keys=list(land_tiles(mask,origin,z))
        with ThreadPoolExecutor(max_workers=5) as pool:
            list(pool.map(lambda k:download_tile(k,args.cache),keys))
        field=elevations(keys,args.cache,origin,mask.size)
        for dz in (7,8,9):
            dem.update((dz,x>>(z-dz),y>>(z-dz)) for _,x,y in keys)
        img=relief_image(field,mask,origin,z)
        path=args.output/f'{name}.webp'
        img.save(path,'WEBP',quality=89,method=5)
        x,y=origin;w,h=mask.size
        corners=[lnglat(a,b,z) for a,b in [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]]
        inside=np.asarray(mask)>0
        spot={}
        for point,(lon,lat) in samples.items():
            px,py=xy((lon,lat),z)
            a,b=math.floor(px)-x,math.floor(py)-y
            if 0<=a<w and 0<=b<h and inside[b,a]:
                spot[point]=round(float(field[b,a]))
        sheets.append(dict(name=name,coordinates=corners,width=w,height=h,sourceZoom=z,
                           landPixels=int(inside.sum()),maxMeters=round(float(field[inside].max())),
                           samples=spot,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        print(name,mask.size,len(keys),spot,flush=True)
    with ThreadPoolExecutor(max_workers=5) as pool:
        list(pool.map(lambda k:download_tile(k,args.cache),sorted(dem)))
    demdir=args.output/'dem'
    demdir.mkdir(exist_ok=True)
    digest=hashlib.sha256()
    for z,x,y in sorted(dem):
        dest=demdir/f'{z}-{x}-{y}.png'
        shutil.copyfile(args.cache/dest.name,dest)
        digest.update(dest.read_bytes())
    manifest=dict(boundaryDataset='https://data.gov.tw/dataset/7441',
                  boundaryDownload='https://maps.nlsc.gov.tw/download/鄉鎮市區界線(TWD97經緯度).zip',boundaryRevision=revision,
                  boundarySha256=hashlib.sha256(args.boundaries.read_bytes()).hexdigest(),
                  terrainSource=TERRAIN,terrainAttribution='https://github.com/tilezen/joerd/blob/master/docs/attribution.md',
                  sheets=sheets,demSha256=digest.hexdigest(),dem=[f'{z}-{x}-{y}' for z,x,y in sorted(dem)])
    (args.output/'index.js').write_text('// Generated by tools/build-taiwan-relief.py\nexport default '+json.dumps(manifest,ensure_ascii=False,indent=2)+';\n')
    verify_images(args.output,manifest)
    print('sheets',len(sheets),'DEM tiles',len(dem))


if __name__=='__main__':
    main()
