"""Extend the façade mask over all Taipei districts and the mapped shop fronts."""
import argparse
import gzip
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter
from shapely.geometry import shape
from shapely.ops import unary_union

DATA = Path('data')
SHOP_KINDS = {'餐廳','咖啡','麵包','書店','超商','超市','茶飲','熟食','選物','商店','甜點','冰品'}
LANDMARKS = [
    {'name':'中正紀念堂','center':[121.521820,25.034637],'radii':[64,64],'channel':77,
     'source':'https://nchdb.boch.gov.tw/assets/overview/monument/20071109000001'},
    {'name':'圓山大飯店','center':[121.526290,25.078622],'radii':[69,56],'channel':153,
     'source':'https://www.grand-hotel.org/EN/official/about.aspx?gh=TP'},
    {'name':'國立故宮博物院','center':[121.548544,25.102274],'radii':[72,51],'channel':230,
     'source':'https://theme.npm.edu.tw/npmArchitecture/en/page-4.html'},
]


def mercator(lng,lat):
    return (lng+180)/360,(1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--atlas', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    districts = json.loads((DATA/'districts.geojson').read_text())['features']
    area = unary_union([shape(f['geometry']) for f in districts])
    w,s,e,n=area.buffer(.001).bounds
    west,north=mercator(w,n)
    east,south=mercator(e,s)
    size=2048
    def pixel(lng,lat):
        x,y=mercator(lng,lat)
        return (x-west)/(east-west)*(size-1),(y-north)/(south-north)*(size-1)
    def draw_ring(draw,polygon):
        draw.polygon([pixel(*point) for point in polygon.exterior.coords],fill=255)
        for hole in polygon.interiors:
            draw.polygon([pixel(*point) for point in hole.coords],fill=0)
    land=Image.new('L',(size,size))
    pen=ImageDraw.Draw(land)
    for polygon in getattr(area,'geoms',[area]):
        draw_ring(pen,polygon)
    extent=ImageChops.multiply(land,land.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(2.1)))
    shops=Image.new('L',(size,size))
    storefront=ImageDraw.Draw(shops)
    existing = [DATA/f'street-{key}.json' for key in ('101','daan-district','xinyi-district','songshan-district','zhongshan-district','xinyi-link','yongchun','songshan')]
    new = sorted(path for path in args.atlas.glob('*.json.gz') if path.name!='grids.json.gz')
    for path in (*existing,*new):
        raw=gzip.decompress(path.read_bytes()) if path.suffix=='.gz' else path.read_bytes()
        for place in json.loads(raw)['places']:
            if place['kind'] not in SHOP_KINDS:
                continue
            x,y=pixel(*place['point'])
            storefront.ellipse((x-2.2,y-2.0,x+2.2,y+2.0),fill=241)
    green=ImageChops.multiply(extent,shops.filter(ImageFilter.GaussianBlur(.8)))
    landmarks=Image.new('L',(size,size))
    pen=ImageDraw.Draw(landmarks)
    for row in LANDMARKS:
        lon,lat=row['center']
        width,height=row['radii']
        dx=width/(111195*math.cos(math.radians(lat)))
        dy=height/111195
        pen.rectangle([pixel(lon-dx,lat+dy),pixel(lon+dx,lat-dy)],fill=row['channel'])
    Image.merge('RGB',(extent,green,landmarks)).save(args.out/'city-material-mask.png',optimize=True)
    manifest=json.loads((DATA/'street-atlas.json').read_text())
    manifest['materialBounds']=[west,north,east,south]
    manifest['landmarks']=LANDMARKS
    (args.out/'city-atlas-material.json').write_text(json.dumps(manifest,separators=(',',':'))+'\n')
    print('2048 px façade coverage','bounds',manifest['materialBounds'])


if __name__ == '__main__':
    main()
