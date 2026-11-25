"""Pack the official Taipei roadside and park tree inventory for the 170 m atlas.

Requires Shapely 2 and pyproj. By default downloads the official bulk CSVs.
Use --road-csv and --park-csv to replay saved official snapshots.
Use --canopies to also write the illustrated species lookup for the same tree rows.
"""

import argparse
from collections import Counter, defaultdict
import csv
import gzip
from hashlib import sha256
from io import StringIO
import json
import math
from pathlib import Path
import re
from typing import NamedTuple
from unicodedata import normalize
from urllib.error import URLError
from urllib.request import urlopen

from pyproj import Transformer
from shapely import make_valid, points
from shapely.geometry import shape
from shapely.strtree import STRtree


ROOT = Path(__file__).resolve().parents[1]
DATASET_URL = "https://data.gov.tw/dataset/128274"
ATTRIBUTION = "臺北市政府工務局公園路燈工程管理處"
LICENSE_URL = "https://data.gov.tw/license"
SOURCES = (
    (0, "road", "https://tppkl.blob.core.windows.net/blobfs/TaipeiTree.csv"),
    (1, "park", "https://tppkl.blob.core.windows.net/blobfs/TaipeiParkTree.csv"),
)
CELL_METRES = 170
CELLS_PER_PACK = 8
CRS = "EPSG:3826"
GEOGRAPHIC = "EPSG:4326"
HEIGHT_NUMBER = r"([0-9]+(?:\.[0-9]+)?|\.[0-9]+)"
HEIGHT_UNIT = r"\s*(?:m|公尺|米)?"
HEIGHT_PATTERN = re.compile(
    f"{HEIGHT_NUMBER}{HEIGHT_UNIT}(?:\\s*[-–—~至]\\s*{HEIGHT_NUMBER}{HEIGHT_UNIT})?",
    re.IGNORECASE,
)
REQUIRED_FIELDS = {"TreeID", "Dist", "TreeType", "TreeHeight", "TWD97X", "TWD97Y", "SurveyDate", "UpdDate"}
FORMS = {
    "palm": frozenset((
        "大王椰子", "亞力山大椰子", "亞歷山大椰子", "蒲葵", "圓葉蒲葵", "黃椰子",
        "散尾葵", "酒瓶椰子", "華盛頓椰子", "羅比親王海棗", "臺灣海棗", "海棗",
        "椰子", "棕櫚", "魚尾葵", "檳榔", "桄榔",
    )),
    "column": frozenset((
        "龍柏", "落羽松", "落羽杉", "水杉", "小葉南洋杉", "肯氏南洋杉", "義大利柏",
    )),
    "broad": frozenset((
        "榕樹", "垂榕", "雀榕", "印度榕", "印度橡膠樹", "茄苳", "欖仁", "欖仁樹",
        "大葉欖仁", "小葉欖仁", "鳳凰木",
    )),
}
FORM_BY_SPECIES = {species: form for form, species_names in FORMS.items() for species in species_names}


# Use exact inventory names. Unpainted species keep the standard crown.
PAINTED_SPECIES = {
    "榕樹": "banyan", "茄苳": "bishopwood", "樟樹": "camphor",
    "楓香": "sweetgum", "臺灣欒樹": "goldenrain", "白千層": "paperbark",
    "落羽松": "cypress", "落羽杉": "cypress",
}


class Tree(NamedTuple):
    source_id: str
    kind: int
    district: str
    survey_date: str
    x: float
    y: float
    height: float
    form: str
    species: str


def parse_height(raw):
    match = HEIGHT_PATTERN.fullmatch(normalize("NFKC", raw).strip())
    if match is None:
        return 0
    low = float(match[1])
    high = float(match[2]) if match[2] else low
    # All published samples use metres. Ignore uncertain values instead of inferring other units.
    return round((low + high) / 2, 1) if 0 < low <= high <= 55 else 0


def parse_source(raw, kind):
    reader = csv.DictReader(StringIO(raw.decode("utf-8-sig"), newline=""))
    if not REQUIRED_FIELDS.issubset(reader.fieldnames or ()):
        raise ValueError(f"Missing official CSV fields: {sorted(REQUIRED_FIELDS - set(reader.fieldnames or ()))}")
    counts = Counter()
    trees = []
    newest_update = ""
    for row in reader:
        counts["rows"] += 1
        newest_update = max(newest_update, row["UpdDate"].strip())
        try:
            x, y = float(row["TWD97X"]), float(row["TWD97Y"])
        except (TypeError, ValueError):
            counts["invalidCoordinate"] += 1
            continue
        if not (math.isfinite(x) and math.isfinite(y) and 0 < x < 1_000_000 and 0 < y < 10_000_000):
            counts["invalidCoordinate"] += 1
            continue
        species = normalize("NFKC", row["TreeType"]).strip().replace("台", "臺")
        trees.append(Tree(
            row["TreeID"].strip(), kind, row["Dist"].strip(), row["SurveyDate"].strip(),
            x, y, parse_height(row["TreeHeight"]), FORM_BY_SPECIES.get(species, "round"), species,
        ))
    return trees, dict(
        fields=reader.fieldnames, newestSourceUpdate=newest_update, sha256=sha256(raw).hexdigest(),
        bytes=len(raw), counts=counts,
    )


def confidence(tree):
    return tree.height > 0, tree.survey_date, tree.form != "round", -tree.kind, tree.source_id


def district_index(path):
    features = json.loads(path.read_bytes())["features"]
    names = [feature["properties"]["name"] for feature in features]
    if len(set(names)) != 12:
        raise ValueError("Expected the official twelve district polygons")
    return names, STRtree([make_valid(shape(feature["geometry"])) for feature in features])


def assign_packs(trees, names, district_tree, known_packs, stats, canopies):
    exporter = Transformer.from_crs(CRS, GEOGRAPHIC, always_xy=True)
    importer = Transformer.from_crs(GEOGRAPHIC, CRS, always_xy=True)
    x, y = ([getattr(tree, key) for tree in trees] for key in ("x", "y"))
    lons, lats = exporter.transform(x, y)
    centers = [(round(lon, 7), round(lat, 7)) for lon, lat in zip(lons, lats)]
    lon, lat = zip(*centers)
    point_indices, district_indices = district_tree.query(points(lon, lat), predicate="covered_by")
    districts = {}
    for row_index, district_index in zip(point_indices.tolist(), district_indices.tolist()):
        district = names[district_index]
        official_name = trees[row_index].district
        previous = districts.get(row_index)
        if previous is None or district == official_name or previous != official_name and district < previous:
            districts[row_index] = district
    # Assign final coordinates to the grid after rounding, including points on a cell boundary.
    target_x, target_y = importer.transform(lon, lat)
    unique_rows = {}
    used_ids = set()
    for i in sorted(districts, key=lambda n: confidence(trees[n]), reverse=True):
        tree = trees[i]
        key = (tree.kind, tree.source_id)
        position = centers[i]
        tree_stats = stats[tree.kind]
        if (tree.source_id and key in used_ids) or position in unique_rows:
            tree_stats["duplicates"] += 1
            continue
        cell_x, cell_y = math.floor(target_x[i] / CELL_METRES), math.floor(target_y[i] / CELL_METRES)
        pack = f"p{cell_x // CELLS_PER_PACK}_{cell_y // CELLS_PER_PACK}"
        if pack not in known_packs:
            raise ValueError(f"Tree location has no registered city pack: {pack}")
        unique_rows[position] = i, pack
        used_ids.add(key)
    for i, tree in enumerate(trees):
        if i not in districts:
            stats[tree.kind]["outsideDistricts"] += 1

    packs = defaultdict(list)
    counts_by_district = {name: Counter() for name in sorted(names)}
    counts_by_form = Counter()
    for position, (i, pack) in sorted(unique_rows.items()):
        tree = trees[i]
        packs[pack].append([*position, tree.height, tree.form, tree.kind])
        if canopies is not None and (code := PAINTED_SPECIES.get(tree.species)):
            canopies[code].append([*position, tree.kind])
        counts_by_district[districts[i]][tree.kind] += 1
        counts_by_form[tree.form] += 1
        stats[tree.kind]["retained"] += 1
        if tree.height == 0:
            stats[tree.kind]["heightFallback"] += 1
        if tree.district != districts[i]:
            stats[tree.kind]["sourceDistrictDiffers"] += 1
    return packs, counts_by_district, counts_by_form


def compact_json(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode()


def write(path, payload):
    temporary = path.with_name(path.name + ".part")
    temporary.write_bytes(payload)
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--road-csv", type=Path)
    parser.add_argument("--park-csv", type=Path)
    parser.add_argument("--districts", type=Path, default=ROOT / "data/districts.geojson")
    parser.add_argument("--index", type=Path, default=ROOT / "data/city170/index.json")
    parser.add_argument("--out", type=Path, default=ROOT / "data/city170-nature")
    parser.add_argument("--canopies", type=Path)
    args = parser.parse_args()

    index = json.loads(args.index.read_bytes())
    if (index["crs"], index["cellSize"], index["origin"]) != (CRS, CELL_METRES, [0, 0]):
        raise ValueError("This script expects the registered 170 m EPSG:3826 grid")
    known_packs = {item["id"] for item in index["packs"]}
    names, district_tree = district_index(args.districts)
    trees = []
    stats = [Counter(), Counter()]
    sources = {}
    for kind, name, url in SOURCES:
        sources[name] = dict(url=url, kind=kind, available=False)
        cached = getattr(args, name + "_csv")
        if cached:
            raw = cached.read_bytes()
        else:
            try:
                with urlopen(url, timeout=45) as response:
                    raw = response.read()
            except (URLError, TimeoutError) as error:
                sources[name]["error"] = str(error)
                continue
        records, detail = parse_source(raw, kind)
        sources[name].update(detail, available=True)
        trees.extend(records)
        stats[kind] = detail["counts"]
    if not trees:
        raise ValueError("No valid source coordinates available")
    canopies = defaultdict(list) if args.canopies else None
    packs, by_district, by_form = assign_packs(trees, names, district_tree, known_packs, stats, canopies)
    if args.canopies:
        payload = dict(
            version=1,
            sourceHashes={name: source["sha256"] for name, source in sources.items() if source["available"]},
            species=dict(sorted(canopies.items())),
        )
        write(args.canopies, gzip.compress(compact_json(payload), compresslevel=9, mtime=0))

    args.out.mkdir(parents=True, exist_ok=True)
    for pack in sorted(known_packs):
        write(args.out / (pack + ".json.gz"), gzip.compress(compact_json(packs[pack]), compresslevel=6, mtime=0))
    summary = dict(
        version=1, datasetUrl=DATASET_URL, attribution=ATTRIBUTION, licenseUrl=LICENSE_URL,
        sourceCRS=CRS, outputCRS=GEOGRAPHIC, cellSize=CELL_METRES, packSizeMetres=CELLS_PER_PACK * CELL_METRES,
        fields=["lon", "lat", "heightM", "form", "kind"], kinds={"0": "行道樹", "1": "公園樹"},
        sources=sources, count=sum(stats[kind]["retained"] for kind in (0, 1)),
        packCount=len(known_packs), packsWithTrees=sum(bool(rows) for rows in packs.values()),
        districts={name: dict(road=counts[0], park=counts[1], total=sum(counts.values()))
                   for name, counts in by_district.items()},
        forms=dict(sorted(by_form.items())),
        heightRule="Positive metres up to 55; use the midpoint for a bounded range, or 0 when uncertain.",
        formRule="Exact species allowlist for palm, column and broad; round is the neutral illustration.",
        duplicateRule="One record per source kind and TreeID or rounded position, preferring known height and newer survey.",
    )
    write(args.out / "summary.json", (json.dumps(summary, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode())
    print(json.dumps(dict(count=summary["count"], districts=summary["districts"], forms=by_form), ensure_ascii=False))


if __name__ == "__main__":
    main()
