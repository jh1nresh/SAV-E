"""Extract a padded Taipei map from a Geofabrik PBF, with complete way references."""
import argparse
from itertools import chain
import json
from pathlib import Path

import osmium
from shapely.geometry import shape
from shapely.ops import unary_union


def make_node(row):
    result = {'id': row.id, 'type': 'node', 'lat': row.location.lat, 'lon': row.location.lon}
    tags = dict(row.tags)
    if tags:
        result['tags'] = tags
    return result


def make_way(row, refs):
    result = {'id': row.id, 'type': 'way', 'nodes': refs}
    tags = dict(row.tags)
    if tags:
        result['tags'] = tags
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pbf', type=Path)
    parser.add_argument('out', type=Path)
    parser.add_argument('--districts', default=Path('data/districts.geojson'), type=Path)
    args = parser.parse_args()

    boundaries = json.loads(args.districts.read_text())['features']
    area = unary_union([shape(f['geometry']) for f in boundaries])
    west, south, east, north = area.buffer(.008).bounds
    nodes, ways, relations = {}, {}, {}
    referenced_ways = set()

    class Select(osmium.SimpleHandler):
        def node(self, row):
            if row.location.valid() and west <= row.location.lon <= east and south <= row.location.lat <= north:
                nodes[row.id] = make_node(row)

        def way(self, row):
            refs = [n.ref for n in row.nodes]
            if any(n in nodes for n in refs):
                ways[row.id] = make_way(row, refs)

        def relation(self, row):
            tags = dict(row.tags)
            if tags.get('type') != 'multipolygon':
                return
            if not any(key in tags for key in ('building','building:part','natural','waterway','landuse','leisure','amenity','man_made')):
                return
            members = [{'ref': m.ref, 'type': 'way', 'role': m.role}
                       for m in row.members if m.type == 'w']
            if not any(m['ref'] in ways for m in members):
                return
            relations[row.id] = {'id':row.id, 'type':'relation', 'members':members, 'tags':tags}
            referenced_ways.update(m['ref'] for m in members)

    Select().apply_file(str(args.pbf))
    additional_ways = referenced_ways - ways.keys()

    class CompleteWays(osmium.SimpleHandler):
        def way(self, row):
            if row.id in additional_ways:
                ways[row.id] = make_way(row, [node.ref for node in row.nodes])

    if additional_ways:
        CompleteWays().apply_file(str(args.pbf))

    referenced_nodes = {n for row in ways.values() for n in row['nodes']}
    additional_nodes = referenced_nodes - nodes.keys()

    class CompleteNodes(osmium.SimpleHandler):
        def node(self, row):
            if row.id in additional_nodes and row.location.valid():
                nodes[row.id] = make_node(row)

    if additional_nodes:
        CompleteNodes().apply_file(str(args.pbf))

    incomplete = {k for k, way in ways.items() if any(n not in nodes for n in way['nodes'])}
    for key in incomplete:
        del ways[key]
    for key in list(relations):
        if any(member['ref'] not in ways for member in relations[key]['members']):
            del relations[key]
    kept_nodes = [node for key, node in nodes.items() if key in referenced_nodes or node.get('tags')]
    receipt = {'bounds':[west,south,east,north], 'nodes':len(kept_nodes), 'ways':len(ways),
               'multipolygons':len(relations), 'incompleteWays':len(incomplete), 'pbf':args.pbf.name}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.out.with_suffix('.part')
    with temporary.open('w') as output:
        output.write('{"elements":[')
        for i, element in enumerate(chain(kept_nodes, ways.values(), relations.values())):
            if i:
                output.write(',')
            output.write(json.dumps(element,ensure_ascii=False,separators=(',',':')))
        output.write('],"source":')
        output.write(json.dumps(receipt,separators=(',',':')))
        output.write('}')
    temporary.replace(args.out)
    print(json.dumps(receipt,ensure_ascii=False),flush=True)


if __name__ == '__main__':
    main()
