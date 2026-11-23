"""Preserve the exposed lawn around the lighthouse's white fort compound."""
import json
from pathlib import Path

path = Path(__file__).with_name('scene.json')
scene = json.loads(path.read_text())
# The open grass and southern view of the walls are documented in the linked photograph.
scene['trees'] = [tree for tree in scene['trees'] if not (
    scene['species'][tree[2]] == 'Woodland' and -42 < tree[0] < 43 and -56 < tree[1] < 21)]
path.write_text(json.dumps(scene, ensure_ascii=False, separators=(',', ':')) + '\n')
