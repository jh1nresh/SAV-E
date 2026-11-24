"""Index named public POIs inside NLSC town polygons from a Geofabrik Taiwan .osm.pbf.
Run with pyosmium, numpy and Shapely 2. Produces spatial shards and a searchable name index.
"""
import gzip
import hashlib
import json
import math
from pathlib import Path
import sys

import osmium
import shapely
from shapely.geometry import Point, Polygon, shape
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[1] / 'taiwan'
OUT = ROOT / 'places'
OUT.mkdir(exist_ok=True)
pbf = Path(sys.argv[1])
towns = json.loads((ROOT/'townships.geojson').read_text())['features']
parts, codes = [], []
for town in towns:
    for polygon in shapely.get_parts(shape(town['geometry'])):
        parts.append(polygon)
        codes.append(town['properties']['code'])
tree = STRtree(parts)
categories = ['shop','amenity','tourism','leisure','historic','railway','public_transport']
ignore = {'bench','parking_entrance','parking_space','waste_basket','waste_disposal','recycling',
          'post_box','vending_machine','platform_edge','level_crossing','signal','switch',
          'picnic_table','boundary_stone','yes','no'}
def classify(tags):
    for key in categories:
        value=tags.get(key)
        if value and value not in ignore:
            if key=='railway' and value not in ('station','halt','tram_stop'):continue
            if key=='public_transport' and value not in ('station','platform','stop_position'):continue
            return value
    return None

def dump(name,data):
    raw=json.dumps(data,ensure_ascii=False,separators=(',',':')).encode()
    (OUT/name).write_bytes(gzip.compress(raw,compresslevel=9,mtime=0))

shards,counts={},{}
index=[]
factory=osmium.geom.WKBFactory()
def record(name,category,osm_id,point):
    matches=tree.query(point,predicate='intersects')
    if not len(matches): return
    code=codes[matches[0]]
    lon,lat=round(point.x,6),round(point.y,6)
    x=int((lon+180)/360*1024)
    y=int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)*512)
    key=f'{x}-{y}'
    row=[name,category,osm_id,lon,lat,code]
    shards.setdefault(key,[]).append(row)
    counts[code]=counts.get(code,0)+1
    index.append(row)

for obj in osmium.FileProcessor(str(pbf)).with_locations().with_areas(osmium.filter.KeyFilter(*categories)):
    tags=obj.tags
    name=tags.get('name:zh-Hant') or tags.get('name:zh') or tags.get('name')
    if not name or tags.get('access')=='private':continue
    category=classify(tags)
    if not category:continue
    if obj.is_node():
        if obj.location.valid():record(name,category,'n'+str(obj.id),Point(obj.location.lon,obj.location.lat))
    elif obj.is_way():
        if obj.is_closed() or not obj.nodes:continue
        pts=[(n.lon,n.lat) for n in obj.nodes if n.location.valid()]
        if pts:record(name,category,'w'+str(obj.id),Point(pts[len(pts)//2]))
    elif obj.is_area():
        try:
            geom=shapely.from_wkb(bytes.fromhex(factory.create_multipolygon(obj)))
        except (RuntimeError,ValueError):continue
        if not geom.is_empty:record(name,category,('w' if obj.from_way() else 'r')+str(obj.orig_id()),geom.representative_point())

for key,rows in sorted(shards.items()):dump(key+'.json.gz',sorted(rows))
# Search loads a compact name-to-spatial-row index; coordinates and full tags stay in visible shards.
names=[]
for key,rows in sorted(shards.items()):
    for pos,(name,category,osm_id,lon,lat,code) in enumerate(sorted(rows)):
        names.append([name,code,key,pos])
dump('names.json.gz',names)
manifest=dict(source='© OpenStreetMap contributors, ODbL',extract='https://download.geofabrik.de/asia/taiwan.html',
    dataset=osmium.io.Reader(str(pbf)).header().get('osmosis_replication_timestamp'),
    sha256=hashlib.file_digest(pbf.open('rb'),'sha256').hexdigest(),
    count=len(index),townships=counts,tiles=sorted(shards))
(OUT/'index.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':'))+'\n')
print(len(index),'places',len(counts),'townships',len(shards),'shards',flush=True)
