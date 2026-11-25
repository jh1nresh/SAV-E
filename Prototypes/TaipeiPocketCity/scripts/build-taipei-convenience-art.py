"""Build storefront style assignments from the frozen Taipei atlas and OSM tags.

Usage: python build-taipei-convenience-art.py DATA TAIPEI_OSM_JSON_GZ OUTPUT_JS
"""

import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

import ijson


WEB = Path(__file__).resolve().parents[1]
CHAINS = {
    "Q259340": ("7-Eleven", "seven"),
    "Q10891564": ("全家便利商店", "family"),
    "Q11326216": ("萊爾富", "hilife"),
    "Q10851968": ("OK超商", "ok"),
    "Q109676747": ("蝦皮店到店", "shopee"),
}
FRONTAGE_SCRIPT = """
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
import {completeFrontagePack} from './taipei-frontage-pack.js';
const directory=process.argv[1];
const base=join(directory,'city170-frontages');
const {packs}=JSON.parse(readFileSync(join(directory,'city170/index.json')));
const selected=packs.flatMap(({id})=>{
  const rows=JSON.parse(gunzipSync(readFileSync(join(base,id+'.json.gz'))));
  return completeFrontagePack(id,rows)
    .filter(row=>row.category==='convenience'&&row.id.startsWith('poi/'))
    .map(({id,name})=>[id,name]);
});
process.stdout.write(JSON.stringify(selected));
"""


def chain(tags, map_name):
    if tags.get("shop") != "convenience":
        return None
    known = CHAINS.get(tags.get("brand:wikidata"))
    if known and tags.get("brand") == known[0]:
        return known[1]
    # The service uses a unique full storefront name on the official locator.
    # Earlier OSM entries omit brand metadata. Require exact matching public
    # names from both the raw POI and the frontage and no competing brand tag.
    if (
        not tags.get("brand") and not tags.get("brand:wikidata")
        and tags.get("name") == map_name == "蝦皮店到店"
    ):
        return "shopee"
    return None


def build(data, osm, output):
    saved = subprocess.check_output(
        ["node", "--input-type=module", "-e", FRONTAGE_SCRIPT, str(data.resolve())],
        cwd=WEB,
    )
    frontages = dict(json.loads(saved))
    manifest = json.loads((data / "city170/index.json").read_text())
    digest = manifest["source"]["provenance"]["taipeiExtractUncompressedSHA256"]
    with gzip.open(osm, "rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != digest:
            raise ValueError("OSM extract differs from the packed Taipei atlas")
    groups = defaultdict(list)
    with gzip.open(osm, "rb") as stream:
        for feature in ijson.items(stream, "elements.item", use_float=True):
            kind, number = feature["type"], feature["id"]
            place_id = f"poi/{kind}/{number}"
            if place_id not in frontages:
                continue
            style = chain(feature.get("tags", {}), frontages[place_id])
            if style:
                groups[style, kind].append(number)
    contents = [
        "// Generated from the frozen Taipei OSM extract and matched 170 m storefronts.",
        "// Regenerate with scripts/build-taipei-convenience-art.py.",
        "export const storeBrandGroups=[",
    ]
    totals = Counter()
    for (style, kind), ids in sorted(groups.items()):
        contents.append("  " + json.dumps([style, kind, " ".join(map(str, sorted(ids)))], separators=(",", ":")) + ",")
        totals[style] += len(ids)
    contents.extend(["];", ""])
    output.write_text("\n".join(contents), encoding="utf-8")
    print(json.dumps({"matched": sum(totals.values()), "brands": totals}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("data", "osm", "output"):
        parser.add_argument(key, type=Path)
    args = parser.parse_args()
    build(args.data, args.osm, args.output)
