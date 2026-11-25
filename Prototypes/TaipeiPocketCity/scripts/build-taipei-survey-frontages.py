"""Attach ground-floor businesses to unique street-facing walls of connected Taipei 2025 LOD1 buildings.

Run with project atlas dependencies: python build-taipei-survey-frontages.py DATA OSM.json.gz OUTPUT.js
Both the roof footprint and actual vertical mesh face must exist. No inferred building heights are used.
"""

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
from functools import lru_cache
import gzip
import json
import math
from pathlib import Path
import runpy

import numpy as np
from shapely import LineString, Point, STRtree, get_parts, polygons, union_all
from shapely.geometry import shape

HERE = Path(__file__).resolve().parent
G = runpy.run_path(str(HERE / "build-taipei-ground-frontages.py"))
R = runpy.run_path(str(HERE / "build-city170-frontage-recoveries.py"))
D = runpy.run_path(str(HERE / "build-taipei-address-frontages.py"))
F, A, read = G["F"], G["A"], G["read"]
above_or_below_ground = runpy.run_path(str(HERE / "build-city170-grade.py"))["above_or_below_ground"]


@dataclass
class Roof:
    polygon: object
    tile: str
    base: float
    top: float


def roof_components(rows, tile):
    alt = rows[:, :, 2]
    caps = rows[
        (np.ptp(alt, axis=1) < 0.13)
        & (rows[:, 0, 4] >= 2.4)
        & (alt.min(axis=1) >= rows[:, 0, 3] + rows[:, 0, 4] - 0.15)
    ]
    roofs = []
    if not len(caps):
        return roofs
    xy = caps[:, :, :2].astype("float64")
    lon = 360 * (tile["mx"] + xy[:, :, 0] * tile["m"]) - 180
    lat = np.degrees(np.arctan(np.sinh(np.pi * (1 - 2 * (tile["my"] - xy[:, :, 1] * tile["m"])))))
    east, north = F["FORWARD"].transform(lon, lat)
    triangles = polygons(np.stack((east, north), axis=-1))
    groups, assignment = np.unique(caps[:, 0, 3:6], axis=0, return_inverse=True)
    for n, (base, height, _) in enumerate(groups):
        # Connected roof components with identical header values are separated spatially.
        for footprint in get_parts(union_all(triangles[assignment == n])):
            if footprint.geom_type == "Polygon" and footprint.is_valid and footprint.area > 1:
                roofs.append(Roof(footprint, tile["id"], float(base), float(base + height)))
    return roofs


class SurveyFootprints:
    def __init__(self, survey, data):
        self.survey = survey
        self.data = data

    @lru_cache(maxsize=128)
    def tile(self, i):
        tile = self.survey.tiles[i]
        with gzip.open(self.data / "200" / (tile["id"] + ".bin.gz"), "rb") as f:
            rows = np.frombuffer(f.read(), dtype="<f4").reshape(-1, 3, 6)
        roofs = roof_components(rows, tile)
        return roofs, STRtree([r.polygon for r in roofs])

    def blocks_corridor(self, start, road, ground):
        ray = LineString([start, road])
        for i in self.survey.extents.query(ray, predicate="intersects"):
            roofs, tree = self.tile(int(i))
            for j in tree.query(ray, predicate="intersects"):
                roof = roofs[j]
                if roof.base <= ground + 1.6 and roof.top >= ground + 1.8:
                    return True
        return False

    def occupants(self, point, radius=0.30):
        out = []
        for i in self.survey.extents.query(point, predicate="dwithin", distance=radius):
            roofs, tree = self.tile(int(i))
            out.extend(roofs[j] for j in tree.query(point, predicate="dwithin", distance=radius))
        return out


def nearby_plate(plates, store, point):
    nearby = []
    for number, geo, tags in plates:
        if geo.distance(store.geometry) > 0.0005:
            continue
        projected = F["project"](geo)
        if projected.distance(point) <= 25:
            nearby.append((number, projected, tags))
    return nearby


def same_address_floor(store, original, district, address):
    if R["explicit_ground"](original) or address.floor in A["GROUND"]:
        return True
    full = A["split_address"](original.get("addr:full") or store.properties.get("detail", ""), district)
    return bool(full and (full.road, full.house) == (address.road, address.house) and full.floor in A["GROUND"])


def supporting_osm(roof, point, streets, tags):
    inside = streets.footprints.query(point, predicate="covered_by")
    if len(inside) > 1:
        return False, None
    peers = []
    for j in streets.footprints.query(roof, predicate="intersects"):
        b = streets.buildings[j]
        overlap = b.geometry.intersection(roof).area
        if overlap / roof.area < 0.70 or overlap / b.geometry.area < 0.70:
            continue
        if not G["small_building"](b, tags[b.id.split("/", 1)[1]]):
            return False, None
        peers.append(int(j))
    if len(peers) > 1 or (len(inside) and int(inside[0]) not in peers):
        return False, None
    return True, peers[0] if peers else None


def street_eligible(road, tags):
    return (
        F["street_eligible"](road, tags)
        and not above_or_below_ground(tags)
        and tags.get("access") in {None, "yes", "public", "permissive", "designated"}
        and tags.get("foot") not in {"no", "private"}
    )


def ground_roads(streets, point, address):
    key = F["street_name"](address.road)
    return sorted(
        (
            streets.roads[j]
            for j in streets.street_lines.query(point, predicate="dwithin", distance=33)
            if streets.roads[j].properties["streetKey"] == key
        ),
        key=lambda r: r.id,
    )


def clear_corridor(survey, streets, buckets, point, normal, street, base, top, osm_index):
    dx, dy = street.x - point.x, street.y - point.y
    distance = math.hypot(dx, dy)
    if not 1.7 < distance < 22 or (dx * normal[0] + dy * normal[1]) / distance < 0.90:
        return None
    start = Point(point.x + normal[0] * 0.24, point.y + normal[1] * 0.24)
    path = LineString([start, street])
    for j in streets.footprints.query(path, predicate="intersects"):
        overlap = path.intersection(streets.buildings[j].geometry)
        if j != osm_index or overlap.length > 2.4 or overlap.distance(start) > 0.05:
            return None
    return survey.exposure(point, street, buckets, normal, base, top)


def shell_edges(poly):
    coords = poly.exterior.simplify(0.055).coords
    return [LineString([a, b]) for a, b in zip(coords, coords[1:])]


def parallel_to_road(edge, road, station):
    offset = road.project(station)
    a = road.interpolate(max(0, offset - 1))
    b = road.interpolate(min(road.length, offset + 1))
    (x, y), (u, v) = edge.coords
    return (
        abs((u - x) * (b.x - a.x) + (v - y) * (b.y - a.y)) >= edge.length * a.distance(b) * 0.94
        and a.distance(b) > 0.1
    )


def measured_span(edge, start, end, bucket, roof):
    """A contiguous measured vertical surface must back the entire rendered shop window."""
    (x, y), (u, v) = edge.coords
    tx, ty = (u - x) / edge.length, (v - y) / edge.length
    intervals = []
    for j in bucket.tree.query(edge, predicate="dwithin", distance=0.11):
        if abs(bucket.base[j] - roof.base) > 0.16 or abs(bucket.top[j] - roof.top) > 0.16:
            continue
        a, b = bucket.segments[j].coords
        if max(abs((px - x) * ty - (py - y) * tx) for px, py in (a, b)) > 0.11:
            continue
        lo, hi = sorted((px - x) * tx + (py - y) * ty for px, py in (a, b))
        if hi - lo >= bucket.segments[j].length * 0.999:
            intervals.append((lo, hi))
    covered = start
    for lo, hi in sorted(intervals):
        if hi < covered:
            continue
        if lo > covered + 0.085:
            return False
        covered = max(covered, hi)
        if covered >= end - 0.025:
            return True
    return False


def street_front(store, point, roof, roads, streets, survey, footprints, marker, osm_index):
    buckets = survey.buckets(point)
    bucket = next((b for b in buckets if b.tile == roof.tile), None)
    if bucket is None:
        return None
    # Adjacent survey buildings can share height and colour. Their coincident
    # roof edges may dissolve, but the actual internal party wall remains.
    interior = roof.polygon.buffer(-0.18)
    for j in bucket.tree.query(interior, predicate="intersects"):
        if (
            abs(bucket.base[j] - roof.base) <= 0.16
            and abs(bucket.top[j] - roof.top) <= 0.16
            and bucket.segments[j].intersection(interior).length >= 2.5
        ):
            return None
    candidates = []
    for edge in shell_edges(roof.polygon):
        if edge.length < 2.65 or edge.distance(marker) > 3.3:
            continue
        (ax, ay), (bx, by) = edge.coords
        dx, dy = (bx - ax) / edge.length, (by - ay) / edge.length
        offset = (marker.x - ax) * dx + (marker.y - ay) * dy
        if not -0.15 <= offset <= edge.length + 0.15:
            continue
        width = min(4.2, edge.length - 0.20)
        mid = max(width / 2 + 0.1, min(edge.length - width / 2 - 0.1, offset))
        if abs(mid - offset) > 1.55 or not measured_span(edge, mid - width / 2, mid + width / 2, bucket, roof):
            continue
        center = edge.interpolate(mid)
        if marker.distance(center) > 3.05 or center.distance(point) > 12:
            continue
        for road in roads:
            facing = road.geometry.interpolate(road.geometry.project(center))
            if not parallel_to_road(edge, road.geometry, facing):
                continue
            nx, ny = (dy, -dx) if (facing.x - center.x) * dy > (facing.y - center.y) * dx else (-dy, dx)
            if (
                not roof.polygon.covers(Point(center.x - nx * 0.45, center.y - ny * 0.45))
                or roof.polygon.covers(Point(center.x + nx * 0.45, center.y + ny * 0.45))
                or facing.distance(center) - road.properties.get("width", 4) / 2 > 10
            ):
                continue
            if not roof.polygon.buffer(0.15).covers(LineString([point, center])):
                continue
            grades = []
            for along in (mid - width * 0.43, mid, mid + width * 0.43):
                site = edge.interpolate(along)
                road_point = road.geometry.interpolate(road.geometry.project(site))
                ground = clear_corridor(
                    survey, streets, buckets, site, (nx, ny), road_point, roof.base, roof.top, osm_index
                )
                start = Point(site.x + nx * 0.24, site.y + ny * 0.24)
                if ground is None or footprints.blocks_corridor(start, road_point, ground):
                    break
                grades.append(ground)
            if len(grades) != 3 or max(grades) - min(grades) > 0.48:
                continue
            row = F["row_attributes"](
                store,
                streets.buildings[osm_index].id if osm_index is not None else None,
                road,
                "survey-roof-ground-address",
            )
            F["update_wall"](row, center, edge, mid - width / 2, mid + width / 2, (nx, ny))
            row.update(
                surveyTile=roof.tile,
                surveyBase=round(roof.base, 3),
                surveyTop=round(roof.top, 3),
                groundZ=round(grades[1], 3),
                groundEvidence="tagged-ground",
                frontageLocator="municipal-doorplate",
            )
            candidates.append((center, row))
            break
    return candidates[0] if len(candidates) == 1 else None


def build(data, osm):
    front = data / "city170-frontages"
    search = {r[6]: r for r in read(front / "search.json.gz")}
    packs = set(read(front / "summary.json")["packs"])
    existing = [r for p in sorted(packs) for r in read(front / (p + ".json.gz"))] + G["supplements"]()
    for name in ("taipei-ground-frontages.js", "taipei-address-frontages.js"):
        existing.extend(json.loads((HERE.parent / name).read_text().split("=", 1)[1].strip().removesuffix(";")))
    already = {r["id"] for r in existing}
    manifest, places, buildings, roads = F["load_atlas"](data / "city170", read(data / "city170-shops.json.gz"))
    wanted = {p.id.split("/", 1)[1] for p in places + buildings + roads if p.id.count("/") == 2}
    tags, plates, _ = D["raw_evidence"](
        osm, wanted, manifest["source"]["provenance"]["taipeiExtractUncompressedSHA256"], R["address"]
    )
    places.extend(
        F["MapFeature"](f["id"], f["properties"], shape(f["geometry"]))
        for f in read(data / "city170-inspected-shops.json.gz")["features"]
    )
    stores = [p for p in places if p.id in search]
    points = [F["project"](p.geometry) for p in stores]
    tenants = STRtree(points)
    districts = {
        d["properties"]["name"]: F["project"](shape(d["geometry"]))
        for d in read(data / "districts.geojson")["features"]
    }
    streets = F["Streets"](
        buildings, [road for road in roads if street_eligible(road, tags[road.id.split("/", 1)[1]])]
    )
    survey = F["Survey"](data)
    footprints = SurveyFootprints(survey, data)
    addresses = Counter()
    neighbors = defaultdict(list)
    records = []
    for store, point in zip(stores, points):
        original = tags[store.id.split("/", 1)[1]] if store.id.startswith("poi/") else store.properties
        district = search[store.id][1]
        addr = G["shop_address"](store, original, district)
        if addr:
            addresses[district, addr.road, addr.house] += 1
            neighbors[district, addr.road, addr.house.partition("-")[0]].append((store, point, addr))
            records.append((store, point, original, district, addr))
    counts = Counter({"pin-only": len(set(search) - already)})
    proposals = []
    for store, point, original, district, addr in records:
        key = (district, addr.road, addr.house)
        if (
            store.id in already
            or district not in districts
            or F["floor_status"](store, original)
            or F["dihua_duplicate"](store)
            or (addr.floor and addr.floor not in A["GROUND"])
            or addresses[key] != 1
            or not same_address_floor(store, original, district, addr)
            or A["INDOOR_VENUE"].search(
                A["address_text"](store.properties["name"] + store.properties["detail"])
            )
            or G["nearby_identity_conflict"](
                store, point, addr, neighbors[district, addr.road, addr.house.partition("-")[0]]
            )
        ):
            continue
        counts["documented-ground-and-unique-address"] += 1
        nearby = nearby_plate(plates[key], store, point)
        if len(nearby) != 1:
            continue
        number, marker, props = nearby[0]
        if store.id == f"poi/node/{number}":
            continue
        matches = footprints.occupants(point)
        if len(matches) != 1 or not matches[0].polygon.covers(point):
            continue
        roof = matches[0]
        if not 16 <= roof.polygon.area <= 780 or roof.polygon.interiors:
            continue
        counts["single-survey-building"] += 1
        if any(
            stores[j].id != store.id for j in tenants.query(roof.polygon, predicate="dwithin", distance=0.45)
        ):
            continue
        ok, osm_index = supporting_osm(roof.polygon, point, streets, tags)
        if not ok:
            continue
        roads = ground_roads(streets, point, addr)
        if not roads:
            continue
        at_plate = footprints.occupants(marker, 0.40)
        if (
            len(at_plate) != 1
            or roof.polygon.distance(marker) > 0.40
            or roof.polygon.exterior.distance(marker) > 2.95
        ):
            continue
        counts["sole-survey-tenant-and-supported-locator"] += 1
        found = street_front(store, point, roof, roads, streets, survey, footprints, marker, osm_index)
        if not found:
            continue
        center, row = found
        if any(stores[j].id != store.id for j in tenants.query(center, predicate="dwithin", distance=4.5)):
            continue
        if osm_index is not None and buildings[osm_index].geometry.boundary.distance(center) < 0.60:
            continue
        row.update(
            pack=F["pack_for"](center, manifest),
            district=district,
            osmFootprint="missing" if osm_index is None else "different-edge",
        )
        row.update(addressNode=f"node/{number}", addressDataset=props["addr:TW:dataset"])
        if row["pack"] in packs and districts[district].covers(center):
            proposals.append((center, row, district, store))
    conflicts = F["overlapping_slots"]([(None, r, None, None) for r in existing] + proposals)
    rows = [r for i, (_, r, _, _) in enumerate(proposals, len(existing)) if i not in conflicts]
    counts["accepted"] = len(rows)
    return sorted(rows, key=lambda r: r["id"]), counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for k in ("data", "osm", "output"):
        parser.add_argument(k, type=Path)
    args = parser.parse_args()
    rows, counts = build(args.data, args.osm)
    args.output.write_text(
        "// Generated by scripts/build-taipei-survey-frontages.py from the 2025 surveyed Taipei buildings.\n"
        + "export const surveyFronts=[\n"
        + ",\n".join(json.dumps(r, ensure_ascii=False, sort_keys=True, separators=(",", ":")) for r in rows)
        + "\n];\n"
    )
    print(json.dumps({"counts": counts, "districts": Counter(r["district"] for r in rows)}, ensure_ascii=False))
