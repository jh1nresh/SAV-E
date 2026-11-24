"""Recover address-linked Taipei facades without changing previously assigned storefronts.
Usage: python scripts/build-city170-frontage-recoveries.py --data <restored runtime data> --osm <taipei.json.gz>
Uses the same public snapshot, survey wall/ground tests and collision rules as build-city170-frontages.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import runpy

import ijson
from shapely.geometry import LineString, Point
from shapely.strtree import STRtree

F = runpy.run_path(str(Path(__file__).with_name("build-city170-frontages.py")))
A = runpy.run_path(str(Path(__file__).with_name("build-city170-inspected-shops.py")))
read = F["load_json"]
ROOT = Path(__file__).resolve().parents[1]


def raw_records(osm, wanted, checksum):
    with gzip.open(osm, "rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != checksum:
            raise ValueError("OSM extract differs from the Taipei atlas snapshot")
    tags, entrances, building_nodes = {}, {}, {}
    with gzip.open(osm, "rb") as stream:
        for obj in ijson.items(stream, "elements.item", use_float=True):
            kind, ident, props = obj["type"], obj["id"], obj.get("tags", {})
            if kind == "node" and props.get("entrance") in {"main", "shop", "yes"}:
                entrances[ident] = (Point(obj["lon"], obj["lat"]), props)
            key = f"{kind}/{ident}"
            if key not in wanted:
                continue
            tags[key] = props
            if kind == "way" and props.get("building"):
                building_nodes[key] = set(obj["nodes"])
    return tags, {k: sorted(nodes & entrances.keys()) for k, nodes in building_nodes.items()}, entrances


def address(tags, district):
    street, house = tags.get("addr:street"), tags.get("addr:housenumber")
    if street and house:
        parsed = A["split_address"](street + house.removesuffix("號") + "號", district)
    else:
        parsed = A["split_address"](tags.get("addr:full") or tags.get("detail") or "", district)
    return (parsed.road, parsed.house) if parsed else None


def explicit_ground(tags):
    return (tags.get("level") in {"0", "0.0", "ground"}
            or A["address_text"](tags.get("addr:floor") or tags.get("floor") or "") in {"1", "1樓", "1f", "ground"})


def unique_entry(ids, entrances, store):
    eligible = []
    for ident in ids:
        pt, tags = entrances[ident]
        if F["floor_status"](store, tags) or tags.get("access") in {"delivery", "staff", "customers_only_private"}:
            continue
        eligible.append((ident, pt, tags))
    main = [e for e in eligible if e[2]["entrance"] in {"main", "shop"}]
    choices = main or eligible
    return choices[0] if len(choices) == 1 else None


def exposed_front(streets, survey, store, building, tags, district, entry):
    """A unique measured side faces the explicit address road, or an entrance fixes the side."""
    if building.geometry.geom_type != "Polygon":
        return
    coords = building.geometry.exterior.coords
    if entry:
        points = [F["project"](entry[1])]
        tags = {**tags, "entrance": entry[2]["entrance"]}
    else:
        points = [LineString([a, b]).interpolate(.5, normalized=True) for a, b in zip(coords, coords[1:])]
    candidates = {}
    for point in points:
        match, _ = streets.find_wall(store, point, tags, building, True, district)
        if not match or (entry and match.evidence != "mapped-entrance"):
            continue
        if not entry and match.edge.distance(point) > .05:
            continue
        candidates[match.edge_number] = match
    # A missing mesh wall is not evidence that another plausible frontage belongs to the shop.
    if len(candidates) != 1:
        return
    match = next(iter(candidates.values()))
    offset = F["frontage"](match, 0, match.edge.length, limit=4.5)
    if offset is not None:
        center, row = offset
        site, _ = survey.snap(center, row, match)
        if site is not None and (not entry or site.distance(points[0]) <= 2.6):
            return site, row


def build(data, osm):
    base = data / "city170-frontages"
    summary = read(base / "summary.json")
    search = {r[-1]: r for r in read(base / "search.json.gz")}
    manifest, places, buildings, roads = F["load_atlas"](data / "city170", read(data / "city170-shops.json.gz"))
    places.extend(F["MapFeature"](f["id"], f["properties"], Point(f["geometry"]["coordinates"]))
                  for f in read(data / "city170-inspected-shops.json.gz")["features"])
    wanted = {r.id.split("/", 1)[1] for r in places + buildings + roads if r.id.count("/") == 2}
    tags, links, entrances = raw_records(osm, wanted, manifest["source"]["provenance"]["taipeiExtractUncompressedSHA256"])
    roads = [r for r in roads if F["street_eligible"](r, tags[r.id.split("/", 1)[1]])]
    streets, survey = F["Streets"](buildings, roads), F["Survey"](data)
    stores = [p for p in places if p.id in search]
    points = [F["project"](s.geometry) for s in stores]
    tenants = STRtree(points)
    by_id = {b.id.split("/", 1)[1]: b for b in buildings}
    existing = [(None, row, None, None) for pack in summary["packs"] for row in read(base / (pack+".json.gz"))]
    proposals, counts = [], Counter()
    for store, point in zip(stores, points):
        key = store.id.split("/", 1)[1]
        original = tags[key] if store.id.startswith("poi/") else store.properties
        record = search[store.id]
        if record[-2] is not None or F["floor_status"](store, original) or F["dihua_duplicate"](store):
            continue
        district = record[1]
        own = by_id.get(key) if store.id.startswith("poi/") else None
        addr = address(original, district)
        if own:
            building = own
        elif addr and explicit_ground(original):
            inside = [buildings[i] for i in streets.footprints.query(point, predicate="covered_by")]
            if len(inside) != 1 or address(tags[inside[0].id.split("/", 1)[1]], district) != addr:
                continue
            building = inside[0]
        else:
            continue
        building_key = building.id.split("/", 1)[1]
        if any(stores[i].id != store.id for i in tenants.query(building.geometry, predicate="covers")):
            continue
        ids = links.get(building_key, [])
        entry = unique_entry(ids, entrances, store)
        if not entry and (ids or not addr):
            continue
        # Render only an exterior of an evidenced ground-level business or its own mapped building.
        # Street matching and multiplicity are checked independently of distance to the POI centroid.
        facts = dict(original)
        if addr and not facts.get("addr:street"):
            facts["addr:street"] = addr[0]
        counts["eligible"] += 1
        found = exposed_front(streets, survey, store, building, facts, district, entry)
        if not found:
            continue
        site, row = found
        row["evidence"] = "mapped-building-entrance" if entry else "single-addressed-shop-wall"
        if entry:
            row["entranceId"] = "node/" + str(entry[0])
        row["district"] = district
        row["pack"] = F["pack_for"](site, manifest)
        if row["pack"] in summary["packs"]:
            proposals.append((site, row, district, store))
    blocked = F["overlapping_slots"](existing + proposals)
    rows = [r for i, (_, r, _, _) in enumerate(proposals, len(existing)) if i not in blocked]
    rows.sort(key=lambda row: row["id"])
    print(f"{counts['eligible']} exact building/address candidates; {len(proposals)} unique surveyed fronts; {len(rows)} conflict-free")
    return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--osm", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "taipei-shopfront-recoveries.js")
    args = parser.parse_args()
    rows = build(args.data, args.osm)
    rows_json = ",\n".join("  " + json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
                           for row in rows)
    args.output.write_text("// Generated by scripts/build-city170-frontage-recoveries.py.\n"
                           + "export const recoveredFronts=[\n" + rows_json + "\n];\n")
