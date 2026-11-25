"""Recover small Taipei shopfronts on the same wall as a documented ground-floor business.

Usage: python build-taipei-compact-frontages.py DATA TAIPEI_OSM_JSON_GZ OUTPUT_JS
Uses the same geometry dependencies as build-taipei-survey-frontages.py.
"""

import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import runpy

from shapely import LineString, Point, STRtree
from shapely.geometry import shape

HERE = Path(__file__).resolve().parent
S = runpy.run_path(str(HERE / "build-taipei-survey-frontages.py"))
G, R, F, A, read = (S[k] for k in ("G", "R", "F", "A", "read"))
MAX_COMPACT_WIDTH = 3.8


def source_stores(data, osm):
    manifest, places, buildings, roads = F["load_atlas"](
        data / "city170", read(data / "city170-shops.json.gz")
    )
    with gzip.open(osm, "rb") as stream:
        expected = manifest["source"]["provenance"]["taipeiExtractUncompressedSHA256"]
        if hashlib.file_digest(stream, "sha256").hexdigest() != expected:
            raise ValueError("OSM extract differs from the Taipei atlas")
    tags = F["source_tags"](osm, [item.id for item in places + buildings + roads])
    roads = [road for road in roads if S["street_eligible"](road, tags[road.id.split("/", 1)[1]])]
    places.extend(F["MapFeature"](item["id"], item["properties"], shape(item["geometry"]))
                  for item in read(data / "city170-inspected-shops.json.gz")["features"])
    return manifest, places, F["Streets"](buildings, roads), tags


def current_rows(data):
    directory = data / "city170-frontages"
    packs = sorted(read(directory / "summary.json")["packs"])
    search = {row[6]: row for row in read(directory / "search.json.gz")}
    rows = [row for pack in packs for row in read(directory / (pack + ".json.gz"))] + G["supplements"]()
    for filename in ("taipei-ground-frontages.js", "taipei-address-frontages.js", "taipei-survey-frontages.js"):
        rows.extend(json.loads((HERE.parent / filename).read_text().split("=", 1)[1].strip().removesuffix(";")))
    return set(packs), search, rows


def variant(point, match, survey, footprints, streets, building_index, counts):
    # Use only enough of the named street facade for a compact representative bay.
    # This can fit a short measured strip or leave nearby tenants' bays free.
    narrow = F["frontage"](match, 0, match.edge.length, limit=MAX_COMPACT_WIDTH)
    if narrow is None:
        return None
    site, row = narrow
    site, failure = survey.snap(site, row, match)
    if failure or row["width"] < 2.45:
        return None
    counts["compact-survey-wall"] += 1
    wall = F["project"](LineString(row["wall"]))
    # Confirm this actual LiDAR strip corresponds to the entire proposed OSM
    # facade, even when the survey roof and OSM polygon split a row differently.
    if (any(match.edge.distance(Point(p)) > .55 for p in wall.coords)
        or not match.building.geometry.buffer(.56).covers(LineString([point,site]))):
        counts["unconfirmed-survey-side"] += 1
        return None
    (ax,ay), (bx,by) = wall.coords
    nx, ny = (by-ay)/wall.length, (ax-bx)/wall.length
    if nx*match.normal[0]+ny*match.normal[1] < 0:
        nx, ny = -nx, -ny
    buckets = survey.buckets(site)
    tested = []
    for fraction in (.04,.5,.96):
        origin = wall.interpolate(fraction, normalized=True)
        facing = match.road.geometry.interpolate(match.road.geometry.project(origin))
        ground = S["clear_corridor"](survey, streets, buckets, origin, (nx,ny), facing,
                                     row["surveyBase"], row["surveyTop"], building_index)
        start = Point(origin.x + nx*.24, origin.y + ny*.24)
        if ground is None or footprints.blocks_corridor(start, facing, ground):
            counts["blocked-corridor"] += 1
            return None
        tested.append(ground)
    if max(tested) - min(tested) > .48:
        counts["sloping-facade"] += 1
        return None
    row.update(evidence="compact-measured-street-wall", groundZ=round(tested[1],3))
    return site, row


def build(data, osm):
    packs, search, existing = current_rows(data)
    secured = {row["id"] for row in existing}
    manifest, places, streets, tags = source_stores(data, osm)
    stores = [p for p in places if p.id in search]
    points = [F["project"](store.geometry) for store in stores]
    tenants = STRtree(points)
    districts = {d["properties"]["name"]: F["project"](shape(d["geometry"]))
                 for d in read(data / "districts.geojson")["features"]}
    survey = F["Survey"](data)
    footprints = S["SurveyFootprints"](survey, data)
    address_groups = Counter()
    neighbors = defaultdict(list)
    records = []
    for store, point in zip(stores, points):
        district = search[store.id][1]
        tags_for_store = tags[store.id.split("/",1)[1]] if store.id.startswith("poi/") else store.properties
        address = G["shop_address"](store, tags_for_store, district)
        if address:
            address_groups[district, address.road, address.house] += 1
            neighbors[district, address.road, address.house.partition("-")[0]].append((store,point,address))
            records.append((store,point,tags_for_store,district,address))
    counts = Counter({"pin-only":len(set(search) - secured)})
    proposals = []
    for store, point, original, district, address in records:
        if (store.id in secured or district not in districts or F["floor_status"](store, original)
            or F["dihua_duplicate"](store) or (address.floor and address.floor not in A["GROUND"])
            or A["INDOOR_VENUE"].search(A["address_text"](store.properties["name"]+" "+store.properties["detail"]))
            or address_groups[district,address.road,address.house] != 1
            or G["nearby_identity_conflict"](store, point, address,
                neighbors[district,address.road,address.house.partition("-")[0]])):
            continue
        inside = streets.footprints.query(point, predicate="covered_by")
        if len(inside) != 1:
            continue
        i = int(inside[0])
        building = streets.buildings[i]
        building_tags = tags[building.id.split("/",1)[1]]
        if not G["small_building"](building, building_tags):
            continue
        ground = S["same_address_floor"](store, original, district, address)
        single = (building_tags.get("building:levels") == "1"
                  and building_tags.get("building:levels:underground") in (None,"0"))
        if not ground and not single:
            continue
        if any(stores[j].id != store.id for j in tenants.query(building.geometry, predicate="covered_by")):
            continue
        counts["documented-ground-single-tenant"] += 1
        ground_tags = {**original, "addr:street":address.road}
        match, _ = streets.find_wall(store, point, ground_tags, building, True, district)
        if match is None:
            continue
        fit = variant(point, match, survey, footprints, streets, i, counts)
        if fit is None:
            continue
        site, row = fit
        pack = F["pack_for"](site,manifest)
        if pack not in packs or not districts[district].covers(site):
            continue
        if any(stores[j].id != store.id for j in tenants.query(site, predicate="dwithin", distance=4.5)):
            continue
        row.update(pack=pack, district=district, groundEvidence="tagged-ground" if ground else "single-storey-footprint")
        proposals.append((site,row,district,store))
    blocked = F["overlapping_slots"]([(None,row,None,None) for row in existing]+proposals)
    rows = [row for i,(_,row,_,_) in enumerate(proposals,len(existing)) if i not in blocked]
    counts["accepted"] = len(rows)
    return sorted(rows, key=lambda row: row["id"]), counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("data", "osm", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    rows, counts = build(args.data, args.osm)
    args.output.write_text("// Generated by scripts/build-taipei-compact-frontages.py.\n"
                           + "export const compactFronts=[\n"
                           + ",\n".join(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",",":"))
                                        for row in rows) + "\n];\n")
    print(json.dumps({"counts":counts,"districts":Counter(row["district"] for row in rows)}, ensure_ascii=False))
