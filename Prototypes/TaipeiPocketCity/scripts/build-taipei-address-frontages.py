"""Recover eligible ground-floor shops from municipal doorplates or separately mapped customer entrances.

Run with the Taipei atlas dependencies (ijson, shapely 2, numpy, pyproj, Pillow):
  python build-taipei-address-frontages.py --project Prototypes/TaipeiPocketCity --data RESTORED_DATA --osm taipei.json.gz --output taipei-address-frontages.js
"""
import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import runpy

import ijson
from shapely.geometry import Point, shape
from shapely.strtree import STRtree


def municipal_plate(tags):
    return (tags.get("source") in {"臺北市政府", "台北市政府"} and tags.get("addr:TW:dataset")
            and tags.get("addr:city") in {"臺北市", "台北市"} and tags.get("addr:district")
            and tags.get("addr:street") and tags.get("addr:housenumber")
            and not {"office", "shop", "amenity", "craft", "tourism"}.intersection(tags))


def customer_entrance(tags):
    return (tags.get("entrance") == "shop" and tags.get("access") in {"customers", "yes", "public"}
            and tags.get("level") in {None, "0", "0.0", "ground"}
            and tags.get("layer") in {None, "0"} and tags.get("indoor") in {None, "no"}
            and tags.get("location") not in {"underground", "indoor", "roof"}
            and tags.get("door") not in {"no", "emergency", "service", "exit"})


def raw_evidence(osm, wanted, checksum, address):
    tags, entrances, buildings, owners = {}, {}, {}, defaultdict(set)
    plates = defaultdict(list)
    with gzip.open(osm, "rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != checksum:
            raise ValueError("This OSM extract differs from the published Taipei atlas")
    with gzip.open(osm, "rb") as stream:
        for row in ijson.items(stream, "elements.item", use_float=True):
            kind, number, props = row["type"], row["id"], row.get("tags", {})
            key = f"{kind}/{number}"
            if key in wanted:
                tags[key] = props
            if kind == "way" and props.get("building"):
                # Count outside-atlas adjacent walls as well before assigning a doorway.
                buildings[key] = row["nodes"]
            elif kind == "node":
                if props.get("entrance") == "shop":
                    entrances[number] = (Point(row["lon"], row["lat"]), props)
                if municipal_plate(props):
                    district = props["addr:district"]
                    addr = address(props, district)
                    if addr:
                        plates[district, *addr].append((number, Point(row["lon"], row["lat"]), props))
    for key, nodes in buildings.items():
        for number in set(nodes).intersection(entrances):
            owners[number].add(key)
    by_building = defaultdict(list)
    for number, values in owners.items():
        if len(values) == 1:
            by_building[next(iter(values))].append((number, *entrances[number]))
    return tags, plates, by_building


def choose_wall(g, r, streets, survey, store, point, building_index, address, original, district,
                plate, entrances, tenant_points, stores, counts):
    f = g["F"]
    building = streets.buildings[building_index]
    road_name = f["street_name"](address.road)
    proposals = []
    # A separate public entrance need not have an address. Tie it to the sole known
    # retail tenant inside this footprint and require the actual named address road.
    if entrances:
        counts["shop-entrance-on-building"] += 1
    if len(entrances) == 1:
        number, geo, props = entrances[0]
        entry = f["project"](geo)
        other_address = r["address"](props, district)
        if (customer_entrance(props) and not f["floor_status"](store, props)
                and entry.distance(point) < 22 and (not other_address or other_address == (address.road, address.house))
                and not any(stores[i].id != store.id for i in tenant_points.query(building.geometry, predicate="covers"))):
            site = r["exposed_front"](streets, survey, store, building, {**original, "addr:street": address.road},
                                      district, (number, geo, props))
            if site:
                site[1].update(evidence="ground-shop-customer-entrance", entranceId=f"node/{number}")
                proposals.append(site)
    # The independent municipal house-number is address evidence, not a surveyed door.
    # Exclude neighbouring plate aliases before testing a facade, and exclude multiple
    # plausible named tenants at the plate. The road must be visible from the measured wall.
    nearby = [(n, f["project"](geo), props) for n, geo, props in plate if geo.distance(store.geometry) < .0005]
    nearby = [(n, p, props) for n, p, props in nearby if p.distance(point) <= 25]
    if len(nearby) == 1:
        number, marker, props = nearby[0]
        if (store.id != f"poi/node/{number}" and .35 < marker.distance(point)
                and building.geometry.distance(marker) <= .35 and building.geometry.boundary.distance(marker) <= 2.5
                and set(streets.footprints.query(marker, predicate="dwithin", distance=.35)) == {building_index}
                and not any(stores[i].id != store.id for i in tenant_points.query(marker, predicate="dwithin", distance=4.5))):
            counts["municipal-plate-at-unambiguous-edge"] += 1
            site = g["shop_bay"](survey, streets, marker, store, building_index, road_name)
            if site and site[0].distance(marker) <= 2.75 and building.geometry.boundary.distance(site[0]) <= 2.5:
                site[1].update(evidence="ground-store-municipal-doorplate", addressNode=f"node/{number}",
                               addressDataset=props["addr:TW:dataset"])
                proposals.append(site)
    if len(proposals) == 2 and proposals[0][0].distance(proposals[1][0]) > .6:
        counts["conflicting-sources"] += 1
        return None
    return proposals[0] if proposals else None


def build(project, data, osm):
    g = runpy.run_path(str(project / "scripts/build-taipei-ground-frontages.py"))
    r = runpy.run_path(str(project / "scripts/build-city170-frontage-recoveries.py"))
    f, a, read = g["F"], g["A"], g["read"]
    front = data / "city170-frontages"
    packs = read(front / "summary.json")["packs"]
    search = {row[-1]: row for row in read(front / "search.json.gz")}
    existing = [row for pack in packs for row in read(front / (pack + ".json.gz"))] + g["supplements"]()
    existing.extend(json.loads((project / "taipei-ground-frontages.js").read_text().split("=", 1)[1].strip().removesuffix(";")))
    secured = {row["id"] for row in existing}
    manifest, places, buildings, roads = f["load_atlas"](data / "city170", read(data / "city170-shops.json.gz"))
    wanted = {p.id.split("/", 1)[1] for p in places + buildings + roads if p.id.count("/") == 2}
    tags, plates, portals = raw_evidence(osm, wanted, manifest["source"]["provenance"]["taipeiExtractUncompressedSHA256"], r["address"])
    places.extend(f["MapFeature"](row["id"], row["properties"], shape(row["geometry"]))
                  for row in read(data / "city170-inspected-shops.json.gz")["features"])
    stores = [p for p in places if p.id in search]
    points = [f["project"](p.geometry) for p in stores]
    tenants = STRtree(points)
    streets = f["Streets"](buildings, [road for road in roads if f["street_eligible"](road, tags[road.id.split("/", 1)[1]])])
    survey = f["Survey"](data)
    districts = {d["properties"]["name"]: f["project"](shape(d["geometry"])) for d in read(data / "districts.geojson")["features"]}
    addresses, neighbors = Counter(), defaultdict(list)
    records, proposals, counts = [], [], Counter()
    for store, point in zip(stores, points):
        district = search[store.id][1]
        original = tags[store.id.split("/", 1)[1]] if store.id.startswith("poi/") else store.properties
        address = g["shop_address"](store, original, district)
        if address:
            addresses[district, address.road, address.house] += 1
            neighbors[district, address.road, address.house.partition("-")[0]].append((store, point, address))
            records.append((store, point, original, district, address))
    counts["pin-only"] = len(set(search) - secured)
    for store, point, original, district, address in records:
        if store.id in secured or district not in districts or f["floor_status"](store, original) or f["dihua_duplicate"](store):
            continue
        key = (district, address.road, address.house)
        if ((address.floor and address.floor not in a["GROUND"]) or addresses[key] != 1
                or a["INDOOR_VENUE"].search(a["address_text"](store.properties["name"] + store.properties["detail"]))
                or g["nearby_identity_conflict"](store, point, address, neighbors[district, address.road, address.house.partition("-")[0]])):
            continue
        inside = streets.footprints.query(point, predicate="covered_by")
        if len(inside) != 1:
            continue
        index = int(inside[0])
        building = buildings[index]
        osm_building = building.id.split("/", 1)[1]
        bt = tags[osm_building]
        if not g["small_building"](building, bt):
            continue
        ground = r["explicit_ground"](original) or address.floor in a["GROUND"]
        single = bt.get("building:levels") == "1" and bt.get("building:levels:underground") in {None, "0"}
        if not (ground or single):
            continue
        found = choose_wall(g, r, streets, survey, store, point, index, address, original, district,
                            plates[key], portals[osm_building], tenants, stores, counts)
        if found:
            site, row = found
            row.update(district=district, pack=f["pack_for"](site, manifest),
                       groundEvidence="tagged-ground" if ground else "single-storey-footprint")
            if row["pack"] in packs and districts[district].covers(site):
                proposals.append((site, row, district, store))
    blocked = f["overlapping_slots"]([(None, row, None, None) for row in existing] + proposals)
    rows = [row for i, (_, row, _, _) in enumerate(proposals, len(existing)) if i not in blocked]
    counts["recovered"] = len(rows)
    return sorted(rows, key=lambda row: row["id"]), counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("project", "data", "osm", "output"):
        parser.add_argument("--" + option, required=True, type=Path)
    args = parser.parse_args()
    rows, counts = build(args.project.resolve(), args.data, args.osm)
    args.output.write_text("// Generated from the frozen Taipei atlas, original OSM and surveyed building walls.\n"
                           + "export const addressFronts=[\n" + ",\n".join(
                               json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
                               for row in rows) + "\n];\n")
    print(json.dumps(counts, sort_keys=True))
