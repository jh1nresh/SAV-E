"""Build a point index from the checked-in Taipei atlas using Shapely 2.x.

Run from any directory with Python and the same Shapely environment as the
city170 scripts. The script uses local data only and prints coverage as JSON.
"""

import argparse
from collections import Counter, defaultdict
import gzip
import json
import math
from pathlib import Path
import re
import unicodedata
from urllib.parse import urlsplit

from shapely import STRtree, union_all
from shapely.geometry import Point, shape


DATA = Path(__file__).resolve().parents[1] / "data"
OSM_ID = re.compile(r"(?:^|/)(node|way|relation)/(\d+)$")
SCHOOLS = {
    "school": "學校", "university": "大學", "college": "學院", "kindergarten": "幼兒園",
    "education": "教育設施",
}
PUBLIC_AREAS = {
    "park": "公園", "garden": "花園", "playground": "遊樂場", "recreation_ground": "休憩場地",
    "nature_reserve": "自然保護區", "stadium": "體育場", "sports_centre": "運動中心",
}
LABELS = {
    **SCHOOLS, **PUBLIC_AREAS,
    "market-area": "攤販集中場", "atm": "自動提款機", "bank": "銀行",
    "artwork": "公共藝術", "attraction": "景點", "bicycle_rental": "自行車租借站",
    "bakery": "麵包店", "bar": "酒吧", "beauty": "美容店", "beverages": "飲品店",
    "butcher": "肉舖", "car_repair": "汽車維修", "charging_station": "充電站",
    "clinic": "診所", "clothes": "服飾店", "community_centre": "社區中心",
    "convenience": "便利商店", "dentist": "牙科診所", "drinking_water": "飲水處",
    "fire_station": "消防分隊", "florist": "花店", "fuel": "加油站", "gift": "禮品店",
    "greengrocer": "蔬果店", "grocery": "雜貨店", "hairdresser": "美髮店",
    "hospital": "醫院", "hotel": "旅館", "information": "資訊服務", "laundry": "洗衣店",
    "library": "圖書館", "lottery": "彩券行", "mall": "商場", "marketplace": "市場",
    "massage": "按摩店", "monument": "紀念碑", "museum": "博物館",
    "optician": "眼鏡行", "pharmacy": "藥局", "place_of_worship": "宗教場所",
    "police": "警察機關", "post_office": "郵局", "shoes": "鞋店", "supermarket": "超市",
    "toilets": "洗手間", "variety_store": "生活用品店", "viewpoint": "觀景點",
}


def load(path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as stream:
        return json.load(stream)


def name_key(value):
    value = unicodedata.normalize("NFKC", value).replace("台", "臺").casefold()
    return "".join(value.split())


def valid_url(value):
    if not isinstance(value, str) or any(c.isspace() for c in value):
        return False
    try:
        parsed = urlsplit(value)
        return parsed.scheme in {"https", "http"} and bool(parsed.hostname) and not parsed.username
    except ValueError:
        return False


def near(point, other, metres=25):
    return math.hypot((point.x - other.x) * 100780, (point.y - other.y) * 110800) <= metres


def build(data):
    atlas = data / "city170"
    manifest = load(atlas / "index.json")
    district_rows = load(data / "districts.geojson")["features"]
    district_names = [row["properties"]["name"] for row in district_rows]
    districts = STRtree([shape(row["geometry"]) for row in district_rows])
    city = union_all(districts.geometries)
    search = {row[6]: row for row in load(data / "city170-frontages/search.json.gz")}
    features, osm_objects = {}, set()
    by_district, exclusions = Counter(), Counter()
    schools_by_name, markets_by_name, places_by_name = (defaultdict(list) for _ in range(3))

    def add(record, point, category, points_by_name=None):
        identity, source_props = record["id"], record["properties"]
        source = source_props["source"]
        osm = OSM_ID.search(identity) if source == "OpenStreetMap" else None
        if identity in features or (osm and osm.groups() in osm_objects):
            exclusions["same-source-record"] += 1
            return False
        if point.is_empty or not (math.isfinite(point.x) and math.isfinite(point.y)):
            exclusions["invalid-point"] += 1
            return False
        position = [round(point.x, 8), round(point.y, 8)]
        locations = districts.query(Point(position), predicate="covered_by")
        if not len(locations):
            exclusions["outside-city"] += 1
            return False
        district = district_names[min(locations)]
        name = source_props.get("name", "").strip()
        given_label = source_props.get("categoryLabel", "").strip()
        label = given_label if given_label and given_label != category else LABELS.get(category, category)
        detail = source_props.get("detail", "").strip()
        if not detail or detail in {given_label, label}:
            street = search[identity][2] if identity in search else None
            detail = " · ".join(part for part in (district, street) if part)
        url = source_props.get("url")
        if not valid_url(url) and osm:
            url = f"https://www.openstreetmap.org/{osm[1]}/{osm[2]}"
        properties = dict(placeId=identity, category=category, categoryLabel=label, district=district, source=source)
        if name:
            properties["name"] = name
        if detail:
            properties["detail"] = detail
        if valid_url(url):
            properties["url"] = url
        features[identity] = dict(type="Feature", id=identity, geometry=dict(type="Point", coordinates=position),
                                  properties=properties)
        by_district[district] += 1
        if osm:
            osm_objects.add(osm.groups())
        if name and points_by_name is not None:
            points_by_name[name_key(name)].append(point)
        return True

    school_records = load(atlas / manifest["schools"])["features"]
    school_shapes = {row["id"]: shape(row["geometry"]) for row in school_records
                     if row["properties"]["kind"] == "school"}

    def school_match(name, point):
        return any(near(point, previous) or (area is not None and area.covers(point))
                   for previous, area in schools_by_name[name])

    for row in school_records:
        props = row["properties"]
        if props["kind"] != "school-label":
            continue
        point = shape(row["geometry"])
        key = name_key(props["name"])
        area = school_shapes.get(row["id"].removeprefix("label/"))
        if school_match(key, point):
            exclusions["same-campus"] += 1
        elif add(row, point, props["category"]):
            schools_by_name[key].append((point, area))

    for row in load(data / "city170-markets.json.gz")["features"]:
        add(row, shape(row["geometry"]), row["properties"]["kind"], markets_by_name)

    areas, attractions = [], []
    for pack in manifest["packs"]:
        for row in load(atlas / pack["url"])["features"]["features"]:
            props = row["properties"]
            kind, category, name = props["kind"], props["category"], props.get("name", "")
            if kind in {"park", "pitch"} and category in PUBLIC_AREAS and name:
                areas.append(row)
            if kind != "poi":
                continue
            if category == "attraction" and name and props.get("detail") not in {None, "", props.get("categoryLabel")}:
                attractions.append(row)
                continue
            point = shape(row["geometry"])
            key = name_key(name)
            if row["id"] not in search and key:
                if category in SCHOOLS and school_match(key, point):
                    exclusions["same-campus"] += 1
                    continue
                if category == "marketplace" and any(near(point, previous) for previous in markets_by_name[key]):
                    exclusions["same-market"] += 1
                    continue
            add(row, point, category, places_by_name if category in PUBLIC_AREAS or category == "attraction" else None)

    # A landmark may appear as both the building and its commercial site.
    # Require the same name and mapped address at essentially the same location.
    attraction_sites = defaultdict(list)
    for row in sorted(attractions, key=lambda row: (row["id"] not in search,
                                                   not row["properties"].get("building"), row["id"])):
        props = row["properties"]
        key = name_key(props["name"]), name_key(props["detail"])
        point = shape(row["geometry"])
        if row["id"] not in search and any(near(point, previous, 15) for previous in attraction_sites[key]):
            exclusions["same-attraction-address"] += 1
        elif add(row, point, "attraction", places_by_name):
            attraction_sites[key].append(point)

    for filename in ("city170-shops.json.gz", "city170-inspected-shops.json.gz"):
        for row in load(data / filename)["features"]:
            add(row, shape(row["geometry"]), row["properties"]["category"])

    for row in areas:
        props = row["properties"]
        key = name_key(props["name"])
        area = shape(row["geometry"])
        if any(area.covers(point) for point in places_by_name[key]):
            exclusions["same-park-or-attraction"] += 1
            continue
        point = area.intersection(city).representative_point()
        add(row, point, props["category"], places_by_name)

    summary = dict(total=len(features), byDistrict=dict(sorted(by_district.items())),
                   bySource=dict(Counter(f["properties"]["source"] for f in features.values())),
                   unnamed=sum("name" not in f["properties"] for f in features.values()),
                   searchCoverage=dict(covered=len(search.keys() & features.keys()), total=len(search)),
                   excluded=dict(exclusions))
    return dict(type="FeatureCollection", features=[features[key] for key in sorted(features)]), summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=DATA)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    target = args.out or args.data / "city-place-index.json.gz"
    collection, summary = build(args.data)
    body = json.dumps(collection, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode()
    compressed = gzip.compress(body, compresslevel=9, mtime=0)
    target.write_bytes(compressed)
    print(json.dumps({**summary, "gzipBytes": len(compressed)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
