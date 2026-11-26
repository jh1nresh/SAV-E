"""Compile the 200 m Pocket City scenes into the continuous Taipei street layer.

Grid ownership is in EPSG:3826. The established survey buildings, named places,
at-grade district carriageways and inventoried trees remain geographically
anchored across cells. This exports the kit's pedestrian paving and markings.
"""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
import gzip
import hashlib
import json
import math
import multiprocessing
from pathlib import Path
import runpy

from pyproj import Transformer
from shapely import clip_by_rect, make_valid, set_precision
from shapely.affinity import affine_transform
from shapely.geometry import LineString, Polygon, box, mapping, shape
from shapely.ops import transform, unary_union
from shapely.strtree import STRtree

HERE=Path(__file__).resolve().parent
GROUND=runpy.run_path(str(HERE/'build-xinyi-street-ground.py'))
prepare=runpy.run_path(str(HERE/'prepare-taipei200.py'))
encode=prepare['encode']
project=Transformer.from_crs(4326,3826,always_xy=True).transform
geo=Transformer.from_crs(3826,4326,always_xy=True).transform
ZERO=(121.55,25)
SIZE=prepare['SIZE']


def ground_indices():
    roads, sidewalks = [], []
    for path in sorted(Path('assets').glob('*-street-ground.json.gz')):
        data = json.loads(gzip.decompress(path.read_bytes()))
        for kind, polygons in [('road', roads), ('walk', sidewalks), ('path', sidewalks)]:
            polygons.extend(affine_transform(GROUND['packed_polygon'](row), [1e-6,0,0,1e-6,*ZERO])
                            for row in data[kind])
    waters = []
    for source in sorted(Path('data/city170').glob('p*.json.gz')):
        features = json.loads(gzip.decompress(source.read_bytes()))['features']['features']
        waters.extend(area(shape(f['geometry'])) for f in features if f['properties']['kind'] == 'water')
    return STRtree(roads), STRtree(sidewalks), STRtree(waters)


def within(index, clip, bounds):
    matches = index.query(clip)
    pieces = [area(clip_by_rect(index.geometries[n], *bounds)) for n in matches]
    # A shared boundary can intersect as a line even when both inputs are areas.
    return area(area(unary_union(pieces)).intersection(clip, grid_size=1e-9))


def polygon_rows(geom):
    if geom.is_empty:
        return
    if geom.geom_type=='Polygon':
        yield geom
    elif hasattr(geom,'geoms'):
        for part in geom.geoms:
            yield from polygon_rows(part)


def area(geom):
    geom=make_valid(geom) if not geom.is_valid else geom
    if geom.geom_type in ('Polygon','MultiPolygon'):
        return geom
    return unary_union(list(polygon_rows(geom))) if not geom.is_empty else Polygon()


def pieces(cell):
    i,j,(lon,lat),rotation,names,bounds=cell
    key=f'{i}_{j}'
    scene=json.loads(gzip.decompress((WORK/'scenes'/f'{key}.json.gz').read_bytes()))
    assert scene['meta']['size']==SIZE and scene['meta']['rotation']==rotation
    stats={kind:len(scene[kind]) for kind in ('buildings','trees','pois','routes','roads','water','furniture')}
    paint=json.loads(gzip.decompress((HALO/'scenes'/f'{key}.json.gz').read_bytes()))
    meta=paint['meta']
    if meta['size'] != SIZE + 50 or [meta['lon'],meta['lat']] != [lon,lat] or meta['rotation'] != rotation:
        raise ValueError(f'Wrong street paint context for {key}')
    owner=box(i*SIZE,j*SIZE,(i+1)*SIZE,(j+1)*SIZE)
    if not CITY.contains(owner):
        owner=owner.intersection(CITY)
    clip=area(transform(geo,owner))
    angle=math.radians(rotation)
    c,s=math.cos(angle),math.sin(angle)
    east=111320*math.cos(math.radians(lat))
    to_geo=[c/east,-s/east,s/110574,c/110574,lon,lat]
    center_x,center_y=(i+.5)*SIZE,(j+.5)*SIZE

    # Reconstruct the original kit geometry in metres, then split the final
    # strokes at cell ownership boundaries. Adjacent cells share dash phase.
    zebra=[]
    for row in paint['markings']:
        if len(row)<2:continue
        line=LineString(row)
        if not 3<line.length<36:continue
        a,b=line.coords[0],line.coords[-1]
        dx,dy=(b[0]-a[0])/line.length,(b[1]-a[1])/line.length
        for k in range(math.ceil((line.length-.4)/1.1)):
            pt=line.interpolate(.4+k*1.1)
            zebra.append(Polygon([(pt.x+u*dx-v*dy,pt.y+u*dy+v*dx)
                             for u,v in [(-.23,-1.2),(.23,-1.2),(.23,1.2),(-.23,1.2)]]))
    dashes=[]
    for row in paint['centerlines']:
        pts=row['p']
        for a,b in zip(pts,pts[1:]):
            dx,dy=b[0]-a[0],b[1]-a[1]
            first,last=(a[0]+center_x,b[0]+center_x) if abs(dx)>=abs(dy) else (a[1]+center_y,b[1]+center_y)
            if abs(last-first)<.01:continue
            lo,hi=sorted((first,last))
            for k in range(math.floor(lo/7.4),math.floor(hi/7.4)+1):
                start,end=max(lo,k*7.4),min(hi,k*7.4+2.9)
                if end-start<.02:continue
                t,u=(start-first)/(last-first),(end-first)/(last-first)
                dashes.append(LineString([(a[0]+t*dx,a[1]+t*dy),(a[0]+u*dx,a[1]+u*dy)]).buffer(.075,cap_style='flat'))
    # Test against the real at-grade surface. This prevents painting the kit's
    # clipped upper or underground road geometry through water and green space.
    asphalt=Polygon()
    if dashes or zebra:
        asphalt=within(ROAD,clip,bounds)
    zebras=unary_union(zebra)
    lanes=unary_union(dashes).difference(zebras.buffer(.65)) if zebra else unary_union(dashes)
    paths=[Polygon(r[0],r[1:]) for r in paint['paths']+paint['walk'] if r and len(r[0])>=3]
    sidewalk = within(WALK,clip,bounds).difference(within(WATER,clip,bounds),grid_size=1e-9) if paths else Polygon()
    # Coordinates quantised at five centimetres of a cell-local tangent frame keep
    # these tiny polygons compact and avoid a full GeoJSON record per stripe.
    def packed(geom):
        def ring(points):
            last=(0,0);out=[]
            for x,y in points.coords:
                pos=(round(x),round(y))
                if pos!=last or not out:
                    out.extend((pos[0]-last[0],pos[1]-last[1]));last=pos
            return out
        result=[]
        # Snap with topology repair before serialising so sub-pixel slivers
        # cannot turn into self-intersecting rings during integer rounding.
        scaled=affine_transform(geom,[east*20,0,0,110574*20,-lon*east*20,-lat*110574*20])
        for poly in polygon_rows(set_precision(make_valid(scaled),1)):
            shell=ring(poly.exterior)
            if len(shell)<8:continue
            holes=[ring(h) for h in poly.interiors]
            result.append([shell,*[h for h in holes if len(h)>=8]])
        return result
    output=[]
    for geometries,mask in [(lanes,asphalt),(zebras,asphalt),(unary_union([make_valid(p) for p in paths]),sidewalk)]:
        geom=affine_transform(geometries,to_geo)
        output.append(packed(area(geom).intersection(area(mask),grid_size=1e-9)))
    return key,[bounds,[lon,lat],names,output],stats,mapping(clip)


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--work',type=Path,required=True)
    ap.add_argument('--paint-context',type=Path,required=True,help='Directory prepared with --paint-halo.')
    ap.add_argument('--out',type=Path,default=Path('assets/taipei200'))
    ap.add_argument('--workers',type=int,default=4)
    args=ap.parse_args()
    WORK=args.work.resolve()
    manifest=json.loads((WORK/'input.json').read_bytes())
    HALO=args.paint_context.resolve()
    context=json.loads((HALO/'input.json').read_bytes())
    grade_hash = hashlib.sha256(Path('city170-grade-ids.js').read_bytes()
                                + (HERE/'build-city170-grade.py').read_bytes()).hexdigest()
    if (context.get('paintGradeSHA256') != grade_hash or context.get('paintHalo') != 25 or manifest.get('paintHalo',0) != 0
            or any(context[k] != manifest[k] for k in ('size','crs','osmSHA256','prepSHA256','cells'))):
        raise ValueError('Mismatched city or source for the 25 m paint context.')
    cells=manifest['cells']
    args.out.mkdir(parents=True,exist_ok=True)
    def gz(path,value):
        path.write_bytes(gzip.compress(encode(value),compresslevel=7,mtime=0))
    CITY=unary_union([make_valid(transform(project,shape(f['geometry']))) for f in json.loads(Path('data/districts.geojson').read_bytes())['features']])
    ROAD,WALK,WATER=ground_indices()
    groups=defaultdict(list)
    for cell in cells:
        groups[f'{cell[0]//8}_{cell[1]//8}'].append(cell)
    counts=Counter();districts=Counter();manifest_packs=[];grid=[]
    with ProcessPoolExecutor(args.workers,mp_context=multiprocessing.get_context('fork')) as pool:
        for n,(group,rows) in enumerate(sorted(groups.items()),1):
            pack={}
            for key,data,stats,footprint in pool.map(pieces,rows,chunksize=3):
                pack[key]=data;counts.update(stats);districts.update(data[2])
                grid.append({'type':'Feature','id':key,'properties':{'id':key},'geometry':footprint})
            bounds=[min(row[0][0] for row in pack.values()),min(row[0][1] for row in pack.values()),
                    max(row[0][2] for row in pack.values()),max(row[0][3] for row in pack.values())]
            gz(args.out/(group+'.json.gz'),pack);manifest_packs.append({'id':group,'bounds':bounds,'cells':len(pack)})
            if n%12==0:print(f'{n}/{len(groups)} packs compiled',flush=True)
    gz(args.out/'grid.json.gz',{'type':'FeatureCollection','features':grid})
    (args.out/'index.json').write_bytes(encode({'size':SIZE,'crs':manifest['crs'],'cells':len(cells),'districtCells':districts,
       'paintHalo':25,'paintGradeSHA256':grade_hash,'sourceOSM':manifest['osmSHA256'],'kitPrep':manifest['prepSHA256'],'packs':manifest_packs,'sceneRecords':counts}))
