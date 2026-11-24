#!/usr/bin/env python3
"""Build the Taiwan scenery overlay from a Geofabrik Taiwan PBF using pyosmium and Shapely."""
import argparse
import collections
import gzip
import hashlib
import json
import math
from pathlib import Path
import re
import tempfile

import osmium
from shapely import from_wkb, get_parts, prepare
from shapely.geometry import Point, mapping, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree

NATURAL = {
    'peak':'peak', 'volcano':'peak', 'cape':'cape', 'cliff':'cliff', 'beach':'beach',
    'spring':'spring', 'hot_spring':'hot_spring', 'bay':'bay', 'wetland':'wetland',
    'wood':'wood','reef':'reef', 'cave_entrance':'cave', 'waterfall':'waterfall', 'water':'water'
}
WATER = {'lake':'lake', 'reservoir':'reservoir', 'lagoon':'lagoon', 'pond':'pond'}
# The index pin describes the selected geographic object and may have related field notes.
# Exact source identities for highlights are added to the renderer after inspecting the extract.
TYPE_KEYS = [('natural', key) for key in NATURAL] + [('water', key) for key in WATER] + [
    ('place','island'),('place','islet'),('leisure','park'),('leisure','nature_reserve'),
    ('waterway','canal'),('waterway','drain'),('waterway','ditch'),('waterway','river'),('waterway','stream'),('waterway','waterfall'),('landuse','reservoir')]
FACTORY = osmium.geom.WKBFactory()
OUT = Path(__file__).resolve().parents[1] / 'taiwan' / 'scenery'
# These two islands are outside the Geofabrik regional extract. Retain the
# reference-complete, nature-only OSM input so the published build is repeatable.
ISLANDS = {
    'dongsha':'116.70,20.69,116.737,20.714',
    'taiping':'114.349,10.364,114.38,10.389',
}


def category(tags):
    if tags.get('place') in ('island','islet'):
        return 'island'
    waterway = tags.get('waterway')
    if waterway in ('river', 'stream', 'waterfall','canal','drain','ditch'):
        return waterway
    if tags.get('landuse') == 'reservoir':
        return 'reservoir'
    water = tags.get('water')
    if water:
        return WATER.get(water)
    landform = NATURAL.get(tags.get('natural'))
    return landform or (tags.get('leisure') if tags.get('leisure') in ('park','nature_reserve') else None)


def name(tags):
    return tags.get('name:zh-Hant') or tags.get('name:zh') or tags.get('name')


def selected(pbf, target):
    filters = osmium.filter.TagFilter(*TYPE_KEYS)
    with osmium.BackReferenceWriter(str(target), str(pbf), overwrite=True) as writer:
        for feature in osmium.FileProcessor(str(pbf)).with_filter(filters):
            if name(feature.tags) and category(feature.tags) and not (category(feature.tags)=='island' and name(feature.tags) in ('臺灣','台灣','Taiwan')):
                writer.add(feature)


def round_coordinates(coords):
    if isinstance(coords[0], (int, float)):
        return [round(v, 6) for v in coords]
    return [round_coordinates(item) for item in coords]


def feature(geom, props):
    out = mapping(geom)
    return {'type':'Feature', 'properties':props, 'geometry':{
        'type':out['type'], 'coordinates':round_coordinates(out['coordinates'])}}


def waterway_lengths(line):
    """Lengths in metres before midpoint interpolation on the rendered polyline."""
    lengths = []
    for (x1, y1), (x2, y2) in zip(line, line[1:]):
        dy = math.radians(y2 - y1)
        dx = math.radians(x2 - x1) * math.cos(math.radians((y1 + y2) / 2))
        lengths.append(6_371_008.8 * math.hypot(dx, dy))
    return lengths


def write_river_search(rivers, target):
    longest = {}
    for feature in rivers:
        props = feature['properties']
        if props['k'] not in ('river', 'stream'):
            continue
        line = feature['geometry']['coordinates']
        lengths = waterway_lengths(line)
        distance = sum(lengths)
        key = props['n']
        if not distance:
            continue
        previous = longest.get(key)
        if previous and (distance, props['id']) <= previous[:2]:
            continue
        halfway = distance / 2
        for i, length in enumerate(lengths):
            if length and halfway <= length:
                fraction = halfway / length
                point = [round(a + fraction * (b - a), 7) for a, b in zip(line[i], line[i + 1])]
                row = [key, props['k'], props['id'], *point]
                longest[key] = (distance, props['id'], row)
                break
            halfway -= length
    rows = [longest[name][2] for name in sorted(longest)]
    raw = (json.dumps(rows, ensure_ascii=False, separators=(',', ':')) + '\n').encode()
    target.write_bytes(gzip.compress(raw, compresslevel=9, mtime=0))


def build(args):
    input_hash=hashlib.file_digest(args.pbf.open('rb'), 'sha256').hexdigest()
    mask_bytes=args.mask.read_bytes()
    if args.mask.suffix=='.gz':
        mask_bytes=gzip.decompress(mask_bytes)
    mask_json=json.loads(mask_bytes)
    townships = [shape(f['geometry']) for f in mask_json['features']]
    tree = STRtree(townships)
    mask=unary_union(townships)
    # Land-only town boundaries omit lagoons and nearshore islands/reef features.
    nearshore=mask.buffer(.014)
    prepare(mask)
    prepare(nearshore)
    points=[]
    rivers=[]
    waters=[]
    invalid=0
    with tempfile.TemporaryDirectory() as tmp:
        target=Path(tmp,'named.osm.pbf')
        selected(args.pbf,target)
        files=[target, *[OUT/'sources'/(key+'.osm.pbf') for key in ISLANDS]]
        for obj in (feature for file in files for feature in osmium.FileProcessor(str(file)).with_locations().with_areas()):
            tags=obj.tags
            label=name(tags)
            kind=category(tags)
            if not label or not kind:
                continue
            if obj.is_relation():
                continue  # closed multipolygon relations arrive as Area objects
            if obj.is_area():
                source='w' if obj.from_way() else 'r'
                oid=obj.orig_id()
                if kind in ('river','stream','canal','drain','ditch','cliff','waterfall'):
                    continue
            else:
                source=obj.type_str()
                oid=obj.id
                if obj.is_way() and obj.is_closed() and kind not in ('river','stream','canal','drain','ditch','cliff','waterfall'):
                    continue
            try:
                if obj.is_node():
                    geom=Point(obj.location.lon,obj.location.lat)
                elif obj.is_way():
                    geom=from_wkb(FACTORY.create_linestring(obj))
                else:
                    geom=from_wkb(FACTORY.create_multipolygon(obj))
            except (RuntimeError, ValueError, osmium.InvalidLocationError):
                invalid+=1
                continue
            if geom.is_empty:
                continue
            anchor = geom if geom.geom_type=='Point' else (
                geom.interpolate(.5,normalized=True) if obj.is_way() else geom.representative_point())
            extent = nearshore if kind in ('bay','cape','cliff','reef','beach','island','lagoon') else mask
            if not extent.covers(anchor):
                continue
            props={'id':source+str(oid),'n':label,'k':kind}
            raw=tags.get('ele','')
            if re.fullmatch(r'-?\d{1,4}(?:\.\d+)?(?:\s*m)?', raw):
                props['ele']=round(float(raw.rstrip('m ')))
            if obj.is_way() and kind in ('river','stream','canal','drain','ditch'):
                # National overview uses medium-scale generalization. The street
                # map takes over before this error is visible on the ground.
                if tags.get('tunnel','no') == 'no' and tags.get('covered','no') == 'no':
                    rivers.append(feature(geom.simplify(.00012),{**props,'large':kind=='river'}))
                continue
            if obj.is_area() and kind in ('lake','reservoir','water','pond','lagoon','wetland'):
                polygons=[p for p in get_parts(geom) if p.area>=.000001]
                if polygons:
                    gen=unary_union(polygons).simplify(.00008,preserve_topology=True)
                    waters.append(feature(gen,props))
            points.append(feature(anchor,props))
    # A few mapped features share the same named node and enclosing area;
    # prefer the area identity when a close duplicate would share the same pin.
    points.sort(key=lambda f: (f['properties']['id'][0]=='n',f['properties']['id']))
    kept=[]
    # only collapse exact duplicated position/name, never different same-named summits
    seen=set()
    for p in points:
        key=(p['properties']['n'],p['properties']['k'],*p['geometry']['coordinates'])
        if key not in seen:
            kept.append(p);seen.add(key)
    args.out.mkdir(parents=True,exist_ok=True)
    data={'places':kept,'rivers':rivers,'waters':waters}
    represented = set()
    for file,features in data.items():
        for item in features:
            represented.update(tree.query(shape(item['geometry']), predicate='intersects'))
        features.sort(key=lambda f:f['properties']['id'])
        body={'type':'FeatureCollection','features':features}
        raw=(json.dumps(body,ensure_ascii=False,separators=(',',':'))+'\n').encode()
        (args.out/(file+'.geojson.gz')).write_bytes(gzip.compress(raw,compresslevel=9,mtime=0))
    write_river_search(rivers, args.out / 'river-search.json.gz')
    report={'extract':args.source,'sha256':input_hash,'license':'ODbL 1.0',
            'supplements':{key:{'file':'sources/'+key+'.osm.pbf',
                'source':'https://api.openstreetmap.org/api/0.6/map?bbox='+bbox,
                'sha256':hashlib.file_digest((OUT/'sources'/(key+'.osm.pbf')).open('rb'),'sha256').hexdigest()}
                for key,bbox in ISLANDS.items()},
            'geometry':'WGS84, simplified for regional use; full-resolution base vectors at street scale',
            'boundaries':{'source':'https://data.gov.tw/dataset/7441','file':'townships.geojson',
                          'sha256':hashlib.sha256(mask_bytes).hexdigest()},
            'counts':{k:len(v) for k,v in data.items()},
            'coverage':{'townshipsInMask':len(townships),'townshipsWithScenery':len(represented),
                        'countiesWithScenery':len({mask_json['features'][i]['properties']['county'] for i in represented})},
            'placeKinds':dict(sorted(collections.Counter(f['properties']['k'] for f in kept).items())),
            'invalidGeometriesSkipped':invalid}
    (args.out/'sources.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pbf',type=Path)
    parser.add_argument('--source',required=True,help='Versioned extract URL')
    parser.add_argument('--mask',type=Path,required=True,help='WGS84 county/town boundaries (GeoJSON FeatureCollection)')
    parser.add_argument('--out',type=Path,default=OUT)
    build(parser.parse_args())
