"""Recover storefronts where ground occupancy and a surveyed facade agree at the mapped shop pin.

Usage: python build-taipei-edge-frontages.py DATA TAIPEI_OSM_JSON_GZ OUTPUT_JS
Uses the same dependencies and pinned snapshots as build-taipei-compact-frontages.py.
"""

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import runpy

from shapely import LineString, STRtree
from shapely.geometry import shape


HERE = Path(__file__).resolve().parent
C = runpy.run_path(str(HERE / "build-taipei-compact-frontages.py"))
F, G, S, R, A, read = (C[key] for key in ("F", "G", "S", "R", "A", "read"))


def single_storey_tenant(streets, point, store, tags, tenants, stores):
    owners = streets.footprints.query(point, predicate="covered_by")
    if len(owners) != 1:
        return False
    building = streets.buildings[int(owners[0])]
    info = tags[building.id.split("/", 1)[1]]
    if not (
        info.get("building:levels") == "1"
        and info.get("building:levels:underground") in {None, "0"}
        and G["small_building"](building, info)
    ):
        return False
    occupants = tenants.query(building.geometry, predicate="covers")
    return len(occupants) == 1 and stores[occupants[0]].id == store.id


def name_identity(value):
    token = A["name_token"](value).replace("緑", "綠")
    # Two spellings of the same café brand appear beside each other in the source.
    return "8icecafe" if token == "8cafe" else token


def has_nearby_alias(store, point, tenants, stores):
    identity = name_identity(store.properties["name"])
    return bool(identity) and any(
        stores[j].id != store.id and name_identity(stores[j].properties["name"]) == identity
        for j in tenants.query(point, predicate="dwithin", distance=8)
    )


def locally_supported(polygon, wall, point, center):
    # Whole-roof overlap can fail when the survey and OSM group rowhouses differently.
    # The complete proposed span must still agree with this shop's local OSM facade.
    return polygon.exterior.buffer(.55).covers(wall) and polygon.buffer(.55).covers(LineString([point, center]))


def measured_front(store, point, street_key, streets, tags, survey, footprints, counts):
    roofs = footprints.occupants(point)
    if len(roofs) != 1 or not roofs[0].polygon.covers(point):
        return None
    roof = roofs[0]
    counts["single-survey-roof"] += 1
    if not 12 <= roof.polygon.area <= 1250 or roof.polygon.interiors or roof.polygon.boundary.distance(point) > 3.05:
        return None
    whole_roof_match, building_index = S["supporting_osm"](roof.polygon, point, streets, tags)
    local_footprint = None
    if not whole_roof_match:
        owners = streets.footprints.query(point, predicate="covered_by")
        if len(owners) != 1:
            return None
        building_index = int(owners[0])
        owner = streets.buildings[building_index]
        if not G["small_building"](owner, tags[owner.id.split("/", 1)[1]]):
            return None
        local_footprint = owner.geometry
    roads = [
        streets.roads[j] for j in streets.street_lines.query(point, predicate="dwithin", distance=25)
        if streets.roads[j].properties.get("streetKey")
        and (not street_key or street_key == streets.roads[j].properties["streetKey"])
    ]
    # Use the shop's own tightly located pin in place of a separate municipal plate.
    found = S["street_front"](store, point, roof, roads, streets, survey, footprints, point, building_index)
    if found is None:
        return None
    center, row = found
    wall = F["project"](LineString(row["wall"]))
    if local_footprint is not None and not locally_supported(local_footprint, wall, point, center):
        return None
    row.update(
        evidence="ground-pin-measured-edge",
        frontageLocator="ground-shop-pin",
        footprintEvidence="local-osm-wall" if local_footprint is not None else "survey-roof",
    )
    return center, row, wall


def build(data, osm):
    packs, search, existing = C["current_rows"](data)
    compact = (HERE.parent / "taipei-compact-frontages.js").read_text()
    existing.extend(json.loads(compact.split("=", 1)[1].strip().removesuffix(";")))
    placed = {row["id"] for row in existing}
    manifest, places, streets, tags = C["source_stores"](data, osm)
    stores = [place for place in places if place.id in search]
    points = [F["project"](store.geometry) for store in stores]
    tenants = STRtree(points)
    districts = {f["properties"]["name"]: F["project"](shape(f["geometry"]))
                 for f in read(data / "districts.geojson")["features"]}
    survey = F["Survey"](data)
    footprints = S["SurveyFootprints"](survey, data)
    addresses, neighbors, records = Counter(), defaultdict(list), []
    for store, point in zip(stores, points):
        district = search[store.id][1]
        original = tags[store.id.split("/", 1)[1]] if store.id.startswith("poi/") else store.properties
        address = G["shop_address"](store, original, district)
        if address:
            addresses[district, address.road, address.house] += 1
            neighbors[district, address.road, address.house.partition("-")[0]].append((store, point, address))
        records.append((store, point, district, original, address))
    counts = Counter({"pin-only": len(set(search) - placed)})
    proposals = []
    for store, point, district, original, address in records:
        if (
            store.id in placed or district not in districts or F["floor_status"](store, original)
            or F["dihua_duplicate"](store) or A["INDOOR_VENUE"].search(
                A["address_text"](store.properties["name"] + " " + store.properties["detail"])
            )
        ):
            continue
        if address and (
            addresses[district, address.road, address.house] != 1
            or G["nearby_identity_conflict"](store, point, address,
                                           neighbors[district, address.road, address.house.partition("-")[0]])
        ):
            continue
        tagged = R["explicit_ground"](original) or (
            address and S["same_address_floor"](store, original, district, address)
        )
        if not tagged and not single_storey_tenant(streets, point, store, tags, tenants, stores):
            continue
        counts["documented-ground"] += 1
        if has_nearby_alias(store, point, tenants, stores):
            counts["nearby-name-conflict"] += 1
            continue
        road = address.road if address else F["source_street"](store, original)
        found = measured_front(store, point, F["street_name"](road), streets, tags, survey, footprints, counts)
        if found is None:
            continue
        center, row, wall = found
        pack = F["pack_for"](center, manifest)
        if pack not in packs or not districts[district].covers(center):
            continue
        if any(stores[j].id != store.id for j in tenants.query(wall, predicate="dwithin", distance=3.75)):
            continue
        row.update(pack=pack, district=district, groundEvidence="tagged-ground" if tagged else "single-storey-footprint")
        proposals.append((center, row, district, store))
    rejected = F["overlapping_slots"]([(None, row, None, None) for row in existing] + proposals)
    rows = [row for i, (_, row, _, _) in enumerate(proposals, len(existing)) if i not in rejected]
    counts["accepted"] = len(rows)
    return sorted(rows, key=lambda row: row["id"]), counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("data", "osm", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    rows, counts = build(args.data, args.osm)
    args.output.write_text(
        "// Generated by scripts/build-taipei-edge-frontages.py from the frozen Taipei atlas.\n"
        + "export const edgeFronts=[\n"
        + ",\n".join(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) for row in rows)
        + "\n];\n",
        encoding="utf-8",
    )
    print(json.dumps({"counts": counts, "districts": Counter(r["district"] for r in rows)}, ensure_ascii=False))
