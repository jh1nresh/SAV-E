"""Build a viewport-loadable city atlas from the archived Taipei OSM extract.

Use ijson, pyproj and Shapely 2.1+. No network is needed for the build.
The city grid uses EPSG:3826 (TWD97 TM2) with origin [0, 0]. Cell
geometries are clipped to the official district union and exported in WGS84.
An OSM feature keeps its full geometry and has one owning pack. Other cells
reference its ID, and their pack manifest lists the owning pack in deps.
"""

import argparse
from collections import Counter, defaultdict
import gzip
import json
import math
from pathlib import Path
import re

import ijson
from pyproj import Transformer
from shapely import make_valid, orient_polygons, set_precision, transform
from shapely.geometry import LineString, Point, Polygon, box, mapping, shape
from shapely.ops import polygonize, unary_union
from shapely.strtree import STRtree


SIZE = 170
PACK_SIZE = 8
CRS = "EPSG:3826"
WGS84 = "EPSG:4326"
ROAD_WIDTH = {
    "motorway": 14, "motorway_link": 7, "trunk": 13, "trunk_link": 7,
    "primary": 11, "primary_link": 7, "secondary": 9, "secondary_link": 6,
    "tertiary": 8, "tertiary_link": 5, "unclassified": 5, "residential": 5,
    "living_street": 4.5, "service": 3.2, "track": 3, "road": 5,
    "busway": 5, "bus_guideway": 3.5, "escape": 3.5, "raceway": 7,
}
WALK_WIDTH = {
    "footway": 2.2, "path": 1.5, "pedestrian": 4, "steps": 1.6,
    "cycleway": 2, "bridleway": 2, "corridor": 1.5,
}
SCHOOLS = {"school": 1, "college": 1, "university": 0, "kindergarten": 2}
SCHOOL_KINDS = SCHOOLS.keys()
VENDORS = {"street_vendor", "market_stall", "food_stand", "food_truck"}
AMENITY_POI = set(SCHOOLS) | VENDORS | {
    "restaurant", "fast_food", "cafe", "ice_cream", "food_court", "marketplace",
    "kiosk", "vending_machine", "biergarten", "bar", "pub", "drinking_water", "toilets",
    "community_centre", "social_centre", "library", "arts_centre", "cinema",
    "theatre", "music_venue", "clinic", "pharmacy", "hospital", "dentist",
    "veterinary", "bank", "atm", "post_office", "place_of_worship", "townhall",
    "fire_station", "police", "fuel", "charging_station", "bicycle_rental",
}
CATEGORY_LABELS = {
    "restaurant": "餐廳", "fast_food": "餐飲", "cafe": "咖啡", "bakery": "麵包",
    "ice_cream": "冰品", "food_court": "美食廣場", "marketplace": "市場",
    "street_vendor": "街邊攤商", "market_stall": "市集攤位", "food_stand": "小吃攤",
    "food_truck": "餐車", "kiosk": "小型店舖", "vending_machine": "自動販賣機",
    "convenience": "超商", "supermarket": "超市", "department_store": "百貨",
    "mall": "商場", "books": "書店", "pharmacy": "藥局", "clothes": "服飾",
    "school": "學校", "college": "學院", "university": "大學", "kindergarten": "幼兒園",
}
MAPPED_TAGS = (
    "access", "surface", "layer", "bridge", "tunnel", "indoor", "covered", "lanes",
    "oneway", "service", "footway", "building", "building:part", "building:levels",
    "sport", "cuisine", "brand", "operator", "wheelchair", "natural", "water",
)
INACTIVE = {"no", "vacant", "closed", "abandoned", "disused", "proposed", "construction", "demolished"}


def records(path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rb") as stream:
        yield from ijson.items(stream, "elements.item", use_float=True)


def name_of(tags):
    return tags.get("name:zh-Hant") or tags.get("name:zh") or tags.get("name")


def polygonal(geometry):
    if geometry.is_empty:
        return None
    if geometry.geom_type in ("Polygon", "MultiPolygon"):
        return geometry
    polygons = [part for part in getattr(geometry, "geoms", ())
                if part.geom_type in ("Polygon", "MultiPolygon")]
    return unary_union(polygons) if polygons else None


def area_kinds(tags):
    amenity = tags.get("amenity")
    leisure = tags.get("leisure")
    natural = tags.get("natural")
    landuse = tags.get("landuse")
    if tags.get("building") not in (None, "no") or tags.get("building:part") not in (None, "no"):
        yield "building", tags.get("building") or tags["building:part"]
    if amenity in SCHOOL_KINDS or landuse == "education":
        yield "school", amenity if amenity in SCHOOL_KINDS else "education"
    if leisure in ("pitch", "sports_centre", "stadium", "track", "exercise_station"):
        yield "pitch", leisure
    if leisure in ("park", "garden", "playground", "recreation_ground", "nature_reserve") \
            or landuse in ("grass", "recreation_ground", "village_green", "meadow"):
        yield "park", leisure or landuse
    if natural in ("wood", "scrub", "grassland", "wetland") or landuse == "forest":
        yield "forest", natural or landuse
    if natural == "water" or landuse in ("reservoir", "basin") or tags.get("waterway") == "riverbank":
        yield "water", tags.get("water") or landuse or tags.get("waterway") or "water"


def place_category(tags):
    shop = tags.get("shop")
    if shop and shop not in INACTIVE:
        return shop
    amenity = tags.get("amenity")
    if amenity in AMENITY_POI:
        return amenity
    vendor = mapped_vendor(tags)
    if vendor:
        return vendor[0]
    if name_of(tags):
        for key in ("tourism", "historic", "craft", "office"):
            category = tags.get(key)
            if category and category not in INACTIVE and category != "yes":
                return category
    return None


def mapped_vendor(tags):
    """Require affirmative mapped evidence; kiosk, takeaway and vending are separate."""
    if tags.get("amenity") == "vending_machine" or tags.get("shop") == "vending_machine":
        return None
    street = tags.get("street_vendor")
    if street == "no":
        return None
    if street == "yes":
        return "street_vendor", "street_vendor=yes"
    if street in VENDORS:
        return street, f"street_vendor={street}"
    for key in ("shop", "amenity"):
        kind = tags.get(key)
        if kind in VENDORS:
            return kind, f"{key}={kind}"
    return None


def read_osm(path):
    locations, tagged_nodes, ways, relations = {}, [], {}, []
    for record in records(path):
        tags = record.get("tags", {})
        if record["type"] == "node":
            locations[record["id"]] = (record["lon"], record["lat"])
            if tags and (tags.get("natural") == "tree" or place_category(tags)):
                tagged_nodes.append(record)
        elif record["type"] == "way":
            ways[record["id"]] = record
        elif record["type"] == "relation" and (any(area_kinds(tags)) or place_category(tags)):
            relations.append(record)
    return locations, tagged_nodes, ways, relations


def properties(kind, category, tags):
    result = {key: tags[key] for key in MAPPED_TAGS if key in tags}
    result.update(kind=kind, category=category, source="OpenStreetMap")
    label = name_of(tags)
    if label:
        result["name"] = label
    return result


def place_properties(record, category):
    tags = record["tags"]
    info = properties("poi", category, tags)
    operator = tags.get("contact:website") or tags.get("website")
    if operator and not operator.startswith(("http://", "https://")):
        operator = None
    number = tags.get("addr:housenumber", "")
    if number and not re.search("[號号]", number):
        number += " 號"
    detail = " ".join(part for part in (
        tags.get("addr:street"), number, tags.get("addr:unit"),
    ) if part)
    vendor = mapped_vendor(tags)
    label = CATEGORY_LABELS.get(vendor[0] if vendor else category, category)
    if category == "kiosk" and not detail:
        detail = tags.get("description", "")
    info.update(
        categoryLabel=label,
        detail=detail or label,
        url=f"https://www.openstreetmap.org/{record['type']}/{record['id']}",
        rank=0 if info.get("name") and operator else 1 if info.get("name") else 2,
        vendor=bool(vendor),
    )
    if vendor:
        info.update(vendorClass=vendor[0], vendorEvidence=vendor[1])
    if operator:
        info["operatorUrl"] = operator
    return info


def physical_width(kind, category, tags):
    raw = tags.get("width")
    if raw:
        match = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(?:m)?", raw.strip())
        if match:
            width = float(match[1])
            if .45 <= width <= 60:
                return width
    widths = ROAD_WIDTH if kind == "road" else WALK_WIDTH
    return widths[category]


def relation_polygon(record, way_line):
    outer, inner = [], []
    for member in record.get("members", ()):
        if member["type"] != "way" or member.get("role") not in ("", "inner", "outer"):
            continue
        geometry = way_line(member["ref"])
        if geometry is None:
            continue
        (inner if member["role"] == "inner" else outer).append(geometry)
    if not outer:
        return None
    shells = unary_union(list(polygonize(unary_union(outer))))
    if inner:
        shells = shells.difference(unary_union(list(polygonize(unary_union(inner)))))
    return polygonal(make_valid(shells))


def compact_json(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode()


def write_gzip(path, value):
    temporary = path.with_name(path.name + ".part")
    temporary.write_bytes(gzip.compress(compact_json(value), compresslevel=5, mtime=0))
    temporary.replace(path)


def collection(features):
    return dict(type="FeatureCollection", features=features)


def create_grid(districts, unproject):
    names = list(districts)
    shapes = [districts[name] for name in names]
    union = unary_union(shapes)
    districts_tree = STRtree(shapes)
    min_x, min_y, max_x, max_y = union.bounds
    grid, positions, owners = [], [], []
    by_district = Counter()
    for y in range(math.floor(min_y / SIZE), math.ceil(max_y / SIZE)):
        for x in range(math.floor(min_x / SIZE), math.ceil(max_x / SIZE)):
            square = box(x * SIZE, y * SIZE, (x + 1) * SIZE, (y + 1) * SIZE)
            clipped = polygonal(square.intersection(union))
            if clipped is None or clipped.area <= 0:
                continue
            belongs = [
                names[i] for i in sorted(districts_tree.query(clipped, predicate="intersects"))
                if clipped.intersection(shapes[i]).area > 1e-6
            ]
            by_district.update(belongs)
            geographic = unproject(clipped)
            pack = f"p{x // PACK_SIZE}_{y // PACK_SIZE}"
            center = unproject(square.centroid)
            owners.append(pack)
            positions.append(clipped)
            grid.append(dict(
                id=f"{x}_{y}", bounds=geographic.bounds, geometry=mapping(geographic),
                center=list(center.coords[0]), districts=belongs, refs=[], deps=set(),
            ))
    residual = unary_union(positions).symmetric_difference(union).area
    if residual > .02:
        raise ValueError(f"Grid misses {residual:.3f} m² of the official boundary")
    return union, grid, positions, owners, by_district


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--osm", required=True, type=Path, help="Taipei OSM JSON or JSON.gz extract")
    parser.add_argument("--districts", type=Path, default=Path("data/districts.geojson"))
    parser.add_argument("--out", type=Path, default=Path("data/city170"))
    parser.add_argument("--provenance", type=Path, help="Optional snapshot provenance JSON")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    forward = Transformer.from_crs(WGS84, CRS, always_xy=True)
    reverse = Transformer.from_crs(CRS, WGS84, always_xy=True)

    def unproject(geometry):
        geographic = transform(geometry, reverse.transform, interleaved=False)
        if not geographic.is_valid:
            geographic = polygonal(make_valid(geographic, method="structure"))
        return orient_polygons(set_precision(geographic, 1e-8))

    district_rows = json.loads(args.districts.read_text())["features"]
    districts = {
        row["properties"]["name"]: polygonal(make_valid(transform(
            shape(row["geometry"]), forward.transform, interleaved=False,
        )))
        for row in district_rows
    }
    if len(districts) != 12 or any(geometry is None for geometry in districts.values()):
        raise ValueError("Expected all 12 valid Taipei districts")
    union, grid, positions, owners, by_district = create_grid(districts, unproject)
    geographic_city = unproject(union)
    tree = STRtree(positions)
    pack_cells, pack_features, pack_dependencies = defaultdict(list), defaultdict(list), defaultdict(set)
    total_counts = Counter()
    for row, owner in zip(grid, owners):
        pack_cells[owner].append(row)
    write_gzip(args.out / "grid.json.gz", collection([
        dict(type="Feature", id=row["id"], geometry=row["geometry"],
             properties=dict(id=row["id"], center=row["center"], districts=row["districts"], pack=owner))
        for row, owner in zip(grid, owners)
    ]))
    print(f"Grid: {len(grid)} cells in {len(pack_cells)} packs", flush=True)

    locations, tagged_nodes, ways, relations = read_osm(args.osm)
    print(f"Source: {len(locations)} nodes, {len(ways)} ways, {len(relations)} usable-tag relations", flush=True)
    relation_members = defaultdict(set)
    schools, school_labels, school_sites = [], [], defaultdict(list)

    def way_line(way_id):
        row = ways.get(way_id)
        if not row or len(row["nodes"]) < 2 or any(ref not in locations for ref in row["nodes"]):
            return None
        line = LineString([locations[ref] for ref in row["nodes"]])
        return line if line.length else None

    def add(record, geometry, info):
        if geometry is None or geometry.is_empty:
            return False
        projected = transform(geometry, forward.transform, interleaved=False)
        ids = tree.query(projected, predicate="intersects")
        if not len(ids):
            return False
        kind = info["kind"]
        if kind in ("poi", "tree") and not union.covers(projected):
            return False
        # Keep a single canonical whole feature even when its geometry crosses cells.
        representative = projected.representative_point()
        owner = owners[min(ids, key=lambda i: (positions[i].distance(representative), i))]
        identity = f"{kind}/{record['type']}/{record['id']}"
        f = dict(type="Feature", id=identity, geometry=mapping(orient_polygons(geometry)), properties=info)
        pack_features[owner].append(f)
        total_counts[kind] += 1
        if kind == "school":
            schools.append(f)
            if info.get("name"):
                anchor = geometry.intersection(geographic_city).representative_point()
                if not anchor.is_empty:
                    school_labels.append(dict(
                        type="Feature", id=f"label/{identity}", geometry=mapping(anchor),
                        properties={**info, "kind": "school-label"},
                    ))
                    school_sites[info["name"]].append(projected)
        for i in ids:
            grid[i]["refs"].append(identity)
            if owners[i] != owner:
                pack_dependencies[owners[i]].add(owner)
                grid[i]["deps"].add(owner)
        return True

    for record in relations:
        tags = record["tags"]
        geometry = relation_polygon(record, way_line)
        if geometry is None:
            continue
        for kind, category in area_kinds(tags):
            info = properties(kind, category, tags)
            if kind == "school":
                info["rank"] = SCHOOLS.get(category, 2)
            if add(record, geometry, info):
                for member in record.get("members", ()):
                    if member["type"] == "way" and member.get("role") in ("", "outer"):
                        relation_members[member["ref"]].add((kind, name_of(tags)))
        category = place_category(tags)
        if category:
            add(record, geometry.representative_point(), place_properties(record, category))

    for record in ways.values():
        tags = record.get("tags", {})
        highway = tags.get("highway")
        categories = list(area_kinds(tags))
        shop = place_category(tags)
        if highway not in ROAD_WIDTH and highway not in WALK_WIDTH and not categories and not shop:
            continue
        line = way_line(record["id"])
        if line is None:
            continue
        if highway in ROAD_WIDTH or highway in WALK_WIDTH:
            if tags.get("area") != "yes":
                kind = "road" if highway in ROAD_WIDTH else "walk"
                info = properties(kind, highway, tags)
                info.update(width=physical_width(kind, highway, tags), **{"class": highway})
                add(record, line, info)
        area = polygonal(make_valid(Polygon(line.coords))) if line.is_closed and len(line.coords) >= 4 else None
        for kind, category in categories:
            covered = relation_members[record["id"]]
            label = name_of(tags)
            if any(kind == member_kind and (not label or label == member_name) for member_kind, member_name in covered):
                continue
            info = properties(kind, category, tags)
            if kind == "school":
                info["rank"] = SCHOOLS.get(category, 2)
            add(record, area, info)
        if shop:
            point = area.representative_point() if area is not None else line.interpolate(.5, normalized=True)
            add(record, point, place_properties(record, shop))

    for record in tagged_nodes:
        tags = record["tags"]
        point = Point(locations[record["id"]])
        if tags.get("natural") == "tree":
            add(record, point, properties("tree", "tree", tags))
        category = place_category(tags)
        if category:
            add(record, point, place_properties(record, category))
        label = name_of(tags)
        if category in SCHOOLS and label:
            projected = transform(point, forward.transform, interleaved=False)
            if union.covers(projected) and not any(site.distance(projected) < 25 for site in school_sites[label]):
                info = properties("school-label", category, tags)
                info["rank"] = SCHOOLS[category]
                school_labels.append(dict(
                    type="Feature", id=f"label/school/node/{record['id']}", geometry=mapping(point),
                    properties=info,
                ))

    print(f"Features: {dict(total_counts)}", flush=True)
    write_gzip(args.out / "schools.json.gz", collection(schools + school_labels))
    manifests = []
    for pack, rows in sorted(pack_cells.items()):
        features = pack_features[pack]
        boxes = [cell["bounds"] for cell in rows]
        bounds = [min(b[0] for b in boxes), min(b[1] for b in boxes),
                  max(b[2] for b in boxes), max(b[3] for b in boxes)]
        url = f"{pack}.json.gz"
        for row in rows:
            row["deps"] = sorted(row["deps"])
        payload = dict(id=pack, cells=rows, features=collection(features))
        write_gzip(args.out / url, payload)
        manifests.append(dict(
            id=pack, url=url, bounds=bounds, deps=sorted(pack_dependencies[pack]),
            counts=dict(cells=len(rows), features=len(features), refs=sum(len(cell["refs"]) for cell in rows)),
        ))

    provenance = json.loads(args.provenance.read_text()) if args.provenance else {}
    manifest = dict(
        version=1, cellSize=SIZE, crs=CRS, origin=[0, 0], bounds=geographic_city.bounds, packs=manifests,
        grid="grid.json.gz", schools="schools.json.gz",
        districts=[dict(name=name, bounds=unproject(geometry).bounds, cells=by_district[name])
                   for name, geometry in districts.items()],
        stats=dict(cells=len(grid), packs=len(manifests), features=sum(len(features) for features in pack_features.values()),
                   vendors=sum(f["properties"].get("vendor", False) for features in pack_features.values() for f in features),
                   schools=len(schools), schoolLabels=len(school_labels), byKind=dict(sorted(total_counts.items()))),
        source=dict(provider="OpenStreetMap", attribution="© OpenStreetMap contributors",
                    license="ODbL", licenseUrl="https://www.openstreetmap.org/copyright", provenance=provenance),
    )
    temporary = args.out / "index.json.part"
    temporary.write_bytes(compact_json(manifest))
    temporary.replace(args.out / "index.json")
    print(json.dumps(manifest["stats"], ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
