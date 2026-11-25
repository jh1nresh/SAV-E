"""Locate existing Taipei shop pins on surveyed walls using the city's friendly store list.

Usage: build-taipei-friendly-frontages.py DATA TAIPEI_OSM_JSON_GZ FRIENDLY_CSV OUTPUT_JS
Source: Taipei City Office of Commerce, 2026-07-20 Chinese point inventory.
"""

import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import re
import runpy

from shapely import Point, STRtree
from shapely.geometry import shape

HERE = Path(__file__).resolve().parent
M = runpy.run_path(str(HERE / 'build-taipei-registered-frontages.py'))
EDGE, C, F, G, S, A, read = (M[key] for key in ('EDGE', 'C', 'F', 'G', 'S', 'A', 'read'))
SOURCE = 'https://data.taipei/dataset/detail?id=d807396c-e41f-4005-be42-0160280783a1'
SHA256 = '301a3fe1b08dbcf2fc478eeaaa4a19886451df4a7b6f507ceca0ab09b67126c5'
LOCATOR = 'city-friendly-store-coordinate'
# Explicit public listings for these exact places support the window illustrations.
SPECIALTIES = {
    'poi/node/8378684488': ('hot_pot', 'https://findbiz.nat.gov.tw/fts/business/82308392/90100000000019014610'),
    'poi/node/10259602106': ('breakfast', 'https://www.friendlystore.taipei/store/tw/pg1/3/company/8568'),
    'poi/node/12412924771': ('coffee_shop', 'https://friendlystore.taipei/store/tw/pg1/7/company/8598'),
}


def source_index(stream):
    rows = csv.DictReader(stream)
    if not {'友善店家名稱', '地址', '經度', '緯度'}.issubset(rows.fieldnames or ()):
        raise ValueError('Unexpected Taipei friendly store fields')
    records = defaultdict(set)
    for entry in rows:
        detail = re.sub(r'^\d{3,6}(?=臺北市)', '', A['clean'](entry['地址']))
        district = detail[3:6]
        name = M['identity'](entry['友善店家名稱'])
        if district not in M['DISTRICTS'] or len(name) < 2:
            continue
        address = M['registry_address'](detail, district)
        if not address:
            continue
        try:
            lon, lat = float(entry['經度']), float(entry['緯度'])
        except (TypeError, ValueError):
            continue
        if 121.4 < lon < 121.7 and 24.9 < lat < 25.25:
            records[name, district].add((address, (lon, lat)))
    return records


def ground_evidence(address, mapped, original_ground):
    explicit = address.floor in A['GROUND']
    if (address.floor and not explicit) or (mapped and mapped[:2] != address[:2]):
        return None
    if explicit:
        return 'city-friendly-store-ground-floor'
    return 'original-ground-floor-and-city-list' if mapped and original_ground else None


def build(data, osm, friendly):
    if hashlib.sha256(friendly.read_bytes()).hexdigest() != SHA256:
        raise ValueError('Unexpected Taipei friendly store snapshot')
    with friendly.open(encoding='utf-8-sig', newline='') as stream:
        source = source_index(stream)
    packs, search, existing = C['current_rows'](data)
    for filename in ('taipei-compact-frontages.js', 'taipei-edge-frontages.js', 'taipei-registered-frontages.js'):
        module = (HERE.parent / filename).read_text()
        existing.extend(json.loads(module.split('=', 1)[1].strip().removesuffix(';')))
    placed = {row['id'] for row in existing}
    manifest, places, streets, tags = C['source_stores'](data, osm)
    roads = {road.id: road for road in streets.roads}
    stores = [store for store in places if store.id in search]
    points = [F['project'](store.geometry) for store in stores]
    tenants = STRtree(points)
    districts = {f['properties']['name']: F['project'](shape(f['geometry']))
                 for f in read(data / 'districts.geojson')['features']}
    survey = F['Survey'](data)
    footprints = S['SurveyFootprints'](survey, data)
    addresses, neighbors, records = Counter(), defaultdict(list), []
    for store, point in zip(stores, points, strict=True):
        district = search[store.id][1]
        original = tags[store.id.split('/', 1)[1]] if store.id.startswith('poi/') else store.properties
        mapped = G['shop_address'](store, original, district)
        if mapped:
            addresses[district, mapped.road, mapped.house] += 1
            neighbors[district, mapped.road, mapped.house.partition('-')[0]].append((store, point, mapped))
        records.append((store, point, district, original, mapped))
    counts = Counter()
    proposed = []
    for store, point, district, original, mapped in records:
        name = store.properties['name']
        if (store.id in placed or district not in districts or F['floor_status'](store, original)
                or F['dihua_duplicate'](store)
                or A['INDOOR_VENUE'].search(A['address_text'](name + ' ' + store.properties['detail']))):
            continue
        matches = source.get((M['identity'](name), district), ())
        if len(matches) != 1:
            continue
        counts['same-name-and-district'] += 1
        address, coordinate = next(iter(matches))
        explicit_ground = mapped and S['same_address_floor'](store, original, district, mapped)
        evidence = ground_evidence(address, mapped, explicit_ground)
        if not evidence:
            continue
        marker = F['project'](Point(*coordinate))
        if not (.10 < point.distance(marker) <= (8 if mapped else 4) and districts[district].covers(marker)):
            continue
        counts['nearby-and-ground-documented'] += 1
        key = district, address.road, address.house
        if (addresses[key] > int(mapped is not None) or EDGE['has_nearby_alias'](store, point, tenants, stores)
                or G['nearby_identity_conflict'](store, point, address,
                    neighbors[district, address.road, address.house.partition('-')[0]])):
            continue
        found = M['measured_bay'](store, point, [(None, marker, {})], F['street_name'](address.road),
                                  roads, survey, streets, footprints, tags, locator=LOCATOR)
        if found is None:
            continue
        site, row, wall = found
        pack = F['pack_for'](site, manifest)
        if pack not in packs or not districts[district].covers(site):
            continue
        if any(stores[j].id != store.id for j in tenants.query(wall, predicate='dwithin', distance=3.75)):
            continue
        # Authored display facts stay with the frontage layer and never rewrite the source pin.
        row.pop('detail', None)
        row.update(pack=pack, district=district, groundEvidence=evidence, evidence='friendly-store-measured-bay')
        specialty = SPECIALTIES.get(store.id)
        if specialty is not None:
            row.update(cuisine=specialty[0], displaySource=specialty[1])
        proposed.append((site, row, district, store))
    rejected = F['overlapping_slots']([(None, row, None, None) for row in existing] + proposed)
    accepted = [row for i, (_, row, _, _) in enumerate(proposed, len(existing)) if i not in rejected]
    counts['accepted'] = len(accepted)
    return sorted(accepted, key=lambda row: row['id']), counts


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('data', 'osm', 'friendly', 'output'):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    rows, counts = build(args.data, args.osm, args.friendly)
    args.output.write_text(
        '// Taipei City Office of Commerce · Taipei friendly store list.\n'
        + '// '+SOURCE+' · Government Open Data License 1.0.\n'
        + 'export const friendlyFronts=[\n'
        + ',\n'.join(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for row in rows)
        + '\n];\n', encoding='utf-8')
    print(json.dumps({'counts': counts, 'districts': Counter(row['district'] for row in rows)}, ensure_ascii=False))
