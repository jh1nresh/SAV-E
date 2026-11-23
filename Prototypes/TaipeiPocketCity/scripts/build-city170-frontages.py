"""Match named Taipei retail and dining POIs to mapped street-facing walls.

Dependencies: ijson, NumPy, Pillow, pyproj and Shapely 2.1+. Run from any directory with
--osm Taipei's archived Geofabrik extract. City atlas packs supply OSM
footprints and roads, while original tags preserve level and address evidence.
Published wall coordinates are refined to the 2025 Taipei survey mesh. Output
rows identify estimated shop frontages and explicitly mapped entrances.
"""

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
from functools import lru_cache
import gzip
import json
import math
from pathlib import Path
import re
import unicodedata

import ijson
import numpy as np
from PIL import Image
from pyproj import Geod, Transformer
from shapely import orient_polygons, transform
from shapely.geometry import LineString, Point, box, shape
from shapely.strtree import STRtree


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
FORWARD = Transformer.from_crs("EPSG:4326", "EPSG:3826", always_xy=True)
REVERSE = Transformer.from_crs("EPSG:3826", "EPSG:4326", always_xy=True)
GEOD = Geod(ellps="WGS84")
DINING = {"restaurant", "fast_food", "cafe", "ice_cream", "bar", "pub", "biergarten"}
NON_STOREFRONT = {
    "no", "vacant", "closed", "abandoned", "disused", "proposed", "construction",
    "demolished", "department_store", "mall", "shopping_centre", "marketplace",
    "food_court", "concession", "kiosk", "vending_machine", "market_stall",
    "food_truck", "food_stand", "street_vendor",
}
NON_CUSTOMER_BUILDINGS = {
    "hospital", "school", "university", "college", "kindergarten", "transportation",
    "train_station", "trainstation", "station", "parking", "garage", "garages",
    "mall", "marketplace", "industrial", "warehouse", "shed",
    "service", "roof", "church", "temple", "cathedral", "mosque", "stadium",
}
PUBLIC_STREETS = {
    "trunk", "primary", "secondary", "tertiary", "residential", "unclassified",
    "living_street", "pedestrian", "service", "road",
}
DIHUA_IDS = {"commerce/153", "poi/node/6681493385"}
DIHUA_NAMES = (
    "爵林堅果", "永盛藥行", "德成藥行", "德成蔘藥", "婉藝埕", "利生堂", "黃裕生",
    "老成記", "正元參藥", "正元蔘藥", "度小月",
)
DIHUA_NUMBERS = {"85", "87", "89", "91", "93", "95", "97", "112"}
ADDRESS_STREET = re.compile(r"([^區里鄰\s]+?(?:大道|街|路)(?:[一二三四五六七八九十0-9]+段)?(?:[0-9]+巷)?(?:[0-9]+弄)?)")
UPPER_FLOOR = re.compile(
    r"地下|夾層|樓上|地庫|負[\d一二三四五]|(?:B[1-9][0-9]*|[2-9][0-9]*F)(?![a-z])"
    r"|(?:[2-9]|[1-9][0-9]+|[二三四五六七八九十百]+)\s*(?:樓|层|層)|(?:^|[\s・])樓[2-9]",
    re.IGNORECASE,
)


@dataclass
class MapFeature:
    id: str
    properties: dict
    geometry: object


@dataclass
class Match:
    place: MapFeature
    building: MapFeature
    road: MapFeature
    district: str
    edge: LineString
    edge_number: int
    offset: float
    normal: tuple
    evidence: str
    score: float


def normalize(value):
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", str(value or ""))).replace("台", "臺")


def street_name(value):
    value = normalize(value)
    return re.sub(
        r"([一二三四五六七八九])段",
        lambda match: str("一二三四五六七八九".index(match[1]) + 1) + "段",
        value,
    )


def source_street(place, tags):
    if tags.get("addr:street"):
        return tags["addr:street"].strip()
    if not place.id.startswith("poi/"):
        match = ADDRESS_STREET.search(normalize(place.properties.get("detail")))
        if match:
            return match[1]
    return ""


def expected_street(place, tags):
    return street_name(source_street(place, tags))


def is_commerce(place, tags):
    shop = str(tags.get("shop", ""))
    return not place.id.startswith("poi/") or (
        bool(shop and shop not in NON_STOREFRONT) or tags.get("amenity") in DINING
    )


def dihua_duplicate(place):
    if place.id in DIHUA_IDS:
        return True
    lon, lat = place.geometry.x, place.geometry.y
    if not (121.5089 < lon < 121.5109 and 25.0556 < lat < 25.0573):
        return False
    name = normalize(place.properties.get("name"))
    if any(alias in name for alias in DIHUA_NAMES):
        return True
    detail = street_name(place.properties.get("detail"))
    return "迪化街1段" in detail and bool(
        set(re.findall(r"(\d+)號", detail)) & DIHUA_NUMBERS
    )


def floor_status(place, tags):
    indoor, location = tags.get("indoor"), tags.get("location")
    if indoor not in (None, "no", "false") or location in {"indoor", "underground", "roof", "rooftop"}:
        return "indoor-or-complex"
    for key, ground_values in (
        ("level", {"0", "ground", "ground_floor", "g", "0;0", "0.0"}),
        ("addr:floor", {"0", "1", "1f", "1樓", "一樓", "ground", "g"}),
        ("floor", {"0", "1", "1f", "1樓", "一樓", "ground", "g"}),
    ):
        value = normalize(tags.get(key)).lower()
        if value and value not in ground_values:
            return "upper-or-unknown-floor"
    if any(UPPER_FLOOR.search(normalize(value)) for value in (
        place.properties.get("detail"), tags.get("addr:full"), tags.get("addr:unit"),
    )):
        return "upper-or-unknown-floor"
    if re.search(r"地下街|地下商場|購物中心|百貨|美食街|機場|車站", normalize(place.properties.get("detail"))):
        return "indoor-or-complex"
    if tags.get("layer") not in (None, "0") or tags.get("access") in {"no", "private"} or place.properties.get("vendor"):
        return "non-storefront"
    return None


def load_json(path):
    if path.suffix == ".gz":
        with gzip.open(path, "rb") as stream:
            return json.load(stream)
    return json.loads(path.read_bytes())


def project(geometry):
    return transform(geometry, FORWARD.transform, interleaved=False)


def load_atlas(path, city_shops):
    manifest = load_json(path / "index.json")
    buildings, places, roads = [], [], []
    for pack in manifest["packs"]:
        for feature in load_json(path / pack["url"])["features"]["features"]:
            props = feature["properties"]
            kind = props["kind"]
            ident = feature["id"]
            if kind == "poi" and props.get("name"):
                name = city_shops["matches"].get(ident, {})
                places.append(MapFeature(ident, {**props, **name}, shape(feature["geometry"])))
            elif kind == "building":
                geometry = project(shape(feature["geometry"]))
                if geometry.is_valid and 14 <= geometry.area <= 40_000:
                    buildings.append(MapFeature(ident, props, orient_polygons(geometry)))
            elif kind in {"road", "walk"}:
                if props.get("category") not in PUBLIC_STREETS and not (
                    props.get("footway") == "sidewalk" or props.get("name")
                ):
                    continue
                props = {**props, "streetKey": street_name(props.get("name"))}
                roads.append(MapFeature(ident, props, project(shape(feature["geometry"]))))
    places.extend(
        MapFeature(f["id"], f["properties"], shape(f["geometry"]))
        for f in city_shops["features"]
    )
    return manifest, places, buildings, roads


def source_tags(path, ids):
    wanted = defaultdict(set)
    for identity in ids:
        if identity.count("/") == 2:
            _, kind, raw = identity.split("/")
            wanted[kind].add(int(raw))
    results = {}
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rb") as stream:
        for feature in ijson.items(stream, "elements.item", use_float=True):
            kind, index = feature["type"], feature["id"]
            if index in wanted[kind]:
                results[f"{kind}/{index}"] = feature.get("tags", {})
    return results


def street_eligible(road, tags):
    if tags.get("access") in {"no", "private"} or tags.get("service") in {"driveway", "parking_aisle", "drive-through"}:
        return False
    if tags.get("bridge") not in (None, "no") or tags.get("tunnel") not in (None, "no"):
        return False
    if tags.get("layer") not in (None, "0"):
        return False
    return road.properties.get("category") in PUBLIC_STREETS or (
        road.properties.get("footway") == "sidewalk" and bool(road.properties.get("name"))
    )


class Streets:
    def __init__(self, buildings, roads):
        self.buildings = buildings
        self.roads = roads
        self.footprints = STRtree([building.geometry for building in buildings])
        self.street_lines = STRtree([road.geometry for road in roads])

    def building_at(self, point, place):
        candidates = [
            self.buildings[i] for i in self.footprints.query(point, predicate="dwithin", distance=2.9)
        ]
        own = f"building/{place.id.removeprefix('poi/')}"
        exact = next((building for building in candidates if building.id == own), None)
        if exact is not None:
            return exact, True, None
        inside = [building for building in candidates if building.geometry.covers(point)]
        if len(inside) == 1:
            return inside[0], True, None
        if inside:
            return None, False, "ambiguous-building"
        candidates.sort(key=lambda building: building.geometry.distance(point))
        if not candidates:
            return None, False, "no-building"
        if len(candidates) > 1 and (
            candidates[1].geometry.distance(point) - candidates[0].geometry.distance(point) < 1.3
        ):
            return None, False, "ambiguous-building"
        return candidates[0], False, None

    def clear_street(self, center, normal, road_point):
        origin = (center.x + normal[0] * .28, center.y + normal[1] * .28)
        path = LineString((origin, road_point.coords[0]))
        return not len(self.footprints.query(path, predicate="intersects"))

    def find_wall(self, place, point, tags, building, inside, district):
        requested_street = expected_street(place, tags)
        explicit = tags.get("entrance") in {"yes", "main", "shop"}
        same_object = place.id.removeprefix("poi/") == building.id.removeprefix("building/")
        area = building.geometry.area
        if (
            building.properties.get("building") in NON_CUSTOMER_BUILDINGS
            or building.properties.get("building:part") and not building.properties.get("building")
        ) and not explicit:
            return None, "indoor-or-complex"
        if area > (2600 if explicit or same_object else 1250):
            return None, "indoor-or-complex"

        polygons = building.geometry.geoms if building.geometry.geom_type == "MultiPolygon" else [building.geometry]
        roads = [
            self.roads[i] for i in self.street_lines.query(point, predicate="dwithin", distance=40)
        ]
        if requested_street:
            roads = [road for road in roads if road.properties["streetKey"] == requested_street]
        if not roads:
            return None, "no-accessible-street"

        matches = []
        edge_number = -1
        for polygon in polygons:
            for a, b in zip(polygon.exterior.coords, polygon.exterior.coords[1:]):
                edge_number += 1
                edge = LineString((a, b))
                length = edge.length
                if length < 2.75 or edge.distance(point) > 12.0:
                    continue
                normal = ((b[1] - a[1]) / length, (a[0] - b[0]) / length)
                offset = min(length - 1.375, max(1.375, edge.project(point)))
                center = edge.interpolate(offset)
                setback = point.distance(center)
                confirmed = explicit and setback <= 2.6
                if setback > (12 if requested_street or same_object else 6.5):
                    continue
                if not inside and not confirmed and setback > (3.2 if requested_street else 2.0):
                    continue
                road_matches = []
                for road in roads:
                    street = road.geometry.interpolate(road.geometry.project(center))
                    dx, dy = street.x - center.x, street.y - center.y
                    distance = math.hypot(dx, dy)
                    alignment = (dx * normal[0] + dy * normal[1]) / max(distance, .001)
                    curb = distance - float(road.properties.get("width", 4)) * .5
                    if distance < 1.4 or distance > 30 or alignment < .80 or curb > 14:
                        continue
                    if (
                        road.properties.get("category") == "service" and not road.properties.get("name")
                        and not (confirmed or same_object or setback < 2.5)
                    ):
                        continue
                    evidence = (
                        "mapped-entrance" if confirmed else "street-address"
                        if requested_street else "shop-footprint" if same_object else "near-wall"
                    )
                    score = setback + .10 * max(0, curb) + 2.4 * (1 - alignment)
                    road_matches.append((score, road, street, evidence))
                for score, road, street, evidence in sorted(road_matches, key=lambda row: (row[0], row[1].id)):
                    if self.clear_street(center, normal, street):
                        matches.append(Match(place, building, road, district, edge, edge_number,
                                             offset, normal, evidence, score))
                        break
        if not matches:
            return None, "no-street-facing-wall"
        matches.sort(key=lambda match: (match.score, match.edge_number))
        best = matches[0]
        if (
            len(matches) > 1 and matches[1].score - best.score < 1.45
            and best.evidence != "mapped-entrance"
        ):
            return None, "ambiguous-wall"
        return best, None


@dataclass
class SurveyWalls:
    tile: str
    segments: list
    base: list
    top: list
    tree: STRtree


class Survey:
    """Find outer wall strips in the same triangle buffers drawn by the map."""

    def __init__(self, root):
        self.root = root
        self.tiles = load_json(root / "survey-index.json")["levels"]["200"]
        self.extents = STRtree([project(box(*tile["box"])) for tile in self.tiles])
        terrain_index = load_json(root / "city-streets" / "index.json")
        self.terrain_tiles = set(terrain_index.get("terrainTiles", ()))

    @lru_cache(maxsize=512)
    def walls(self, index):
        tile = self.tiles[index]
        with gzip.open(self.root / "200" / f"{tile['id']}.bin.gz", "rb") as stream:
            rows = np.frombuffer(stream.read(), dtype="<f4").reshape(-1, 3, 6)
        # Discard synthetic foundation skirts and retain vertical surveyed faces.
        alt = rows[:, :, 2]
        keep = ((alt.min(1) >= rows[:, 0, 3] - .13)
                & (np.ptp(alt, axis=1) >= 2.4) & (rows[:, 0, 4] >= 2.4))
        rows = rows[keep]
        segments, heights = [], {}
        for a, b, c in ((0, 1, 2), (1, 2, 0), (2, 0, 1)):
            duplicates = (np.abs(rows[:, a, :2] - rows[:, b, :2]) <= .023).all(1)
            rows2 = rows[duplicates]
            for first, second, base, top in zip(
                rows2[:, a, :2], rows2[:, c, :2], rows2[:, 0, 3], rows2[:, :, 2].max(1),
            ):
                endpoints = tuple(sorted((tuple(first), tuple(second))))
                old = heights.get(endpoints)
                if old is None or top > old[1]:
                    heights[endpoints] = float(base), float(top)
        if not heights:
            return SurveyWalls(tile["id"], [], [], [], STRtree([]))
        xy = np.array(list(heights), dtype="float64")
        lon = 360 * (tile["mx"] + xy[:, :, 0] * tile["m"]) - 180
        merc_y = tile["my"] - xy[:, :, 1] * tile["m"]
        lat = np.degrees(np.arctan(np.sinh(np.pi * (1 - 2 * merc_y))))
        east, north = FORWARD.transform(lon, lat)
        locations = np.stack((east, north), axis=-1)
        base, top = [], []
        for points, (low, high) in zip(locations, heights.values()):
            line = LineString(points)
            if line.length >= .65:
                segments.append(line)
                base.append(low)
                top.append(high)
        return SurveyWalls(tile["id"], segments, base, top, STRtree(segments))

    @lru_cache(maxsize=80)
    def pixels(self, tile_x, tile_y):
        candidates = [
            self.root / "city-streets" / "terrain" / f"14-{tile_x}-{tile_y}.png",
        ] if f"{tile_x}/{tile_y}" in self.terrain_tiles else [
            self.root / "terrain" / "street-atlas" / f"14-{tile_x}-{tile_y}.png",
        ]
        for path in candidates:
            if path.exists():
                with Image.open(path) as source:
                    return np.array(source.convert("RGB"))
        return None

    def ground(self, center):
        lon, lat = REVERSE.transform(center.x, center.y)
        x = (lon + 180) / 360 * 2**14
        y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) * .5 * 2**14
        tx, ty = math.floor(x), math.floor(y)
        raster = self.pixels(tx, ty)
        if raster is None:
            return None
        w, h = raster.shape[1], raster.shape[0]
        px, py = (x - tx) * w - .5, (y - ty) * h - .5
        ix, iy = math.floor(px), math.floor(py)
        if not (0 <= ix < w - 1 and 0 <= iy < h - 1):
            return None
        colors = raster[iy:iy+2, ix:ix+2].astype("float64")
        elevation = colors @ [256, 1, 1 / 256] - 32768
        fx, fy = px - ix, py - iy
        return float(np.array([1 - fy, fy]) @ elevation @ [1 - fx, fx])

    def buckets(self, center):
        indices = self.extents.query(center, predicate="dwithin", distance=32)
        return [self.walls(int(i)) for i in sorted(indices)]

    def exposure(self, site, road, buckets, outward, base, top):
        dx, dy = road.x - site.x, road.y - site.y
        distance = math.hypot(dx, dy)
        if distance < 1.15 or dx * outward[0] + dy * outward[1] < .76 * distance:
            return None
        ground = self.ground(site)
        if ground is None or top - ground < 2.30 or ground < base - 1.5:
            return None
        ray = LineString(((site.x + outward[0] * .22, site.y + outward[1] * .22), road.coords[0]))
        if any(
            bucket.top[index] >= ground + 1.8 and bucket.base[index] <= ground + 2.0
            for bucket in buckets for index in bucket.tree.query(ray, predicate="intersects")
        ):
            return None
        return ground

    def snap(self, center, row, match):
        native = LineString([FORWARD.transform(*p) for p in row["wall"]])
        buckets = self.buckets(center)
        candidates = []
        for bucket in buckets:
            for index in bucket.tree.query(center, predicate="dwithin", distance=2.6):
                segment = bucket.segments[index]
                a, b = segment.coords
                length = segment.length
                dx, dy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
                outward = (dy, -dx)
                aligned = outward[0] * match.normal[0] + outward[1] * match.normal[1]
                if abs(aligned) < .972:
                    continue
                if aligned < 0:
                    outward = (-outward[0], -outward[1])
                # Project both OSM wall endpoints onto an actual surveyed wall and
                # keep only the overlap, never adding new surveyed wall length.
                offsets = sorted((p[0] - a[0]) * dx + (p[1] - a[1]) * dy for p in native.coords)
                begin, end = max(0, offsets[0]), min(length, offsets[1])
                span = end - begin
                if span < max(2.35, row["width"] * .61):
                    continue
                site = segment.interpolate((begin + end) * .5)
                if site.distance(center) > 2.6:
                    continue
                score = site.distance(center) + (row["width"] - span) * .29
                candidates.append((score, site, segment, begin, end, outward, bucket, index))
        if not candidates:
            return None, "no-survey-wall"
        for _, site, segment, begin, end, outward, bucket, index in sorted(candidates, key=lambda candidate: candidate[0]):
            road = match.road.geometry.interpolate(match.road.geometry.project(site))
            base, top = bucket.base[index], bucket.top[index]
            ground = self.exposure(site, road, buckets, outward, base, top)
            if ground is None:
                continue
            update_wall(row, site, segment, begin, end, outward)
            row.update(groundZ=round(ground, 3), surveyBase=round(base, 3), surveyTop=round(top, 3),
                       surveyTile=bucket.tile)
            return site, None
        return None, "survey-wall-occluded-or-ground-unknown"

    def fallback(self, place, point, tags, streets):
        """Use a surveyed wall where the near-POI OSM footprint is missing."""
        expected = expected_street(place, tags)
        radius = 7.25 if expected else 4.3
        roads = [
            streets.roads[i] for i in streets.street_lines.query(point, predicate="dwithin", distance=32)
            if streets.roads[i].properties["streetKey"] and (
                not expected or streets.roads[i].properties["streetKey"] == expected
            )
        ]
        if not roads:
            return None, "survey-fallback-no-street"
        buckets = self.buckets(point)
        candidates = []
        for bucket in buckets:
            for index in bucket.tree.query(point, predicate="dwithin", distance=radius):
                segment = bucket.segments[index]
                length = segment.length
                if length < 2.9 or bucket.top[index] - bucket.base[index] > 42:
                    continue
                a, b = segment.coords
                dx, dy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
                width = min(length, 4.45)
                offset = max(width / 2, min(length - width / 2, segment.project(point)))
                site = segment.interpolate(offset)
                setback = site.distance(point)
                if setback > radius:
                    continue
                # A street crossing between the POI and the candidate implies the other side of the road.
                join = LineString((site, point))
                if setback > .15 and len(streets.street_lines.query(join, predicate="intersects")):
                    continue
                for road in roads:
                    street = road.geometry.interpolate(road.geometry.project(site))
                    rx, ry = street.x - site.x, street.y - site.y
                    distance = math.hypot(rx, ry)
                    curb = distance - float(road.properties.get("width", 4)) * .5
                    if distance < 1.4 or distance > 24 or curb > 11.5:
                        continue
                    # Pick the wall's normal on the same side as the road.
                    factor = 1 if rx * dy - ry * dx > 0 else -1
                    normal = factor * dy, -factor * dx
                    alignment = (normal[0] * rx + normal[1] * ry) / distance
                    from_wall = (point.x - site.x) * normal[0] + (point.y - site.y) * normal[1]
                    if alignment < .85 or from_wall > (1.9 if expected else .85):
                        continue
                    base, top = bucket.base[index], bucket.top[index]
                    ground = self.exposure(site, street, buckets, normal, base, top)
                    if ground is None:
                        continue
                    score = setback + .13 * max(0, curb) + 2.4 * (1 - alignment)
                    candidates.append((score, site, segment, offset, width, normal, road, ground, base, top, bucket.tile))
        if not candidates:
            return None, "survey-fallback-no-clear-wall"
        candidates.sort(key=lambda candidate: (candidate[0], candidate[6].id, candidate[10]))
        score, site, segment, offset, width, normal, road, ground, base, top, tile = candidates[0]
        for alternative in candidates[1:]:
            if alternative[0] - score >= 1.9:
                break
            # The two triangles of the same wall or a duplicate segment can yield one site.
            if alternative[1].distance(site) > .30 or sum(a * b for a, b in zip(alternative[5], normal)) < .96:
                return None, "survey-fallback-ambiguous"
        evidence = "survey-street-address" if expected else "survey-near-wall"
        row = row_attributes(place, None, road, evidence)
        update_wall(row, site, segment, offset - width / 2, offset + width / 2, normal)
        row.update(groundZ=round(ground, 3), surveyBase=round(base, 3), surveyTop=round(top, 3), surveyTile=tile)
        return (site, row), None


def geographic(point):
    return [round(value, 8) for value in REVERSE.transform(point.x, point.y)]


def pack_for(point, manifest):
    cell = manifest["cellSize"]
    ox, oy = manifest["origin"]
    return f"p{math.floor((point.x - ox) / cell / 8)}_{math.floor((point.y - oy) / cell / 8)}"


def frontage(match, start, end, limit=7.6):
    maximum = min(limit, end - start)
    if maximum < 2.45:
        return None
    offset = max(start + maximum / 2, min(end - maximum / 2, match.offset))
    center = match.edge.interpolate(offset)
    # Avoid reassigning a business to a distant end of a building's long wall.
    if abs(offset - match.offset) > 2.6:
        return None
    row = row_attributes(match.place, match.building.id, match.road, match.evidence)
    update_wall(row, center, match.edge, offset - maximum / 2, offset + maximum / 2, match.normal)
    return center, row


def row_attributes(place, building_id, road, evidence):
    props = place.properties
    return {
        "id": place.id,
        "name": props["name"],
        "category": props["category"],
        "categoryLabel": props["categoryLabel"],
        "detail": props["detail"],
        "source": props["source"],
        "url": props["url"],
        "poiCenter": [place.geometry.x, place.geometry.y],
        "buildingId": building_id,
        "streetId": road.id,
        "street": road.properties.get("name", ""),
        "evidence": evidence,
    }


def update_wall(row, center, line, start, end, normal):
    lon_lat = geographic(center)
    out = Point(center.x + normal[0], center.y + normal[1])
    azimuth, _, _ = GEOD.inv(*lon_lat, *geographic(out))
    row.update(
        center=lon_lat, angle=round((90 - azimuth) % 360, 2) % 360, width=round(end - start, 2),
        wall=[geographic(line.interpolate(start)), geographic(line.interpolate(end))],
    )


def overlapping_slots(preliminary):
    walls = [LineString([FORWARD.transform(*point) for point in row["wall"]]) for _, row, _, _ in preliminary]
    tree = STRtree(walls)
    blocked = set()
    for i, wall in enumerate(walls):
        x, y = wall.coords[0]
        u, v = wall.coords[1]
        tx, ty = (u - x) / wall.length, (v - y) / wall.length
        for j in tree.query(wall, predicate="dwithin", distance=.62):
            if j <= i:
                continue
            other = walls[j]
            a, b = other.coords
            # Nearly parallel slots in the same plane must not compete for wall space.
            if abs((b[0] - a[0]) * tx + (b[1] - a[1]) * ty) < other.length * .992:
                continue
            if max(abs((p[0] - x) * ty - (p[1] - y) * tx) for p in (a, b)) > .62:
                continue
            offsets = sorted((p[0] - x) * tx + (p[1] - y) * ty for p in (a, b))
            if min(offsets[1], wall.length) - max(offsets[0], 0) > .24:
                blocked.update((i, int(j)))
    return blocked


def save_json(path, value, compressed=False):
    payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode()
    pending = path.with_suffix(path.suffix + ".part")
    pending.write_bytes(gzip.compress(payload, mtime=0) if compressed else payload + b"\n")
    pending.replace(path)


def build(args):
    commerce = load_json(args.shops)
    manifest, places, buildings, roads = load_atlas(args.atlas, commerce)
    raw_ids = [feature.id for feature in places + buildings + roads]
    tags = source_tags(args.osm, raw_ids)
    missing = {identity for identity in raw_ids if identity.count("/") == 2} - {
        identity for identity in raw_ids if identity.split("/", 1)[1] in tags
    }
    if missing:
        raise ValueError(f"OSM snapshot differs from the packed source ({len(missing)} records absent)")
    roads = [road for road in roads if street_eligible(road, tags[road.id.split("/", 1)[1]])]
    streets = Streets(buildings, roads)
    survey = Survey(args.survey)
    inspected = load_json(args.inspected) if args.inspected.exists() else {"features": []}
    places.extend(MapFeature(f["id"], f["properties"], shape(f["geometry"])) for f in inspected["features"])
    print(f"Indexed {len(buildings):,} footprints, {len(roads):,} surface streets and {len(places):,} named POIs", flush=True)

    district_rows = load_json(args.districts)["features"]
    district_names = [row["properties"]["name"] for row in district_rows]
    district_shapes = STRtree([project(shape(row["geometry"])) for row in district_rows])
    by_district = defaultdict(Counter)
    source_counts = defaultdict(Counter)
    groups = defaultdict(list)
    fallbacks = []
    search = {}
    counts = Counter()

    def note(district, place, reason):
        counts[reason] += 1
        by_district[district][reason] += 1
        source_counts[place.properties["source"]][reason] += 1

    for place in places:
        original = tags.get(place.id.split("/", 1)[1], {}) if place.id.startswith("poi/") else place.properties
        if not is_commerce(place, original):
            continue
        metrics = project(place.geometry)
        district_indices = district_shapes.query(metrics, predicate="covered_by")
        district = district_names[district_indices[0]] if len(district_indices) else "outside"
        note(district, place, "input")
        search[place.id] = [
            place.properties["name"], district if district != "outside" else "",
            source_street(place, original), place.geometry.x, place.geometry.y, None, place.id,
        ]
        reason = floor_status(place, original)
        if district == "outside":
            reason = "outside-district"
        elif dihua_duplicate(place):
            reason = "illustrated-dihua"
        if reason:
            note(district, place, reason)
            continue
        building, inside, reason = streets.building_at(metrics, place)
        if building:
            match, reason = streets.find_wall(place, metrics, original, building, inside, district)
            if match:
                groups[building.id, match.edge_number].append(match)
        if reason == "no-building":
            fallbacks.append((place, metrics, original, district))
        elif reason:
            note(district, place, reason)
    print(f"Paired {sum(map(len, groups.values())):,} POIs to provisional walls", flush=True)

    packs = {pack["id"]: [] for pack in manifest["packs"]}
    accepted = Counter()
    samples = defaultdict(list)
    preliminary = []
    for group in groups.values():
        group.sort(key=lambda match: (match.offset, match.place.id))
        length = group[0].edge.length
        for i, match in enumerate(group):
            before = group[i - 1].offset if i else None
            after = group[i + 1].offset if i + 1 < len(group) else None
            if any(abs(neighbor - match.offset) < 1.8 for neighbor in (before, after) if neighbor is not None):
                note(match.district, match.place, "shared-ambiguous-wall")
                continue
            start = (before + match.offset) * .5 + .08 if before is not None else 0
            end = (after + match.offset) * .5 - .08 if after is not None else length
            candidate = frontage(match, start, end)
            if candidate is None:
                note(match.district, match.place, "insufficient-wall-width")
                continue
            center, row = candidate
            center, reason = survey.snap(center, row, match)
            if reason:
                note(match.district, match.place, reason)
                continue
            preliminary.append((center, row, match.district, match.place))

    print(f"Survey-refined {len(preliminary):,} OSM wall matches; testing {len(fallbacks):,} missing-footprint POIs", flush=True)
    for place, point, original, district in fallbacks:
        candidate, reason = survey.fallback(place, point, original, streets)
        if candidate is None:
            note(district, place, reason)
        else:
            preliminary.append((*candidate, district, place))
    blocked = overlapping_slots(preliminary)
    for i, (center, row, district, place) in enumerate(preliminary):
        if i in blocked:
            note(district, place, "overlapping-survey-wall")
            continue
        pack = pack_for(center, manifest)
        if pack not in packs or not len(district_shapes.query(center, predicate="covered_by")):
            note(district, place, "outside-district")
            continue
        packs[pack].append(row)
        note(district, place, "matched")
        search[place.id][2:6] = [row["street"] or search[place.id][2], *row["center"], row["angle"]]
        accepted[row["evidence"]] += 1
        if len(samples[district]) < 4:
            samples[district].append(row)

    args.out.mkdir(parents=True, exist_ok=True)
    for pack, rows in packs.items():
        save_json(args.out / f"{pack}.json.gz", sorted(rows, key=lambda row: row["id"]), compressed=True)
    search_rows = sorted(search.values(), key=lambda row: (normalize(row[0]).casefold(), row[1], row[6]))
    save_json(args.out / "search.json.gz", search_rows, compressed=True)
    total = counts["input"]
    assert len(search_rows) == total
    matched = counts["matched"]
    skipped = total - matched
    assert matched + sum(v for key, v in counts.items() if key not in {"input", "matched"}) == total
    summary = {
        "version": 1,
        "input": total,
        "matched": matched,
        "skipped": skipped,
        "namedPoiInventory": len(places),
        "searchCount": len(search_rows),
        "missingOsmFootprint": len(fallbacks),
        "skipReasons": {key: val for key, val in sorted(counts.items()) if key not in {"input", "matched"}},
        "evidence": dict(accepted),
        "districts": {
            name: {**by_district[name], "skipped": by_district[name]["input"] - by_district[name]["matched"]}
            for name in district_names
        },
        "sourceCounts": dict(source_counts),
        "source": {"osm": manifest["source"], "commerce": commerce["source"], "commerceSha256": commerce["sha256"],
                   "inspection": inspected.get("source"), "inspectionSha256": inspected.get("sha256")},
        "packs": {pack: len(rows) for pack, rows in packs.items()},
        "samples": dict(samples),
        "survey": "臺北市都市發展局 LOD1_2025 · 200m",
        "geometryMeaning": "依來源位置和街向推定，貼合 2025 測繪外牆。只有 mapped-entrance 指入口有 OSM 標註。",
    }
    save_json(args.out / "summary.json", summary)
    print(f"{matched:,} matched of {total:,} storefront candidates; {skipped:,} retained as POI", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--osm", required=True, type=Path, help="archived Taipei OSM extract")
    parser.add_argument("--atlas", type=Path, default=DATA / "city170")
    parser.add_argument("--survey", type=Path, default=DATA)
    parser.add_argument("--shops", type=Path, default=DATA / "city170-shops.json.gz")
    parser.add_argument("--inspected", type=Path, default=DATA / "city170-inspected-shops.json.gz")
    parser.add_argument("--districts", type=Path, default=DATA / "districts.geojson")
    parser.add_argument("--out", type=Path, default=DATA / "city170-frontages")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
