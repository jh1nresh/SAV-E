"""Locate illustrative crowns inside mapped grasslands/wetlands using exact atlas geometry."""
import argparse
import gzip
import json
from pathlib import Path

import shapely
from shapely.geometry import shape


def read(path):
    return json.loads(gzip.decompress(path.read_bytes()))


def build(data):
    open_land, woodland = [], []
    for path in sorted((data/'city170').glob('p*.json.gz')):
        for feature in read(path)['features']['features']:
            p = feature['properties']
            if p['kind'] == 'forest' and p['category'] in ('grassland', 'wetland', 'forest', 'wood'):
                group = open_land if p['category'] in ('grassland','wetland') else woodland
                group.append(shapely.make_valid(shape(feature['geometry'])))
    area = shapely.union_all(open_land).difference(shapely.union_all(woodland))
    shapely.prepare(area)
    sites = {}
    for path in sorted((data/'city170-prepared').glob('*.json.gz')):
        for cell, features in read(path).items():
            points = [f['geometry']['coordinates'] for f in features if f['properties']['kind']=='grove-tree']
            if points:
                covered = shapely.contains_xy(area, *zip(*points))
                excluded = [point for point, hit in zip(points, covered) if hit]
                if excluded:
                    sites[cell] = excluded
    return sites


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data',type=Path)
    parser.add_argument('output',type=Path)
    args = parser.parse_args()
    sites = build(args.data)
    args.output.write_bytes(gzip.compress(json.dumps(sites,separators=(',',':')).encode(),mtime=0))
    print(len(sites),'cells;',sum(map(len,sites.values())),'illustrative crowns on open ground')
