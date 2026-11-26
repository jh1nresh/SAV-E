"""Repair lowland road DEM outliers against nearby measured building undersides.

Replay from TaipeiPocketCity:
  uv run --python 3.12 --with numpy==2.5.5 --with scipy==1.18.1 --with shapely==2.2.0 --with pillow==13.0.0 scripts/build-taipei-street-grade.py --all

Use --district xinyi --district songshan --out <directory> for a regional check.
Generate the shipping manifest in one pass over all districts: both sides of a
shared street and tile border use the same survey fit and optimization grid.
The Z14 Terrarium source priority matches app.js, including the Songyan override.
"""
import argparse
import gzip
import json
import math
from pathlib import Path
import re
import runpy

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter, map_coordinates, maximum_filter1d
from scipy.spatial import cKDTree
from scipy.optimize import linprog
from scipy.sparse import csr_matrix, vstack
from shapely.affinity import affine_transform
from shapely.geometry import Polygon, box, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]
BASE = runpy.run_path(str(ROOT/'scripts/smooth-taipei-road-terrain.py'))
GROUND = runpy.run_path(str(ROOT/'scripts/build-xinyi-street-ground.py'))
M = BASE['METRES_PER_PIXEL']
WORLD = BASE['WORLD']
ramp = BASE['ramp']


def read(path):
    return json.loads(gzip.decompress(path.read_bytes()))


def source(x, y):
    if (x, y) == (13724, 7014):
        return ROOT/'assets/taipei-songyan-factory-terrain.png'
    return ROOT/f'data/city-streets/terrain/14-{x}-{y}.png'


def screen_xy(lon, lat):
    return ((np.asarray(lon)+180)*WORLD/360,
            (1-np.arcsinh(np.tan(np.radians(lat)))/np.pi)*WORLD/2)


def draw_geometry(image, geom, x0, y0):
    """Every XYZ tile shares these absolute pixel-centre coordinates."""
    def points(ring):
        coords = np.asarray(ring.coords)
        x, y = screen_xy(coords[:,0], coords[:,1])
        return list(zip(x-x0-.5, y-y0-.5))
    if geom.is_empty:
        return
    if hasattr(geom, 'geoms'):
        for g in geom.geoms:
            draw_geometry(image, g, x0, y0)
        return
    pen = ImageDraw.Draw(image)
    if geom.geom_type == 'Polygon':
        # A hole in this feature must not erase another overlapping exclusion.
        if geom.interiors:
            patch = Image.new('1', image.size)
            pen = ImageDraw.Draw(patch)
        pen.polygon(points(geom.exterior), fill=1)
        for ring in geom.interiors:
            pen.polygon(points(ring), fill=0)
        if geom.interiors:
            image.paste(1, mask=patch)
    elif geom.geom_type == 'LineString':
        pen.line(points(geom), fill=1, width=1)


def masks(data, boundary, area, x0, y0, dims, districts):
    def blank():
        return Image.new('1', dims)
    roads, natural, structures, region = blank(), blank(), blank(), blank()
    draw_geometry(region, boundary, x0, y0)
    ox, oy = GROUND['ORIGIN']
    for slug in districts:
        for row in read(ROOT/f'assets/{slug}-street-ground.json.gz')['road']:
            grid = GROUND['packed_polygon'](row)
            g = affine_transform(grid, [1e-6,0,0,1e-6,ox*1e-6,oy*1e-6])
            draw_geometry(roads,g,x0,y0)

    grade = json.loads((ROOT/'city170-grade-ids.js').read_text().split('export default ')[1].rstrip(';\n'))
    off_ground = {f'{key}/{ident}' for key, ids in grade.items() for ident in ids}
    # Inspect owning packs, including entries outside the district. They can
    # carry a long bridge or river which passes into the repair area.
    profiles = []
    for path in sorted((data/'city170').glob('p*.json.gz')):
        for f in read(path)['features']['features']:
            p = f['properties']
            if p['kind'] not in ('water','forest','road','walk'):
                continue
            separated = (f['id'] in off_ground or p.get('layer','0') != '0'
                         or any(p.get(k,'no') != 'no' for k in ('bridge','tunnel','indoor')))
            major = p.get('class') in ('trunk','motorway') or p.get('class','').endswith('_link')
            if p['kind']=='walk' and not separated:
                continue
            g = shape(f['geometry'])
            if not g.intersects(area):
                continue
            if p['kind'] == 'road' and not separated:
                # At a grid pitch of 8.65 m, both polygon holes can snap onto
                # the same row and erase a 3–5 m alley. Preserve its centreline.
                if not major:
                    draw_geometry(roads,g,x0,y0)
                samples = road_samples(g, x0, y0, dims)
                if len(samples):
                    profiles.append(samples)
            if p['kind'] in ('water','forest'):
                draw_geometry(natural,g,x0,y0)
            elif separated or major:
                draw_geometry(structures,g,x0,y0)
    for file in ('city170-airfield','city170-waterways'):
        for f in read(data/(file+'.json.gz'))['features']:
            g=shape(f['geometry'])
            if g.intersects(area):
                draw_geometry(natural,g,x0,y0)

    # Preserve registered scene surfaces and the protected apron/pond as a whole.
    def constant(path, key):
        return json.JSONDecoder().raw_decode((ROOT/path).read_text().split(key,1)[1])[0]
    plot = Polygon(constant('taipei101-single-ground-data.js','export const coordinates='))
    draw_geometry(structures, plot,x0,y0)
    scene = read(ROOT/'scripts/songyan-street-plot.json.gz')
    meta = scene['meta']
    angle = math.radians(meta['rotation'])
    c,s = math.cos(angle),math.sin(angle)
    east = 111320*math.cos(math.radians(meta['lat']))
    campus = Polygon([(meta['lon']+(a*c-b*s)/east,meta['lat']+(a*s+b*c)/110574) for a,b in scene['corners']])
    draw_geometry(structures,campus,x0,y0)
    # Dome apron is authored in WGS84, immediately south of the campus.
    text = (ROOT/'taipei-dome-geography.js').read_text().split('export const domeApron=',1)[1]
    coords = json.JSONDecoder().raw_decode(re.sub(r',\s*]', ']', text.split('coordinates:',1)[1].lstrip()))[0]
    draw_geometry(structures,Polygon(coords[0]),x0,y0)
    return [np.asarray(img) for img in (roads,natural,structures,region)], profiles


def road_samples(line, x0, y0, dims):
    """Pairs of bilinear sample positions along the actual full road centreline."""
    x, y = screen_xy(*np.asarray(line.coords).T)
    x, y = x-x0-.5, y-y0-.5
    along = np.r_[0, np.cumsum(np.hypot(np.diff(x),np.diff(y))*M)]
    if along[-1] < 3:
        return []
    span = min(12, along[-1])
    start = np.unique(np.r_[np.arange(0,along[-1]-span,3),along[-1]-span])
    cols = [np.interp(distance,along,axis) for distance in (start,start+span) for axis in (x,y)]
    samples = np.column_stack((*cols, np.full(len(start),span)))
    inside = np.all((samples[:,:4]>=0) & (samples[:,:4]<np.tile(dims,2)-1),axis=1)
    return samples[inside]


def checked_profile(original, proposed, profiles):
    """Keep the survey correction where it can join the actual road grades.

    One shared weight every four DEM pixels allows both sides of a street to
    follow the same correction. Bilinear interpolation of DEM heights along each
    road is linear in those weights. Zero correction is always feasible.
    """
    samples = np.concatenate(profiles)
    x,y,u,v,distance = samples.T
    def samples_of(field,xx,yy):
        return map_coordinates(field,[yy,xx],order=1)
    signed = samples_of(original,u,v) - samples_of(original,x,y)
    old = abs(signed)/distance
    offsets = np.cumsum([len(p) for p in profiles])[:-1]
    nearby = np.concatenate([maximum_filter1d(part,size=17,mode='nearest') for part in np.split(old,offsets)])
    # Bound small crests against their own 48 m neighbourhood. A repaired
    # interval over 7% may gain at most 1.5 grade points; a neighbourhood
    # already above 3.5% may gain at most half a grade point at its peak.
    limits = np.minimum(np.maximum(.035,nearby+.005),np.maximum(.07,old+.015))*distance
    delta = proposed-original
    active = (samples_of(abs(delta),x,y)+samples_of(abs(delta),u,v))>0
    rows,cols = original.shape
    step = 4
    width = (cols-1)//step+2
    count = width*((rows-1)//step+2)

    def controls(px,py):
        cx,cy = px//step,py//step
        fx,fy = (px%step)/step,(py%step)/step
        for dx,wx in ((0,1-fx),(1,fx)):
            for dy,wy in ((0,1-fy),(1,fy)):
                yield (cy+dy)*width+cx+dx,wx*wy

    def sampled_correction(px,py):
        xi,yi = np.floor(px).astype(int),np.floor(py).astype(int)
        fx,fy = px-xi,py-yi
        indices,weights = [],[]
        for dx,wx in ((0,1-fx),(1,fx)):
            for dy,wy in ((0,1-fy),(1,fy)):
                xx,yy = np.minimum(xi+dx,cols-1),np.minimum(yi+dy,rows-1)
                effect = delta[yy,xx]*wx*wy
                for index,weight in controls(xx,yy):
                    indices.append(index)
                    weights.append(weight*effect)
        rr = np.tile(np.arange(len(px)),len(indices))
        return csr_matrix((np.concatenate(weights),(rr,np.concatenate(indices))),shape=(len(px),count))

    change = sampled_correction(u[active],v[active])-sampled_correction(x[active],y[active])
    # Leave room for the final Terrarium quantization at the two samples.
    cap = limits[active]-1/256
    groups = [change, -change]
    allowed = [cap-signed[active], cap+signed[active]]
    # Bound both the curb-to-curb cross fall and off-road transitions, including
    # every tile border; a constrained road must not create a cliff beside it.
    for dr,dc in ((0,1),(1,0)):
        window = np.s_[:rows-dr,:cols-dc]
        ry,rx = np.nonzero((delta[window]!=0) | (delta[dr:,dc:]!=0))
        cross = sampled_correction(rx+dc,ry+dr)-sampled_correction(rx,ry)
        difference = original[ry+dr,rx+dc]-original[ry,rx]
        slope_cap = np.maximum(.15*M,abs(difference)+.04*M)-1/256
        groups.extend([cross,-cross])
        allowed.extend([slope_cap-difference,slope_cap+difference])
    constraints = vstack(groups,format='csr')
    bounds = np.concatenate(allowed)
    yy,xx = np.nonzero(delta)
    objective = np.zeros(count)
    for index,weight in controls(xx,yy):
        objective += np.bincount(index,weight*abs(delta[yy,xx]),minlength=count)
    used = objective>0
    matrix = constraints[:,used]
    coeff = np.ones(used.sum())
    enforce = np.zeros(len(bounds),dtype=bool)
    while True:
        violation = matrix@coeff > bounds+1e-6
        if not np.any(violation):
            break
        if np.all(enforce[violation]):
            raise RuntimeError('Street grade bound failed solver tolerance')
        enforce |= violation
        solved = linprog(-objective[used],A_ub=matrix[enforce],b_ub=bounds[enforce],
                         bounds=(0,1),method='highs')
        if not solved.success:
            raise RuntimeError('Could not match the measured street profile: '+solved.message)
        coeff = solved.x
    values = np.ones(count)
    values[used] = coeff
    blend = sum(weight*values[index] for index,weight in controls(xx,yy))
    result = original.copy()
    result[yy,xx] = np.rint((original[yy,xx]+blend*delta[yy,xx])*256)/256
    new = abs(samples_of(result,u,v)-samples_of(result,x,y))/distance
    if np.any(new>limits/distance+1e-6):
        raise ValueError('A rounded output interval exceeds the road-grade bound')
    print(f'{len(old)} road intervals checked; {sum(new+.025<old)} improve by >2.5 grade points')
    return result


def survey_grade(data, eligibility, bounds, x0, y0):
    # Reuse the 25-metre survey bins and the native mesh-to-DEM coordinate transform.
    sample = BASE['survey_bases']
    sample.__globals__['DATA'] = data
    evidence = sample(bounds)
    tree = cKDTree(evidence[:,:2])
    target = np.zeros(eligibility.shape)
    confidence = np.zeros_like(target)
    for start in range(0, eligibility.shape[0], 64):
        y, x = np.nonzero(eligibility[start:start+64])
        if not len(x):
            continue
        y += start
        distance, indices = tree.query(np.column_stack((x+x0+.5,y+y0+.5)), k=12)
        levels = evidence[indices,2]
        typical = np.median(levels,axis=1,keepdims=True)
        weight = np.exp(-((distance*M)/47)**2)*(1-ramp(.65,1.8,np.abs(levels-typical)))
        total = weight.sum(axis=1)
        grade = np.divide((levels*weight).sum(axis=1),total,out=typical[:,0].copy(),where=total>1e-9)
        # Low measured terrain, independently agreeing nearby blocks, no extrapolation.
        ordered = np.sort(levels,axis=1)
        confidence[y,x] = (1-ramp(48,80,distance[:,5]*M))*(1-ramp(.9,2.4,ordered[:,-2]-ordered[:,1]))
        confidence[y,x] *= (1-ramp(14,19,grade)) * ramp(0,2,grade)
        target[y,x] = grade
    support = gaussian_filter(confidence,1.5)
    grade = gaussian_filter(target*confidence,1.5)
    np.divide(grade,support,out=grade,where=support>1e-9)
    return grade, support


DISTRICTS = {'xinyi':'信義區','songshan':'松山區','daan':'大安區','zhongshan':'中山區',
             'zhongzheng':'中正區','datong':'大同區','wanhua':'萬華區','shilin':'士林區',
             'beitou':'北投區','neihu':'內湖區','nangang':'南港區','wenshan':'文山區'}


def build(output, districts=None):
    districts = list(DISTRICTS) if districts is None else districts
    data = ROOT/'data'
    features = json.loads((data/'districts.geojson').read_bytes())['features']
    boundary = unary_union([shape(f['geometry']) for f in features if f['properties']['name'] in {DISTRICTS[slug] for slug in districts}])
    west,south,east,north = boundary.bounds
    limits = west-.003,south-.003,east+.003,north+.003
    a,b = (int(v//256) for v in screen_xy(limits[0],limits[3]))
    c,d = (int(v//256) for v in screen_xy(limits[2],limits[1]))
    dims = (256*(c-a+1),256*(d-b+1))
    before = np.zeros(dims[::-1])
    valid = np.zeros(dims[::-1],dtype=bool)
    active = set(json.loads((data/'city-streets/index.json').read_bytes())['terrainTiles'])
    tiles = {}
    for x in range(a,c+1):
        for y in range(b,d+1):
            if f'{x}/{y}' not in active:
                continue
            window = np.s_[(y-b)*256:(y-b+1)*256,(x-a)*256:(x-a+1)*256]
            tiles[x,y] = window
            before[window] = BASE['decode'](source(x,y))
            valid[window] = True
    (roads,natural,structures,region),profiles = masks(data,boundary,box(*limits),256*a,256*b,dims,districts)
    road_dist = distance_transform_edt(~roads)*M
    # A false roof plateau can cover a whole city block between two streets.
    # Retain one block of survey support so its centre cannot pin the carriageway.
    candidate = valid & region & (road_dist < 155)
    grade,support = survey_grade(data,candidate,limits,256*a,256*b)
    # Feather on the full mosaic, never on individual 256 px tiles. Buffers
    # also protect all four texels used by bilinear sampling at each exclusion.
    mask = (1-ramp(62,140,road_dist)) * ramp(18,65,distance_transform_edt(region)*M)
    mask *= ramp(27,80,distance_transform_edt(~natural)*M)
    mask *= ramp(24,62,distance_transform_edt(~structures)*M)
    mask *= ramp(.45,.87,support) * (1-ramp(.035,.075,np.hypot(*np.gradient(grade,M))))
    # Require an actual local DEM undulation as well as disagreement with the
    # independent ground evidence. Retain gentle street grades and drainage.
    broad = gaussian_filter(before,6)
    roughness = gaussian_filter(np.abs(before-broad),2.8)
    mask *= ramp(.30,1.15,roughness)*ramp(.38,2.0,np.abs(grade-before))
    # Preserve the outer column of a replaced tile if its neighbour has no
    # frozen source. All interior borders use a shared elevation field.
    border = distance_transform_edt(np.pad(valid,1))[1:-1,1:-1]
    mask *= ramp(18,65,border*M) * candidate
    after = checked_profile(before, before+mask*(grade-before), profiles)
    output.mkdir(parents=True,exist_ok=True)
    changed = []
    for (x,y),window in sorted(tiles.items()):
        if np.any(after[window] != before[window]):
            BASE['write_dem'](after[window],output/f'14-{x}-{y}.png')
            changed.append(f'{x}/{y}')
    (output/'index.json').write_text(json.dumps(changed,separators=(',',':'))+'\n')
    print(f'{len(changed)} tiles, {np.count_nonzero(before!=after)} changed texels')
    print(json.dumps(changed,separators=(',',':')))
    return changed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'assets/taipei-street-grade')
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument('--district',choices=DISTRICTS,action='append',help='Repeat for adjoining districts; compute one mosaic')
    scope.add_argument('--all',action='store_true',help='Process all twelve Taipei districts together')
    args = parser.parse_args()
    build(args.out, args.district)
