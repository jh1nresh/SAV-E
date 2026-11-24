"""Restore the open plaza and shallow reflecting basin visible in the site photo."""
import json
from math import cos, sin, tau
from pathlib import Path

path = Path(__file__).with_name('scene.json')
scene = json.loads(path.read_text())
shoe = next(row for row in scene['buildings'] if row['id'] == 'w1352427633')
(x, y), (a, b) = shoe['obb']['c'], shoe['obb']['ax']
scene['trees'] = [tree for tree in scene['trees']
                  if scene['species'][tree[2]] != 'Park tree' or abs(tree[0] - x) > 37 or abs(tree[1] - y) > 36]
# The basin is visible in the photograph but unmapped in the OSM snapshot.
basin = []
for i in range(44):
    angle = i / 44 * tau
    u, v = 17.1 * cos(angle), 10.65 * sin(angle)
    basin.append([round(x + u*a - v*b, 2), round(y + u*b + v*a, 2)])
if [basin] not in scene['water']:
    scene['water'].append([basin])
path.write_text(json.dumps(scene, ensure_ascii=False, separators=(',', ':')) + '\n')
