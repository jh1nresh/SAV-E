"""Preflight store-window cameras against the same Taipei LOD1 triangles the WebGL layer draws.

Usage: python build-taipei-frontage-cameras.py DATA OUTPUT [--jobs 4]
Requires Node, NumPy, Pillow and the restored public atlas. No browser or network traffic.
"""
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from functools import lru_cache
import gzip
import json
import math
from pathlib import Path
import subprocess
import time

import numpy as np
from PIL import Image

WEB = Path(__file__).resolve().parents[1]
CIRCUMFERENCE = 2*math.pi*6371008.8  # MapLibre MercatorCoordinate metres.
# Each tuple is bearing offset from (270 - outward angle), pitch, desktop zoom, mobile zoom.
PRESETS = [(-5, 58, 21.4, 21.38)]
PRESETS += [(offset, pitch, 21.6, 21.6) for pitch in (52, 43, 35) for offset in (-5, 20, -25, 38, -42)]
# Highly oblique views keep a narrow alley visible when it is blocked head-on.
PRESETS += [(offset, pitch, 21.6, 21.6) for pitch in (48, 37) for offset in (53, -53)]
# Width selects the browser's mobile/desktop camera; MapLibre's perspective depends on viewport height.
MAX_ZOOM = 21.6
VIEW_HEIGHTS = {'mobile':[440,667,845], 'desktop':[720,900,1050,1440]}
VIEWPORTS = [(mode=='mobile', height) for mode,heights in VIEW_HEIGHTS.items() for height in heights]
MAX_RANGE = 60  # Farther than every tested eye, including matching camera offsets.
TREE_RADIUS = {'broad':.49, 'round':.35, 'column':.21, 'palm':.36}
MISSING, OCCLUDED = -2, -1


def read_json(path):
    return json.loads(gzip.decompress(path.read_bytes()) if path.suffix == '.gz' else path.read_bytes())


def matched_rows(data):
    # Use the runtime's supplement and duplicate policy; private search/import data is unnecessary.
    js = """
import fs from 'node:fs';
import {join} from 'node:path';
import {gunzipSync} from 'node:zlib';
const [moduleURL, data] = process.argv.slice(1);
const {completeFrontagePack} = await import(moduleURL);
const {packs} = JSON.parse(fs.readFileSync(join(data,'city170/index.json')));
const rows = packs.flatMap(({id}) => completeFrontagePack(id,
    JSON.parse(gunzipSync(fs.readFileSync(join(data,'city170-frontages',id+'.json.gz'))))));
process.stdout.write(JSON.stringify(rows));
"""
    command = ['node', '--input-type=module', '-e', js, (WEB / 'taipei-frontage-pack.js').as_uri(), str(data)]
    rows = json.loads(subprocess.check_output(command))
    if len({r['id'] for r in rows}) != len(rows):
        raise ValueError('Ambiguous duplicate public frontage IDs')
    return rows


def rectangle_intersects(bounds, x, y, radius):
    return ((bounds[:, 0] <= x+radius) & (bounds[:, 2] >= x-radius) &
            (bounds[:, 1] <= y+radius) & (bounds[:, 3] >= y-radius))


def position(lon, lat):
    # One metric Mercator coordinate system for the city's survey tiles. Distances
    # used below are corrected to ground metres at each shop's latitude.
    return np.array([CIRCUMFERENCE * (lon - 121.55) / 360,
                     CIRCUMFERENCE / (2 * np.pi) * (np.arcsinh(np.tan(np.radians(lat)))
                     - math.asinh(math.tan(math.radians(25.05))))])


@lru_cache(maxsize=1)
def wood_templates():
    # Read the renderer's static CPU vertex buffers once, without a browser or GL context.
    # The first ten triangles are the five-sided trunk. Their two bark inks mark
    # all woody geometry, including each fork; leafy cards and fronds have their own inks.
    js = """
import {CityNature} from './city-nature.js';
const models=[];
const gl=new Proxy({STATIC_DRAW:1,getShaderParameter:()=>true,getProgramParameter:()=>true,
    bufferData(_target,model,usage){if(usage===1)models.push(model);}},
    {get:(object,key)=>object[key]??(()=>{})});
const nature=new CityNature();
nature.onAdd({on(){}},gl);
const result={};
for(const [i,form] of nature.forms.entries()){
    const model=models[i].subarray(0,nature.meshes[i].street*8);
    const ink=n=>model.subarray(n+5,n+8).join(',');
    const bark=new Set(Array.from({length:10},(_,k)=>ink(24*k)));
    if(bark.size!==2)throw Error('Unexpected trunk material: '+form);
    const triangles=[];
    for(let n=0;n<model.length;n+=24){
        if(bark.has(ink(n)))triangles.push([0,8,16].map(k=>Array.from(model.subarray(n+k,n+k+3))));
    }
    if(!triangles.length)throw Error('Missing tree mesh: '+form);
    result[form]=triangles;
}
process.stdout.write(JSON.stringify(result));
"""
    result = json.loads(subprocess.check_output(['node','--input-type=module','-e',js], cwd=WEB))
    return {form:np.asarray(result[form]) for form in TREE_RADIUS}


def wood_triangles(rows, grade):
    """Instance the same near-distance tapered trunks and forks as the Taipei tree layer."""
    woods = []
    for form_id,(form,model) in enumerate(wood_templates().items()):
        mask = rows[:,5]==form_id
        if not np.any(mask):
            continue
        # Shape is (trees, triangles, three vertices). Turn is the same root hash as GLSL.
        batch = rows[mask]
        c,s = np.cos(batch[:,6,None,None]),np.sin(batch[:,6,None,None])
        h = batch[:,2,None,None]
        x = (c*model[:,:,0]-s*model[:,:,1])*h+batch[:,0,None,None]
        y = (s*model[:,:,0]+c*model[:,:,1])*h+batch[:,1,None,None]
        z = model[:,:,2]*h+grade[mask,None,None]
        woods.append(np.stack((x,y,z),axis=-1).reshape(-1,3,3))
    return np.concatenate(woods) if woods else np.empty((0,3,3))


class Terrain:
    def __init__(self, data):
        self.rasters = {}
        for directory in (data/'terrain/street-atlas', data/'city-streets/terrain'):
            self.rasters.update((p.stem,p) for p in directory.glob('14-*.png'))
        single = data/'terrain/14-13724-7014.png'
        if single.exists():
            self.rasters.setdefault(single.stem,single)

    @lru_cache(maxsize=24)
    def tile(self, x, y):
        path = self.rasters.get(f'14-{x}-{y}')
        if path:
            with Image.open(path) as image:
                rgb = np.asarray(image.convert('RGB'), dtype=np.float64)
                return rgb @ np.array([256,1,1/256]) - 32768
        return None

    def heights(self, lon, lat):
        lon,lat = np.asarray(lon),np.asarray(lat)
        x = (lon+180)/360*16384
        y = (1-np.arcsinh(np.tan(np.radians(lat)))/np.pi)*8192
        tx,ty = np.floor(x).astype(int),np.floor(y).astype(int)
        out = np.full(len(lon),np.nan)
        for ix,iy in set(zip(tx,ty)):
            raster = self.tile(ix,iy)
            if raster is None:
                continue
            mask = np.where((tx==ix)&(ty==iy))[0]
            h,w = raster.shape
            px,py = (x[mask]-ix)*w-.5,(y[mask]-iy)*h-.5
            # Use edge pixels within half a texel of a tile boundary.
            px,py = np.clip(px,0,w-1),np.clip(py,0,h-1)
            left,top = np.minimum(px.astype(int),w-2),np.minimum(py.astype(int),h-2)
            fx,fy = px-left,py-top
            out[mask] = ((1-fy)*((1-fx)*raster[top,left]+fx*raster[top,left+1])+
                         fy*((1-fx)*raster[top+1,left]+fx*raster[top+1,left+1]))
        return out


class City:
    def __init__(self, data):
        self.data = data
        self.tiles = read_json(data/'survey-index.json')['levels']['200']
        self.tile_ids = {t['id'] for t in self.tiles}
        self.bounds = np.array([np.r_[position(*t['box'][:2]), position(*t['box'][2:])] for t in self.tiles])
        self.terrain = Terrain(data)
        self.trees = defaultdict(list)
        for path in sorted((data/'city170-nature').glob('p*.json.gz')):
            rows = read_json(path)
            if not rows:
                continue
            ll = np.array([r[:2] for r in rows]).T
            locations = position(*ll).T
            grounds = self.terrain.heights(*ll)
            for (x,y), ground, row in zip(locations, grounds, rows):
                h, form = row[2:4]
                h = h or (7 if form == 'palm' else 6)
                turn = np.float32(((row[0]*26553+row[1]*8179)%1)*math.tau)
                self.trees[(math.floor(x/50),math.floor(y/50))].append(
                    (x, y, h, TREE_RADIUS[form], ground, list(TREE_RADIUS).index(form), turn))

    @lru_cache(maxsize=32)
    def triangles(self, index):
        tile = self.tiles[index]
        raw = gzip.decompress((self.data/'200'/(tile['id']+'.bin.gz')).read_bytes())
        pts = np.frombuffer(raw, dtype='<f4').reshape(-1,3,6)[:,:,:3].astype('float64')
        if len(pts)*3 != tile['verts']:
            raise ValueError('Incomplete survey tile: '+tile['id'])
        # The sign of the surveyed north coordinate is inverted in Mercator Y.
        origin = position((tile['mx'] - .5)*360, np.degrees(np.arctan(np.sinh(np.pi*(1-2*tile['my'])))))
        pts[:,:,:2] = origin + pts[:,:,:2]*(tile['m']*CIRCUMFERENCE)
        bounds = np.column_stack((pts[:,:,0].min(1),pts[:,:,1].min(1),pts[:,:,0].max(1),pts[:,:,1].max(1)))
        return pts, bounds

    def context(self, row):
        lon,lat = row['center']
        site = position(lon,lat)
        conv = math.cos(math.radians(lat))
        radius = MAX_RANGE/conv
        parts = []
        for index in np.where(rectangle_intersects(self.bounds,*site,radius))[0]:
            tris,bounds = self.triangles(int(index))
            mask = rectangle_intersects(bounds,*site,radius)
            if np.any(mask):
                parts.append(tris[mask])
        if not parts:
            return None
        tris = np.concatenate(parts)
        tris[:,:,:2] = (tris[:,:,:2] - site)*conv
        # Relative Z permits stable point-on-face tests at Taiwan's larger elevations.
        tris[:,:,2] -= row['groundZ']
        trees = []
        for i in range(math.floor((site[0]-radius)/50),math.floor((site[0]+radius)/50)+1):
            for j in range(math.floor((site[1]-radius)/50),math.floor((site[1]+radius)/50)+1):
                trees.extend(self.trees.get((i,j),()))
        if trees:
            trees = np.array(trees)
            trees[:,:2] = (trees[:,:2]-site)*conv
        return tris, trees


def hits_triangles(first, edge1, edge2, origin, delta):
    """Möller–Trumbore segment test, double-sided including roof and wall triangles."""
    h = np.cross(delta,edge2)
    det = np.einsum('ij,ij->i',edge1,h)
    valid = np.abs(det)>1e-9
    inv = np.divide(1,det,out=np.zeros_like(det),where=valid)
    s = origin-first
    u = inv*np.einsum('ij,ij->i',s,h)
    q = np.cross(s,edge1)
    v = inv*(q@delta)
    t = inv*np.einsum('ij,ij->i',edge2,q)
    return bool(np.any(valid & (u>=0) & (v>=0) & (u+v<=1) & (t>1e-5) & (t<1)))


def hits_crowns(trees, origin, delta):
    # A conservative crown envelope at the mapped tree's terrain height.
    # The inventory cannot capture unregistered vegetation.
    if not len(trees):
        return False
    centers,radii = trees
    start = (origin-centers)/radii
    travel = delta/radii
    along = np.clip(-np.sum(start*travel,1)/np.sum(travel**2,1),0,1)
    return bool(np.any(np.sum((start+along[:,None]*travel)**2,1)<1))


def visible(context, targets, eyes):
    tri,trees = context
    for eye in eyes:
        # An inexpensive conservative AABB cull before the exact intersection.
        lo = np.minimum(eye,targets.min(0))
        hi = np.maximum(eye,targets.max(0))
        mask = np.all(tri['min']<=hi,axis=1) & np.all(tri['max']>=lo,axis=1)
        a,b,c = tri['first'][mask],tri['edge1'][mask],tri['edge2'][mask]
        for pixel in targets:
            ray = eye-pixel
            if hits_crowns(trees,pixel,ray) or (len(a) and hits_triangles(a,b,c,pixel,ray)):
                return False
    return True


def shop_geometry(city, row):
    required = ('angle','width','groundZ','surveyBase','surveyTop')
    coord = row.get('center')
    def finite(n):
        return isinstance(n,(float,int)) and math.isfinite(n)
    if (row.get('surveyTile') not in city.tile_ids or not all(finite(row.get(k)) for k in required)
            or row['width']<1.5 or not isinstance(coord,(list,tuple)) or len(coord)!=2 or not all(map(finite,coord))):
        return None
    base = max(row['groundZ'],row['surveyBase'])-row['groundZ']
    height = row['surveyTop']-row['groundZ']-base
    if height<1.9:
        return None
    result = city.context(row)
    if result is None:
        return None
    tris, trees = result
    if len(trees):
        h = trees[:,2]
        grade = trees[:,4]-row['groundZ']
        # Where the public DEM is missing, include extra vertical margin around
        # the mapped crown rather than dropping the obstruction.
        unknown = ~np.isfinite(grade)
        tris = np.concatenate((tris,wood_triangles(trees,np.where(unknown,0,grade))))
        trees = (np.column_stack((trees[:,:2], np.where(unknown,0,grade)+h*.68)),
                 np.column_stack((h*trees[:,3],h*trees[:,3],h*.32+np.where(unknown,2,0))))
    tri = {'first':tris[:,0], 'edge1':tris[:,1]-tris[:,0], 'edge2':tris[:,2]-tris[:,0],
           'min':tris.min(1), 'max':tris.max(1)}
    a = math.radians(row['angle'])
    normal = np.array([math.cos(a), math.sin(a)])
    tangent = np.array([-normal[1],normal[0]])
    # Match frontageCamera's longitude/latitude offsets, including its metre constants.
    centerLL = np.array(coord)+normal*np.array([1.1/100780,1.1/110800])
    center = (position(*centerLL)-position(*coord))*math.cos(math.radians(coord[1]))
    camera_ground = city.terrain.heights([centerLL[0]],[centerLL[1]])[0]
    ground_delta = camera_ground-row['groundZ'] if np.isfinite(camera_ground) else 0
    zscale = min(1,(height-.13)/3.25)
    width = min(9,row['width'])
    # Sample the central sign, both display/door faces and the merchandise near the sill.
    targets = np.array([np.r_[normal*.20+tangent*width*side,base+z*zscale]
                        for side,z in [(-.25,1.15),(.25,1.15),(0,2.96),(-.39,.72),(.39,.72),(0,1.5)]])
    metres_per_world = CIRCUMFERENCE*math.cos(math.radians(row['center'][1]))
    return (tri,trees),targets,center,ground_delta,metres_per_world


def first_visible(geometry, angle, presets, viewports):
    if geometry is None:
        return MISSING
    occluders,targets,center,ground_delta,metres_per_world = geometry
    for code,(offset,pitch,desktop,mobile) in enumerate(presets):
        bearing = math.radians(270-angle+offset)
        away = np.array([-math.sin(bearing),-math.cos(bearing)])
        pitch = math.radians(pitch)
        eyes = []
        for compact,px in viewports:
            distance = 1.5*px*metres_per_world/(512*2**(mobile if compact else desktop))
            eyes.append(np.r_[center+away*distance*math.sin(pitch),ground_delta+distance*math.cos(pitch)])
        if visible(occluders,targets,eyes):
            return code
    return OCCLUDED


def shop_code(city,row,presets=PRESETS,viewports=VIEWPORTS):
    return first_visible(shop_geometry(city,row),row.get('angle'),presets,viewports)


def camera_options(city,row):
    geometry = shop_geometry(city,row)
    angle = row.get('angle')
    shared = first_visible(geometry,angle,PRESETS,VIEWPORTS)
    partial = []
    if shared==OCCLUDED:
        candidates = [first_visible(geometry,angle,PRESETS,[v]) for v in VIEWPORTS]
        if any(n>=0 for n in candidates):
            partial = candidates
    return shared,partial


def initialize(data):
    global CITY
    CITY = City(data)


def solve(row):
    return row['id'],camera_options(CITY,row)


def write_module(path, codes, partial):
    content = ('// Generated by scripts/build-taipei-frontage-cameras.py from public survey meshes.\n'
               '// Each preset is [bearing offset from 270-angle, pitch, desktop zoom, mobile zoom].\n'
               '// Shared codes: -1 no preset passes every anchor, -2 insufficient survey information.\n'
               'export const frontageViewHeights='+json.dumps(VIEW_HEIGHTS,separators=(',',':'))+';\n'
               'export const frontageViewMaxZoom='+str(MAX_ZOOM)+';\n'
               'export const frontageViewPresets='+json.dumps(PRESETS,separators=(',',':'))+';\n'
               'export const frontageViews={\n'+
               ',\n'.join(json.dumps(k)+':'+str(v) for k,v in sorted(codes.items()))+'\n};\n')
    content += ('// Per-anchor alternatives, mobile first then desktop; -1 means no accepted preset for that anchor.\n'
                'export const frontagePartialViews={\n' + ',\n'.join(
                    json.dumps(k)+':'+json.dumps(v,separators=(',',':')) for k,v in sorted(partial.items()))+'\n};\n')
    path.write_text(content)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--jobs',type=int,default=4)
    args = parser.parse_args()
    data = args.data.resolve()
    rows = sorted(matched_rows(data),key=lambda r:(r.get('surveyTile') or '',r['id']))
    start = time.monotonic()
    print(f'{len(rows)} frontages, {len(PRESETS)} camera candidates, {len(VIEWPORTS)} viewports',flush=True)
    codes,partial = {},{}
    with ProcessPoolExecutor(max_workers=args.jobs,initializer=initialize,initargs=(data,)) as pool:
        for shop,(code,alternatives) in pool.map(solve,rows,chunksize=32):
            codes[shop] = code
            if alternatives:
                partial[shop] = alternatives
            if len(codes)%512==0:
                print(len(codes),dict(Counter(codes.values())),round(time.monotonic()-start,1),'s',flush=True)
    write_module(args.output,codes,partial)
    print('Complete',len(codes),dict(sorted(Counter(codes.values()).items())),len(partial),'partial',round(time.monotonic()-start,1),'s')
