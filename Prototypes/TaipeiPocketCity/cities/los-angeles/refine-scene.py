"""Keep the lawn and terrace open, and thin illustrative hillside tree scatter."""
import json
from math import floor
from pathlib import Path

path = Path(__file__).with_name('scene.json')
scene = json.loads(path.read_text())
occupied = set()
retained = []
for tree in scene['trees']:
    x, y = tree[:2]
    # The official grounds plan and aerial photos show open lawns and paved terraces here.
    if -53 <= x <= 46 and -58 <= y <= 99:
        continue
    square = floor(x / 8.2), floor(y / 8.2)
    if square in occupied:
        continue
    occupied.add(square)
    retained.append(tree)
scene['trees'] = retained
path.write_text(json.dumps(scene,ensure_ascii=False,separators=(',',':'))+'\n')
