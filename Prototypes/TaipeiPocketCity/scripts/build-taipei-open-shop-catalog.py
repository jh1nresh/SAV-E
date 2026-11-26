"""Build the local Taipei store crosswalk from open data snapshots."""
import argparse
from collections import Counter, defaultdict
import csv
import gzip
from hashlib import file_digest
from importlib.util import module_from_spec, spec_from_file_location
import json
import math
from pathlib import Path
import re
from unicodedata import normalize

import ijson
from pyproj import Transformer
from shapely import Point, STRtree, make_valid
from shapely.geometry import shape

FOOD_AND_DRINK = {"restaurant", "cafe", "fast_food", "bar", "pub", "food_court", "ice_cream", "biergarten"}
NON_STOREFRONT = re.compile(r"高級中學|學校財團法人|校園福利社|家政教室|食品工廠|溫泉度假村|^台北馥敦[-－]|[-－]\S{1,4}廠$")


def distance(a, b):
    return math.hypot((a[0] - b[0]) * 100840, (a[1] - b[1]) * 110780)


def name_key(name, parser):
    return parser.clean(name).casefold()


def address_key(value, district, parser):
    if not value:
        return None
    value = re.sub(r"^\s*\d{3,6}\s*(?:台灣|臺灣)?\s*(?=台北市|臺北市)", "", value)
    value = normalize("NFKC", value)
    # Preserve the original digit boundary before the shared parser folds floor numerals.
    value = re.sub(r"(\d+)\s*號\s*[之-]\s*(\d+)(?=(?:[一二三四五六七八九十]+(?:樓|層)|\s+\d+(?:樓|層|[Ff])))",
                   r"\1-\2號", value)
    if re.search(r"\d+號[之-]\d+(?:樓|層|[Ff])", parser.clean(value)):
        return None
    parsed = parser.split_address(value, district)
    if not parsed:
        return None
    floor = parsed.floor
    if floor in parser.GROUND:
        floor = "1樓"
    match = re.fullmatch(r"([0-9]+)(?:f|樓|層)", floor)
    if match:
        floor = f"{match[1]}樓"
    match = re.fullmatch(r"(?:地下|b)([0-9]+)(?:f|樓|層)?", floor)
    if match:
        floor = f"b{match[1]}"
    return (district, parsed.road, parsed.house), floor


def osm_address(tags, district, parser):
    road, number = tags.get("addr:street"), tags.get("addr:housenumber")
    short = ""
    if road and number:
        for tag, unit in (("addr:lane", "巷"), ("addr:alley", "弄")):
            value = tags.get(tag, "")
            unit_value = value if value.endswith(unit) else value + unit
            if value and not parser.address_text(road).endswith(parser.address_text(unit_value)):
                road += unit_value
        house = number.replace("号", "號")
        floor = tags.get("addr:floor", "")
        short = road + (house if "號" in house else house + "號") + (floor + "樓" if floor.isdecimal() else floor)
    unit = parser.address_text(tags.get("addr:unit", ""))
    for label in (tags.get("addr:full"), short):
        key = address_key(label, district, parser)
        if key:
            if not key[1] and not parser.osm_ground(tags):
                key = key[0], "osm:" + "|".join(tags.get(field, "")
                    for field in ("level", "floor", "location", "layer", "indoor", "addr:floor"))
            return key, label, unit
    return None


def read_osm(path, features, parser):
    ids = {f["properties"]["url"].removeprefix("https://www.openstreetmap.org/"): f
           for f in features if f["properties"]["source"] == "OpenStreetMap"}
    result, businesses, evidence = {}, set(), {}
    with gzip.open(path, "rb") as stream:
        for obj in ijson.items(stream, "elements.item", use_float=True):
            tags = obj.get("tags")
            if not tags:
                continue
            f = ids.get(f'{obj["type"]}/{obj["id"]}')
            if not f:
                continue
            id = f["id"]
            if tags.get("shop") not in (None, "no", "vacant", "closed", "disused") or tags.get("amenity") in FOOD_AND_DRINK:
                businesses.add(id)
            if (address := osm_address(tags, f["properties"]["district"], parser)):
                result[id] = address
                evidence[id] = {
                    "branch": name_key(tags.get("branch", ""), parser),
                    "phone": re.sub(r"\D", "", tags.get("phone", tags.get("contact:phone", ""))),
                }
    return result, businesses, evidence


def read_doors(path, wanted, districts, parser):
    project = Transformer.from_crs(3826, 4326, always_xy=True)
    positions = defaultdict(lambda: defaultdict(set))
    with gzip.open(path, "rt", encoding="utf-8-sig", newline="") as stream:
        rows = csv.DictReader(stream)
        if not parser.ADDRESS_FIELDS.issubset(rows.fieldnames or ()):
            raise ValueError("Invalid Civil Affairs doorplate schema")
        for count, row in enumerate(rows, 1):
            district = parser.DISTRICTS.get(row["鄉鎮市區代碼"])
            if row["省市縣市代碼"] != "63000" or not district:
                continue
            road = "".join(row[field] for field in ("街路段", "地區", "巷", "弄"))
            road = parser.address_text(road)
            # Do not parse the million apartment numbers when this street is unneeded.
            if (district, road) not in wanted:
                continue
            key = address_key(road + row["號"], district, parser)
            if not key or key[0][2] not in wanted[district, road]:
                continue
            try:
                x, y = float(row["橫座標"]), float(row["縱座標"])
            except (ValueError, TypeError):
                continue
            if 280000 < x < 330000 and 2750000 < y < 2805000:
                point = tuple(round(v, 7) for v in project.transform(x, y))
                if districts[district].covers(Point(point)):
                    positions[key[0]][key[1]].add(point)
    return positions, count


def door_point(doors, key):
    exact = doors.get(key[0], {})
    points = exact.get(key[1]) or exact.get("") or exact.get("1樓")
    if not points:
        return None
    anchor = min(points)
    return anchor if all(distance(anchor, point) <= 2 for point in points) else None


def duplicates(rows, known, protected, parser, evidence=None):
    evidence = evidence or {}
    groups = defaultdict(list)
    for f in rows:
        name = f["properties"].get("name")
        if name and f["id"] in known:
            groups[(name_key(name, parser), known[f["id"]][0], known[f["id"]][2])].append(f)
    aliases = {}
    for (_, key, unit), group in groups.items():
        if len(group) < 2 or sum(f["id"] in protected for f in group) > 1:
            continue
        identity_values = [
            [evidence.get(f["id"], {}).get(field, "") for f in group] for field in ("branch", "phone")
        ]
        if any(len(set(values) - {""}) > 1 for values in identity_values):
            continue
        # A door shared by unnumbered counters needs corroborating business identity.
        explicit = bool(unit or (key[1] and not key[1].startswith("osm:")))
        if not explicit and not any(values[0] and len(set(values)) == 1 for values in identity_values):
            continue
        max_distance = 30 if explicit else 12
        if any(distance(a["geometry"]["coordinates"], b["geometry"]["coordinates"]) > max_distance
               for i, a in enumerate(group) for b in group[i + 1:]):
            continue
        primary = min(group, key=lambda f: (f["id"] not in protected,
                      f["properties"]["source"] != "OpenStreetMap", f["id"]))["id"]
        aliases.update((f["id"], primary) for f in group if f["id"] != primary)
    return aliases


def initial_addresses(rows, raw, parser):
    known = {}
    for f in rows:
        p, id = f["properties"], f["id"]
        detail = p.get("detail", "")
        key = address_key(detail, p["district"], parser)
        if id in raw:
            raw_key, label, unit = raw[id]
            if key and (key[0] != raw_key[0] or (key[1] and raw_key[1] and key[1] != raw_key[1])):
                continue
            if not key or key[0] == raw_key[0]:
                best = (raw_key, label) if raw_key[1] else (key or raw_key, detail if key else label)
                known[id] = (*best, unit)
                continue
        if key:
            known[id] = key, detail, ""
    return known


def aligned_address(label, point):
    return dict(address=label, navLng=point[0], navLat=point[1], verifiedDoor=True)


def project_catalog(baseline, known, candidates, doors, protected, parser, evidence=None):
    aliases = duplicates(baseline, known, protected, parser, evidence)
    existing_ids = {f["id"] for f in baseline}
    entries, counts, examples = {}, Counter(), defaultdict(list)
    pool = defaultdict(list)
    street = [f for f in baseline
              if f["id"].startswith(("poi/", "inspection/", "commerce/")) and f["properties"].get("name")]
    tree = STRtree([parser.planar(f["geometry"]["coordinates"]) for f in street])
    for f in street:
        p = f["properties"]
        if f["id"] not in aliases:
            pool[(p["district"], name_key(p["name"], parser))].append(f)
    for f in baseline:
        id, p = f["id"], f["properties"]
        if id in aliases or id not in known:
            continue
        key, label, _ = known[id]
        if not label.startswith(("臺北市", "台北市")) and not label[:1].isdecimal():
            label = "臺北市" + p["district"] + label.removeprefix(p["district"])
        entries[id] = {"address": label}
        point = door_point(doors, key)
        if point and distance(point, f["geometry"]["coordinates"]) <= 45:
            entries[id] = aligned_address(label, point)
            counts["verifiedExistingDoor"] += 1
        elif point:
            counts["doorCoordinateConflict"] += 1
    added = []
    names_by_door = defaultdict(set)
    for candidate in candidates:
        key = address_key(candidate.detail, candidate.district, parser)
        if key:
            names_by_door[key].add(parser.name_token(candidate.name))
    added_keys, added_ids = set(), set()
    for row in candidates:
        if NON_STOREFRONT.search(row.name) or "、" in row.name:
            counts["nonStorefrontOrComposite"] += 1
            continue
        ref = "inspection/" + row.id
        key = address_key(row.detail, row.district, parser)
        if not key:
            counts["assessmentNoOfficialDoor"] += 1
            continue
        point = door_point(doors, key)
        canonical = aliases.get(ref, ref)
        if canonical in existing_ids:
            counts["assessmentAlreadyIndexed"] += 1
            continue
        if not point:
            counts["assessmentNoOfficialDoor"] += 1
            continue
        name = name_key(row.name, parser)
        identity = name, key
        if identity in added_keys or ref in added_ids:
            counts["assessmentDuplicate"] += 1
            continue
        nearby = [f for f in pool[row.district, name]
                  if distance(point, f["geometry"]["coordinates"]) <= 100]
        if len(nearby) == 1:
            f = nearby[0]
            id = f["id"]
            owned_address, _, unit = known.get(id, (None, "", ""))
            if unit:
                counts["assessmentIdentityConflict"] += 1
                continue
            metres = distance(point, f["geometry"]["coordinates"])
            if owned_address == key and metres <= 45:
                entries[id] = {**aligned_address(row.detail, point), "assessmentListed": True}
                known[id] = key, row.detail, ""
                counts["joinedAssessmentToExisting"] += 1
                examples["joined"].append([id, row.name, row.detail])
                continue
        token = parser.name_token(row.name)
        shared_door_brand = any(token != other and parser.name_match(token, other, 0)
                                for other in names_by_door[key])
        if nearby or shared_door_brand:
            counts["assessmentIdentityConflict"] += 1
            continue
        comparable = tree.query(parser.planar(point), predicate="dwithin", distance=45)
        # Similar names are only a reason to hold a new pin. They never merge records.
        if any(parser.name_match(parser.name_token(row.name),
                   parser.name_token(street[i]["properties"]["name"]), distance(point, street[i]["geometry"]["coordinates"]))
               for i in comparable if street[i]["properties"]["district"] == row.district):
            counts["assessmentIdentityConflict"] += 1
            continue
        door_label = re.sub(r"^(?:(?:台|臺)北市" + row.district + r")+", "臺北市" + row.district, row.detail)
        properties = dict(placeId=ref, kind="poi", name=row.name, category="inspection_store",
                          categoryLabel="餐飲店家", district=row.district, detail=door_label, rank=0,
                          source="臺北市政府衛生局", url=parser.INSPECTION_PAGE)
        added.append(dict(type="Feature", id=ref, properties=properties,
                          geometry=dict(type="Point", coordinates=point)))
        added_keys.add(identity)
        added_ids.add(ref)
        entries[ref] = {**aligned_address(door_label, point), "assessmentListed": True}
        examples["added"].append([ref, row.name, row.detail])

    return dict(aliases=aliases, entries=entries, added=added), {
        **counts, "baseline": len(baseline), "duplicatePinsRemoved": len(aliases),
        "addressEntries": len(entries), "officialDoorAligned": sum(r.get("verifiedDoor", False) for r in entries.values()),
        "addedGovernmentStores": len(added), "districtsWithDoorAlignment": dict(Counter(
            f["properties"]["district"] for f in baseline + added if entries.get(f["id"], {}).get("verifiedDoor"))),
        "examples": dict(examples),
    }


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    for field in ("data", "osm", "doors", "inspections", "out", "report"):
        cli.add_argument("--" + field, type=Path, required=True)
    args = cli.parse_args()
    script_dir = Path(__file__).resolve().parent
    spec = spec_from_file_location("inspection", script_dir / "build-city170-inspected-shops.py")
    parser = module_from_spec(spec)
    spec.loader.exec_module(parser)
    baseline = parser.load_json(args.data / "city-place-index.json.gz")["features"]
    districts = {f["properties"]["name"]: make_valid(shape(f["geometry"])) for f in
                 json.loads((args.data / "districts.geojson").read_bytes())["features"]}
    protected = set(re.findall(r"(?:poi|commerce)/(?:node/|way/|relation/)?\d+",
                               (script_dir.parent / "place-photos.js").read_text()))
    protected.update(("commerce/153", "poi/node/6681493385"))
    raw, businesses, evidence = read_osm(args.osm, baseline, parser)
    businesses.update(f["id"] for f in baseline if f["id"].startswith(("commerce/", "inspection/")))
    store_rows = [f for f in baseline if f["id"] in businesses]
    known = initial_addresses(store_rows, raw, parser)
    candidates, inspection = parser.read_inspections(args.inspections)
    wanted = defaultdict(set)
    for (district, road, house), _ in [key for key, _, _ in known.values()] + [
        ((c.district, c.address.road, c.address.house), "") for c in candidates
    ]:
        wanted[district, road].add(house)
    doors, lines = read_doors(args.doors, wanted, districts, parser)
    catalog, report = project_catalog(baseline, known, candidates, doors, protected, parser, evidence)
    businesses.update(f["id"] for f in catalog["added"])
    businesses.difference_update(catalog["aliases"])
    verified = {id for id in businesses if catalog["entries"].get(id, {}).get("verifiedDoor")}
    report.update(officialDoorSourceRows=lines, officialDoorKeysFound=len(doors), osmDirectAddresses=len(raw),
                  candidateStores=len(businesses), storesWithOfficialDoor=len(verified),
                  storesWithoutOfficialDoor=len(businesses - verified),
                  namedStoresWithOfficialDoor=sum(bool(f["properties"].get("name")) and f["id"] in verified
                                                  for f in baseline + catalog["added"]),
                  governmentInspectionRead=dict(inspection), assessedEligible=len(candidates),
                  sources={url: sha(path) for url, path in [
                      ("https://www.openstreetmap.org/copyright", args.osm),
                      (parser.ADDRESS_PAGE, args.doors), (parser.INSPECTION_PAGE, args.inspections)]})
    payload = json.dumps(catalog, ensure_ascii=False, separators=(",", ":"))
    args.out.write_text("export default " + payload + ";\n")
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print({k: v for k, v in report.items() if k not in ("examples", "sources")})


def sha(path):
    with path.open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest()


if __name__ == "__main__":
    main()
