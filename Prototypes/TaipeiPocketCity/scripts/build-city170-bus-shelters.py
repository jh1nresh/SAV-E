"""Build schematic shelters only at OSM bus platforms explicitly tagged shelter=yes.

Usage: python build-city170-bus-shelters.py taipei.json.gz RESTORED_DATA OUTPUT_JS
Platform centers use tagged OpenStreetMap coordinates. Shelter footprints and orientation are illustrative. Use a compact frame when the standard model overlaps mapped geometry.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import runpy

import ijson
from shapely import STRtree, points
from shapely.geometry import Point, Polygon, shape

H = runpy.run_path(str(Path(__file__).with_name('build-city170-hydrants.py')))
F, read = H['F'], H['read']
MOTOR = {'residential','unclassified','service','tertiary','secondary','primary','living_street','busway'}
SHELTER_SIZES = ((4.0, 1.9), (2.8, 1.5))


def platform(t):
    return (t.get('highway')=='bus_stop' and t.get('public_transport')=='platform' and t.get('bus')=='yes'
            and t.get('shelter')=='yes' and not H['off_ground'](t) and t.get('access') in H['OPEN_ACCESS']
            and t.get('disused','no')=='no' and t.get('construction','no')=='no' and not t.get('fixme'))


def build(source,data):
    meta=read(data/'city170/index.json')
    with gzip.open(source,'rb') as f:
        if hashlib.file_digest(f,'sha256').hexdigest()!=meta['source']['provenance']['taipeiExtractUncompressedSHA256']:
            raise ValueError('Wrong OSM snapshot')
    grid=read(data/'city170/grid.json.gz')['features']
    cells=STRtree([shape(r['geometry']) for r in grid])
    city=shape(read(data/'city170-boundary.json'))
    obstacles,lines,areas={}, {}, {}
    for p in sorted((data/'city170').glob('p*.json.gz')):
        for f in read(p)['features']['features']:
            key,t=f['id'],f['properties']
            if t['kind'] in {'building','water','school'} and key not in obstacles and 'Polygon' in f['geometry']['type']:
                obstacles[key]=F['project'](shape(f['geometry']))
            if (t['kind']!='road' or t['category'] not in MOTOR or key in lines or t.get('offGround')
                or any(str(t.get(k,d))!=d for k,d in [('layer','0'),('tunnel','no'),('bridge','no')])):
                continue
            line=F['project'](shape(f['geometry']))
            if line.geom_type!='LineString' or line.length<1:
                continue
            try: width=float(t.get('width',5.4))
            except (TypeError,ValueError): width=5.4
            lines[key]=line
            areas[key]=line.buffer(max(1,min(24,width))/2+.45)
    trunks=[r for path in sorted((data/'city170-nature').glob('p*.json.gz')) for r in read(path)]
    tx,ty=F['FORWARD'].transform([r[0] for r in trunks],[r[1] for r in trunks])
    tree_points=STRtree(points(tx,ty))
    radii=[max(.18,(r[2] or 7)*.08) for r in trunks]
    max_radius=max(radii,default=0)
    survey=F['Survey'](data)
    covered=H['survey_cover'](survey,data)
    stops=[]; benches=[]; counts=Counter()
    ground_roads=set()
    boarding_roads=set()
    with gzip.open(source,'rb') as src:
        for r in ijson.items(src,'elements.item',use_float=True):
            t=r.get('tags',{})
            if r['type']=='way':
                key=f"road/way/{r['id']}"
                if key in lines and not H['off_ground'](t):
                    ground_roads.add(key)
                    if t.get('access') in H['OPEN_ACCESS'] and t.get('service') not in {'driveway','parking_aisle'}:
                        boarding_roads.add(key)
            if r['type']!='node' or not (platform(t) or t.get('amenity')=='bench'):
                continue
            ll=Point(r['lon'],r['lat'])
            if not city.covers(ll):
                continue
            pt=F['project'](ll)
            if t.get('amenity')=='bench': benches.append(pt)
            if platform(t): stops.append((r,ll,pt))
    tree=STRtree([lines[k] for k in sorted(boarding_roads)])
    masks=STRtree([*obstacles.values(),*(areas[k] for k in sorted(ground_roads))])
    stop_points=STRtree([p for _,_,p in stops]); seats=STRtree(benches)
    result=defaultdict(list)
    counts['sourcePlatforms']=len(stops)
    for r,ll,pt in sorted(stops,key=lambda entry:entry[0]['id']):
        roadway=tree.geometries[tree.nearest(pt)]
        distance=roadway.distance(pt)
        if not 1 <= distance <= 18:
            counts['unclearRoadOffset'] += 1
            continue
        if len(stop_points.query(pt,predicate='dwithin',distance=4.5)) > 1:
            counts['duplicatePlatformNearby'] += 1
            continue
        station=roadway.project(pt)
        a,b=[roadway.interpolate(max(0,min(roadway.length,station+i))) for i in (-2.25,2.25)]
        dx,dy=b.x-a.x,b.y-a.y
        if math.hypot(dx,dy)<3:
            counts['unclearRoadTangent'] += 1
            continue
        # Local east/north at Taipei. The roof's open side faces the boarding street.
        road=roadway.interpolate(station)
        if -dy*(road.x-pt.x)+dx*(road.y-pt.y)<0: dx,dy=-dx,-dy
        bearing=round(math.degrees(math.atan2(dy,dx)))%360
        angle=math.radians(bearing);c,s=math.cos(angle),math.sin(angle)
        for width, depth in SHELTER_SIZES:
            half_width, half_depth = width / 2 + .04, depth / 2 + .04
            # Expand all four sides slightly for transform and bearing rounding.
            corners = [(-half_width, -half_depth), (half_width, -half_depth),
                       (half_width, half_depth), (-half_width, half_depth)]
            roof = Polygon([(pt.x + u*c - v*s, pt.y + u*s + v*c) for u, v in corners])
            if len(masks.query(roof, predicate='intersects')):
                failure = 'footprintConflicts'
                continue
            if covered(ll, pt, 2.28 if width == 4 else math.hypot(half_width, half_depth) + .012):
                failure = 'surveyBuildingConflicts'
                continue
            nearby = tree_points.query(roof, predicate='dwithin', distance=max_radius)
            if any(roof.distance(tree_points.geometries[i]) <= radii[i] for i in nearby):
                failure = 'trunkConflicts'
                continue
            samples = [survey.ground(pt)] + [survey.ground(Point(q)) for q in roof.exterior.coords[:-1]]
            if None in samples or max(samples) - min(samples) > .4:
                failure = 'unclearGround'
                continue
            break
        else:
            counts[failure] += 1
            continue
        cell=cells.query(ll,predicate='intersects')
        if not len(cell):
            counts['outsideCellGrid'] += 1
            continue
        bench=r['tags'].get('bench')=='yes' and not len(seats.query(pt,predicate='dwithin',distance=3))
        row=[r['id'],round(ll.x*1e7),round(ll.y*1e7),bearing,int(bench),width,depth]
        result[min(grid[i]['id'] for i in cell)].append(row)
        counts['illustrated']+=1
        counts['compact']+=int((width, depth) == SHELTER_SIZES[1])
        counts['seats']+=int(bench)
    return result,counts


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ('source','data','output'):parser.add_argument(key,type=Path)
    args=parser.parse_args()
    rows,counts=build(args.source,args.data)
    args.output.write_text('// © OpenStreetMap contributors, ODbL. Generated by scripts/build-city170-bus-shelters.py.\n'
        +'export default '+json.dumps(dict(sorted(rows.items())),separators=(',',':'))+';\n')
    print(dict(counts))
