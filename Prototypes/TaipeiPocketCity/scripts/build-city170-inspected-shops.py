"""Match Taipei Health Department restaurant assessments to exact doorplates.

Requires Shapely 2 and pyproj, and ijson when using --osm. Pass saved source
paths to reproduce a snapshot. Storefront placement is a separate step.
"""

import argparse
from collections import Counter, defaultdict
import csv
from difflib import SequenceMatcher
from functools import lru_cache
import gzip
from hashlib import file_digest
import json
import math
from pathlib import Path
import re
from shutil import copyfileobj
from tempfile import TemporaryDirectory
from typing import NamedTuple
from unicodedata import normalize
from urllib.request import urlopen

from pyproj import Transformer
from shapely import make_valid
from shapely.geometry import Point, shape
from shapely.strtree import STRtree


DATA = Path(__file__).resolve().parents[1] / "data"
INSPECTION_PAGE = "https://data.taipei/dataset/detail?id=59579c19-a561-4564-8c0f-545bfb32c0f6"
INSPECTION_URL = (
    "https://data.taipei/api/frontstage/tpeod/dataset/resource.download"
    "?rid=c5646d80-9118-4439-b924-075f96371d75"
)
ADDRESS_PAGE = "https://data.gov.tw/dataset/155472"
ADDRESS_URL = (
    "https://data.taipei/api/dataset/b7c8e724-1e98-45ee-a0bd-f3840623ed97"
    "/resource/ce76ca0c-7f94-4935-ab47-1d2a41ca2abb/download"
)
DISTRICTS = {
    f"63000{i:02d}0": name + "區"
    for i, name in enumerate(("松山", "信義", "大安", "中山", "中正", "大同", "萬華",
                              "文山", "南港", "內湖", "士林", "北投"), start=1)
}
DISTRICT_PREFIX = re.compile(r"^(?:" + "|".join(DISTRICTS.values()) + r")")
REGISTRATION = re.compile(r"[A-Z]-[0-9]+-[0-9]+-[0-9]+")
DOORPLATE = re.compile(r"([^號,、;]+?)([0-9]{1,5}(?:[-之][0-9]{1,4})?)號(.*)")
NUMBERED_UNIT = re.compile(r"([零〇一二兩三四五六七八九十百千]+)(?=[段巷弄號之樓層摟]|$)")
CHINESE_DIGITS = dict(zip("零一二三四五六七八九", range(10)), 〇=0, 兩=2)
UNITS = {"十": 10, "百": 100, "千": 1000}
GROUND = {"1樓", "1層", "1f", "gf", "g樓", "地面層"}
INSTITUTION = re.compile(
    r"機關|政府|衛生所|醫院|醫學中心|護理|長照|長期照顧|照護|安養|養護|老人福利|托嬰|託嬰|幼兒園|"
    r"國小|小學|國中|高中|高職|大學|學園|學校|校區|校舍|宿舍|教保|監獄|軍區|營區|行政院|"
    r"員工餐廳|團膳|膳食|伙食|中央廚房|營養科|外燴供膳|基金會|社福|照顧中心"
)
INDOOR_VENUE = re.compile(
    r"機場|站內|車站|高鐵站|北車|捷運站|百貨|購物中心|購物廣場|商場|美食街|美食廣場|"
    r"地下街|地下商街|展覽館|會展中心|藝文中心|文化中心|影城|大飯店|酒店|旅館|旅店|文旅|飯店|"
    r"sogo|新光三越|誠品生活|微風(?:北車|信義|南山|松高|廣場|南京)|遠百|大葉高島屋|"
    r"夢時代|京站|三創|美麗華|att4fun|101(?:購物|美食|店)|世貿|院區|營業大樓|貨櫃"
)
INSPECTION_FIELDS = {"行政區域代碼", "業者名稱店名", "食品業者登錄字號", "地址", "評核結果"}
ADDRESS_FIELDS = {"省市縣市代碼", "鄉鎮市區代碼", "街路段", "地區", "巷", "弄", "號", "橫座標", "縱座標"}
BRANDS = (
    ("麥當勞", "mcdonalds"), ("星巴克", "starbucks"), ("肯德基", "kfc"),
    ("摩斯漢堡", "mosburger"), ("路易莎", "louisacoffee"),
    ("必勝客", "pizzahut"), ("達美樂", "dominos"), ("丹堤", "dantecoffee"),
)


class Address(NamedTuple):
    road: str
    house: str
    floor: str


class Candidate(NamedTuple):
    id: str
    district: str
    name: str
    detail: str
    result: str
    address: Address


def clean(value):
    return re.sub(r"\s+", "", normalize("NFKC", value or "")).replace("台", "臺")


def chinese_number(value):
    if not any(c in UNITS for c in value):
        return "".join(str(CHINESE_DIGITS[c]) for c in value)
    acc = digit = 0
    for char in value:
        if char in UNITS:
            acc += (digit or 1) * UNITS[char]
            digit = 0
        else:
            digit = CHINESE_DIGITS[char]
    return str(acc + digit)


@lru_cache(maxsize=32768)
def address_text(value):
    value = clean(value).lower().replace("摟", "樓")
    return NUMBERED_UNIT.sub(lambda match: chinese_number(match[1]), value)


def split_address(value, district=""):
    value = address_text(value)
    while value:
        without_city = value.removeprefix("臺北市")
        found = DISTRICT_PREFIX.match(without_city)
        if found and district and found[0] != district:
            return None
        stripped = without_city[found.end():] if found else without_city
        if stripped == value:
            break
        value = stripped
    field = DOORPLATE.fullmatch(value)
    if not field:
        return None
    road, house, suffix = field.groups()
    house = house.replace("之", "-")
    subnumber = re.match(r"^[之-]([0-9]{1,4})(.*)$", suffix)
    if subnumber:
        if "-" in house:
            return None
        house += "-" + subnumber[1]
        suffix = subnumber[2]
    return Address(road, house, suffix)


def read_inspections(path):
    records, addresses = [], defaultdict(list)
    counts = Counter()
    with path.open(encoding="utf-8-sig", newline="") as stream:
        rows = csv.DictReader(stream)
        if not INSPECTION_FIELDS.issubset(rows.fieldnames or ()):
            raise ValueError("Unexpected Health Department assessment CSV schema")
        for row in rows:
            counts["rows"] += 1
            name, detail, code = (row[key].strip() for key in ("業者名稱店名", "地址", "行政區域代碼"))
            district = DISTRICTS.get(code)
            source_id, result = row["食品業者登錄字號"].strip(), row["評核結果"].strip()
            if not district or not name or not REGISTRATION.fullmatch(source_id) or result not in {"優", "良"}:
                counts["invalidAssessment"] += 1
                continue
            address = split_address(detail, district)
            if address is None:
                counts["unrecognizedAddress"] += 1
                continue
            evidence = clean(name + " " + detail).lower()
            institution = bool(INSTITUTION.search(evidence))
            indoor = bool(INDOOR_VENUE.search(evidence))
            non_ground = bool(address.floor and address.floor not in GROUND)
            addresses[(district, address.road, address.house)].append((name_token(name), institution or indoor, non_ground))
            if institution or indoor:
                counts["institutionOrIndoor"] += 1
                continue
            if non_ground:
                counts["nonGroundOrUnclearFloor"] += 1
                continue
            records.append(Candidate(source_id, district, name, detail, result, address))
    ambiguous = {
        key for key, rows in addresses.items() if len({row[0] for row in rows}) > 1
        and (any(row[1] or row[2] for row in rows) or len({row[0] for row in rows}) > 2)
    }
    filtered = [
        row for row in records if (row.district, row.address.road, row.address.house) not in ambiguous
    ]
    counts["ambiguousSharedAddress"] = len(records) - len(filtered)
    return filtered, counts


def locate_doorplates(path, candidates):
    wanted = defaultdict(set)
    for candidate in candidates:
        wanted[candidate.district, candidate.address.road].add(candidate.address.house)
    positions = defaultdict(set)
    with path.open(encoding="utf-8-sig", newline="") as stream:
        rows = csv.DictReader(stream)
        if not ADDRESS_FIELDS.issubset(rows.fieldnames or ()):
            raise ValueError("Unexpected official doorplate CSV schema")
        for row in rows:
            if row["省市縣市代碼"] != "63000":
                continue
            district = DISTRICTS.get(row["鄉鎮市區代碼"])
            road = address_text("".join(row[field] for field in ("街路段", "地區", "巷", "弄")))
            allowed = wanted.get((district, road))
            if not allowed:
                continue
            exact = split_address(road + row["號"], district)
            if exact is None or exact.house not in allowed or (exact.floor and exact.floor not in GROUND):
                continue
            try:
                position = (float(row["橫座標"]), float(row["縱座標"]))
            except ValueError:
                continue
            if all(math.isfinite(number) and number > 0 for number in position):
                positions[(district, road, exact.house, bool(exact.floor))].add(position)
    return positions


def osm_ground(tags):
    if tags.get("indoor") not in (None, "no", "false") or tags.get("location") in ("underground", "rooftop", "indoor"):
        return False
    for key, valid in (
        ("level", {"0", "0.0", "ground", "g"}),
        ("layer", {"0", "0.0"}),
        ("addr:floor", GROUND | {"0", "1"}),
        ("floor", GROUND | {"0", "1"}),
    ):
        if key in tags and address_text(tags[key]) not in valid:
            return False
    full = tags.get("addr:full", "")
    parsed = split_address(full) if full else None
    return not (parsed and parsed.floor and parsed.floor not in GROUND)


def osm_doorplates(path, candidates, districts):
    import ijson

    wanted = defaultdict(set)
    for item in candidates:
        wanted[item.address.road, item.address.house].add(item.district)
    positions = defaultdict(list)
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rb") as stream:
        for item in ijson.items(stream, "elements.item", use_float=True):
            tags = item.get("tags", {})
            if item.get("type") != "node" or not tags.get("addr:street") or not tags.get("addr:housenumber"):
                continue
            road = address_text(tags["addr:street"])
            for component in ("addr:lane", "addr:alley"):
                value = address_text(tags.get(component, ""))
                if value and value not in road:
                    road += value
            house = address_text(tags["addr:housenumber"]).replace("号", "號")
            if "號" not in house:
                house += "號"
            address = split_address(road + house)
            if not address or address.floor or not osm_ground(tags):
                continue
            possible = wanted.get((address.road, address.house), ())
            if not possible:
                continue
            point = (round(item["lon"], 7), round(item["lat"], 7))
            reported = clean(tags.get("addr:district", ""))
            for district in possible:
                if (reported not in DISTRICTS.values() or reported == district) and districts[district].covers(Point(point)):
                    positions[(district, address.road, address.house)].append((point, item["id"]))
    return positions


def name_token(name):
    value = re.sub(r"[^\w]", "", clean(name).casefold()).replace("_", "")
    for traditional, english in BRANDS:
        value = value.replace(english, traditional)
    return value


def name_match(first, second, distance):
    if first == second:
        return distance <= 90
    common_length = min(len(first), len(second))
    if common_length >= 3 and distance <= 40 and (first in second or second in first):
        return True
    if distance <= 32 and any(first.startswith(zh) and second.startswith(zh) for zh, _ in BRANDS):
        return True
    return distance <= 20 and common_length >= 4 and SequenceMatcher(None, first, second).ratio() >= 0.78


def planar(point):
    return Point(point[0] * 100840, point[1] * 110780)


def load_json(path):
    with gzip.open(path, "rb") as stream:
        return json.load(stream)


def existing_places(data):
    rows = []
    for path in sorted((data / "city170").glob("p*.json.gz")):
        places = [f for f in load_json(path)["features"]["features"] if f["properties"]["kind"] == "poi"]
        rows.extend(places)
    rows.extend(load_json(data / "city170-shops.json.gz")["features"])
    positions, names, addresses = [], [], []
    for feature in rows:
        properties = feature["properties"]
        name = name_token(properties.get("name", ""))
        if not name or feature["geometry"]["type"] != "Point":
            continue
        positions.append(planar(feature["geometry"]["coordinates"]))
        names.append(name)
        addresses.append(split_address(properties.get("detail", "")))
    return STRtree(positions), names, addresses


def select_address(key, address, doorplates, osm_positions, project):
    official = (doorplates.get((*key, True)) if address.floor else None) or doorplates.get((*key, False), ())
    if official:
        x0, y0 = min(official)
        if any(math.hypot(x - x0, y - y0) > 1 for x, y in official):
            return None, "ambiguousDoorplate"
        point = [round(number, 7) for number in project.transform(x0, y0)]
        return (point, ADDRESS_PAGE, "臺北市政府民政局門牌位置"), "officialDoorplate"
    mapped = osm_positions.get(key, ())
    if not mapped:
        return None, "noExactDoorplate"
    point, node_id = min(mapped)
    if any(planar(point).distance(planar(other)) > 1 for other, _ in mapped):
        return None, "ambiguousOsmDoorplate"
    return (list(point), f"https://www.openstreetmap.org/node/{node_id}", "OpenStreetMap 門牌點"), "osmDoorplate"


def build(inspection_path, address_path, osm_path, partial, data):
    candidates, counts = read_inspections(inspection_path)
    districts = {
        f["properties"]["name"]: make_valid(shape(f["geometry"]))
        for f in json.loads((data / "districts.geojson").read_bytes())["features"]
    }
    doorplates = locate_doorplates(address_path, candidates) if address_path else {}
    osm_positions = osm_doorplates(osm_path, candidates, districts) if osm_path else {}
    existing, existing_names, existing_addresses = existing_places(data)
    projection = Transformer.from_crs(3826, 4326, always_xy=True)
    features, accepted = [], defaultdict(list)
    retained_ids = set()
    district_counts = Counter()
    for item in sorted(candidates, key=lambda c: (not bool(c.address.floor), c.id)):
        address = item.address
        key = item.district, address.road, address.house
        location, status = select_address(key, address, doorplates, osm_positions, projection)
        if not location:
            counts[status] += 1
            continue
        point, address_url, address_label = location
        if not districts[item.district].covers(Point(point)):
            counts["outsideReportedDistrict"] += 1
            continue
        name, spot = name_token(item.name), planar(point)
        duplicate = False
        for i in existing.query(spot, predicate="dwithin", distance=90):
            distance = spot.distance(existing.geometries[i])
            old_address = existing_addresses[i]
            same_road = old_address and old_address.road == address.road
            if same_road and old_address.house != address.house:
                continue
            if name_match(name, existing_names[i], distance) or (same_road and distance <= 24):
                duplicate = True
                break
        if duplicate:
            counts["existingMapOrCommerce"] += 1
            continue
        nearby = [
            other for i in range(math.floor(spot.x / 100) - 1, math.floor(spot.x / 100) + 2)
            for j in range(math.floor(spot.y / 100) - 1, math.floor(spot.y / 100) + 2)
            for other in accepted.get((i, j), ())
        ]
        if item.id in retained_ids or any(
            name_match(name, other_name, spot.distance(other_point)) or key == other_key
            for other_name, other_point, other_key in nearby
        ):
            counts["duplicateAssessment"] += 1
            continue
        accepted[(math.floor(spot.x / 100), math.floor(spot.y / 100))].append((name, spot, key))
        retained_ids.add(item.id)
        district_counts[item.district] += 1
        counts[status] += 1
        properties = dict(
            kind="poi", category="inspection_store", categoryLabel="餐飲店家",
            name=item.name, detail=item.detail, source="臺北市政府衛生局",
            url=INSPECTION_PAGE, rank=0, addressSource=address_url, addressSourceLabel=address_label, assessment=item.result,
        )
        if address.floor:
            properties.update(floor="1", level="0")
        features.append(dict(
            type="Feature", id="inspection/" + item.id,
            geometry=dict(type="Point", coordinates=point),
            properties=properties,
        ))
    if not features:
        raise ValueError("No assessment records matched an eligible exact doorplate")
    address_provenance = {}
    if address_path:
        address_provenance["official"] = dict(url=ADDRESS_URL, sha256=hash_path(address_path), partial=partial,
                                              bytes=address_path.stat().st_size)
    if osm_path:
        address_provenance["osm"] = dict(url="https://www.openstreetmap.org/copyright", sha256=hash_path(osm_path),
                                         fields=["addr:street", "addr:housenumber"])
    return dict(
        features=features, matches={}, audit=dict(counts, added=len(features), districts=dict(sorted(district_counts.items()))),
        source=INSPECTION_URL, sha256=hash_path(inspection_path),
        addressProvenance=address_provenance,
        evidence="Assessment site, matched to an exact official doorplate or OpenStreetMap address point. Streetfront placement requires separate evidence.",
    )


def hash_path(path):
    with path.open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest()


def fetch(path, url):
    with urlopen(url, timeout=90) as stream, path.open("wb") as output:
        content_length = stream.headers.get("Content-Length")
        copyfileobj(stream, output)
    if content_length and path.stat().st_size != int(content_length):
        raise ValueError(f"Official download size mismatch for {url}")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspection-csv", type=Path)
    parser.add_argument("--address-csv", type=Path)
    parser.add_argument("--partial-address-csv", action="store_true", help="declare a saved CSV as a partial official download")
    parser.add_argument("--osm", type=Path, help="fallback to exact address nodes from a local OpenStreetMap snapshot")
    parser.add_argument("--data", type=Path, default=DATA)
    parser.add_argument("--out", type=Path, default=DATA / "city170-inspected-shops.json.gz")
    args = parser.parse_args()
    if args.partial_address_csv and not args.address_csv:
        parser.error("--partial-address-csv requires --address-csv")
    with TemporaryDirectory(prefix="taipei-inspected-shops-") as temporary:
        inspection = args.inspection_csv or fetch(Path(temporary) / "assessment.csv", INSPECTION_URL)
        address = args.address_csv
        if not address and not args.osm:
            address = fetch(Path(temporary) / "doorplate.csv", ADDRESS_URL)
        result = build(inspection, address, args.osm, args.partial_address_csv, args.data)
    payload = json.dumps(result, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode()
    pending = args.out.with_name(args.out.name + ".part")
    pending.write_bytes(gzip.compress(payload, compresslevel=6, mtime=0))
    pending.replace(args.out)
    print(json.dumps(result["audit"], ensure_ascii=False))


if __name__ == "__main__":
    main()
