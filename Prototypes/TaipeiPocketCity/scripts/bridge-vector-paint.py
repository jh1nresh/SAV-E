"""Match complete road decks to the z14 transportation geometry used by the map."""
from collections import defaultdict
import gzip
import json
import math

from mapbox_vector_tile.decoder import TileData
from shapely import STRtree, union_all
from shapely.geometry import LineString, shape

MOTOR = {'motorway', 'link', 'trunk', 'primary', 'secondary', 'tertiary',
         'minor', 'street', 'street_limited', 'service', 'track'}
TOLERANCE = 1.1  # z14 grid step in Taipei is ~0.54 m, including line simplification.


def bridge_strokes(directory, metres):
    lines, grades = defaultdict(list), defaultdict(set)
    index = json.loads((directory / 'index.json').read_bytes())
    shared = json.loads((directory.parent / 'index.json').read_bytes())
    paths = {(x,y): directory.parent / f'{x}-{y}.pbf' for x,y in shared['tiles']}
    paths.update({(x,y): directory / f'{z}-{x}-{y}.pbf' for z,x,y in index['tiles'] if z == 14})
    for (tx, ty), path in sorted(paths.items()):
        raw = path.read_bytes()
        tile = TileData(gzip.decompress(raw) if raw.startswith(b'\x1f\x8b') else raw)
        for layer in tile.tile.layers:
            if layer.name != 'transportation':
                continue
            def lonlat(x, y):
                wx = (tx+x/layer.extent)/2**14
                wy = (ty+y/layer.extent)/2**14
                return (wx*360-180, math.degrees(math.atan(math.sinh(math.pi*(1-2*wy)))))
            for f in layer.features:
                props = {layer.keys[k]: tile.parse_value(layer.values[v])
                         for k, v in zip(f.tags[::2], f.tags[1::2])}
                if f.type != 2 or props.get('brunnel') != 'bridge' or props.get('class') not in MOTOR:
                    continue
                geometry = shape(tile.parse_geometry(f.geometry, f.type, layer.extent, True, lonlat))
                lines[f.id].append(metres(geometry))
                grades[f.id].add(props.get('layer', 0))
    return {k: union_all(parts) for k, parts in lines.items()}, grades


def paint_ids(line, grade, tree, ids, grades):
    # A feature-state ID affects every tile/part. Only suppress IDs fully
    # contained by this deck, and only when those IDs cover its whole length.
    area = line.buffer(TOLERANCE)
    hits = tree.query(area, predicate='intersects')
    owned = [i for i in hits if grades[ids[i]] == {grade} and area.covers(tree.geometries[i])]
    if not owned or not union_all(tree.geometries[owned]).buffer(TOLERANCE).covers(line):
        return []
    if any(tree.geometries[i].intersection(area).length > 3*TOLERANCE
           for i in set(hits)-set(owned)):
        return []  # A merged base stroke also follows this deck but continues beyond it.
    return sorted(ids[i] for i in owned)

def certify(spans, grades, directory, metres, reasons):
    strokes, tile_grades = bridge_strokes(directory, metres)
    ids = list(strokes)
    tree = STRtree(list(strokes.values()))
    lines = [metres(LineString(span['line'])) for span in spans]
    footprints = [line.buffer(span['width']/2, cap_style='flat', join_style='mitre')
                  for span, line in zip(spans, lines)]
    surfaces = STRtree(footprints)
    certified = []
    for i, (span, line, deck) in enumerate(zip(spans, lines, footprints)):
        if any(j != i and deck.intersection(footprints[j]).area > .01
               for j in surfaces.query(deck, predicate='intersects')):
            reasons['overlapping cartographic decks'] += 1
            continue
        matches = paint_ids(line, grades[span['id']], tree, ids, tile_grades)
        if not matches:
            reasons['incomplete, shared or stacked base stroke'] += 1
            continue
        certified.append(dict(span, paintIds=matches))
    return certified
