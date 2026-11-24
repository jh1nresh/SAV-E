"""After Pocket City prep.py, add the reflecting basin visible on the architect's plan.

The open reservoir outline comes directly from OSM. The planted roofs and this
approximate site-plan basin are illustrations. No marina is present in this bay.
Run with the same Python/Shapely environment as Pocket City.
"""
import json
import math
from pathlib import Path

from shapely.geometry import Polygon, box
from shapely.ops import unary_union

folder = Path(__file__).resolve().parent
scene = json.loads((folder / "scene.json").read_text())
meta = scene["meta"]
angle = math.radians(meta["rotation"])
dx = (meta["lon"] - 120.90199) * 111320 * math.cos(math.radians(meta["lat"]))
dy = (meta["lat"] - 23.85132) * 110574


def point(east, north):
    e, n = east - dx, north - dy
    return (e * math.cos(angle) + n * math.sin(angle),
            -e * math.sin(angle) + n * math.cos(angle))


# At this view scale the arc is a short polyline. Coordinates deliberately
# exclude the cycleway, central lawn and visitors' asphalt car parks.
rim = [(82, 49), (83, 68), (80, 71), (60, 74), (53, 86), (-14, 102),
       (-20, 102), (-24, 100), (-43, 55), (-46, 54), (-43, 102),
       (-42, 106), (-37, 107), (73, 97), (86, 95), (89, 93),
       (89, 88), (82, 49)]
inner = [(84, 69), (81, 72), (53, 88), (1, 76), (-5, 69),
         (0, 50), (3, 60), (6, 64), (80, 71)]
buildings = unary_union([Polygon(b["ring"]) for b in scene["buildings"]])
water = unary_union([Polygon([point(*p) for p in loop]).buffer(0) for loop in (rim, inner)])
water = water.difference(buildings.buffer(.25)).intersection(box(-115, -115, 115, 115))
parts = [water] if water.geom_type == "Polygon" else list(water.geoms)
for part in parts:
    if part.area < 5:
        continue
    paths = [part.exterior, *part.interiors]
    rings = [[[round(x, 2), round(y, 2)] for x, y in list(path.coords)[:-1]] for path in paths]
    if rings not in scene["water"]:
        scene["water"].append(rings)
scene["boats"] = []
(folder / "scene.json").write_text(json.dumps(scene, ensure_ascii=False, separators=(",", ":")) + "\n")
