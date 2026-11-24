"""Build the national land mask and searchable township anchors from NLSC's TWD97 ZIP.

Input: https://maps.nlsc.gov.tw/download/鄉鎮市區界線(TWD97經緯度).zip
Requires pyshp and Shapely 2.1. EPSG:3824 coordinates are longitude/latitude.
"""
import hashlib
import io
import json
from pathlib import Path
import sys
import zipfile

import shapefile
from shapely import coverage_simplify, get_parts, make_valid, set_precision, union_all
from shapely.geometry import mapping, shape

archive = Path(sys.argv[1])
out = Path(__file__).resolve().parents[1] / 'taiwan' / 'townships.geojson'
with zipfile.ZipFile(archive) as z:
    name = next(p[:-4] for p in z.namelist() if p.upper().startswith('TOWN_MOI_') and p.endswith('.shp'))
    records = shapefile.Reader(**{
        ext: io.BytesIO(z.read(name + '.' + ext)) for ext in ('dbf', 'shp', 'shx')
    })
    rows = sorted(records.iterShapeRecords(), key=lambda row: row.record.TOWNCODE)
    geometries = [shape(row.shape.__geo_interface__) for row in rows]

# Simplify shared edges together so administrative neighbours still fit.
simple = coverage_simplify(geometries, tolerance=.00008)
features = []
for row, geom in zip(rows, simple):
    geom = set_precision(make_valid(geom), .00001)
    polygons = [part for part in get_parts(geom) if part.geom_type in ('Polygon', 'MultiPolygon')]
    geom = union_all(polygons)
    primary = max(get_parts(geom), key=lambda p: p.area)
    anchor = primary.representative_point()
    doc = row.record
    features.append(dict(type='Feature', bbox=list(geom.bounds), properties=dict(
        code=doc.TOWNCODE, county=doc.COUNTYNAME, name=doc.TOWNNAME,
        anchor=[round(anchor.x, 6), round(anchor.y, 6)]), geometry=mapping(geom)))
assert len(features) == 368 and len({f['properties']['county'] for f in features}) == 22
out.write_text(json.dumps(dict(type='FeatureCollection', source='內政部國土測繪中心',
    url='https://maps.nlsc.gov.tw/pro/download.jsp', layer=name,
    sha256=hashlib.sha256(archive.read_bytes()).hexdigest(), features=features),
    separators=(',', ':'), ensure_ascii=False) + '\n', encoding='utf8')
print(out.name, len(features), out.stat().st_size)

# Encode every occupied 170 m cell as inclusive column runs grouped by grid row.
# A narrow coastline crossing a cell counts even if its centre lies in the sea.
import gzip
import math
import numpy as np
import shapely
from collections import defaultdict
runs = defaultdict(set)
step_x = 170 / (111320 * math.cos(math.radians(23.5)))
step_y = 170 / 110574
for feature in features:
    for poly in get_parts(shape(feature['geometry'])):
        w,s,e,n = poly.bounds
        xs = np.arange(math.floor((w-120)/step_x), math.floor((e-120)/step_x)+1)
        ys = np.arange(math.floor((s-23.5)/step_y), math.floor((n-23.5)/step_y)+1)
        shapely.prepare(poly)
        for y in ys:
            left, bottom = 120+xs*step_x, 23.5+y*step_y
            mask = shapely.intersects(poly, shapely.box(left,bottom,left+step_x,bottom+step_y))
            runs[int(y)].update(xs[mask].tolist())
rows=[]
for y,columns in sorted(runs.items()):
    if not columns:continue
    cols=sorted(columns)
    limits=[cols[0]]
    for prev,cur in zip(cols,cols[1:]):
        if cur!=prev+1:limits.extend((prev,cur))
    rows.append([y,*limits,cols[-1]])
folder=out.parent
(folder/'cells.json').write_text(json.dumps(dict(metres=170,origin=[120,23.5],
    count=sum(map(len,runs.values())),rows=rows),separators=(',',':'))+'\n')
(folder/'townships.geojson.gz').write_bytes(gzip.compress(out.read_bytes(),compresslevel=9,mtime=0))
(folder/'town-index.json').write_text(json.dumps([f['properties'] for f in features],separators=(',',':'),ensure_ascii=False)+'\n')
print('Intersecting land cells',sum(map(len,runs.values())))
