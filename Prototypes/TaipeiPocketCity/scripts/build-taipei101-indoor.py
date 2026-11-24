"""Build floor-specific geometry for the retail wing of Taipei 101 from the frozen public OSM extract.

python build-taipei101-indoor.py taipei.json.gz RESTORED_DATA taipei101-indoor-data.js
Add --directory taipei101-directory.js to reconcile a uniquely identified, mapped tenant with its official floor.
"""

import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import unicodedata

import ijson
from shapely.geometry import LineString, Point, Polygon, mapping

MALL = 64566862
# This envelope limits the streaming index only. Every output is tested against the actual retail building way.
BOUNDS = (121.5605, 25.0300, 121.5685, 25.0380)
shop_amenities = {"restaurant", "cafe", "fast_food", "food_court", "ice_cream", "bar", "pub"}
FOOD = {"restaurant": "餐廳", "cafe": "咖啡", "fast_food": "餐飲", "clothes": "服飾", "hifi": "音響"}


def parse_floors(value, posted):
    values = set()
    for raw in unicodedata.normalize('NFKC',value).upper().split(';'):
        raw = raw.strip()
        if posted:
            floor = re.fullmatch(r'(?:B|地下)([1-9]\d?)(?:F|樓|層)?',raw)
            if floor:
                values.add(-int(floor[1]))
                continue
            match = re.fullmatch(r'(-?[1-9]\d?)(?:F|樓|層)?',raw)
        else:
            match = re.fullmatch(r'(-?(?:0|[1-9]\d?))',raw)
        if not match:
            return None
        n = int(match[1])
        values.add(n if posted or n<0 else n+1)
    return values


def public_snapshot(source, checksum):
    with gzip.open(source, "rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != checksum:
            raise ValueError("OSM extract differs from the published Taipei atlas")
    nodes, ways, related = {}, [], []
    west, south, east, north = BOUNDS
    with gzip.open(source, "rb") as stream:
        for row in ijson.items(stream, "elements.item", use_float=True):
            if row["type"] == "node":
                if west < row["lon"] < east and south < row["lat"] < north:
                    nodes[row["id"]] = row
            elif row["type"] == "way" and any(n in nodes for n in row["nodes"]):
                ways.append(row)
            elif row["type"] == "relation" and row.get("tags", {}).get("indoor") in {
                "area",
                "room",
                "corridor",
            }:
                related.append(row)
    return nodes, ways, related


def geometry(row, nodes):
    if row["type"] == "node":
        return Point(row["lon"], row["lat"])
    if not all(n in nodes for n in row["nodes"]):
        return None
    xy = [(nodes[n]["lon"], nodes[n]["lat"]) for n in row["nodes"]]
    if len(xy) > 3 and row["nodes"][0] == row["nodes"][-1]:
        return Polygon(xy)
    return LineString(xy) if len(xy) >= 2 else None


def floor_labels(tags):
    """At the mall, level 0 denotes 1F. Contradictory local labels remain unresolved."""
    fields = [(tags[k], True) for k in ("addr:floor", "level:ref") if tags.get(k)]
    if tags.get("level"):
        fields.append((tags["level"], False))
    if not fields:
        return set()
    levels = [parse_floors(v, posted) for v, posted in fields]
    if not levels[0] or any(group != levels[0] for group in levels[1:]):
        return set()
    return levels[0]


def aed_location(tags):
    if (
        tags.get("emergency") != "defibrillator"
        or tags.get("source") != "hear_aed"
        or not tags.get("ref:TW:AED")
        or not re.search(r"市府路45號", tags.get("object:addr:full", ""))
        or "辦公大樓" in tags.get("hear_aed:site:name", "")
    ):
        return None
    location = tags.get("hear_aed:defibrillator:location", "")
    match = re.match(r"^(B[1-9]\d?F?|[1-9]\d?F)(?![0-9])", location, re.I)
    if not match:
        return None
    levels = parse_floors(match[1], True)
    return (levels, location) if levels else None


def label(n):
    return f"B{-n}" if n < 0 else f"{n}F"


def feature(row, geom, kind, category, name, level=None, detail="", **extra):
    ident = f"{row['type']}/{row['id']}"
    props = {
        "id": ident,
        "kind": kind,
        "name": name,
        "category": category,
        "categoryLabel": FOOD.get(category, category),
        "level": level,
        "detail": detail,
        "source": "OpenStreetMap",
        "url": f"https://www.openstreetmap.org/{ident}",
        **extra,
    }
    return {"type": "Feature", "id": ident, "properties": props, "geometry": mapping(geom)}


def collection(features):
    return {"type": "FeatureCollection", "features": sorted(features, key=lambda f: f["id"])}


def normalized_name(name):
    return unicodedata.normalize("NFKC", name).strip().casefold()


def official_tenants(path):
    if not path:
        return {}
    js = (
        "const {officialFloorDirectory:d}=await import(process.argv[1]);process.stdout.write(JSON.stringify(d))"
    )
    catalog = json.loads(
        subprocess.check_output(["node", "--input-type=module", "-e", js, path.resolve().as_uri()])
    )
    matches = defaultdict(list)
    for floor, rows in catalog.items():
        for row in rows:
            if row.get("name") and row.get("url", "").startswith("https://www.taipei-101.com.tw/"):
                matches[normalized_name(row["name"])].append((floor, row["url"]))
    return {name: rows[0] for name, rows in matches.items() if len(rows) == 1}


def assemble(nodes, ways, relations, official=None):
    mall = next(r for r in ways if r["id"] == MALL)
    outline = geometry(mall, nodes)
    if (
        outline is None
        or outline.geom_type != "Polygon"
        or not outline.is_valid
        or mall["tags"].get("shop") != "mall"
    ):
        raise ValueError("Expected the complete surveyed retail wing of Taipei 101")
    max_floor = int(mall["tags"]["building:levels"])
    boundary_nodes = set(mall["nodes"])
    in_mall = []
    for row in [*nodes.values(), *ways]:
        if not row.get("tags") or (row["type"] == "way" and row["id"] == MALL):
            continue
        geom = geometry(row, nodes)
        if geom is not None and outline.covers(geom):
            in_mall.append((row, geom))
    local_ways = {row["id"] for row, _ in in_mall if row["type"] == "way"}
    if any(any(m["type"] == "way" and m["ref"] in local_ways for m in r["members"]) for r in relations):
        raise ValueError("New indoor relation needs geometric validation")
    counted = Counter(normalized_name(row["tags"].get("name", "")) for row, _ in in_mall)
    official = official or {}
    floors, entrances, corridors = defaultdict(list), [], []
    for row, geom in in_mall:
        t = row["tags"]
        category = t.get("shop") or t.get("amenity") or ""
        name = t.get("name", "")
        detail = ""
        proof = {}
        levels = floor_labels(t)
        if row["type"] == "node" and row["id"] in boundary_nodes and t.get("entrance") == "main":
            ent = feature(row, geom, "entrance", "main", name or "主要出入口")
            entrances.append(ent)
            kind = "entrance"
            category = "main"
            name = ent["properties"]["name"]
        elif t.get("indoor") == "room" and geom.geom_type == "Polygon" and not t.get("shop"):
            kind, category = "room", "room"
        elif t.get("highway") == "corridor" or t.get("indoor") == "corridor":
            kind, category = "corridor", "corridor"
            if not levels:
                corridors.append(feature(row, geom, kind, category, name))
        elif (
            t.get("shop") not in {None, "vacant", "no", "mall"} or t.get("amenity") in shop_amenities
        ) and name:
            kind = "shop"
            if t.get("addr:street") and t["addr:street"] != "市府路":
                continue
            if t.get("addr:housenumber", "45").removesuffix("號") != "45":
                continue
            # Reconcile a genuinely mapped tenant with a single public-facing floor.
            # Conflicting existing level tags, other house numbers and duplicate brands remain unresolved.
            key = normalized_name(name)
            if key in official and counted[key] == 1:
                target, url = official[key]
                corroboration = parse_floors(target, True) or set()
                if not any(t.get(k) for k in ("addr:floor", "level:ref", "level")):
                    levels = corroboration
                if levels and levels == corroboration:
                    proof["floorSourceUrl"] = url
        elif aed := aed_location(t):
            kind, category, name = "facility", "defibrillator", "AED 自動體外心臟電擊去顫器"
            levels, detail = aed
            proof["categoryLabel"] = "AED"
            proof["ref"] = t["ref:TW:AED"]
            proof["registry"] = "hear_aed"
        else:
            continue
        for floor in sorted(levels):
            if floor > max_floor or floor == 0:
                continue
            floors[floor].append(feature(row, geom, kind, category, name, label(floor), detail, **proof))
    return {
        "id": f"way/{MALL}",
        "name": mall["tags"]["name"],
        "footprint": mapping(outline),
        "source": {
            "name": "OpenStreetMap contributors",
            "license": "ODbL",
            "attributionUrl": "https://www.openstreetmap.org/copyright",
            "url": f"https://www.openstreetmap.org/way/{MALL}",
        },
        "description": "外框描繪 OpenStreetMap 標示的購物中心翼樓。各樓層的完整空間與店鋪邊界仍缺圖資。",
        "entrances": collection(entrances),
        "unassignedCorridors": collection(corridors),
        "levels": [{"label": label(n), "features": collection(floors[n])} for n in sorted(floors)],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ("osm", "data", "output"):
        parser.add_argument(arg, type=Path)
    parser.add_argument(
        "--directory", type=Path, default=Path(__file__).resolve().parents[1] / "taipei101-directory.js"
    )
    args = parser.parse_args()
    meta = json.loads((args.data / "city170/index.json").read_bytes())
    nodes, ways, relations = public_snapshot(
        args.osm, meta["source"]["provenance"]["taipeiExtractUncompressedSHA256"]
    )
    result = assemble(nodes, ways, relations, official_tenants(args.directory))
    args.output.write_text(
        "// OpenStreetMap contributors · ODbL. Generated by scripts/build-taipei101-indoor.py.\n"
        + "export const taipei101Indoor="
        + json.dumps(result, ensure_ascii=False, separators=(",", ":"))
        + ";\n"
    )
    print([(f["label"], len(f["features"]["features"])) for f in result["levels"]])
