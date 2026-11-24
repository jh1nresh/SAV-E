"""Restore sourced farm parcels and orchards from the same snapshot as Taipei's grid.

Usage: python build-city170-farmland.py taipei.json.gz /path/to/data output.json.gz
"""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path

from shapely.geometry import LineString, Polygon, mapping, shape
from shapely import make_valid, orient_polygons
from shapely.ops import unary_union

spec = importlib.util.spec_from_file_location('atlas',Path(__file__).with_name('build-city170.py'))
atlas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(atlas)


def build(source, data):
    expected = json.loads((data/'city170/index.json').read_bytes())['source']['provenance']['taipeiExtractUncompressedSHA256']
    with gzip.open(source,'rb') as stream:
        if hashlib.file_digest(stream,'sha256').hexdigest()!=expected:
            raise ValueError('Farm polygons need the same source as the Taipei grid')
    boundary = unary_union([make_valid(shape(f['geometry'])) for f in
                            json.loads((data/'districts.geojson').read_bytes())['features']])
    types = {'farmland','orchard'}
    relations = [r for r in atlas.records(source) if r['type']=='relation' and r.get('tags',{}).get('landuse') in types]
    members = {m['ref'] for r in relations for m in r['members'] if m['type']=='way'}
    ways = {w['id']:w for w in atlas.records(source) if w['type']=='way' and
            (w['id'] in members or w.get('tags',{}).get('landuse') in types)}
    needed = {n for w in ways.values() for n in w['nodes']}
    points = {r['id']:(r['lon'],r['lat']) for r in atlas.records(source) if r['type']=='node' and r['id'] in needed}
    lines = {i:LineString([points[n] for n in w['nodes']]) for i,w in ways.items() if len(w['nodes'])>=2}
    features = []
    def add(record, geom):
        if geom is None:return False
        clipped = atlas.polygonal(make_valid(geom).intersection(boundary))
        if clipped is None:return False
        features.append(dict(type='Feature',id='farm/'+record['type']+'/'+str(record['id']),
            properties=dict(kind='farm',category=record['tags']['landuse']),geometry=mapping(orient_polygons(clipped))))
        return True
    represented = set()
    for r in relations:
        if add(r,atlas.relation_polygon(r,lines.get)):
            represented.update((m['ref'],r['tags']['landuse']) for m in r['members'] if m['type']=='way' and m.get('role') in ('','outer'))
    for i,w in ways.items():
        k=w.get('tags',{}).get('landuse')
        if k in types and (i,k) not in represented and i in lines and lines[i].is_ring:
            add(w,Polygon(lines[i]))
    return dict(type='FeatureCollection',sourceSHA256=expected,features=features)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for arg in ('source','data','output'):parser.add_argument(arg,type=Path)
    args=parser.parse_args()
    layer=build(args.source,args.data);atlas.write_gzip(args.output,layer)
    print(len(layer['features']),'mapped agricultural areas')
