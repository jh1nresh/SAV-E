"""Build the registered Songyan close-up from the prepared Pocket City and survey data."""
import argparse
from collections import defaultdict
import gzip
import json
import math
from pathlib import Path
from random import Random
import struct

from PIL import Image
import numpy as np
from shapely import constrained_delaunay_triangles,transform
from shapely.geometry import LineString, Point, Polygon, box, mapping, shape
from shapely.geometry.polygon import orient
from shapely.ops import unary_union


DATA = Path('data')
LON, LAT = 121.56178, 25.0435
WORLD = 40075016.686
METRE = 1/(WORLD*math.cos(math.radians(LAT)))


def mercator(lon, lat):
    return (lon+180)/360, (1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2


MX, MY = mercator(LON, LAT)


def local(lon, lat):
    x, y = mercator(lon, lat)
    return (x-MX)/METRE, (MY-y)/METRE


def geographic(x, y):
    return (MX+x*METRE)*360-180, math.degrees(math.atan(math.sinh(math.pi*(1-2*(MY-y*METRE)))))


def remap(geometry, project):
    return transform(geometry,lambda xy:np.array([project(a,b) for a,b in xy]))


def polygons(geometry):
    if geometry.geom_type == 'Polygon':
        return [geometry]
    return [p for p in getattr(geometry,'geoms',()) if p.geom_type == 'Polygon']


class Mesh:
    def __init__(self):
        self.data = bytearray()

    def face(self, points, color, base=0, height=1):
        for point in points:
            self.data.extend(struct.pack('<6f', *point, base, height, int(color,16)+2))

    def quad(self, a, b, c, d, color):
        self.face((a,b,c),color)
        self.face((a,c,d),color)

    def disc(self, x, y, z, radius, color, steps=18):
        for index in range(steps):
            a,b=[i*math.tau/steps for i in (index,index+1)]
            self.face(((x,y,z),(x+radius*math.cos(a),y+radius*math.sin(a),z),
                       (x+radius*math.cos(b),y+radius*math.sin(b),z)),color)

    def cylinder(self, x,y,z0,z1,r0,r1,color,steps=9,lean=(0,0)):
        for index in range(steps):
            a,b=[i*math.tau/steps for i in (index,index+1)]
            c,s=math.cos(a),math.sin(a)
            d,t=math.cos(b),math.sin(b)
            self.quad((x+c*r0,y+s*r0,z0),(x+d*r0,y+t*r0,z0),
                      (x+d*r1+lean[0],y+t*r1+lean[1],z1),(x+c*r1+lean[0],y+s*r1+lean[1],z1),color)

    def leaf_crown(self,x,y,z,rx,ry,rz,rng,colors):
        rings=[]
        sides=9
        for ring,(h,r) in enumerate(((-.64,.48),(-.34,.91),(.04,1),(.49,.83),(.82,.49))):
            points=[]
            for i in range(sides):
                angle=(i+.18*(ring%2))*math.tau/sides
                bump=r*rng.uniform(.85,1.12)
                points.append((x+rx*bump*math.cos(angle),y+ry*bump*math.sin(angle),z+rz*(h+rng.uniform(-.075,.075))))
            rings.append(points)
        for j in range(len(rings)-1):
            for i in range(sides):
                k=(i+1)%sides
                self.quad(rings[j][i],rings[j][k],rings[j+1][k],rings[j+1][i],colors[min(3,j+rng.randrange(2))])
        for i in range(sides):
            self.face((rings[-1][i],rings[-1][(i+1)%sides],(x,y,z+rz)),colors[-1])


# Base, height and tone identify the exact source components across both survey LODs.
PARTS=[
    ('factory',(5.39,11.1502,.815),'c3a586','736960'),
    ('repair',(5.5103,9.5296,.865),'cbb18a','645f55'),
    ('boiler',(7.1797,13.2805,.115),'b17d66','755954'),
    ('boiler-annex',(7.1797,4.7404,.005),'bd9776','776053'),
]
LIMIT=(-260,-82,5,72)


def survey_shell(mesh):
    index=json.loads((DATA/'survey-index.json').read_text())
    roof_faces=defaultdict(list)
    counts=defaultdict(int)
    w,s=geographic(*LIMIT[:2]); e,n=geographic(*LIMIT[2:])
    for tile in index['levels']['200']:
        x,y,a,b=tile['box']
        if a<w or x>e or b<s or y>n:
            continue
        raw=gzip.decompress((DATA/'200'/f"{tile['id']}.bin.gz").read_bytes())
        values=list(struct.iter_unpack('<18f',raw))
        for triangle in values:
            coords=[((tile['mx']-MX+triangle[i]*tile['m'])/METRE,
                     (MY-tile['my']+triangle[i+1]*tile['m'])/METRE,triangle[i+2]) for i in (0,6,12)]
            name=None
            for field,signature,wall,roof in PARTS:
                if all(abs(a-b)<.0015 for a,b in zip(triangle[3:6],signature)):
                    name,base,height=field,triangle[3],triangle[4]
                    break
            if not name or not all(LIMIT[0]-.02<=x<=LIMIT[2]+.02 and LIMIT[1]-.02<=y<=LIMIT[3]+.02 for x,y,z in coords):
                continue
            counts[name]+=1
            cap=all(abs(z-base-height)<.12 for x,y,z in coords)
            mesh.face(coords,roof if cap else wall,base,height)
            if cap:
                polygon=Polygon([(x,y) for x,y,z in coords])
                if polygon.area>.004:
                    roof_faces[name].append(polygon)
    assert set(counts)=={r[0] for r in PARTS},counts
    return {name:unary_union(rows).simplify(.17) for name,rows in roof_faces.items()},dict(counts)


def facade(mesh,form,base,height,kind):
    z=base+height
    for p in polygons(form):
        p=orient(p,sign=1)
        for ring in (p.exterior,*p.interiors):
            for a,b in zip(ring.coords,ring.coords[1:]):
                length=math.dist(a,b)
                if length<2.3:
                    continue
                ux,uy=(b[0]-a[0])/length,(b[1]-a[1])/length
                nx,ny=uy,-ux
                def plane(start,end,bottom,top,depth,color):
                    def at(t,h):return (a[0]+ux*t+nx*depth,a[1]+uy*t+ny*depth,h)
                    mesh.quad(at(start,bottom),at(end,bottom),at(end,top),at(start,top),color)

                plane(0,length,z-.26,z+.16,.14,'ded1b6')
                plane(0,length,z-.32,z-.26,.17,'6e6354')
                plane(0,length,base+.38,base+1.02,.07,'9b846a')
                if kind=='factory':
                    plane(0,length,base+5.15,base+5.38,.1,'dfc4a1')
                    plane(0,length,base+5.10,base+5.20,.12,'967a61')
                count=max(1,round(length/(4.9 if kind=='factory' else 5.8)))
                pitch=length/count
                for i in range(count):
                    center=(i+.5)*pitch
                    width=min(pitch*.73,3.5)
                    left,right=center-width/2,center+width/2
                    rows=(base+1.55,base+6.15) if kind=='factory' else (base+1.55,)
                    for sill in rows:
                        top=min(sill+(2.25 if kind=='factory' else 2.7),z-.59)
                        if top <= sill:
                            continue
                        plane(left-.16,right+.16,sill-.18,top+.15,.09,'ead6b8')
                        plane(left,right,sill,top,.12,'4a5551')
                        plane(left+.13,right-.13,sill+.13,top-.14,.14,
                              ('728784','658079','81938b')[i%3])
                        plane(left,right,sill+(top-sill)*.42,sill+(top-sill)*.42+.10,.16,'b7afa0')
                        for frac in (1/3,2/3):
                            mid=left+width*frac
                            plane(mid-.045,mid+.045,sill,top,.17,'c9bc9f')
                        plane(left-.13,right+.13,sill-.095,sill+.02,.18,'ead5b4')
                if kind in ('factory','repair') and length>10:
                    plane(.25,length-.25,z-.70,z-.57,.10,'9c8770')


def terrain_sampler():
    city=json.loads((DATA/'city-streets/index.json').read_text())
    loaded={}
    def pixel(x,y):
        tile=(x//256,y//256)
        if tile not in loaded:
            ix,iy=tile; name=f'14-{ix}-{iy}.png'
            root=DATA/'city-streets/terrain' if f'{ix}/{iy}' in city['terrainTiles'] else DATA/'terrain/street-atlas'
            loaded[tile]=Image.open(root/name).convert('RGB')
        r,g,b=loaded[tile].getpixel((x%256,y%256))
        return r*256+g+b/256-32768
    def elevation(x,y):
        size=256*2**14
        px=(MX+x*METRE)*size-.5; py=(MY-y*METRE)*size-.5
        i,j=math.floor(px),math.floor(py)
        k,l=px-i,py-j
        return (pixel(i,j)*(1-k)+pixel(i+1,j)*k)*(1-l)+(pixel(i,j+1)*(1-k)+pixel(i+1,j+1)*k)*l
    return elevation


def waterfront(mesh,osm,prepared,footprints):
    elements={x['id']:x for x in osm['elements'] if x['type']=='way'}
    def way(id):
        return [local(p['lon'],p['lat']) for p in elements[id]['geometry']]
    pond=Polygon(way(188843434),[way(1463682728)]).buffer(0)
    woods=Polygon(way(1575178461)).buffer(0)
    courtyard=Polygon(way(228920406)).buffer(0)
    fountain=Polygon(way(1390847382)).buffer(0).intersection(courtyard)
    assert not fountain.is_empty
    fountain_center=fountain.centroid
    rng=Random(249)
    ground=[]
    def paint(geometry,kind):
        if not geometry.is_empty:
            ground.append({'type':'Feature','properties':{'kind':kind},'geometry':mapping(remap(geometry,geographic))})

    old=json.loads((DATA/'street-songshan.json').read_text())
    walk_lines=[]
    for ident in (229056580,229056581,229056582,229056583,229056680,229056681,315570031,1389696173):
        walk_lines.append(LineString(way(ident)).intersection(box(-255,-88,99,83)))
    paths=unary_union([line.buffer(1.65 if i not in (1,4) else 2.8,cap_style=2) for i,line in enumerate(walk_lines)])
    dry_walk=paths.difference(pond.buffer(.35)).difference(footprints)
    paint(woods.difference(pond).difference(footprints),'woods')
    paint(pond.buffer(.66).difference(pond),'shore')
    paint(pond,'water')
    paint(pond.buffer(-3.9),'deep')
    paint(pond.boundary.buffer(.15).intersection(pond),'edge')
    paint(dry_walk.buffer(.30).difference(pond).difference(footprints),'walk-edge')
    paint(dry_walk,'walk')
    paint(courtyard,'court')
    garden_center=courtyard.centroid
    if not courtyard.contains(garden_center):
        garden_center=courtyard.representative_point()
    if courtyard.boundary.distance(garden_center)>11:
        x,y=garden_center.x,garden_center.y
        for p in (box(x-16,y-7.3,x-4.5,y-2),box(x+4.5,y-7.3,x+16,y-2),
                  box(x-16,y+2,x-4.5,y+7.3),box(x+4.5,y+2,x+16,y+7.3)):
            paint(p.intersection(courtyard.buffer(-1.9)),'garden')
    else:
        paint(courtyard.buffer(-2.8),'garden')
    paint(fountain,'shore')
    paint(fountain.buffer(-.65),'deep')
    for line in walk_lines:
        for segment in getattr(line,'geoms',(line,)):
            for run in range(12,int(segment.length),9):
                point=segment.interpolate(run)
                a,b=segment.interpolate(run-.5),segment.interpolate(min(segment.length,run+.5))
                dx,dy=b.x-a.x,b.y-a.y
                length=math.hypot(dx,dy)
                if length:
                    edges=[(point.x+dy/length*t,point.y-dx/length*t) for t in (-2.6,2.6)]
                    paint(LineString(edges).buffer(.045).intersection(dry_walk),'joint')
    wet=pond.buffer(-2)
    ripples=[]
    for _ in range(165):
        x,y=rng.uniform(12,88),rng.uniform(-58,50)
        p=Point(x,y)
        if wet.contains(p):
            w=rng.uniform(.6,2.7)
            ripple=LineString([(x-w,y),(x-.15,y+.18),(x+w,y)]).buffer(.10).intersection(wet)
            ripples.append(ripple)

    elevation=terrain_sampler()
    x,y=fountain_center.x,fountain_center.y
    z=elevation(x,y)+.13
    # Official field notes describe the original three-tier champagne-style fountain.
    if courtyard.boundary.distance(fountain_center)>4:
        mesh.cylinder(x,y,z,z+.48,3.2,3.05,'9e957f',24)
        mesh.disc(x,y,z+.49,3.05,'bdad92',24)
        mesh.disc(x,y,z+.505,2.74,'557f75',24)
        for offset,radius in ((.51,1.10),(1.06,.76),(1.58,.47)):
            mesh.cylinder(x,y,z+offset,z+offset+.40,.16,radius,'b7a88f',16)
            mesh.disc(x,y,z+offset+.41,radius,'d6c6a8',16)
            mesh.disc(x,y,z+offset+.425,radius*.76,'76938a',16)
    def surface(area,color,lift):
        west,south,east,north=area.bounds
        for x in range(math.floor(west),math.ceil(east),7):
            for y in range(math.floor(south),math.ceil(north),7):
                part=area.intersection(box(x,y,x+7,y+7))
                for polygon in polygons(part):
                    for triangle in constrained_delaunay_triangles(polygon).geoms:
                        mesh.face([(a,b,elevation(a,b)+lift) for a,b in list(triangle.exterior.coords)[:3]],color)

    # Match the same height field under the pond. Small patches keep the
    # painted water surface close to the underlying terrain at tile seams.
    depth=pond.buffer(-3.5)
    centre=pond.buffer(-9.25)
    surface(pond.difference(depth),'789385',.31)
    surface(depth.difference(centre),'55877f',.31)
    surface(centre,'477873',.31)
    for ripple in ripples:
        surface(ripple,'91b2aa',.35)

    existing=[local(*item[:2]) for item in old['objects'] if item[2]=='tree']
    tree_points=[]
    # Use the kit's wood/park planting as seeds, keeping mapped walks and pond clear.
    for px,py,*_ in prepared['trees']:
        x,y=local(*prepared_point(prepared,px,py))
        point=Point(x,y)
        if not woods.contains(point) or paths.distance(point)<1.9 or pond.distance(point)<.4 or footprints.distance(point)<1.9:
            continue
        if min((math.dist((x,y),p) for p in (*existing,*tree_points)),default=100)<5.4:
            continue
        tree_points.append((x,y))
    for x,y in tree_points:
        z=elevation(x,y)-.13
        height=rng.uniform(4.8,8.6)
        radius=rng.uniform(1.15,2.1)
        colors=rng.choice((('526341','627951','839d62','a8b674'),
                           ('566944','769155','90aa68','b4c17a'),
                           ('486b54','648867','82a16d','a5b47a')))
        mesh.cylinder(x,y,z,z+height*.76,.23,.08,'786445',7)
        for a in range(4):
            theta=(a+.12)*math.tau/4
            mesh.leaf_crown(x+math.cos(theta)*radius*.64,y+math.sin(theta)*radius*.64,
                            z+height*(.68+.075*a),radius,radius*.86,radius*.80,rng,colors)
    for i in range(32):
        point=pond.exterior.interpolate(pond.exterior.length*(i+.37)/32)
        land=pond.buffer(.85).exterior.interpolate(pond.buffer(.85).exterior.project(point))
        x,y=land.x,land.y
        p=Point(x,y)
        if paths.distance(p)<.6 or not woods.buffer(.6).contains(p):
            continue
        mesh.leaf_crown(x,y,elevation(x,y)+.41,.59,.48,.48,rng,('606545','7a814d','939751','a4a75c'))

    bridge=LineString(way(229056584))
    for i in range(max(1,round(bridge.length/.46))):
        a,b=[bridge.interpolate(t*.46) for t in (i,i+.9)]
        length=a.distance(b)
        if length<.05:
            continue
        dx,dy=(b.x-a.x)/length,(b.y-a.y)/length
        za,zb=elevation(a.x,a.y)+.55,elevation(b.x,b.y)+.55
        mesh.quad((a.x-dy*1.03,a.y+dx*1.03,za),(b.x-dy*1.03,b.y+dx*1.03,zb),
                  (b.x+dy*1.03,b.y-dx*1.03,zb),(a.x+dy*1.03,a.y-dx*1.03,za),
                  ('b18c66','957753','ab8662')[i%3])
    return {'type':'FeatureCollection','features':ground},len(tree_points)


def prepared_point(scene,x,y):
    cfg=scene['meta']
    angle=math.radians(cfg['rotation'])
    east,north=x*math.cos(angle)-y*math.sin(angle),x*math.sin(angle)+y*math.cos(angle)
    return cfg['lon']+east/(111320*math.cos(math.radians(cfg['lat']))),cfg['lat']+north/110574


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--osm',type=Path,required=True)
    parser.add_argument('--scene',type=Path,required=True)
    parser.add_argument('--out',type=Path,default=DATA/'city-streets')
    args=parser.parse_args()
    mesh=Mesh()
    footprints,counts=survey_shell(mesh)
    for kind,(base,height,tone),_,_ in PARTS:
        facade(mesh,footprints[kind],base,height,kind)
    ground,trees=waterfront(mesh,json.loads(args.osm.read_text()),json.loads(args.scene.read_text()),unary_union(list(footprints.values())))
    asset={'id':'songyan','file':'songyan-v5','mx':MX,'my':MY,'m':METRE,'box':[*geographic(-261,-90),*geographic(101,91)],
           'limit':LIMIT,'matches':[row[1] for row in PARTS],'verts':len(mesh.data)//24,
           'ground':ground,'trees':trees,'surveyTriangles':counts,
           'credits':['https://www.songshanculturalpark.org/map','https://www.songshanculturalpark.org/gallery/1768198480_972c6a37bd143a264a69.pdf',
                      'https://www.openstreetmap.org/relation/20039406']}
    target=args.out/'landmark'
    target.mkdir(parents=True,exist_ok=True)
    (target/(asset['file']+'.bin.gz')).write_bytes(gzip.compress(mesh.data,compresslevel=6,mtime=0))
    payload=(json.dumps(asset,ensure_ascii=False,separators=(',',':'))+'\n').encode()
    (args.out/(asset['file']+'.json.gz')).write_bytes(gzip.compress(payload,compresslevel=6,mtime=0))
    print('Songyan',asset['verts']//3,'triangles,',len(ground['features']),'ground details,',trees,'new trees, survey',counts)


if __name__=='__main__':
    main()
