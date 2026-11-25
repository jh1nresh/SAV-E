"""Extract factual names and floor memberships from the mall's public directory.

The snapshot directory contains {B1,1F,...,6F}.json from
https://ws.taipei-101.com.tw/api/v1/shopping/floor/detail/brands?lang=zh-tw&floor=FLOOR_1F
(substitute the floor) and food.json from /api/v1/food/search?lang=zh-tw.
The directory provides floor membership, not a store coordinate or a unit plan.
"""
from pathlib import Path
import argparse
import json
import re
import unicodedata
from urllib.parse import quote

FLOORS = ['B1', '1F', '2F', '3F', '4F', '5F', '6F']
WEBSITE = 'https://www.taipei-101.com.tw/tw/'


def build(snapshot):
    directory = {floor: {} for floor in FLOORS}

    def add(floor, row, food=False):
        name = ' '.join(row['title' if food else 'name'].split())
        identity = row['id'].strip()
        if not name or not identity:
            raise ValueError(f'Missing store identity for {floor}')
        key = re.sub(r'\s+', '', unicodedata.normalize('NFKC', name)).casefold()
        page = 'food/content/' if food else 'shopping/brandsearch/content/'
        directory[floor].setdefault(key, dict(name=name, url=WEBSITE + page + quote(identity, safe='')))

    for floor in FLOORS:
        brands = json.loads((snapshot / (floor + '.json')).read_bytes())
        for group in brands.values():
            for row in group:
                if floor in [f.strip() for f in row['floor'].split(',')]:
                    add(floor, row)
    for row in json.loads((snapshot / 'food.json').read_bytes()):
        for floor in row['floor'].split(','):
            if floor.strip() in directory:
                add(floor.strip(), row, food=True)
    return {floor: [group[k] for k in sorted(group)] for floor, group in directory.items()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    rows = build(args.snapshot)
    args.output.write_text('// Factual listings from the TAIPEI 101 official mall and food guides.\n'
                           'export const officialFloorDirectory = ' + json.dumps(rows, ensure_ascii=False, indent=1) + ';\n')
    print({level: len(stores) for level, stores in rows.items()})
