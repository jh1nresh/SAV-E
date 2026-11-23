"""Register the additional Taipei districts on the established 220 m atlas grid."""
import argparse
import json
import math
from pathlib import Path

from shapely import make_valid
from shapely.geometry import box, mapping, shape
from shapely.ops import transform, unary_union

DISTRICTS = {
    'zhongzheng':'中正區', 'datong':'大同區', 'wanhua':'萬華區', 'shilin':'士林區',
    'beitou':'北投區', 'neihu':'內湖區', 'nangang':'南港區', 'wenshan':'文山區',
}
SIZE = 220
LAT_METRES = 111195


def polygon_parts(geometry):
    if geometry.geom_type in ('Polygon', 'MultiPolygon'):
        return geometry
    return unary_union([g for g in getattr(geometry, 'geoms', ()) if g.geom_type in ('Polygon', 'MultiPolygon')])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('out', type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    data = Path('data')
    origin = json.loads((data/'street-xinyi-link.json').read_text())['origin']
    east_metres = LAT_METRES*math.cos(math.radians(origin[1]))
    def local(lon, lat):
        return (lon-origin[0])*east_metres, (lat-origin[1])*LAT_METRES
    def geo(x, y):
        return round(x/east_metres+origin[0], 8), round(y/LAT_METRES+origin[1], 8)
    rows = {f['properties']['name']:f['geometry'] for f in json.loads((data/'districts.geojson').read_text())['features']}
    seen = set()
    for key, name in DISTRICTS.items():
        boundary = polygon_parts(make_valid(shape(rows[name])))
        native = transform(local, boundary)
        west, south, east, north = native.bounds
        cells, areas = [], []
        for y in range(math.floor(south/SIZE), math.ceil(north/SIZE)):
            for x in range(math.floor(west/SIZE), math.ceil(east/SIZE)):
                clipped = polygon_parts(native.intersection(box(x*SIZE,y*SIZE,(x+1)*SIZE,(y+1)*SIZE)))
                if clipped.is_empty or clipped.area <= 0:
                    continue
                geometry = polygon_parts(make_valid(transform(geo, clipped)))
                if geometry.is_empty:
                    continue
                cell = f'{x}:{y}'
                areas.append(clipped)
                cells.append({'id':cell,'bounds':geometry.bounds,'geometry':mapping(geometry)})
                seen.add(cell)
        assert unary_union(areas).symmetric_difference(native).area < .05, name
        payload = {'name':name, 'cellSize':SIZE, 'origin':origin, 'bounds':boundary.bounds, 'footprint':mapping(boundary),
                   'cells':cells, 'paths':[], 'objects':[]}
        (args.out/f'street-{key}-district.json').write_text(json.dumps(payload,ensure_ascii=False,separators=(',',':'))+'\n')
        print(name, len(cells), flush=True)
    print(len(seen),'unique cells among the eight new districts')


if __name__ == '__main__':
    main()
