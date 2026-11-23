"""Fit lowland street elevations without altering protected terrain features."""
from collections import defaultdict
import gzip
import json

import ijson
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter
from scipy.spatial import cKDTree
from shapely.geometry import LineString, Polygon, box
from shapely.ops import polygonize, unary_union


STREETS = {'trunk', 'primary', 'secondary', 'tertiary', 'residential', 'unclassified',
           'living_street', 'pedestrian', 'service'}
WATERWAYS = {'river', 'canal', 'stream', 'ditch', 'drain'}


def water_area(tags):
    return (tags.get('natural') == 'water' or tags.get('waterway') == 'riverbank'
            or tags.get('landuse') in {'reservoir', 'basin'})


def mapped_surfaces(osm, raster_shape, to_pixel, metres, work):
    ways = {}
    classified = {}
    relations = []
    with gzip.open(osm, 'rb') as source:
        for record in ijson.items(source, 'elements.item', use_float=True):
            tags = record.get('tags', {})
            if record['type'] == 'relation' and water_area(tags):
                relations.append(record.get('members', []))
            if record['type'] != 'way':
                continue
            ident = record['id']
            ways[ident] = record['nodes']
            highway, railway = tags.get('highway'), tags.get('railway')
            layer = tags.get('layer', '0')
            bridge = tags.get('man_made') == 'bridge' or tags.get('bridge', 'no') != 'no' or (
                (highway or railway) and layer.lstrip('+').isdigit() and int(layer) > 0)
            levels = tags.get('level', '').split(';')
            below_ground = all(level.startswith('-') and level[1:].replace('.', '', 1).isdigit() for level in levels)
            surface = tags.get('tunnel', 'no') == 'no' and tags.get('location') != 'underground' and not below_ground
            if bridge or water_area(tags) or highway in STREETS or tags.get('waterway') in WATERWAYS:
                classified[ident] = (tags, bool(bridge), surface)
    needed_ways = set(classified)
    needed_ways.update(member['ref'] for row in relations for member in row if member['type'] == 'way')
    ways = {key: ways[key] for key in needed_ways if key in ways}
    needed_nodes = {node for refs in ways.values() for node in refs}
    locations = {}
    with gzip.open(osm, 'rb') as source:
        for record in ijson.items(source, 'elements.item', use_float=True):
            if record['type'] != 'node':
                break
            if record['id'] in needed_nodes:
                locations[record['id']] = (record['lon'], record['lat'])

    roads, bridges, waterways = [Image.new('1', raster_shape[::-1]) for _ in range(3)]
    street_pen, bridge_pen, water_pen = map(ImageDraw.Draw, (roads, bridges, waterways))
    water_polygons = []
    named_roads = []
    counts = dict(roads=0, bridgeWays=0, waterWays=0, waterRelations=0)
    for ident, (tags, bridge, surface) in classified.items():
        geographic = [locations[node] for node in ways[ident]]
        if len(geographic) < 2:
            continue
        line = [to_pixel(*point) for point in geographic]
        if bridge:
            bridge_pen.line(line, fill=1, width=max(2, round(20/metres)))
            if tags.get('man_made') == 'bridge' and len(line) >= 4 and line[0] == line[-1]:
                bridge_pen.polygon(line, fill=1)
            counts['bridgeWays'] += 1
        if surface and water_area(tags) and len(line) >= 4 and line[0] == line[-1]:
            water_polygons.append(Polygon(line).buffer(0))
            counts['waterWays'] += 1
        if surface and tags.get('waterway') in WATERWAYS and not bridge:
            widths = {'river': 34, 'canal': 21, 'stream': 14, 'ditch': 9, 'drain': 9}
            water_pen.line(line, fill=1, width=max(1, round(widths[tags['waterway']]/metres)))
        if surface and not bridge and tags.get('highway') in STREETS:
            width = 16 if tags['highway'] in {'trunk', 'primary', 'secondary'} else 8
            street_pen.line(line, fill=1, width=max(1, round(width/metres)))
            counts['roads'] += 1
            name = tags.get('name:zh-Hant') or tags.get('name:zh') or tags.get('name')
            if name:
                named_roads.append({'id':ident, 'name':name, 'points':geographic})

    for members in relations:
        rings = defaultdict(list)
        for member in members:
            refs = ways.get(member['ref'])
            if member['type'] == 'way' and refs and len(refs) >= 2:
                role = 'inner' if member['role'] == 'inner' else 'outer'
                rings[role].append(LineString([to_pixel(*locations[node]) for node in refs]))
        outer = unary_union(list(polygonize(rings['outer'])))
        if not outer.is_empty:
            water_polygons.append(outer.difference(unary_union(list(polygonize(rings['inner'])))))
            counts['waterRelations'] += 1
    paint_area(water_pen, unary_union(water_polygons))
    (work/'named-roads.json').write_text(json.dumps(named_roads, ensure_ascii=False, separators=(',', ':')))
    return np.asarray(roads), np.asarray(bridges), np.asarray(waterways), counts


def smoothstep(lo, hi, values):
    t = np.clip((values-lo)/(hi-lo), 0, 1)
    return t*t*(3-2*t)


def paint_area(pen, area):
    if area.is_empty:
        return
    if area.geom_type != 'Polygon':
        for part in area.geoms:
            paint_area(pen, part)
        return
    pen.polygon(list(area.exterior.coords), fill=1)
    for hole in area.interiors:
        pen.polygon(list(hole.coords), fill=0)


def inhabited_grade(points, candidate, origin, metres):
    """Fit robust neighbourhood grades in row bands, then smooth through their joins."""
    tree = cKDTree(points[:, :2])
    x0, y0 = origin
    height = np.zeros(candidate.shape, dtype=np.float32)
    confidence = np.zeros_like(height)
    for start in range(0, height.shape[0], 48):
        rows, columns = np.nonzero(candidate[start:start+48])
        rows += start
        if not len(rows):
            continue
        positions = np.column_stack((columns+x0+.5, rows+y0+.5))
        distances, nearest = tree.query(positions, k=15, workers=2)
        distances *= metres
        supported = distances[:, 5] < 165
        distances, nearest = distances[supported], nearest[supported]
        levels = points[nearest, 2]
        median = np.median(levels, axis=1, keepdims=True)
        weights = np.exp(-(distances/58)**2) * (1-smoothstep(1.5, 4.5, np.abs(levels-median)))
        rr, cc = rows[supported], columns[supported]
        height[rr, cc] = (weights*levels).sum(axis=1)/weights.sum(axis=1)
        confidence[rr, cc] = 1-smoothstep(82, 165, distances[:, 5])
    influence = gaussian_filter(confidence, 32/metres)
    grade = gaussian_filter(height*confidence, 32/metres)
    np.divide(grade, influence, out=grade, where=influence > 1e-5)
    return grade, influence


def repair_bad_heights(values, applicable=None):
    """Replace implausible raster samples with the local median of valid elevations."""
    invalid = (values < -35) | (values > 1600)
    repair = invalid if applicable is None else invalid & applicable
    rows, columns = np.nonzero(repair)
    extent = np.arange(-3, 4)
    rr = np.clip(rows[:, None, None]+extent[None, :, None], 0, values.shape[0]-1)
    cc = np.clip(columns[:, None, None]+extent[None, None, :], 0, values.shape[1]-1)
    neighbours = values[rr, cc].copy()
    neighbours[invalid[rr, cc]] = np.nan
    supported = np.isfinite(neighbours).any(axis=(1, 2))
    values[rows[supported], columns[supported]] = np.nanmedian(neighbours[supported], axis=(1, 2))
    return repair & ((values >= -35) & (values <= 1600))


def calibrate_city(target, source_dem, city, points, osm, world_pixel, origin, metres, xinyi, work):
    x0, y0 = origin
    def project(lon, lat):
        x, y = world_pixel(lon, lat)
        return x-x0-.5, y-y0-.5

    # Rasterize in one shared coordinate system so neither district nor XYZ
    # tile boundaries can introduce steps between adjacent streets.
    from shapely.ops import transform
    def projected_area(x, y, z=None):
        if np.isscalar(x):
            return project(x, y)
        cols, rows = zip(*(project(lon, lat) for lon, lat in zip(x, y)))
        return cols, rows

    city_mask = Image.new('1', target.shape[::-1])
    paint_area(ImageDraw.Draw(city_mask), transform(projected_area, city))
    inside = np.asarray(city_mask)
    outside_original = Image.new('1', target.shape[::-1], 1)
    ImageDraw.Draw(outside_original).polygon(list(transform(projected_area, box(*xinyi)).exterior.coords), fill=0)
    xinyi_guard = ~np.asarray(outside_original)
    roads, bridges, water, counts = mapped_surfaces(osm, target.shape, project, metres, work)
    def distance(mask):
        return distance_transform_edt(mask).astype(np.float32)*metres

    raw = source_dem.copy()
    repair_bad_heights(raw)
    regional_grade = gaussian_filter(raw, 34/metres)
    repaired = repair_bad_heights(target, inside & ~xinyi_guard)
    local = target.copy()
    repair_bad_heights(local)
    road_distance = distance(~roads)
    eligibility = inside & (road_distance < 230) & (regional_grade < 76)
    grade, influence = inhabited_grade(points, eligibility, origin, metres)
    slope = np.hypot(*np.gradient(grade, metres))
    regional_slope = np.hypot(*np.gradient(regional_grade, metres))
    hillside = (regional_grade >= 48) | (regional_slope >= .20)
    hillside |= (regional_grade >= 23) & (regional_slope >= .115)
    water_distance, bridge_distance = distance(~water), distance(~bridges)
    weights = smoothstep(0, 85, distance(inside)) * (1-smoothstep(72, 170, road_distance))
    weights *= smoothstep(.22, .83, influence) * (1-smoothstep(.04, .115, slope))
    weights *= (1-smoothstep(20, 37, grade)) * (1-smoothstep(36, 48, regional_grade))
    weights *= smoothstep(0, 95, distance(~hillside))
    weights *= smoothstep(18, 145, water_distance) * smoothstep(13, 112, bridge_distance)
    weights *= smoothstep(0, 155, distance(~xinyi_guard))
    street_grade = gaussian_filter(local, 20/metres)
    surveyed_bias = gaussian_filter(weights*np.clip(grade-street_grade, -5, 1.5), 54/metres)
    correction = weights * np.clip(street_grade-target + surveyed_bias, -12, 5)
    protected = hillside | ~inside | xinyi_guard | (water_distance <= 18) | (bridge_distance <= 13)
    assert np.isfinite(correction).all() and not correction[protected].any()
    target += correction
    np.savez_compressed(work/'calibration-masks.npz', origin=origin, protected=np.packbits(protected & ~repaired),
                        water=np.packbits((water_distance <= 18) & ~repaired),
                        bridges=np.packbits((bridge_distance <= 13) & ~repaired),
                        hillside=np.packbits(hillside & ~repaired), repaired=np.packbits(repaired),
                        inside=np.packbits(inside), shape=target.shape)
    return {**counts, 'surveyBins':len(points), 'changedPixels':int(np.count_nonzero(abs(correction) >= 1/256)),
            'invalidSourcePixelsRepaired':int(np.count_nonzero(repaired)),
            'protectedPixels':int(np.count_nonzero(protected & inside & ~repaired))}
