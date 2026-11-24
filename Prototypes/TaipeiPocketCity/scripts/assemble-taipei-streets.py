"""Compose additional Pocket City districts with real street labels and places."""
import argparse
from collections import defaultdict
import gzip
import json
import math
from pathlib import Path

import ijson
from shapely.geometry import LineString, Point, Polygon, shape
from shapely.ops import transform
from shapely.strtree import STRtree


ROAD_RANK = {key: i//2 for i, key in enumerate((
    'trunk','primary','secondary','tertiary','residential','unclassified',
    'pedestrian','living_street','service','footway','path','steps',
))}
SHOPS = {'restaurant':'餐廳','fast_food':'餐廳','cafe':'咖啡','bakery':'麵包',
         'books':'書店','tea':'茶飲','deli':'熟食','convenience':'超商','supermarket':'超市',
         'ice_cream':'冰品','confectionery':'甜點'}
HERITAGE = {'museum':'博物館','gallery':'展館','hotel':'旅宿','viewpoint':'觀景點',
            'attraction':'景點','zoo':'動物園','theme_park':'景點'}
FOCUS = {
    'zhongzheng': ['中正紀念堂','國立臺灣博物館','國家兩廳院','南門市場'],
    'datong': ['霞海城隍廟','大稻埕碼頭','迪化街','寧夏夜市'],
    'wanhua': ['艋舺龍山寺','西門紅樓','剝皮寮','青山宮'],
    'shilin': ['國立故宮博物院','士林官邸','圓山大飯店','士林夜市'],
    'beitou': ['北投溫泉博物館','地熱谷','北投圖書館','新北投車站'],
    'neihu': ['碧湖公園','大湖公園','美麗華','白石湖'],
    'nangang': ['南港展覽館','瓶蓋工廠','中研院','南港公園'],
    'wenshan': ['臺北市立動物園','指南宮','貓空','景美夜市'],
}


def read(path):
    return json.loads(path.read_bytes())


def gzip_json(path, value):
    payload = json.dumps(value,ensure_ascii=False,separators=(',',':')).encode()
    path.write_bytes(gzip.compress(payload, compresslevel=6, mtime=0))


def name(tags):
    return tags.get('name:zh-Hant') or tags.get('name:zh') or tags.get('name')


def collection(features):
    return {'type':'FeatureCollection','features':features}


def split_line(geometry):
    if geometry.geom_type == 'LineString':
        return [geometry]
    return [part for part in getattr(geometry,'geoms',()) if part.geom_type == 'LineString']


def street_labels(by_name, geo):
    used = defaultdict(list)
    result = []
    order = sorted(by_name.items(),key=lambda row:(
        min(rank for rank,_ in row[1]), -sum(line.length for _,line in row[1]), row[0]))
    for label, segments in order:
        for rank, line in sorted(segments,key=lambda item: -item[1].length):
            if line.length < 31:
                continue
            interval = 200 if rank < 3 else 145
            count = max(1, round(line.length/interval))
            for i in range(count):
                point = line.interpolate((i+.5)/count, normalized=True)
                if min((p.distance(point) for p in used[label]),default=math.inf) < interval*.84:
                    continue
                used[label].append(point)
                result.append({'type':'Feature','geometry':{'type':'Point','coordinates':geo(point.x,point.y)},
                               'properties':{'name':label,'rank':rank}})
    return collection(result)


def place_kind(tags):
    kind = SHOPS.get(tags.get('shop')) or SHOPS.get(tags.get('amenity'))
    if kind:
        return kind
    if tags.get('amenity') == 'place_of_worship':
        return '寺廟' if tags.get('religion') in ('buddhist','taoist') else '景點'
    if tags.get('amenity') == 'marketplace':
        return '市場'
    if tags.get('leisure') in ('park','garden'):
        return '公園'
    if tags.get('historic') not in (None, 'no', 'yes'):
        return '古蹟'
    return HERITAGE.get(tags.get('tourism'))


def choose_places(candidates, geo):
    places, locations, names = [], [], defaultdict(list)
    for rank, label, kind, point, tags, record in sorted(candidates,key=lambda row:(row[0],row[1],row[5]['id'])):
        gap = 38 if rank == 0 else 82 if rank <= 2 else 142
        if any(p.distance(point)<gap for p in locations) or any(p.distance(point)<125 for p in names[label]):
            continue
        locations.append(point)
        names[label].append(point)
        address = ' '.join(part for part in (tags.get('addr:street'),tags.get('addr:housenumber')) if part)
        places.append({'id':f"osm-{record['type']}-{record['id']}",'name':label,'kind':kind,
                       'detail':address or kind,'point':geo(point.x,point.y),
                       'url':f"https://www.openstreetmap.org/{record['type']}/{record['id']}",
                       'source':'OpenStreetMap','minZoom':16.6 if rank==0 else 17.65 if rank<=2 else 18,
                       'priority':rank})
        if len(places)>=240:
            break
    return places


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--osm', type=Path, required=True)
    parser.add_argument('--grids', type=Path, required=True)
    parser.add_argument('--prepared', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    keys = list(FOCUS)
    districts = {key:read(args.grids/f'street-{key}-district.json') for key in keys}
    origin = next(iter(districts.values()))['origin']
    lat_metres, east_metres = 111195, 111195*math.cos(math.radians(origin[1]))
    def local(lon, lat):
        return (lon-origin[0])*east_metres, (lat-origin[1])*lat_metres
    def geo(x, y):
        return [round(x/east_metres+origin[0],8),round(y/lat_metres+origin[1],8)]
    boundaries = [transform(local,shape(row['footprint'])) for row in districts.values()]
    owners = STRtree(boundaries)
    roads = defaultdict(lambda:defaultdict(list))
    places = defaultdict(list)
    nodes = {}
    ways = []
    tags_by_node = {}
    open_osm = gzip.open if args.osm.suffix=='.gz' else open
    with open_osm(args.osm,'rb') as base:
        for record in ijson.items(base,'elements.item',use_float=True):
            if record['type']=='node':
                nodes[record['id']] = local(record['lon'],record['lat'])
                tags = record.get('tags')
                if tags and name(tags) and place_kind(tags):
                    tags_by_node[record['id']] = record
            elif record['type']=='way' and record.get('tags'):
                ways.append(record)
    with open_osm(args.osm,'rb') as base:
        input_source = next(ijson.items(base,'source',use_float=True))

    def include_place(record, point):
        tags = record['tags']
        label, kind = name(tags), place_kind(tags)
        if not label or not kind or any(word in label for word in ('歇業','施工','籌備','Temporary')):
            return
        if any(k in tags for k in ('disused:shop','disused:amenity','abandoned:shop','abandoned:amenity')):
            return
        for index in owners.query(point, predicate='intersects'):
            key = keys[index]
            priority = 0 if any(s in label for s in FOCUS[key]) else 1 if kind in ('古蹟','博物館','市場','寺廟') else 2 if kind in ('咖啡','餐廳','麵包','書店','茶飲','甜點') else 3
            places[key].append((priority,label,kind,point,tags,record))

    for item in tags_by_node.values():
        include_place(item, Point(nodes[item['id']]))
    for item in ways:
        tags = item['tags']
        label = name(tags)
        if not label:
            continue
        rank, kind = ROAD_RANK.get(tags.get('highway')), place_kind(tags)
        if rank is None and not kind:
            continue
        coordinates = [nodes[ref] for ref in item['nodes']]
        if len(coordinates)<2:
            continue
        line = LineString(coordinates)
        district_hits = owners.query(line,predicate='intersects')
        if kind:
            point = Polygon(coordinates).buffer(0).representative_point() if len(coordinates)>=4 and coordinates[0]==coordinates[-1] else line.interpolate(.5,normalized=True)
            if not point.is_empty:
                include_place(item,point)
        if rank is None or tags.get('indoor')=='yes' or tags.get('tunnel') not in (None,'no'):
            continue
        for index in district_hits:
            roads[keys[index]][label].extend((rank,segment) for segment in split_line(line.intersection(boundaries[index])))

    stage_summary = read(args.prepared/'receipt.json')
    index = []
    for key,row in districts.items():
        prepared = read(args.prepared/'districts'/f'{key}-district.json')
        base = {k:v for k,v in row.items() if k!='cells'}
        base.update(ground=collection(prepared['ground']),paths=prepared['paths'],objects=prepared['objects'],
                    roads=street_labels(roads[key],geo),places=choose_places(places[key],geo))
        slug = f'{key}-district'
        gzip_json(args.out/f'{slug}.json.gz',base)
        index.append({'key':slug,'name':row['name'],'bounds':row['bounds'],'cells':len(row['cells']),
                      'ground':len(base['ground']['features']),'roads':len(base['roads']['features']),
                      'places':len(base['places']),'paths':len(base['paths']),'objects':len(base['objects'])})
        print(index[-1],flush=True)
    index_data={'districts':index,'source':input_source,'pipeline':stage_summary}
    (args.out/'index.json').write_text(json.dumps(index_data,ensure_ascii=False,separators=(',',':'))+'\n')
    gzip_json(args.out/'grids.json.gz',{f'{key}-district':row['cells'] for key,row in districts.items()})


if __name__=='__main__':
    main()
