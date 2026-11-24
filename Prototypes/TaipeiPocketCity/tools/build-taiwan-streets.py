"""Build the offline neighborhood geometry from the versioned Geofabrik/Taiwan extract.
Usage: python tools/build-taiwan-streets.py taiwan-261123.osm.pbf [--output <path>]
Requires pyosmium and Shapely 2. Reads the published national place shards and boundary snapshot.
"""
import argparse
from collections import Counter, OrderedDict, defaultdict
import gzip
import hashlib
import json
import math
from pathlib import Path
from tempfile import TemporaryDirectory

import osmium
import shapely
from shapely.geometry import LineString, Point, Polygon, box, shape
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[1] / 'taiwan'
UNIT = 100000
TILE = 3125  # 1/32 degree; XY precision about one metre, no visible cell outlines.
CLASSES = [
    ('arterial', {'trunk', 'primary', 'secondary', 'tertiary', 'primary_link', 'secondary_link', 'tertiary_link'}),
    ('street', {'residential', 'unclassified'}),
    ('lane', {'living_street', 'service'}),
    ('walk', {'pedestrian', 'footway', 'steps', 'cycleway', 'path', 'track'}),
]
HIGHWAYS = {kind: i for i, (_, kinds) in enumerate(CLASSES) for kind in kinds}
RETAIL = set('restaurant fast_food food_court street_food bakery cafe coffee tea bar beverages shop mall department_store supermarket convenience electronics gift hardware optician florist greengrocer deli mobile_phone houseware furniture cosmetics pet bicycle computer toys stationery alcohol confectionery variety_store hifi camera clothes shoes jewelry boutique marketplace books'.split())
TINTED_HEIGHT = {'house':6, 'detached':6, 'terrace':6, 'apartments':12, 'office':10, 'retail':6,
                 'commercial':8,'industrial':7, 'warehouse':7, 'garage':3, 'garages':3, 'hut':3}
json_line = lambda row: json.dumps(row, ensure_ascii=False, separators=(',', ':'))


def read_geo(path):
    return json.loads(gzip.decompress(path.read_bytes()))


def encoded(coords, tile):
    """First vertex relative to shard origin; remaining coordinates delta-coded <1m."""
    previous = (tile[0]*TILE, tile[1]*TILE)
    out = []
    for point in coords:
        x,y = point
        out.extend([x-previous[0], y-previous[1]])
        previous = point
    return out


def quantize(coords):
    out=[]
    for lng, lat in coords:
        p=(round(lng*UNIT),round(lat*UNIT))
        if not out or p!=out[-1]:
            out.append(p)
    return out


def bbox(points):
    x,y=zip(*points)
    return min(x),min(y),max(x),max(y)


def tile_keys(bounds):
    w,s,e,n=bounds
    for x in range(w//TILE, e//TILE+1):
        for y in range(s//TILE, n//TILE+1):
            yield (x,y)


class Shards:
    def __init__(self, tmp):
        self.tmp = tmp
        self.open = OrderedDict()
        self.keys = set()

    def write(self, key, row):
        f=self.open.pop(key, None)
        if f is None:
            if len(self.open) == 48:
                self.open.popitem(last=False)[1].close()
            f=(self.tmp / key).open('a')
        self.open[key]=f
        self.keys.add(key)
        f.write(json_line(row)+'\n')

    def publish(self, out):
        for f in self.open.values():
            f.close()
        rows={}
        for key in sorted(self.keys):
            raw=(self.tmp/key).read_text()
            content=('['+raw.rstrip().replace('\n',',')+']').encode()
            data=gzip.compress(content,compresslevel=8,mtime=0)
            (out/(key+'.json.gz')).write_bytes(data)
            rows[key]=len(data)
        return rows


class Counties:
    def __init__(self):
        polygons=defaultdict(list)
        for town in read_geo(ROOT/'townships.geojson.gz')['features']:
            polygons[town['properties']['county']].append(shape(town['geometry']))
        self.geoms=[]
        self.names=[]
        for name, parts in polygons.items():
            for poly in shapely.get_parts(shapely.union_all(parts)):
                self.geoms.append(poly)
                self.names.append(name)
        self.tree=STRtree(self.geoms)
        self.grid={}

    def at(self,x,y):
        key=(math.floor(x*32),math.floor(y*32))
        if key not in self.grid:
            left,bottom=key
            tile=box(left/32,bottom/32,(left+1)/32,(bottom+1)/32)
            hits=self.tree.query(tile,predicate='intersects')
            solid=next((self.names[i] for i in hits if self.geoms[i].covers(tile)),None)
            self.grid[key]=(solid,hits)
        solid,hits=self.grid[key]
        if solid:return solid
        for i in hits:
            if shapely.intersects_xy(self.geoms[i],x,y):
                return self.names[i]
        return None


def interior_tiles(counties,keys):
    """Only cells whose entire rectangle is inside one non-Taipei county may skip shoreline checks."""
    result=[]
    for key in keys:
        x,y=map(int,key.split('-'))
        counties.at((x+.5)/32,(y+.5)/32)
        solid,_=counties.grid[x,y]
        if solid and solid!='臺北市':result.append(key)
    return sorted(result)


def store_locations():
    towns={r['code']:r['county'] for r in json.loads((ROOT/'town-index.json').read_text())}
    rows=[]
    counts=Counter()
    for key in json.loads((ROOT/'places/index.json').read_text())['tiles']:
        for name,kind,osm_id,x,y,code in read_geo(ROOT/'places'/(key+'.json.gz')):
            county=towns[code]
            if kind in RETAIL and county!='臺北市':
                rows.append((x,y,osm_id,kind,county))
                counts[county]+=1
    return rows,STRtree(shapely.points([(r[0],r[1]) for r in rows])),counts


def height(tags):
    def number(raw):
        try:
            return float((raw or '').rstrip(' m'))
        except ValueError:
            return 0
    measured=number(tags.get('height'))
    floors=number(tags.get('building:levels'))
    if 1<=measured<=600:return round(measured)
    if .5<=floors<=150:return round(floors*3.2)
    return TINTED_HEIGHT.get(tags.get('building'),6)


def write_sources(out,manifest):
    counties=manifest['counties']
    sums=sum((Counter(s) for s in counties.values()),Counter())
    lines=[
        '# 全台街區圖資', '',
        '此資料集涵蓋台北市以外的 21 個縣市。地圖在縮放層級 16 載入畫面附近的街巷，17 顯示有來源的建物，18 起顯示近景立面。台北市沿用市府實測圖資。', '',
        f"地圖收錄 {sums['roads']:,} 個公開地面道路 OSM way，其中 {sums['namedRoads']:,} 段帶路名。相連的多個 way 可以屬於同一條街。"
        f"共有 {sums['footprints']:,} 個建物輪廓。{sums['commercialPOIs']:,} 個公開具名商業地點之中，有 {sums['frontagePOIs']:,} 個位於建物內且接近外牆。其他店家沿用原有地點圖釘。", '',
        '| 縣市 | 地面道路 way | 具名 way | 建物輪廓 | 具名商業地點 | 已配對外牆 |',
        '| --- | ---: | ---: | ---: | ---: | ---: |',
    ]
    for county,s in counties.items():
        lines.append(f"| {county} | {s['roads']:,} | {s['namedRoads']:,} | {s['footprints']:,} | {s['commercialPOIs']:,} | {s['frontagePOIs']:,} |")
    lines.extend(['', '## 資料界線', '',
        '- 公開地面街道包含幹道、住宅路、巷道及步行路徑。私有或禁止通行的道路、隧道、高架道路與停車場內車道會略過。缺少路名的線保留幾何。',
        '- 店面配對限於公開店家座標落在實際建物內，距離外緣約 8 公尺內。門面、招牌顏色與朝向屬插畫示意。建物保留中庭，優先使用高度或樓層標記，缺漏時按建物類型推估。',
        f"- 此快照有 {sums['invalidAfterQuantization']:,} 個輪廓在約一公尺精度下失去有效拓撲，已略過。",
        '- 澎湖、金門、馬祖均有公開街巷與建物。東沙與太平島此次補充快照只有自然景觀資料，未收錄地面道路或建物。',
        f"- 分成 {len(manifest['tiles']):,} 份，gzip 合計 {manifest['compressedBytes']:,} bytes，最大一份 {manifest['largestShardBytes']:,} bytes。{len(manifest['interiorTiles']):,} 份的整個範圍已驗證位於同一非台北縣市內，其餘在顯示時核對行政界。",
        '', '## 來源及重建', '',
        f"- 道路、建物、店家依 2026-11-23 公開快照，© OpenStreetMap contributors，ODbL 1.0。[Geofabrik Taiwan]({manifest['osm']})",
        '- 行政範圍採用本專案所附國土測繪中心鄉鎮市區界。[內政資料開放平臺](https://data.gov.tw/dataset/7441)',
        '- 離島補片的原始 URL 和 SHA-256 保存在同目錄的 index.json，原始檔在 taiwan/scenery/sources。',
        '', '使用 Python、pyosmium 與 Shapely 2，從原型根目錄執行下列命令。', '',
        '```sh', 'python tools/build-taiwan-streets.py /path/to/taiwan-261123.osm.pbf', '```', ''])
    (out/'SOURCES.md').write_text('\n'.join(lines))


def build(pbf, out):
    out.mkdir(parents=True,exist_ok=True)
    provenance=json.loads((ROOT/'scenery/sources.json').read_text())
    with pbf.open('rb') as f:
        sha=hashlib.file_digest(f,'sha256').hexdigest()
    if sha!=provenance['sha256']:
        raise ValueError('Input extract differs from public place/boundary snapshot')
    counties=Counties()
    shops,shop_index,shop_counts=store_locations()
    matched=defaultdict(set)
    counts=defaultdict(Counter)
    source_ids=set()
    pbf_files=[pbf]
    for island,meta in provenance['supplements'].items():
        path=ROOT/'scenery'/meta['file']
        if hashlib.sha256(path.read_bytes()).hexdigest()!=meta['sha256']:raise ValueError(island)
        pbf_files.append(path)
    factory=osmium.geom.WKBFactory()
    with TemporaryDirectory() as temp:
        shards=Shards(Path(temp))
        for path in pbf_files:
            print('Reading',path,flush=True)
            processor=(osmium.FileProcessor(str(path)).with_locations()
                       .with_areas(osmium.filter.KeyFilter('building'))
                       .with_filter(osmium.filter.EntityFilter(osmium.osm.WAY|osmium.osm.AREA)))
            for obj in processor:
                tags=obj.tags
                if obj.is_way():
                    road=tags.get('highway')
                    if road not in HIGHWAYS or tags.get('area')=='yes' or tags.get('access') in ('private','no') or tags.get('service')=='parking_aisle':continue
                    # Do not render an elevated motorway or an underground route flush with a surface street.
                    if tags.get('tunnel') not in (None,'no') or tags.get('bridge') not in (None,'no'):continue
                    points=[(v.lon,v.lat) for v in obj.nodes if v.location.valid()]
                    if len(points)<2:continue
                    county=counties.at(*points[len(points)//2])
                    if not county or county=='臺北市':continue
                    token=('r',obj.id)
                    if token in source_ids:continue
                    source_ids.add(token)
                    name=tags.get('name:zh-Hant') or tags.get('name:zh') or tags.get('name') or ''
                    level=HIGHWAYS[road]
                    pts=quantize(LineString(points).simplify(.000005,preserve_topology=False).coords)
                    if len(pts)<2:continue
                    # Cap long fragments to avoid repeatedly decoding a many-kilometre way in neighboring shards.
                    for i in range(0,len(pts)-1,31):
                        line=pts[i:i+32]
                        bounds=bbox(line)
                        for tile in tile_keys(bounds):
                            if len(line)>2 and (bounds[2]-bounds[0]>TILE or bounds[3]-bounds[1]>TILE):
                                x,y=tile
                                if not LineString(line).intersects(box(x*TILE,y*TILE,(x+1)*TILE,(y+1)*TILE)):continue
                            shards.write('%d-%d'%tile,[0,obj.id,i,level,name,encoded(line,tile)])
                    counts[county]['roads']+=1
                    counts[county]['namedRoads']+=bool(name)
                    counts[county]['lanesAndWalks']+=level>=2
                elif obj.is_area():
                    if tags.get('building') in (None,'no','construction','ruins','roof'):continue
                    try:
                        geom=shapely.from_wkb(bytes.fromhex(factory.create_multipolygon(obj)))
                    except (RuntimeError,ValueError):continue
                    ident=obj.orig_id()*(1 if obj.from_way() else -1)
                    token=('b',ident)
                    if token in source_ids:continue
                    source_ids.add(token)
                    for part,poly in enumerate(shapely.get_parts(geom)):
                        if poly.is_empty or poly.geom_type!='Polygon' or not poly.is_valid:continue
                        pt=poly.representative_point();county=counties.at(pt.x,pt.y)
                        if not county or county=='臺北市':continue
                        simple=poly.simplify(.000003,preserve_topology=True)
                        rings=[quantize(r.coords) for r in [simple.exterior,*simple.interiors]]
                        if len(set(rings[0]))<3:continue
                        rings=[r for r in rings if len(set(r))>=3]
                        if not Polygon(rings[0],rings[1:]).is_valid:
                            counts[county]['invalidAfterQuantization']+=1
                            continue
                        bounds=bbox(rings[0])
                        # Only a named commercial POI in this mapped building and near its actual exterior.
                        occupants=[]
                        for idx in shop_index.query(poly,predicate='covers'):
                            x,y,sid,kind,_=shops[idx]
                            if poly.exterior.distance(Point(x,y))>.000075:continue
                            occupants.append([sid,kind,round(x*UNIT),round(y*UNIT)])
                            matched[county].add(sid)
                        for tile in tile_keys(bounds):
                            shop_points=[[sid,kind,x-tile[0]*TILE,y-tile[1]*TILE] for sid,kind,x,y in occupants]
                            row=[1,ident,part,height(tags),[encoded(r[:-1],tile) for r in rings]]
                            if shop_points:row.append(shop_points)
                            shards.write('%d-%d'%tile,row)
                        counts[county]['footprints']+=1
        sizes=shards.publish(out)
    for county,stats in counts.items():
        stats['commercialPOIs']=shop_counts[county]
        stats['frontagePOIs']=len(matched[county])
    manifest={'version':1,'scale':UNIT,'tileSpan':TILE,'osm':provenance['extract'],'sha256':sha,
              'license':'© OpenStreetMap contributors, ODbL 1.0','supplements':provenance['supplements'],
              'roadClasses':[name for name,_ in CLASSES],'counties':dict(sorted(counts.items())),
              'tiles':sorted(sizes),'interiorTiles':interior_tiles(counties,sizes),'compressedBytes':sum(sizes.values()),'largestShardBytes':max(sizes.values())}
    (out/'index.json').write_text(json_line(manifest)+'\n')
    write_sources(out,manifest)
    listed={key+'.json.gz' for key in sizes}
    for path in out.glob('*.json.gz'):
        if path.name not in listed:path.unlink()
    print(len(sizes),'tiles;',manifest['compressedBytes'],'bytes; counties:',len(counts),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pbf',type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'streets')
    args=parser.parse_args()
    build(args.pbf,args.output)
