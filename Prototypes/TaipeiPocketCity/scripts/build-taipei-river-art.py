"""Build Pocket City river illustration from an OSM Taiwan PBF and the atlas boundary.

Usage: python build-taipei-river-art.py taiwan.osm.pbf city170-boundary.json output.json.gz
Requires pyosmium and Shapely 2. Widths and wave spacing are illustration choices.
"""
import argparse
import gzip
import hashlib
import json
import math
import random

import osmium
from shapely import STRtree, from_wkb, get_parts, to_geojson, set_precision
from shapely.affinity import affine_transform, translate
from shapely.geometry import LineString, Point, Polygon, shape
from shapely.ops import unary_union


def metric(geometry, inverse=False):
    # Local equirectangular metres at Taipei; the inverse keeps original shoreline coordinates.
    x, y = 100890, 110780
    matrix = [1/x, 0, 0, 1/y, 121.5, 25] if inverse else [x, 0, 0, y, -121.5*x, -25*y]
    return affine_transform(geometry, matrix)


def source_geometries(pbf, extent):
    areas, axes, piers, banks = [], [], [], []
    factory = osmium.geom.WKBFactory()
    for obj in osmium.FileProcessor(pbf).with_locations().with_areas():
        tags = obj.tags
        if obj.is_area():
            habitat = tags.get('wetland') or tags.get('natural')
            if habitat in ('mangrove', 'reedbed', 'marsh', 'tidalflat', 'mud') or tags.get('man_made') == 'bridge':
                geometry = from_wkb(factory.create_multipolygon(obj))
                if extent.intersects(geometry):
                    identity = ('way/' if obj.from_way() else 'relation/') + str(obj.orig_id())
                    kind = 'bridge' if tags.get('man_made') == 'bridge' else habitat
                    banks.append((identity, kind, metric(geometry if geometry.is_valid else geometry.buffer(0))))
        if tags.get('man_made') == 'pier' and obj.is_area():
            geometry = from_wkb(factory.create_multipolygon(obj))
            target = piers
        elif tags.get('man_made') == 'pier' and obj.is_way() and not obj.is_closed() and len(obj.nodes) >= 2:
            geometry = from_wkb(factory.create_linestring(obj))
            target = piers
        elif obj.is_area() and (tags.get('water') == 'river' or tags.get('waterway') == 'riverbank'):
            geometry = from_wkb(factory.create_multipolygon(obj))
            target = areas
        elif obj.is_way() and tags.get('waterway') in ('river', 'stream') and not tags.get('tunnel'):
            if len(obj.nodes) < 2:
                continue
            geometry = from_wkb(factory.create_linestring(obj))
            target = axes
        else:
            continue
        if extent.intersects(geometry):
            target.append(metric(geometry if geometry.is_valid else geometry.buffer(0)))
    return unary_union(areas), axes, piers, banks


def build(pbf, boundary):
    with open(boundary) as stream:
        city = metric(shape(json.load(stream))).simplify(6)
    area = city.buffer(850)
    water, axes, piers, banks = source_geometries(pbf, metric(area, True))
    tree = STRtree(axes)
    features = []

    def emit(kind, geometry, opacity=1, **tags):
        for part in get_parts(geometry):
            if part.geom_type not in ('Polygon', 'LineString') or part.is_empty:
                continue
            geo = set_precision(metric(part, True), .000001)
            if not geo.is_empty:
                features.append(dict(type='Feature', properties={'k': kind, 'alpha': round(opacity, 3), **tags}, geometry=json.loads(to_geojson(geo))))

    # Form the inner washes before clipping: tile boundaries and the edge of the atlas are not banks.
    # Blend back into the surrounding atlas across the final 240 metres.
    zones = [(city.buffer(610), 1)]
    previous = zones[0][0]
    for step in range(1, 17):
        outer = city.buffer(610 + step * 15)
        zones.append((outer.difference(previous), (16.5 - step) / 16))
        previous = outer
    for kind, inset in [('shore', 0), ('shallows', 5), ('reach', 17), ('channel', 43)]:
        wash = water.buffer(-inset, quad_segs=3) if inset else water
        wash = wash.simplify(.48)
        for zone, alpha in zones:
            emit(kind, wash.intersection(zone), alpha)
    rng = random.Random(170)
    surface = water.intersection(area)
    for polygon in get_parts(surface):
        if polygon.geom_type != 'Polygon':
            continue
        ink_surface = polygon.buffer(-1.2)
        west, south, east, north = polygon.bounds
        for x in range(math.floor(west / 33)*33, math.ceil(east), 33):
            for y in range(math.floor(south / 37)*37, math.ceil(north), 37):
                point = Point(x+rng.uniform(-13,13), y+rng.uniform(-16,16))
                if not polygon.contains(point):
                    continue
                axis = axes[int(tree.nearest(point))]
                station = axis.project(point)
                a, b = axis.interpolate(max(0,station-12)), axis.interpolate(min(axis.length,station+12))
                angle = math.atan2(b.y-a.y,b.x-a.x) + rng.uniform(-.12,.12)
                ux, uy = math.cos(angle), math.sin(angle)
                span = rng.uniform(3,14)
                bend = rng.uniform(-1.55,1.55)
                def stroke(offset, length):
                    return LineString([(point.x+ux*t-uy*s,point.y+uy*t+ux*s)
                                      for t,s in [(-length,offset),(0,offset+bend),(length*.7,offset+bend*.4),(length,offset)]])
                line = stroke(0,span)
                if ink_surface.covers(line):
                    alpha = min(1, max(0, (850 - city.distance(point)) / 240))
                    kind = rng.choice(['ripple','ripple','glint','shade'])
                    emit(kind,line,alpha)
                    if rng.random() < .22:
                        echo = stroke(rng.uniform(2,4),span*.48)
                        if ink_surface.covers(echo):
                            emit(kind,echo,alpha)
    # Broad, broken current ribbons sit underneath the fine strokes. Follow the local
    # tangent from the existing brushwork and taper both ends to avoid a striped fill.
    ribbons = random.Random(536)
    water_parts = list(get_parts(surface))
    water_tree = STRtree(water_parts)
    for f in list(features):
        if f['properties']['k'] != 'shade' or ribbons.random() > .36:
            continue
        line = metric(shape(f['geometry']))
        start, end = line.coords[0], line.coords[-1]
        angle = math.atan2(end[1]-start[1], end[0]-start[0])
        ux, uy = math.cos(angle), math.sin(angle)
        length, width = ribbons.uniform(12, 34), ribbons.uniform(1.3, 4.6)
        bend = ribbons.uniform(-3.5, 3.5)
        center = line.interpolate(.5, normalized=True)

        def position(t, offset):
            return (center.x + ux*length*t - uy*offset, center.y + uy*length*t + ux*offset)
        steps = [i / 6 for i in range(-6, 7)]
        def side(t, sign):
            arc = math.sin(math.pi * (t+1)/2)
            return position(t, arc*(bend*t + sign*width*.5))
        ribbon = Polygon([side(t, 1) for t in steps] + [side(t, -1) for t in reversed(steps)])
        if ribbon.is_valid:
            for i in water_tree.query(ribbon, predicate='intersects'):
                emit('current', ribbon.intersection(water_parts[i]), f['properties']['alpha'])

    # Draw documented tidal habitats with their own boundaries. A riverbank polygon
    # can contain mangroves and exposed mud, so a water fill alone hides the shore.
    for identity, kind, outline in banks:
        if not area.intersects(outline) or water.distance(outline) > 12:
            continue
        properties = {'osm': identity, 'habitat': kind}
        if kind == 'bridge':
            # Cast a short cartographic shadow from the real bridge deck onto open water.
            footprint = translate(outline, xoff=7, yoff=-10).difference(outline).intersection(water)
            label = 'bridge-reflection'
        else:
            footprint = outline
            label = 'bank-mud' if kind in ('tidalflat', 'mud') else 'bank-marsh'
        near_zones = [(z, a) for z, a in zones if z.intersects(footprint)]
        for zone, alpha in near_zones:
            emit(label, footprint.intersection(zone), alpha, **properties)
        if label == 'bank-marsh':
            # A narrow water-side shadow follows the wetland edge, including real inlets.
            fringe = outline.buffer(5, quad_segs=2).difference(outline).intersection(water)
            for zone, alpha in zones:
                if zone.intersects(fringe):
                    emit('bank-reflection', fringe.intersection(zone), alpha, **properties)

    # Only depict mapped landing structures physically adjoining these rivers.
    for pier in piers:
        if area.covers(pier) and water.distance(pier) <= 5:
            kind = 'pier-deck' if pier.geom_type in ('MultiPolygon', 'Polygon') else 'pier-walk'
            opacity = min(1, max(0, (850 - city.distance(pier)) / 240))
            emit(kind, pier, opacity)
            if kind == 'pier-deck':
                for deck in get_parts(pier):
                    # Fine joints across the actual deck, perpendicular to its long axis.
                    corners = list(deck.minimum_rotated_rectangle.exterior.coords)
                    a, b = max(zip(corners, corners[1:]), key=lambda ab: math.dist(*ab))
                    length = math.dist(a, b)
                    ux, uy = (b[0]-a[0])/length, (b[1]-a[1])/length
                    inset = deck.buffer(-.25)
                    for distance in range(1, math.ceil(length), 2):
                        x, y = a[0]+ux*distance, a[1]+uy*distance
                        cross = LineString([(x+uy*length,y-ux*length),(x-uy*length,y+ux*length)])
                        emit('deck-joint', cross.intersection(inset), opacity)
    with open(pbf, 'rb') as stream:
        source_hash = hashlib.file_digest(stream, 'sha256').hexdigest()
    return {'type': 'FeatureCollection', 'source': '© OpenStreetMap contributors, ODbL',
            'sourceSHA256': source_hash, 'features': features}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ('pbf', 'boundary', 'output'):
        p.add_argument(arg)
    args = p.parse_args()
    atlas = build(args.pbf, args.boundary)
    with open(args.output, 'wb') as stream:
        stream.write(gzip.compress(json.dumps(atlas,separators=(',', ':')).encode(),mtime=0))
    from collections import Counter
    print(Counter(f['properties']['k'] for f in atlas['features']))
