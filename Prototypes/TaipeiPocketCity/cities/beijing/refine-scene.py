"""Apply the measured Qigu courtyard paving footprint after Pocket City prep."""
import json
import sys
from pathlib import Path
from shapely.geometry import LineString, Polygon, box
from shapely.ops import unary_union

root = Path(__file__).parent
scene_path = root / 'scene.json'
scene = json.loads(scene_path.read_text())
half = scene['meta']['half']
# Footprint follows OSM barrier ways 43921127/28/31/32, with gaps closed at gates.
plaza = Polygon([(-30.9,-134.2),(-34.3,-45.4),(-38.0,54.8),(124.4,61.0),
                 (128.5,-38.9),(131.9,-128.2)]).intersection(box(-half,-half,half,half))
paved = unary_union([plaza, *(Polygon(shape[0],shape[1:]) for shape in scene['walk'])])
rings = lambda ring: [[round(x,2),round(y,2)] for x,y in list(ring.coords)[:-1]]
polygons = [paved] if paved.geom_type == 'Polygon' else list(paved.geoms)
scene['walk'] = [[rings(p.exterior), *map(rings,p.interiors)] for p in polygons if p.geom_type == 'Polygon']
scene_path.write_text(json.dumps(scene,ensure_ascii=False,separators=(',',':'))+'\n')
