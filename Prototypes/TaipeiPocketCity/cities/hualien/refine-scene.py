"""Keep the lawn among the garden pines open on the main arcade side."""
import json
from pathlib import Path

path = Path(__file__).with_name('scene.json')
scene = json.loads(path.read_text())
# Keep the mapped pine. Only reduce generated trees across the open central lawn.
scatter = {'Park tree', 'Woodland'}
scene['trees'] = [tree for tree in scene['trees'] if not (
    scene['species'][tree[2]] in scatter and -23 < tree[0] < 12 and -41 < tree[1] < -18)]
path.write_text(json.dumps(scene, ensure_ascii=False, separators=(',', ':')) + '\n')
