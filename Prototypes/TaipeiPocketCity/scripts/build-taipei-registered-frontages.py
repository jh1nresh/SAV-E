"""Attach existing Taipei shop pins to measured walls using matched ground-floor records.

Run with the restored Taipei map assets, frozen OSM extract and retail registry CSV:
    build-taipei-registered-frontages.py DATA TAIPEI_OSM_JSON_GZ REGISTRY_CSV OUTPUT_JS
Registry source: 經濟部商業發展署, 台北市商業登記資料-F零售、批發及餐飲業
https://data.gov.tw/dataset/53661
"""

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import re
import runpy

from shapely import LineString, Point, STRtree
from shapely.geometry import shape


HERE = Path(__file__).resolve().parent
EDGE = runpy.run_path(str(HERE / "build-taipei-edge-frontages.py"))
C, F, G, S, A, R, read = (EDGE[key] for key in ("C", "F", "G", "S", "A", "R", "read"))
REGISTRY_SHA256 = "7cdb30593607060b7cd353927ac99d57b18cab107b79b1abe71c3b86296eaa10"
DISTRICTS = frozenset(A["DISTRICTS"].values())
NEIGHBORHOOD_PREFIX = re.compile(r"^[^路街段巷弄號]{1,10}里(?=[^里]+[街路])")
REQUIRED_COLUMNS = {"商業名稱", "商業地址", "營業地址（財政資訊中心匯入）"}


def identity(name):
    return A["clean"](name).casefold()


def registry_address(address, district):
    prefix = "臺北市" + district
    if not address.startswith(prefix):
        return None
    location = NEIGHBORHOOD_PREFIX.sub("", address[len(prefix):], count=1)
    return A["split_address"](location, district)


def registry_index(stream):
    rows = csv.DictReader(stream)
    if not REQUIRED_COLUMNS.issubset(rows.fieldnames or ()):
        raise ValueError("Unexpected Taipei business registry columns")
    records = defaultdict(list)
    for row in rows:
        name = identity(row["商業名稱"])
        address = A["clean"](row["商業地址"])
        district = address[3:6]
        if len(name) < 2 or district not in DISTRICTS:
            continue
        business = registry_address(address, district)
        if business is None:
            continue
        tax = registry_address(A["clean"](row["營業地址（財政資訊中心匯入）"]), district)
        records[name, district, business.road, business.house].append((business, tax))
    return records


def registered_ground(records):
    if len(records) != 1:
        return False
    business, tax = records[0]
    return (
        tax is not None and business[:2] == tax[:2]
        and business.floor in A["GROUND"] and tax.floor in A["GROUND"]
    )


def bay_ground(row, wall, road, survey, streets, footprints, owner):
    center = wall.interpolate(.5, normalized=True)
    buckets = survey.buckets(center)
    (ax, ay), (bx, by) = wall.coords
    normal = ((by - ay) / wall.length, (ax - bx) / wall.length)
    facing = road.interpolate(road.project(center))
    if (facing.x - center.x) * normal[0] + (facing.y - center.y) * normal[1] < 0:
        normal = (-normal[0], -normal[1])
    grades = []
    for fraction in (.07, .5, .93):
        site = wall.interpolate(fraction, normalized=True)
        destination = road.interpolate(road.project(site))
        ground = S["clear_corridor"](survey, streets, buckets, site, normal, destination,
                                    row["surveyBase"], row["surveyTop"], owner)
        start = Point(site.x + normal[0] * .24, site.y + normal[1] * .24)
        if ground is None or footprints.blocks_corridor(start, destination, ground):
            return None
        grades.append(ground)
    return grades[1] if max(grades) - min(grades) <= .48 else None


def unique_municipal_plate(nearby):
    if not nearby:
        return None
    # Some historical imports repeated the very same surveyed address point.
    first = min(nearby, key=lambda row: row[0])
    return first if all(first[1].distance(row[1]) <= .02 for row in nearby) else None


def measured_bay(store, point, nearby, road_name, roads, survey, streets, footprints, tags,
                 *, locator="municipal-address"):
    owners = streets.footprints.query(point, predicate="covered_by")
    plate = unique_municipal_plate(nearby)
    if len(owners) > 1 or (nearby and plate is None):
        return None
    owner = int(owners[0]) if len(owners) else None
    if owner is not None:
        building = streets.buildings[owner]
        if not G["small_building"](building, tags[building.id.split("/", 1)[1]]):
            return None
    samples = [(None, point, False)]
    if plate is not None:
        samples.append((*plate[:2], True))

    fits = []
    for plate_id, marker, independent in samples:
        found = G["shop_bay"](survey, streets, marker, store, owner, road_name)
        if found is None:
            continue
        site, row = found
        if site.distance(point) > 8 or marker.distance(site) > 4.5:
            continue
        wall = F["project"](LineString(row["wall"]))
        grade = bay_ground(row, wall, roads[row["streetId"]].geometry, survey, streets, footprints, owner)
        if grade is None:
            continue
        row.update(evidence="registered-ground-measured-bay", groundZ=round(grade, 3),
                   frontageLocator=locator if independent else "ground-shop-pin")
        if plate_id is not None:
            row["addressNode"] = f"node/{plate_id}"
        fits.append((site, row, wall))
    if not fits or (len(fits) == 2 and fits[0][2].hausdorff_distance(fits[1][2]) > .60):
        return None
    # When both anchors support the same exposed bay the municipal point wins.
    return fits[-1]


def build(data, osm, registry):
    if hashlib.sha256(registry.read_bytes()).hexdigest() != REGISTRY_SHA256:
        raise ValueError("Business registry must match the pinned November 2026 extract")
    with registry.open(encoding="utf-8-sig", newline="") as stream:
        records = registry_index(stream)
    packs, search, existing = C["current_rows"](data)
    for filename in ("taipei-compact-frontages.js", "taipei-edge-frontages.js"):
        source = (HERE.parent / filename).read_text()
        existing.extend(json.loads(source.split("=", 1)[1].strip().removesuffix(";")))
    placed = {row["id"] for row in existing}
    manifest, places, streets, tags = C["source_stores"](data, osm)
    checksum = manifest["source"]["provenance"]["taipeiExtractUncompressedSHA256"]
    _, plates, _ = S["D"]["raw_evidence"](osm, set(), checksum, R["address"])
    roads = {road.id: road for road in streets.roads}
    stores = [store for store in places if store.id in search]
    points = [F["project"](store.geometry) for store in stores]
    tenants = STRtree(points)
    districts = {f["properties"]["name"]: F["project"](shape(f["geometry"]))
                 for f in read(data / "districts.geojson")["features"]}
    survey = F["Survey"](data)
    footprints = S["SurveyFootprints"](survey, data)
    addresses, neighbors, candidates = Counter(), defaultdict(list), []
    for store, point in zip(stores, points):
        district = search[store.id][1]
        source = tags[store.id.split("/", 1)[1]] if store.id.startswith("poi/") else store.properties
        address = G["shop_address"](store, source, district)
        if address is None:
            continue
        addresses[district, address.road, address.house] += 1
        neighbors[district, address.road, address.house.partition("-")[0]].append((store, point, address))
        candidates.append((store, point, district, source, address))

    counts = Counter({"pin-only": len(set(search) - placed)})
    proposed = []
    for store, point, district, source, address in candidates:
        if (
            store.id in placed or district not in districts or F["floor_status"](store, source)
            or F["dihua_duplicate"](store) or (address.floor and address.floor not in A["GROUND"])
            or A["INDOOR_VENUE"].search(A["address_text"](store.properties["name"] + " " + store.properties["detail"]))
        ):
            continue
        counts["pin-only-with-address"] += 1
        key = (district, address.road, address.house)
        matches = records.get((identity(store.properties["name"]), *key), ())
        if len(matches) == 1:
            counts["exact-registry-name-and-address"] += 1
        if not registered_ground(matches):
            continue
        counts["ground-confirmed-by-two-addresses"] += 1
        if (
            addresses[key] != 1 or G["nearby_identity_conflict"](
                store, point, address, neighbors[district, address.road, address.house.partition("-")[0]]
            ) or EDGE["has_nearby_alias"](store, point, tenants, stores)
        ):
            continue
        nearby = S["nearby_plate"](plates[key], store, point)
        found = measured_bay(store, point, nearby, F["street_name"](address.road),
                             roads, survey, streets, footprints, tags)
        if found is None:
            continue
        site, row, wall = found
        pack = F["pack_for"](site, manifest)
        if pack not in packs or not districts[district].covers(site):
            continue
        if any(stores[j].id != store.id for j in tenants.query(wall, predicate="dwithin", distance=3.75)):
            continue
        # Public pin identity and category are reused. The registry supplies only
        # ground-floor evidence. Addresses, tax records and operator data stay out of this layer.
        row.pop("detail", None)
        row.update(pack=pack, district=district, groundEvidence="business-and-tax-addresses")
        proposed.append((site, row, district, store))
    rejected = F["overlapping_slots"]([(None, row, None, None) for row in existing] + proposed)
    accepted = [row for i, (_, row, _, _) in enumerate(proposed, len(existing)) if i not in rejected]
    counts["accepted"] = len(accepted)
    return sorted(accepted, key=lambda row: row["id"]), counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("data", "osm", "registry", "output"):
        parser.add_argument(argument, type=Path)
    args = parser.parse_args()
    rows, counts = build(args.data, args.osm, args.registry)
    args.output.write_text(
        "// Generated by scripts/build-taipei-registered-frontages.py. Ground-floor source: 經濟部商業發展署, "
        "https://data.gov.tw/dataset/53661 (政府資料開放授權條款第 1 版).\n"
        + "export const registeredFronts=[\n"
        + ",\n".join(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) for row in rows)
        + "\n];\n",
        encoding="utf-8",
    )
    print(json.dumps({"counts": counts, "districts": Counter(r["district"] for r in rows)}, ensure_ascii=False))
