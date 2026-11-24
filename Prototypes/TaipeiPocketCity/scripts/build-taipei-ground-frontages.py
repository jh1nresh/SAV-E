"""Recover citywide ground-floor shops where an address can be tied to one exposed survey wall.

Usage: python build-taipei-ground-frontages.py RESTORED_DATA TAIPEI_OSM_JSON_GZ OUTPUT_JS
Uses the same sources and geometry dependencies as build-city170-frontages.py.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import runpy

from shapely.geometry import LineString, Point, shape
from shapely.strtree import STRtree

HERE = Path(__file__).resolve().parent
F = runpy.run_path(str(HERE / "build-city170-frontages.py"))
A = runpy.run_path(str(HERE / "build-city170-inspected-shops.py"))
read = F["load_json"]


def shop_address(place, tags, district):
    street, house = tags.get("addr:street"), tags.get("addr:housenumber")
    full = tags.get("addr:full") or place.properties.get("detail", "")
    if street and house:
        return A["split_address"](street + house.removesuffix("號") + "號", district)
    return A["split_address"](full, district)


def nearby_identity_conflict(store, point, address, neighbors):
    # A branch-less second source may record the frontage under a sub-number.
    # Leave both searchable identities intact until the two addresses are distinguished.
    name = A["name_token"](store.properties["name"])
    for other, position, other_address in neighbors:
        if (other.id == store.id or store.properties["source"] == other.properties["source"]
                or address.road != other_address.road
                or address.house.partition("-")[0] != other_address.house.partition("-")[0]
                or point.distance(position) > 12):
            continue
        other_name = A["name_token"](other.properties["name"])
        shorter, longer = sorted((name, other_name), key=len)
        if shorter and (shorter == longer or (len(shorter) >= 3 and longer.startswith(shorter))):
            return True
    return False


def explicit_floor(address, tags):
    return (address.floor in A["GROUND"] or str(tags.get("level", "")).lower() in {"0", "0.0", "ground", "g"}
            or any(A["address_text"](tags.get(key) or "") in A["GROUND"] | {"1", "ground"}
                   for key in ("floor", "addr:floor"))
            or tags.get("entrance") in {"yes", "shop", "main"})


def small_building(building, tags):
    return (building.geometry.geom_type == "Polygon" and building.geometry.area <= 1250
            and building.properties.get("building") not in F["NON_CUSTOMER_BUILDINGS"]
            and not tags.get("building:part") and not F["floor_status"](building, tags)
            and tags.get("shop") not in {"mall", "shopping_centre", "department_store"}
            and tags.get("amenity") not in {"school", "university", "hospital", "marketplace"})


def shop_bay(survey, streets, point, place, building_index, road_key):
    # Work only against the named ground-level public address road.
    roads = [streets.roads[i] for i in streets.street_lines.query(point, predicate="dwithin", distance=30)
             if streets.roads[i].properties["streetKey"] == road_key]
    if not roads:
        return None
    roads.sort(key=lambda road: road.id)
    buckets = survey.buckets(point)
    slots = {}
    for bucket in buckets:
        for i in bucket.tree.query(point, predicate="dwithin", distance=7.25):
            wall = bucket.segments[i]
            if wall.length < 2.65:
                continue
            (ax, ay), (bx, by) = wall.coords
            dx, dy = (bx - ax) / wall.length, (by - ay) / wall.length
            offset = (point.x - ax) * dx + (point.y - ay) * dy
            if not 0 < offset < wall.length:
                continue
            projection = wall.interpolate(offset)
            width = min(4.2, wall.length - .16)
            middle = max(width/2 + .08, min(wall.length - width/2 - .08, offset))
            if abs(middle - offset) > 1.45:
                continue
            center = wall.interpolate(middle)
            for road in roads:
                street = road.geometry.interpolate(road.geometry.project(center))
                rx, ry = street.x - center.x, street.y - center.y
                distance = math.hypot(rx, ry)
                if not 1.4 < distance < 23 or distance - road.properties.get("width", 4)/2 > 10:
                    continue
                normal = (dy, -dx) if rx * dy > ry * dx else (-dy, dx)
                if (normal[0] * rx + normal[1] * ry) / distance < .92:
                    continue
                # A point inside the shop or at its doorway must be on the same side of the street.
                streetward = (point.x - projection.x)*normal[0] + (point.y - projection.y)*normal[1]
                if streetward > .8 or (point.distance(projection) > .15 and
                        len(streets.street_lines.query(LineString([point, projection]), predicate="intersects"))):
                    continue
                # OSM and measured edges may differ. Only the containing shop footprint can be
                # crossed on the path from the pin to the facade and then out to its named road.
                path = LineString([point, center, street])
                if any(int(j) != building_index for j in streets.footprints.query(path, predicate="intersects")):
                    continue
                ground = survey.exposure(center, street, buckets, normal, bucket.base[i], bucket.top[i])
                if ground is None:
                    continue
                building_id = streets.buildings[building_index].id if building_index is not None else None
                row = F["row_attributes"](place, building_id, road, "ground-address-survey-bay")
                F["update_wall"](row, center, wall, middle-width/2, middle+width/2, normal)
                row.update(groundZ=round(ground, 3), surveyBase=round(bucket.base[i], 3),
                           surveyTop=round(bucket.top[i], 3), surveyTile=bucket.tile)
                # Multiple ways carrying the same road name can face the same bay.
                slots.setdefault((bucket.tile, int(i)), (center, row))
    return next(iter(slots.values())) if len(slots) == 1 else None


def supplements():
    rows = []
    for name in ("taipei-shopfront-recoveries.js", "dihua-north-frontages.js"):
        text = (HERE.parent / name).read_text()
        rows.extend(json.loads(text.split("=", 1)[1].strip().removesuffix(";")))
    return rows


def build(data, osm):
    front = data / "city170-frontages"
    search = {r[6]: r for r in read(front / "search.json.gz")}
    manifest, places, buildings, roads = F["load_atlas"](data / "city170", read(data / "city170-shops.json.gz"))
    with gzip.open(osm, "rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != manifest["source"]["provenance"]["taipeiExtractUncompressedSHA256"]:
            raise ValueError("OSM extract differs from the published Taipei atlas")
    tags = F["source_tags"](osm, (item.id for item in places + buildings + roads))
    places.extend(F["MapFeature"](f["id"], f["properties"], shape(f["geometry"]))
                  for f in read(data / "city170-inspected-shops.json.gz")["features"])
    stores = [p for p in places if p.id in search]
    points = [F["project"](store.geometry) for store in stores]
    tenants = STRtree(points)
    available = set(read(front / "summary.json")["packs"])
    existing = [r for p in sorted(available) for r in read(front / (p+".json.gz"))] + supplements()
    already = {r["id"] for r in existing}
    addresses = defaultdict(list)
    mother_plates = defaultdict(list)
    records = []
    for store, point in zip(stores, points):
        original = tags[store.id.split("/", 1)[1]] if store.id.startswith("poi/") else store.properties
        district = search[store.id][1]
        address = shop_address(store, original, district)
        if address:
            addresses[district, address.road, address.house].append(store.id)
            mother_plates[district, address.road, address.house.partition("-")[0]].append((store, point, address))
            records.append((store, point, original, district, address))
    streets = F["Streets"](buildings, [r for r in roads if F["street_eligible"](r, tags[r.id.split("/", 1)[1]])])
    survey = F["Survey"](data)
    proposals = []
    districts = {d["properties"]["name"]: F["project"](shape(d["geometry"])) for d in read(data / "districts.geojson")["features"]}
    for store, point, original, district, address in records:
        if (store.id in already or district not in districts or F["floor_status"](store, original) or F["dihua_duplicate"](store)
                or (address.floor and address.floor not in A["GROUND"])
                or len(addresses[district, address.road, address.house]) != 1
                or A["INDOOR_VENUE"].search(A["address_text"](store.properties["name"] + store.properties["detail"]))):
            continue
        inside = streets.footprints.query(point, predicate="covered_by")
        if len(inside) > 1:
            continue
        building_index = int(inside[0]) if len(inside) else None
        ground = explicit_floor(address, original)
        evidence = "tagged-ground" if ground else None
        if building_index is not None:
            building = buildings[building_index]
            info = tags[building.id.split("/", 1)[1]]
            if not small_building(building, info):
                continue
            if any(stores[i].id != store.id for i in tenants.query(building.geometry, predicate="covers")):
                continue
            if not ground and info.get("building:levels") == "1" and info.get("building:levels:underground") in {None, "0"}:
                evidence = "single-storey-footprint"
        if not evidence:
            continue
        same_plate = mother_plates[district, address.road, address.house.partition("-")[0]]
        if nearby_identity_conflict(store, point, address, same_plate):
            continue
        # Keep independently named nearby tenants from being assigned to the same bay.
        if len(tenants.query(point, predicate="dwithin", distance=3.5)) != 1:
            continue
        found = shop_bay(survey, streets, point, store, building_index, F["street_name"](address.road))
        if found:
            center, row = found
            row.update(pack=F["pack_for"](center, manifest), district=district, groundEvidence=evidence)
            if row["pack"] in available and districts[district].covers(center):
                proposals.append((center, row, district, store))
    secured = [(None, r, None, None) for r in existing]
    blocked = F["overlapping_slots"](secured + proposals)
    return sorted((r for i, (_,r,_,_) in enumerate(proposals, len(secured)) if i not in blocked), key=lambda r:r["id"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("osm", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    rows = build(args.data, args.osm)
    args.output.write_text("// Generated by scripts/build-taipei-ground-frontages.py. Positions and shop likenesses are illustrative.\n"
                           + "export const groundFronts = [\n" + ",\n".join(json.dumps(r, ensure_ascii=False, separators=(",", ":"))
                                                                           for r in rows) + "\n];\n")
    print(len(rows), dict(sorted(Counter(r["district"] for r in rows).items())))
