"""Build the unlabeled civilian passenger apron fill from the Taipei atlas' archived OSM extract."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

import ijson
from pyproj import Transformer
from shapely import get_parts, intersection, line_merge, make_valid, set_precision, transform, union_all
from shapely.geometry import LineString, Polygon, box, mapping, shape

# Positive list of the public passenger apron, per the Taipei International Airport's published
# passenger-apron designation. The airport-wide aerodrome boundary is not a civilian boundary.
PASSENGER_APRON = 498435009
LOCAL = Transformer.from_crs(4326, 3826, always_xy=True)
GEOGRAPHIC = Transformer.from_crs(3826, 4326, always_xy=True)
BOUNDS = (121.545, 25.060, 121.561, 25.072)


def projected(geom):
    return transform(geom, LOCAL.transform, interleaved=False)


def ground(tags):
    return (tags.get("layer", "0") == "0" and tags.get("level", "0") in {"0", "ground"}
            and all(tags.get(k, "no") == "no" for k in ("bridge", "tunnel", "indoor", "covered"))
            and tags.get("location", "surface") in {"surface", "outdoor"}
            and not tags.get("military") and tags.get("landuse") != "military")


def source_surfaces(path, checksum):
    nodes, lines, apron = {}, [], None
    west, south, east, north = BOUNDS
    with gzip.open(path, "rb") as src:
        if hashlib.file_digest(src, "sha256").hexdigest() != checksum:
            raise ValueError("Taipei OSM archive does not match the city170 source")
    with gzip.open(path, "rb") as src:
        for obj in ijson.items(src, "elements.item", use_float=True):
            if obj["type"] == "node":
                x, y = obj["lon"], obj["lat"]
                if west <= x <= east and south <= y <= north:
                    nodes[obj["id"]] = x, y
                continue
            if obj["type"] != "way":
                continue
            tags = obj.get("tags", {})
            kind = tags.get("aeroway")
            if kind not in {"apron", "taxiway"} or not ground(tags):
                continue
            if kind == "apron" and obj["id"] != PASSENGER_APRON:
                continue
            refs = obj["nodes"]
            if not all(ref in nodes for ref in refs):
                continue
            coordinates = [nodes[ref] for ref in refs]
            if kind == "apron":
                if refs[0] != refs[-1] or tags.get("name") != "1號停機坪":
                    raise ValueError("Reviewed civil passenger apron changed")
                apron = projected(Polygon(coordinates))
            elif tags.get("area") != "yes":
                lines.append(projected(LineString(coordinates)))
    if apron is None or not apron.is_valid:
        raise ValueError("Civil passenger apron missing from the frozen snapshot")
    return apron, lines


def street_and_building_mask(data, atlas):
    # Reuse the same mapped footprints and road widths as the Taipei ground renderer.
    near = box(*BOUNDS)
    entries = {p["id"]:p for p in atlas["packs"]}
    selected = set()
    for key, info in entries.items():
        if near.intersects(box(*info["bounds"])):
            selected.add(key)
            selected.update(info.get("deps", []))
    blockers = []
    for key in selected:
        with gzip.open(data / "city170" / entries[key]["url"]) as src:
            features = json.load(src)["features"]["features"]
        for feature in features:
            p = feature["properties"]
            if p["kind"] not in {"road", "walk", "building"}:
                continue
            geometry = shape(feature["geometry"])
            if not geometry.intersects(near):
                continue
            geometry = make_valid(projected(geometry))
            if p["kind"] in {"road", "walk"}:
                geometry = geometry.buffer(float(p["width"])/2)
            blockers.append(geometry)
    return union_all(blockers)


def geometry_parts(geometry, kind):
    if geometry.is_empty:
        return []
    if geometry.geom_type == kind:
        return [geometry]
    if geometry.geom_type.startswith("Multi") or geometry.geom_type == "GeometryCollection":
        return [part for item in get_parts(geometry) for part in geometry_parts(item, kind)]
    return []


def render_surfaces(apron, lines, obstacles):
    # Keep only the cartographic centerline inside the reviewed apron. Road width and
    # taxiway operating dimensions are not inferred from these lines.
    pavement = set_precision(apron.difference(obstacles), .1)
    inside = pavement.buffer(-1)
    paths = line_merge(union_all([intersection(line, inside) for line in lines if line.intersects(inside)]))
    features = []
    for geom, kind, shape_type in [(pavement, "apron", "Polygon"), (paths, "taxiway", "LineString")]:
        for part in geometry_parts(geom, shape_type):
            if (part.area if shape_type=="Polygon" else part.length) < 2:
                continue
            # Geographic precision of about one decimetre at this latitude.
            geographic = set_precision(transform(part, GEOGRAPHIC.transform, interleaved=False), .000001)
            if not geographic.is_empty:
                features.append({"type":"Feature","properties":{"surface":kind},"geometry":mapping(geographic)})
    return {"type":"FeatureCollection","features":features}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--osm", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args=parser.parse_args()
    atlas=json.loads((args.data/"city170/index.json").read_bytes())
    apron, lines=source_surfaces(args.osm,atlas["source"]["provenance"]["taipeiExtractUncompressedSHA256"])
    result=render_surfaces(apron,lines,street_and_building_mask(args.data,atlas))
    encoded=json.dumps(result,separators=(",",":"),allow_nan=False).encode()
    args.output.write_bytes(gzip.compress(encoded,mtime=0))
    print(len(result["features"]), "unlabeled map surfaces,", args.output.stat().st_size, "compressed bytes")
