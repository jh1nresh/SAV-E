"""Transfer the mapped campus name to its main building and keep its plaza open."""
import json
from math import cos, radians
from pathlib import Path

from shapely.geometry import Point, Polygon

root = Path(__file__).parent
path = root / 'scene.json'
scene = json.loads(path.read_text())
osm = {r['id']: r for r in json.loads((root / 'osm-bbox.json').read_text())['elements']}
lat, lon = scene['meta']['lat'], scene['meta']['lon']

def outline(way):
    return Polygon([((p['lon'] - lon) * 111320 * cos(radians(lat)),
                     (p['lat'] - lat) * 110574) for p in osm[way]['geometry']]).buffer(0)

building = next(b for b in scene['buildings'] if b['id'] == 'w200028241')
campus = outline(355386414)
assert campus.covers(Polygon(building['ring']).representative_point()) and not building.get('cut')
building['n'] = osm[355386414]['tags']['name']
building['famous'] = True
plaza = outline(200028235)
scene['trees'] = [tree for tree in scene['trees'] if not plaza.covers(Point(tree[:2]))]
path.write_text(json.dumps(scene, ensure_ascii=False, separators=(',', ':')) + '\n')
