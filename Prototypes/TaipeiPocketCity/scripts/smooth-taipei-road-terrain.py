"""Smooth low, flat street corridors with continuous terrain corrections across XYZ tiles."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import json
import math
from pathlib import Path
import subprocess

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter
from scipy.spatial import cKDTree
from shapely.geometry import shape
from shapely.ops import unary_union

SIZE = 256
ZOOM = 14
WORLD = SIZE * 2**ZOOM
METRES_PER_PIXEL = 40075016.686 / WORLD * math.cos(math.radians(25.07))
DATA = Path('data')
XINYI_BASIN = (121.5505, 25.0287, 121.5770, 25.0439)


def pixel(lon, lat):
    return (WORLD * (lon + 180)/360,
            WORLD * (1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2)


def ramp(low, high, values):
    t = np.clip((values-low)/(high-low),0,1)
    return t*t*(3-2*t)


def decode(file):
    rgb = np.asarray(Image.open(file).convert('RGB'),dtype=np.float32)
    return rgb[...,0]*256+rgb[...,1]+rgb[...,2]/256-32768


def write_dem(values, output):
    encoded = np.rint((values+32768)*256).astype(np.int32)
    rgb = np.stack([encoded>>16, (encoded>>8)&255, encoded&255],axis=-1).astype(np.uint8)
    Image.fromarray(rgb,'RGB').save(output,optimize=True)


def survey_bases(bounds):
    """Collect one typical ground height per 25-metre bin from survey undersides."""
    west, south, east, north = bounds
    survey = json.loads((DATA/'survey-index.json').read_text())
    samples = []
    for tile in survey['levels']['200']:
        w, s, e, n = tile['box']
        if w > east or e < west or s > north or n < south:
            continue
        compressed = (DATA/'200'/f"{tile['id']}.bin.gz").read_bytes()
        triangles = np.frombuffer(gzip.decompress(compressed), dtype='<f4').reshape(-1, 3, 6)
        corners = triangles[:, :, :2]
        a = corners[:, 1] - corners[:, 0]
        b = corners[:, 2] - corners[:, 0]
        area = np.abs(a[:, 0]*b[:, 1] - a[:, 1]*b[:, 0])/2
        underside = (area >= 8) & (np.abs(triangles[:, :, 2]-triangles[:, :, 3]).max(axis=1) < .15)
        underside &= triangles[:, 0, 4] >= 3.5
        ground = corners[underside].mean(axis=1, dtype=np.float64)
        metre = tile['m']
        samples.append(np.column_stack((
            (tile['mx'] + ground[:, 0]*metre)*WORLD,
            (tile['my'] - ground[:, 1]*metre)*WORLD,
            triangles[underside, 0, 3],
        )))
    points = np.concatenate(samples)
    # A complex footprint should not outweigh all the buildings on the next block.
    bins = np.floor(points[:, :2]*(METRES_PER_PIXEL/25)).astype(int)
    _, indexes = np.unique(bins, axis=0, return_inverse=True)
    ordered = points[np.argsort(indexes)]
    groups = np.split(ordered, np.cumsum(np.bincount(indexes))[:-1])
    return np.array([np.median(group, axis=0) for group in groups])


def calibrate_xinyi(target, regional_grade, x0, y0):
    """Replace short urban elevation spikes with the grade of nearby surveyed bases."""
    west, south, east, north = XINYI_BASIN
    left, top = (int(v) for v in pixel(west,north))
    right, bottom = (math.ceil(v) for v in pixel(east,south))
    yy, xx = np.mgrid[top:bottom, left:right] + .5
    points = survey_bases(XINYI_BASIN)
    distance, neighbours = cKDTree(points[:, :2]).query(np.column_stack((xx.ravel(), yy.ravel())), k=15)
    distance *= METRES_PER_PIXEL
    height = points[neighbours, 2]
    median = np.median(height, axis=1, keepdims=True)
    weights = np.exp(-(distance/58)**2) * (1-ramp(1.5, 4.5, np.abs(height-median)))
    grade = (np.sum(weights*height, axis=1)/weights.sum(axis=1)).reshape(xx.shape)
    grade = gaussian_filter(grade, 30/METRES_PER_PIXEL)
    support = distance[:, 5].reshape(xx.shape)
    slope = np.hypot(*np.gradient(grade, METRES_PER_PIXEL))
    edge = np.minimum.reduce((xx-left, right-xx, yy-top, bottom-yy))*METRES_PER_PIXEL
    landmark = json.loads((DATA/'landmark-101.json').read_text())
    centre = pixel(*landmark['lngLat'])
    landmark_distance = np.hypot(xx-centre[0], yy-centre[1])*METRES_PER_PIXEL
    blend = ramp(0,145,edge) * (1-ramp(84,155,support)) * (1-ramp(17,25,grade))
    blend *= (1-ramp(.035,.095,slope)) * ramp(52,122,landmark_distance)
    bounds = np.s_[top-y0:bottom-y0, left-x0:right-x0]
    blend *= 1-ramp(53,63,regional_grade[bounds])
    window = target[bounds]
    before = window.copy()
    # The earlier 101 correction can also leave a dip just outside the tower base.
    window += blend*np.clip(grade-window, -55, 6)
    assert np.isfinite(window).all()
    assert np.array_equal(window[landmark_distance<=52],before[landmark_distance<=52])
    assert np.array_equal(window[grade>=25],before[grade>=25])
    return int(np.count_nonzero(np.abs(window-before)>=1/256))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--street-data',type=Path,required=True)
    parser.add_argument('--district-index',type=Path,required=True)
    parser.add_argument('--work',type=Path,required=True)
    parser.add_argument('--city-osm',type=Path,help='Include citywide survey calibration using this Taipei OSM extract')
    args=parser.parse_args()
    cache=args.work/'basemap'
    output=args.work/'tiles'
    cache.mkdir(parents=True,exist_ok=True)
    output.mkdir(exist_ok=True)
    old_atlas=json.loads((DATA/'street-atlas.json').read_text())
    old_tiles=set(old_atlas['tiles'])
    index=json.loads(args.district_index.read_text())
    names={row['name'] for row in index['districts']}
    districts=json.loads((DATA/'districts.geojson').read_text())['features']
    area=unary_union([shape(row['geometry']) for row in districts if row['properties']['name'] in names])
    west,south,east,north=area.bounds
    xmin,ymin=(int(v//SIZE) for v in pixel(west,north))
    xmax,ymax=(int(v//SIZE) for v in pixel(east,south))
    x0,y0=SIZE*(xmin-1),SIZE*(ymin-1)
    shape_px=((ymax-ymin+3)*SIZE,(xmax-xmin+3)*SIZE)
    def xy(lon,lat):
        x,y=pixel(lon,lat)
        return x-x0-.5,y-y0-.5
    def window(x,y):
        column,row=x*SIZE-x0,y*SIZE-y0
        return np.s_[row:row+SIZE,column:column+SIZE]
    tiles=[(x,y) for x in range(xmin-1,xmax+2) for y in range(ymin-1,ymax+2)]

    def get_tile(pair):
        x,y=pair
        filename=f'{ZOOM}-{x}-{y}.png'
        earlier=[Path('/tmp')/f'savvy-{key}'/'dem'/filename for key in ('zhongshan','songshan','daan')]
        values=None
        source=cache/filename
        for previous in (source,*earlier):
            if not previous.exists():
                continue
            try:
                values=decode(previous)
                break
            except OSError:
                continue
        if values is None:
            pending=source.with_suffix('.part')
            url=f'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{ZOOM}/{x}/{y}.png'
            subprocess.run(['curl','-fsSL','--connect-timeout','10','--max-time','45','--retry','2',url,'-o',str(pending)],check=True)
            values=decode(pending)
            pending.replace(source)
        old_path=DATA/'terrain'/'street-atlas'/filename
        return x,y,values,decode(old_path) if f'{x}/{y}' in old_tiles else values

    dem=np.empty(shape_px,dtype=np.float32)
    existing=np.empty_like(dem)
    with ThreadPoolExecutor(max_workers=6) as pool:
        for x,y,raw,old in pool.map(get_tile,tiles):
            dem[window(x,y)]=raw
            existing[window(x,y)]=old
    print('Loaded',len(tiles),'terrain tiles',flush=True)

    district=Image.new('1',shape_px[::-1])
    pen=ImageDraw.Draw(district)
    for part in getattr(area,'geoms',(area,)):
        pen.polygon([xy(*p) for p in part.exterior.coords],fill=1)
        for hole in part.interiors:
            pen.polygon([xy(*p) for p in hole.coords],fill=0)
    road=Image.new('1',shape_px[::-1])
    pen=ImageDraw.Draw(road)
    for row in index['districts']:
        streets=json.loads(gzip.decompress((args.street_data/f"{row['key']}.json.gz").read_bytes()))
        for feature in streets['ground']['features']:
            if feature['properties']['kind']!='road':
                continue
            geometry=shape(feature['geometry'])
            for polygon in getattr(geometry,'geoms',(geometry,)):
                pen.polygon([xy(*p) for p in polygon.exterior.coords],fill=1)
    inside=distance_transform_edt(np.asarray(district)).astype(np.float32)*METRES_PER_PIXEL
    distance=distance_transform_edt(~np.asarray(road)).astype(np.float32)*METRES_PER_PIXEL
    base=gaussian_filter(dem,34/METRES_PER_PIXEL)
    dy,dx=np.gradient(base,METRES_PER_PIXEL)
    slope=np.hypot(dx,dy)
    weight=ramp(0,43,inside)*(1-ramp(17,59,distance))*(1-ramp(32,63,base))*(1-ramp(.075,.18,slope))
    # Fade into the existing corrections on the four already calibrated districts.
    target=existing+(base-existing).clip(-3.5,3.5)*weight
    xinyi_pixels=calibrate_xinyi(target,base,x0,y0)
    high=base>=63
    assert np.array_equal(target[high],existing[high])
    city_report = None
    if args.city_osm:
        from calibrate_city_street_terrain import calibrate_city
        city = unary_union([shape(row['geometry']) for row in districts])
        city_report = calibrate_city(
            target,dem,city,survey_bases(city.bounds),args.city_osm,
            pixel,(x0,y0),METRES_PER_PIXEL,XINYI_BASIN,args.work)
    changed=[]
    for x,y in tiles:
        region=window(x,y)
        if np.max(np.abs(target[region]-existing[region]))<1/256:
            continue
        write_dem(target[region],output/f'{ZOOM}-{x}-{y}.png')
        changed.append(f'{x}/{y}')
    peak=float(np.abs(target-existing).max())
    report={'tiles':sorted(old_tiles|set(changed)), 'adjusted':changed,'peakChange':round(peak,4),
            'highTerrainPreserved':True, 'calibratedPixelCount':int(np.count_nonzero(weight)),
            'xinyiSurveyCalibrationPixels':xinyi_pixels}
    if city_report:
        report['citySurveyCalibration']=city_report
    (args.work/'receipt.json').write_text(json.dumps(report,separators=(',',':'))+'\n')
    print(json.dumps(report,ensure_ascii=False),flush=True)


if __name__ == '__main__':
    main()
