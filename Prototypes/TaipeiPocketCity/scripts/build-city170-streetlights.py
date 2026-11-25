"""Build streetlight scenery from Taipei Parks and Street Lights Office's public inventory.

Usage: build-city170-streetlights.py TaipeiLight.csv TAIPEI_OSM.json.gz RESTORED_DATA OUTPUT.json.gz
Source: https://data.taipei/dataset/detail?id=262e80cf-579c-4bfb-ba73-31621bc84616
"""

import argparse
from collections import Counter, defaultdict
import csv
import gzip
import hashlib
import json
import math
from pathlib import Path
import runpy

import ijson
from shapely import Point, STRtree, points
from shapely.geometry import shape


H = runpy.run_path(str(Path(__file__).with_name("build-city170-hydrants.py")))
F, read, off_ground = (H[key] for key in ("F", "read", "off_ground"))
W = runpy.run_path(str(Path(__file__).with_name("build-city170-park-water.py")))
SOURCE_SHA256 = "80c359ca8f05cecfabb35eae06539fef2fdc4036da999ba4dd71b6dbb083c291"
SNAPSHOT = "2025-10-25 06:59:32"
MOTOR_ROADS = {"primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "service"}
FOOTWAYS = {"footway", "path", "cycleway", "pedestrian"}
COLUMNS = {"Dist", "Quantity", "LightHeight", "TWD97X", "TWD97Y", "UpdDate"}


def public_grade(properties):
    return not off_ground(properties) and all(
        properties.get(key) in H["OPEN_ACCESS"] for key in ("access", "foot")
    )


def read_inventory(source):
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Unexpected Taipei streetlight inventory")
    with source.open(encoding="utf-8-sig", newline="") as stream:
        rows = csv.DictReader(stream)
        rows.fieldnames = [name.strip() for name in rows.fieldnames or ()]
        if not COLUMNS.issubset(rows.fieldnames):
            raise ValueError("Missing Taipei streetlight fields")
        sites, conflicts, counts = {}, set(), Counter()
        for row in rows:
            counts["inventory"] += 1
            if row["UpdDate"].strip() != SNAPSHOT:
                raise ValueError("Streetlight source date differs from the known snapshot")
            district = (row["Dist"] or "").strip()
            try:
                x, y, height = (float(row[field]) for field in ("TWD97X", "TWD97Y", "LightHeight"))
                heads = int(row["Quantity"])
            except (TypeError, ValueError):
                counts["missing-measurement"] += 1
                continue
            if not (district and 2.4 <= height <= 14 and heads in (1, 2)
                    and math.isfinite(x) and math.isfinite(y)):
                counts["unsupported-measurement"] += 1
                continue
            key = (x, y)
            data = (round(height * 100), heads, district + "區")
            if key in sites:
                counts["duplicate-location"] += 1
                if data != sites[key] and key not in conflicts:
                    conflicts.add(key)
                    counts["conflicting-position"] += 1
            else:
                sites[key] = data
    return sorted((x, y, *data) for (x, y), data in sites.items() if (x, y) not in conflicts), counts


def map_geometry(data, osm):
    expected = read(data / "city170/index.json")["source"]["provenance"]["taipeiExtractUncompressedSHA256"]
    with gzip.open(osm, "rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != expected:
            raise ValueError("Wrong Taipei OSM snapshot")
    obstacles, roads, widths, paths, shadows, seen = [], [], [], [], [], set()
    ways = defaultdict(list)
    for path in sorted((data / "city170").glob("p*.json.gz")):
        for item in read(path)["features"]["features"]:
            key, props = item["id"], item["properties"]
            if key in seen:
                continue
            seen.add(key)
            kind, category = props["kind"], props["category"]
            geometry = item["geometry"]
            if kind in {"building", "water", "school", "pitch"} and geometry["type"] in {"Polygon", "MultiPolygon"}:
                obstacles.append(F["project"](shape(geometry)))
            elif kind in {"road", "walk"} and "/way/" in key:
                ways[int(key.rsplit("/", 1)[1])].append((kind, category, props, geometry))
    # Older geometry packs omit some access and placement tags. Use the
    # same frozen extract that supplied the actual road and walkway lines.
    with gzip.open(osm, "rb") as stream:
        for row in ijson.items(stream, "elements.item", use_float=True):
            ident = row["id"]
            if row["type"] != "way" or ident not in ways:
                continue
            tags = row.get("tags", {})
            for kind, category, props, geometry in ways[ident]:
                line = F["project"](shape(geometry))
                width = min(float(props["width"]), 38)
                if off_ground(tags) or off_ground(props):
                    # The inventory has no level. Avoid the projected deck
                    # or tunnel where its ground placement is ambiguous.
                    shadows.append(line.buffer(width / 2 + 1.4))
                elif not public_grade(tags) or not public_grade(props):
                    continue
                elif kind == "road" and category in MOTOR_ROADS and tags.get("service") not in {"driveway", "parking_aisle"}:
                    roads.append(line)
                    widths.append(max(1.35, width / 2 - .35))
                elif category in FOOTWAYS:
                    paths.append(line)
    return STRtree(obstacles), STRtree(roads), widths, STRtree(paths), STRtree(shadows)


def street_context(point, height, roads, widths, paths):
    candidates = []
    for i in roads.query(point, predicate="dwithin", distance=25):
        line = roads.geometries[i]
        distance = line.distance(point)
        side = distance - widths[i]
        if side < 0:
            return None
        if height >= 450 and .14 <= side <= 5.5:
            center = line.interpolate(line.project(point))
            orientation = round(math.degrees(math.atan2(center.y - point.y, center.x - point.x))) % 360
            candidates.append((side, int(i), orientation))
    if candidates:
        return "road", min(candidates)[2]
    if height <= 600 and len(paths.query(point, predicate="dwithin", distance=5)):
        return "path", 0
    return None


def tree_trunks(data):
    rows = [r for path in sorted((data / "city170-nature").glob("p*.json.gz")) for r in read(path)]
    east, north = F["FORWARD"].transform([r[0] for r in rows], [r[1] for r in rows])
    # The root diameters in city-nature.js scale with the recorded tree height.
    proportions = {"broad": .039, "palm": .027}
    return STRtree([
        Point(x, y).buffer(proportions.get(form, .03) * (height if height > 0 else (7 if form == "palm" else 6)) + .02)
        for x, y, (_, _, height, form, *_) in zip(east, north, rows, strict=True)
    ])


def build(source, osm, data):
    source_rows, counts = read_inventory(source)
    cells = read(data / "city170/grid.json.gz")["features"]
    cell_tree = STRtree([shape(r["geometry"]) for r in cells])
    districts = read(data / "districts.geojson")["features"]
    district_tree = STRtree([shape(r["geometry"]) for r in districts])
    obstacles, roads, widths, paths, shadows = map_geometry(data, osm)
    trunks = tree_trunks(data)
    older_trunks = W["legacy_trunks"](data)
    survey = F["Survey"](data)
    covered = H["survey_cover"](survey, data)
    pos_index = STRtree(points([r[0] for r in source_rows], [r[1] for r in source_rows]))
    groups, by_district, by_type = defaultdict(list), Counter(), Counter()
    for row, (x, y, height, heads, district) in enumerate(source_rows):
        point = pos_index.geometries[row]
        if len(pos_index.query(point, predicate="dwithin", distance=.38)) > 1:
            counts["overlapping-poles"] += 1
            continue
        context = street_context(point, height, roads, widths, paths)
        if context is None:
            counts["outside-supported-road-or-path"] += 1
            continue
        if len(shadows.query(point, predicate="intersects")):
            counts["ambiguous-road-level"] += 1
            continue
        base_radius = height / 100 * .04
        if (len(trunks.query(point, predicate="dwithin", distance=base_radius))
                or len(older_trunks.query(point, predicate="dwithin", distance=base_radius))):
            counts["near-tree-trunk"] += 1
            continue
        kind, angle = context
        radius = height / 100 * (.18 if kind == "road" else .10)
        if len(obstacles.query(point, predicate="dwithin", distance=radius)):
            counts["near-mapped-structure-or-water"] += 1
            continue
        lon, lat = F["REVERSE"].transform(x, y)
        ll = Point(lon, lat)
        owners = cell_tree.query(ll, predicate="within")
        areas = district_tree.query(ll, predicate="within")
        if len(owners) != 1 or len(areas) != 1 or district != districts[areas[0]]["properties"]["name"]:
            counts["outside-inventory-district"] += 1
            continue
        if covered(ll, point, radius):
            counts["near-surveyed-structure"] += 1
            continue
        if survey.ground(point) is None:
            counts["without-terrain"] += 1
            continue
        style = heads - 1 + (2 if kind == "path" else 0)
        groups[cells[owners[0]]["properties"]["pack"]].append(
            [round(lon * 10000000), round(lat * 10000000), height, angle, style]
        )
        by_district[district] += 1
        by_type[kind] += 1
    receipt = {"snapshot": SNAPSHOT, "sha256": SOURCE_SHA256, "sourceCounts": counts,
               "total": sum(by_type.values()), "districts": by_district, "types": by_type}
    return {"receipt": receipt, "packs": dict(sorted(groups.items()))}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source", "osm", "data", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    result = build(args.source, args.osm, args.data)
    encoded = json.dumps(result, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    args.output.write_bytes(gzip.compress(encoded, mtime=0))
    print(json.dumps(result["receipt"], ensure_ascii=False, sort_keys=True))
