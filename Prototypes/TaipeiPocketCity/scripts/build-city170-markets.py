"""Build the official Taipei market-area points from the Market Administration CSV.

Use Shapely 2. The default input is the Taipei Open Data CSV URL. Pass a saved
copy with --csv to replay a specific snapshot. The output records its SHA-256.
"""

import argparse
import csv
import gzip
from hashlib import sha256
from io import StringIO
import json
from pathlib import Path
import re
from urllib.request import urlopen

from shapely.geometry import Point, shape


ROOT = Path(__file__).resolve().parents[1]
SOURCE = "臺北市市場處"
DATASET_URL = "https://data.taipei/dataset/detail?id=c013d9ec-a550-46bd-ac60-45f085930706"
CSV_URL = (
    "https://data.taipei/api/frontstage/tpeod/dataset/resource.download"
    "?rid=4874f750-b972-4c42-ad76-986960670c70"
)
FACILITY_URL = (
    "https://www.tcma.gov.taipei/News_Content.aspx"
    "?n=FAC14AD2DE4E01A4&sms=32F7BA052C5CA548&s="
)
# Snapshot seqno, CSV name and Market Administration facility IDs. Optional
# display names use the familiar names shown on the official facility pages.
FACILITIES = {
    1: ("廣州街", "BEB4A81BADE97671", "廣州街夜市"),
    2: ("西園路二段140巷", "A83FEE5A1EEA5746"),
    3: ("梧州街", "2468AE6F2D3A724A", "梧州街夜市"),
    4: ("德昌街", "EAA1963C0B19BA0C"),
    5: ("西昌街", "B9D9C9236194FD6C", "西昌街夜市"),
    6: ("東三水街", "0D229E3F22691D88", "東三水市場"),
    7: ("華西街(華西街商圈區協會)", "37321FAC116DD8EE", "華西街觀光夜市"),
    8: ("艋舺夜市(俗稱萬華夜市)", "E822B5A7B1948512", "艋舺夜市"),
    9: ("成德市場外攤", "A25606A8FB78E1E5"),
    10: ("中坡市場", "51785DE718C4F140"),
    11: ("饒河街觀光夜市", "0CFD6ED2C96E9CC4"),
    12: ("民權東路3段103巷", "C50B0ECF9904C02C", "民權東路三段103巷"),
    13: ("南京東路5段59巷27弄", "25D93B429E4EE358", "武昌市場"),
    14: ("新東街", "AFBAC5971526F23F", "草埔市場"),
    15: ("新北投", "FA1745CD674DB8C2", "復興市場"),
    16: ("關渡宮", "C12B6A8B1659C635", "關渡宮攤販集中場"),
    17: ("石牌商城", "3DDC1C1C5A31A24F"),
    18: ("景美街（日）", "AB1DE5B27849FDC1", "景美街日市"),
    19: ("景美夜市", "C784E7F773A38D3E"),
    20: ("興德路兩側", "2D29EC912B9A48B8", "興德市場"),
    21: ("湖光", "BE8704607666CBC8", "湖光市場"),
    22: ("麗山", "A9BB1B0A83D75AB7", "麗山市場"),
    23: ("公館夜市", "01DFBEEC7B87B051"),
    24: ("城中", "B682F8B64610E680", "城中市場"),
    25: ("東門市場外", "2C3A708DA5E41103", "東門外市場"),
    26: ("南機場", "8B537F8C6C708E0E", "南機場夜市"),
    27: ("遼寧街〈朱崙公園〉", "378B3348E6FD63C5", "遼寧街夜市"),
    28: ("晴光", "FA0ACEB102155AD4", "晴光市場"),
    29: ("雙城街", "379543A1C1FBF20B", "雙城夜市"),
    30: ("五常街", "3CEF031323CA996B"),
    31: ("榮星", "85DAA96C5B392AD3", "榮星攤販集中場"),
    32: ("四平街", "CB6640102521B1D8", "四平街攤販集中場"),
    33: ("民生西路45巷(俗稱雙連市集)", "64409AADB4FA491D", "雙連市集"),
    34: ("民族東路410巷(俗稱榮濱商圈)", "B1CCEBDF43409083", "榮濱商圈"),
    35: ("臨江街", "9A5FBF2E607D28CA", "臨江街日市與觀光夜市"),
    36: ("臨江街日市", "5D43CC45A3FC779A"),
    37: ("安居街9巷", "06603833BEF3153D"),
    38: ("建國假日玉市(中華玉器藝術文化交流協會)", "0890E203237B99DC", "建國假日玉市"),
    39: ("建國假日玉市(臺北市玉石文物協進會)", "9F4FABC9AE28984A"),
    40: ("建國假日藝文特區", "259B87126BF1D05D"),
    41: ("延平北路3段", "3465654D959E7A0E", "延三夜市"),
    42: ("寧夏夜市", "0C985156C3DB7335"),
    43: ("太平市場", "1D7822C4EC9AEF39"),
    44: ("華榮街", "98D1493EC1FDC69B", "華榮市場"),
    45: ("社中街", "84412DD8D8AC6FA0"),
    46: ("福華廣場", "015CE7C5C565E624"),
    47: ("士林夜市", "AF2DC775A3AA076A"),
}
# Both coordinates on these reviewed rows are decimal degrees whose digits
# were split into the CSV's DMS fields. Ordinary DMS is invalid or outside
# Taipei there. The reconstructed points agree with the listed market areas.
DECIMAL_COORDINATES = {8, 19, 23, 33, 34, 43, 47}
SAME_SITE = {36: 35, 39: 38}
DMS = re.compile(r"(\d+)°(\d{2})'(\d{2}\.\d+)")


def coordinate(raw, decimal):
    matched = DMS.fullmatch(raw.strip())
    if not matched:
        raise ValueError(f"Unrecognized coordinate {raw!r}")
    degree, minute, second = matched.groups()
    if decimal:
        return float(f"{degree}.{minute}{second.replace('.', '')}")
    if int(minute) >= 60 or float(second) >= 60:
        raise ValueError(f"Invalid DMS coordinate {raw!r}")
    return round(int(degree) + int(minute) / 60 + float(second) / 3600, 7)


def district_shapes(path):
    districts = json.loads(path.read_text())["features"]
    return {f["properties"]["name"]: shape(f["geometry"]) for f in districts}


def build(raw, districts):
    rows = {}
    for row in csv.DictReader(StringIO(raw.decode("cp950"))):
        number = int(row["seqno"])
        facility = FACILITIES.get(number)
        if number in rows or not facility or row["xbody"] != facility[0]:
            raise ValueError(f"Changed official market record {number}; review its source")
        official_name, key, *display = facility
        district = row["stitle"] + "區"
        position = [
            coordinate(row[field], number in DECIMAL_COORDINATES)
            for field in ("GTag_longitude", "GTag_latitude")
        ]
        if not districts[district].covers(Point(position)):
            raise ValueError(f"Market {number} ({official_name}) is outside {district}")
        rows[number] = {
            "type": "Feature",
            "id": f"tcma-market-{number}",
            "geometry": {"type": "Point", "coordinates": position},
            "properties": {
                "kind": "market-area",
                "categoryLabel": "攤販集中場",
                "name": display[0] if display else official_name,
                "detail": district + " · " + row["xAddress"].strip().removeprefix("臺北市" + district),
                "source": SOURCE,
                "url": FACILITY_URL + key,
                "district": district,
                "sourceRecordIds": [number],
            },
        }

    if rows.keys() != FACILITIES.keys():
        raise ValueError(f"Missing official market records: {sorted(FACILITIES.keys() - rows.keys())}")

    features = []
    for number, feature in sorted(rows.items()):
        if number in SAME_SITE:
            first = rows.get(SAME_SITE[number])
            if not first or feature["geometry"] != first["geometry"]:
                raise ValueError(f"Market {number} no longer shares the expected location")
            first["properties"]["sourceRecordIds"].append(number)
        else:
            features.append(feature)

    return {
        "type": "FeatureCollection",
        "attribution": f"{SOURCE}《臺北市攤販集中場》",
        "datasetUrl": DATASET_URL,
        "downloadUrl": CSV_URL,
        "csvSha256": sha256(raw).hexdigest(),
        "geometryMeaning": "攤販集中場代表位置",
        "features": features,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, help="saved original government CSV")
    parser.add_argument("--districts", type=Path, default=ROOT / "data/districts.geojson")
    parser.add_argument("--out", type=Path, default=ROOT / "data/city170-markets.json.gz")
    args = parser.parse_args()
    if args.csv:
        raw = args.csv.read_bytes()
    else:
        with urlopen(CSV_URL, timeout=30) as response:
            raw = response.read()
    data = build(raw, district_shapes(args.districts))
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode()
    args.out.write_bytes(gzip.compress(payload, mtime=0))
    print(f"{len(data['features'])} market areas from {data['csvSha256']}")


if __name__ == "__main__":
    main()
