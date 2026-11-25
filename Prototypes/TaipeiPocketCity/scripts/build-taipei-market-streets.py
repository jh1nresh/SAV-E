"""Author illustrative street stalls along official Taipei night-market segments.

The named pedestrian centre lines, openings and background footprints come from
the restored city atlas. This is a street vignette, with no inferred merchant
names, stall numbers, schedules or POI associations.
"""

import argparse
from collections import Counter, defaultdict
import gzip
import json
import math
from pathlib import Path
import runpy

from shapely import STRtree, get_parts, union_all
from shapely.geometry import LineString, Point, Polygon, box, shape


HERE = Path(__file__).resolve().parent
SURVEY = runpy.run_path(str(HERE / "build-taipei-survey-frontages.py"))
F = SURVEY["F"]
MARKETS = {
    "tcma-market-11": ("walk/way/51813045", "饒河街", True),
    "tcma-market-35": ("walk/way/41605143", "臨江街", False),
}
HALF_LENGTH = 1.12
HALF_DEPTH = .81
CENTRAL_WALK = 1.20


def read(path):
    return json.loads(gzip.decompress(path.read_bytes()) if path.suffix == ".gz" else path.read_bytes())


def extent_blockers(features, selected, corridor, data):
    survey = F["Survey"](data)
    survey_roofs = SURVEY["SurveyFootprints"](survey, data)
    blockers = []
    crossings = []
    for i in survey.extents.query(corridor, predicate="intersects"):
        roofs, index = survey_roofs.tile(int(i))
        blockers.extend(roofs[j].polygon.buffer(.32) for j in index.query(corridor, predicate="intersects"))
    for f in features:
        props = f["properties"]
        if f["id"] == selected or props["kind"] not in {"building", "water", "road", "walk"}:
            continue
        if props.get("offGround") or str(props.get("layer", "0")) not in {"0", "None"}:
            continue
        geometry = F["project"](shape(f["geometry"]))
        if not geometry.intersects(corridor):
            continue
        kind = props["kind"]
        if kind in {"road", "walk"}:
            # Preserve mapped ways crossing the market and existing circulation.
            crossings.append(geometry.buffer(max(1.35, props.get("width", 3) / 2) + .25))
        else:
            blockers.append(geometry.buffer(.35))
    return blockers, crossings


def cart_box(point, tangent, side_delta):
    along_x, along_y = tangent
    cross_x, cross_y = -along_y, along_x
    x, y = point.x + side_delta * cross_x, point.y + side_delta * cross_y
    corners = [
        (x + u * along_x + v * cross_x, y + u * along_y + v * cross_y)
        for u, v in [(-HALF_LENGTH, -HALF_DEPTH), (HALF_LENGTH, -HALF_DEPTH),
                     (HALF_LENGTH, HALF_DEPTH), (-HALF_LENGTH, HALF_DEPTH)]
    ]
    return Point(x, y), Polygon(corners)


def pack_key(point):
    return f"p{math.floor(point.x / 1360)}_{math.floor(point.y / 1360)}"


def market_scene(centerline, market_id, central, walls, crossings, old_paths, pack_extents):
    # The real north/south walking aisles around the Raohe center row are
    # represented by offsets. Linjiang keeps the pedestrian centre line clear.
    lanes = [centerline.offset_curve(value) for value in (-2.20, 2.20)] if central else [centerline]
    pedestrian_space = union_all([*old_paths, *lanes]).buffer(CENTRAL_WALK)
    blockers = STRtree([*walls, *crossings])
    stalls = []
    for i, distance in enumerate(range(12, int(centerline.length) - 12, 5)):
        point = centerline.interpolate(distance + (i % 3) * .46)
        a, b = (centerline.interpolate(distance + delta) for delta in (-1, 1))
        span = a.distance(b)
        if span < 1.85:
            continue
        tangent = ((b.x - a.x) / span, (b.y - a.y) / span)
        sides = [0] if central else ([2.55, -2.55] if i % 2 == 0 else [-2.55, 2.55])
        for side in sides:
            center, footprint = cart_box(point, tangent, side)
            if (pedestrian_space.intersects(footprint)
                    or len(blockers.query(footprint, predicate="intersects"))
                    or any(footprint.distance(old) < .40 for _, _, old, _, _ in stalls)):
                continue
            stalls.append((i, center, footprint, tangent, side))
            break

    # The same illustrated people stay out of the stall footprints and buildings.
    solid = union_all([*walls, *(item[2] for item in stalls)]).buffer(.42)
    if not central:
        solid = solid.union(union_all(old_paths).buffer(1.10))
    groups = defaultdict(lambda: {"objects": {}, "paths": {}})
    for i, center, _, (u, v), side in stalls:
        lon, lat = F["REVERSE"].transform(center.x, center.y)
        x2, y2 = F["REVERSE"].transform(center.x + u, center.y + v)
        angle = math.degrees(math.atan2(y2 - lat, (x2 - lon) * math.cos(math.radians(lat))))
        if side > 0 or (central and (i // 3) % 2):
            angle += 180
        kind = ("market-grill", "market-canopy", "market-counter", "market-canopy")[i % 4]
        groups[pack_key(center)]["objects"][f"{market_id}/stall/{i}"] = [
            round(lon, 8), round(lat, 8), kind, 1, round(angle % 360, 2), (i * 17 + i // 3) % 6,
        ]
    for index, route in enumerate(lanes):
        # Pedestrians can traverse streets crossing the market. A road is an
        # obstacle to a fixed stall, not to the market's existing pedestrian way.
        for j, segment in enumerate(get_parts(route.difference(solid))):
            if segment.geom_type != "LineString" or segment.length < 13:
                continue
            points = [tuple(round(coord, 8) for coord in F["REVERSE"].transform(*p)) for p in segment.coords]
            key = f"{market_id}/walk/{index}/{j}"
            row = {"points": points, "people": min(12, max(2, math.floor(segment.length / 12)))}
            for pack, extent in pack_extents.items():
                if extent.intersects(segment):
                    groups[pack]["paths"][key] = row
    return groups


def build(data):
    market_points = {f["id"]: f for f in read(data / "city170-markets.json.gz")["features"]}
    index = read(data / "city170/index.json")
    atlas = {f["id"]: f for pack in index["packs"] for f in read(data / "city170" / pack["url"])["features"]["features"]}
    atlas_extents = {pack["id"]: F["project"](box(*pack["bounds"])) for pack in index["packs"]}
    groups = defaultdict(lambda: {"objects": {}, "paths": {}})
    generated = Counter()
    for market_id, (street_id, name, central) in MARKETS.items():
        marker = market_points[market_id]
        street = atlas[street_id]
        assert marker["properties"]["source"] == "臺北市市場處"
        assert name in marker["properties"]["name"]
        assert street["properties"]["name"] == name and street["properties"]["category"] == "pedestrian"
        line = F["project"](shape(street["geometry"]))
        assert 250 < line.length < 650
        assert line.distance(F["project"](shape(marker["geometry"]))) < 65
        corridor = line.buffer(8)
        pack_extents = {key: bounds for key, bounds in atlas_extents.items() if corridor.intersects(bounds)}
        if not pack_extents:
            raise ValueError(f"Market {market_id} is outside the atlas grid")
        walls, crossings = extent_blockers(atlas.values(), street_id, corridor, data)
        # Preserve the tree trunks and existing props alongside old pedestrian routes.
        old_paths = []
        replaced = defaultdict(list)
        original_aisle = line.buffer(1.40)
        for pack in pack_extents:
            life = read(data / "city170-life" / (pack + ".json.gz"))
            for row in life["objects"].values():
                point = F["project"](Point(row[:2]))
                if corridor.covers(point):
                    walls.append(point.buffer(.43 if row[2] == "tree" else 1.55 * row[3]))
            for lon, lat, *_ in read(data / "city170-nature" / (pack + ".json.gz")):
                point = F["project"](Point(lon, lat))
                if corridor.covers(point):
                    walls.append(point.buffer(.43))
            for key, path in life["paths"].items():
                route = F["project"](LineString(path["points"]))
                if central and original_aisle.covers(route):
                    # Replace the existing centre-line animation with the side aisles.
                    replaced[pack].append(key)
                elif route.intersects(corridor):
                    old_paths.append(route)
        scene = market_scene(line, market_id, central, walls, crossings, old_paths, pack_extents)
        for pack, part in scene.items():
            groups[pack]["objects"].update(part["objects"])
            groups[pack]["paths"].update(part["paths"])
            generated[market_id] += len(part["objects"])
        for pack, keys in sorted(replaced.items()):
            groups[pack]["replacePaths"] = sorted(keys)
    assert set(groups) <= set(atlas_extents)
    if not all(generated[key] for key in MARKETS):
        raise ValueError("A documented market did not produce any unobstructed scenery")
    print(dict(generated))
    return dict(sorted(groups.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    rows = build(args.data)
    args.output.write_text(
        "// Generated by scripts/build-taipei-market-streets.py. Fixtures and walking crowds are illustrative.\n"
        + "export default " + json.dumps(rows, ensure_ascii=False, separators=(",", ":")) + ";\n"
    )


if __name__ == "__main__":
    main()
