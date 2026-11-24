"""Generate two georeferenced Pocket Nature mountain washes. Uses Pillow, numpy and scipy."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import shutil
import tempfile

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

# Share the existing Terrarium reader, Web Mercator projection and XYZ tile cache.
spec = importlib.util.spec_from_file_location("taiwan_relief", Path(__file__).with_name("build-taiwan-relief.py"))
relief = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relief)
TAIWAN = Path(__file__).resolve().parents[1] / "taiwan"
PEAK = (120.957274, 23.469987)  # OSM n3428095932, from the bundled scenery dataset.
WATER = TAIWAN / "scenery" / "waters.geojson.gz"
BROAD = "taiwan-highlands"
DETAIL = "yushan-ridges"


def manifest(path):
    return json.loads(path.read_text().split("export default ", 1)[1].strip().removesuffix(";"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def corners(origin, size, z):
    x, y = origin
    w, h = size
    return [relief.lnglat(i, j, z) for i, j in [(x, y), (x+w, y), (x+w, y+h), (x, y+h)]]


def tile_keys(z, origin, size, ancestor):
    divisor = 256 * 2 ** (z - ancestor)
    x, y = origin
    w, h = size
    return [(ancestor, i, j) for j in range(y//divisor, (y+h-1)//divisor+1)
            for i in range(x//divisor, (x+w-1)//divisor+1)]


def smooth(lo, hi, v):
    t = np.clip((v-lo)/(hi-lo), 0, 1)
    return t*t*(3-2*t)


def lake_mask(size, origin, z):
    result = Image.new("L", size, 255)
    with gzip.open(WATER) as f:
        lakes = json.load(f)["features"]
    west, north = relief.lnglat(*origin, z)
    east, south = relief.lnglat(origin[0]+size[0], origin[1]+size[1], z)
    for feature in lakes:
        geom = feature["geometry"]
        polygons = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
        for rings in polygons:
            ll = np.array(rings[0])[:, :2]
            if ll[:,0].max() < west or ll[:,0].min() > east or ll[:,1].max() < south or ll[:,1].min() > north:
                continue
            xy = [[(x-origin[0], y-origin[1]) for x, y in (relief.xy(point, z) for point in ring)] for ring in rings]
            # Islands inside lake polygons retain their land mask.
            box = np.array(xy[0])
            x0, y0 = np.maximum([0, 0], np.floor(box.min(axis=0)).astype(int))
            x1, y1 = np.minimum(size, np.ceil(box.max(axis=0)).astype(int)+1)
            if x1 <= x0 or y1 <= y0:
                continue
            part = Image.new("L", (x1-x0, y1-y0))
            draw = ImageDraw.Draw(part)
            for i, ring in enumerate(xy):
                draw.polygon([(x-x0, y-y0) for x, y in ring], fill=0 if i else 255)
            result.paste(0, (x0, y0), part)
    return np.asarray(result, dtype=np.float32)/255


def tint(values, stops, colours):
    return np.stack([np.interp(values, stops, c).astype(np.float32) for c in zip(*colours)], axis=-1)


def grove_marks(image, h, slope, rock, cover, rng):
    """Three-quarter-view symbols represent stands, with irregular clearings in exposed terrain."""
    d = ImageDraw.Draw(image)
    rows, cols = h.shape
    for row in range(10, rows-15, 17):
        for col in range(10, cols-15, 17):
            cx, cy = col + rng.integers(-7, 8), row + rng.integers(-7, 8)
            high = smooth(3150, 3620, h[cy, cx])
            chance = np.clip(.58 + .5*cover[cy,cx] - .3*slope[cy,cx], 0, .9)
            if h[cy,cx] < 590 or rng.random() > chance*(1-rock[cy,cx])*(1-high):
                continue
            broadleaf = h[cy,cx] < 2450 + rng.normal(0, 110)
            for _ in range(rng.integers(2, 6)):
                x, y = int(cx+rng.integers(-6, 7)), int(cy+rng.integers(-4, 5))
                green = np.array(image.getpixel((x,y)), dtype=float)
                scale = rng.uniform(.62, 1.35)
                height = int(scale*(8 if broadleaf else 10) * (1-.27*high))
                radius = max(2, round(height*(.52 if broadleaf else .34)))
                def colour(gain, bias):
                    return tuple(np.clip(green*gain+bias, 0, 255).astype(int))
                shade = colour(.70, [-1, 2, 5])
                sun = colour(1.06, [8, 7, -3])
                if broadleaf:
                    d.ellipse((x-radius, y-height, x+radius, y-1), fill=shade)
                    d.ellipse((x-radius, y-height, x+1, y-3), fill=sun)
                else:
                    # Two uneven fans and a short trunk keep grouped dark firs distinct at a glance.
                    d.line((x, y-height+2, x, y), fill=shade)
                    d.polygon([(x,y-height), (x-radius,y-3), (x-1,y-4), (x-radius-1,y-1),
                               (x+radius,y-2), (x+1,y-6)], fill=shade)
                    d.line((x,y-height+1, x-radius,y-3), fill=sun)
    return image


def stone_marks(image, gx, gy, rock, rng):
    pen = ImageDraw.Draw(image)
    h, w = rock.shape
    for j in range(5,h-8,6):
        for i in range(5,w-8,7):
            x, y = i+rng.integers(-3,4), j+rng.integers(-3,4)
            if rng.random() > rock[y,x]*.67:
                continue
            # Weathered slab strokes follow the DEM's local contour tangent.
            normal = math.hypot(gx[y,x], gy[y,x])
            if normal < .10:
                continue
            tx, ty = -gy[y,x]/normal, gx[y,x]/normal
            length = rng.uniform(2, 6)
            bg = np.array(image.getpixel((x,y)), dtype=float)
            shade = tuple(np.clip(bg*.78+[4, 4, 5], 0, 255).astype(int))
            glint = tuple(np.clip(bg*.99+[17, 12, 6], 0, 255).astype(int))
            pen.line((int(x-tx*length),int(y-ty*length),int(x+tx*length),int(y+ty*length)),fill=shade)
            pen.line((int(x-tx*length),int(y-ty*length-1),int(x),int(y-1)),fill=glint)


def repair_summit_voids(field):
    """Interpolate single negative DEM samples between two high, agreeing neighbours."""
    left, value, right = field[:,:-2], field[:,1:-1], field[:,2:]
    void = (value < -1000) & (left > 1400) & (right > 1400) & (np.abs(left-right) < 150)
    count = int(void.sum())
    if count:
        value[void] = np.rint((left[void]+right[void])*128)/256
    return count


def copy_dem(key, source, dest):
    if key[0] == 14:
        with Image.open(source) as im:
            rgb = np.array(im.convert("RGB"), dtype=np.float32)
        field = rgb[:,:,0]*256 + rgb[:,:,1] + rgb[:,:,2]/256 - 32768
        count = repair_summit_voids(field)
        if count:
            code = np.rint((field+32768)*256).astype(np.uint32)
            raw = np.stack([code>>16, (code>>8)&255, code&255],axis=-1).astype(np.uint8)
            Image.fromarray(raw).save(dest)
            return count
    shutil.copyfile(source,dest)
    return 0


def paint(heights, meters, mask, close):
    rng = np.random.default_rng(3428095932 if close else 7441)
    h = gaussian_filter(heights, 1.3 if close else .65)
    gy, gx = np.gradient(h, meters)
    slope = np.hypot(gx, gy)
    # The light falls from upper left in a north-up image. Two scales distinguish rock edges
    # from the long cast of a wooded spur, while ridge positions stay fixed to the terrain.
    light = (.83*gx + .67*gy) / np.sqrt(1 + slope**2)
    local = h-gaussian_filter(h, 6 if close else 2.7)
    spur = h-gaussian_filter(h, 25 if close else 8)
    texture = rng.standard_normal(h.shape, dtype=np.float32)
    cover = np.clip(gaussian_filter(texture, 9)*38, -1, 1)
    line = np.clip(local / (meters*(.5+1.8*slope)), -1, 1)
    macro = np.clip(spur / (meters*(2+4*slope)), -1, 1)
    rgb = tint(h+cover*(28 if close else 18),
               [500,1000,1700,2300,2900,3250,3490,3650,3900],
               [(167,187,118),(137,173,113),(118,158,107),(116,158,119),(104,145,117),
                (108,145,116),(143,157,115),(183,174,128),(191,183,157)])
    # Exposed steep faces, wind-scoured crests and alpine slopes carry rock and scree.
    alpine = smooth(3370, 3760, h)
    rock = np.clip(alpine*(.35+.65*smooth(.32, .96, slope))+
                   smooth(.88, 1.52, slope)*smooth(2400, 3350, h)*.9+
                   smooth(3680, 3850, h)*.64, 0, 1)
    stone = tint(np.clip(light, -1, 1), [-1, -.35, .25, 1],
                 [(103,117,117),(152,150,136),(199,184,155),(218,199,166)])
    rgb += (stone-rgb)*rock[:,:,None]
    contour_step = 65 if close else 260
    distance = np.abs((h+contour_step/2) % contour_step-contour_step/2)
    contour = np.clip(1-distance/np.maximum(2, slope*meters*.52), 0, 1)
    # Wet/dark falls of rock and fine broken elevation strokes stay under the ridgeline.
    ink = contour*(.55+.45*smooth(-.9,.65,cover))*(.30+.70*rock)
    tone = light*.25 + macro*.095 + line*.04 - ink*.115 + cover*.028 + texture*.011
    rgb *= 1+tone[:,:,None]
    image = Image.fromarray(np.clip(rgb,0,250).astype(np.uint8))
    if close:
        image = grove_marks(image, h, slope, rock, cover, rng)
        stone_marks(image, gx, gy, rock, rng)
    alpha = smooth(520,1000,h)*mask
    if close:
        # A transparent feather on all four sides and corners blends into the national coverage.
        yy, xx = np.ogrid[:h.shape[0], :h.shape[1]]
        edge = np.minimum(np.minimum(xx, h.shape[1]-xx-1), np.minimum(yy, h.shape[0]-yy-1))
        alpha *= smooth(0, 100, edge)
    image.putalpha(Image.fromarray(np.round(alpha*250).astype(np.uint8)))
    return image


def build(cache, out):
    cache.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    relief_meta = manifest(TAIWAN/"relief/index.js")
    main = next(s for s in relief_meta["sheets"] if s["name"] == "taiwan")
    source_wash = TAIWAN / "relief/taiwan.webp"
    if digest(source_wash) != main["sha256"]:
        raise ValueError("Taiwan relief footprint does not match its manifest")
    with Image.open(source_wash) as im:
        island = im.getchannel("A").point(lambda a: 255 if a else 0)
    country_origin = tuple(map(round, relief.xy(main["coordinates"][0], 10)))
    w, h = 1536, 1280
    center_x, center_y = map(round, relief.xy(PEAK, 14))
    focus_origin = (center_x-w//2, center_y-h//2)
    sheets = []
    keys = [k for z in range(10,15) for k in tile_keys(14, focus_origin, (w,h), z)]
    for name,z,origin,mask in [(BROAD,10,country_origin,island),
                                (DETAIL,14,focus_origin,Image.new("L",(w,h),255))]:
        tiles = sorted(relief.land_tiles(mask,origin,z))
        with ThreadPoolExecutor(6) as pool:
            list(pool.map(lambda k: relief.download_tile(k,cache),tiles))
        field = relief.elevations(tiles,cache,origin,mask.size)
        footprint = np.array(mask, dtype=np.float32)/255 * lake_mask(mask.size,origin,z)
        center_lat = relief.lnglat(origin[0], origin[1]+mask.height/2, z)[1]
        meters = 40075016.69*math.cos(math.radians(center_lat))/(256*2**z)
        close = name == DETAIL
        if close:
            repair_summit_voids(field)
        image = paint(field,meters,footprint,close)
        path = out/f"{name}.webp"
        image.save(path,"WEBP",quality=89 if close else 84, method=5)
        samples = []
        for lon,lat in [PEAK,(121.2318,24.3832),(121.535,25.04),(120.915,23.486)]:
            px,py = relief.xy([lon,lat],z)
            ix,iy = math.floor(px)-origin[0],math.floor(py)-origin[1]
            if 0<=ix<mask.width and 0<=iy<mask.height:
                samples.append({"coordinates":[lon,lat],"demMeters":round(float(field[iy,ix])),
                                "alpha":image.getpixel((ix,iy))[3]})
        src = hashlib.sha256()
        for level,x,y in tiles:
            src.update((cache/f"{level}-{x}-{y}.png").read_bytes())
        sheets.append(dict(name=name,coordinates=corners(origin,mask.size,z),width=mask.width,height=mask.height,
                           minzoom=10.5 if close else 6, maxzoom=17 if close else 13.5,
                           sourceZoom=z,inputTiles=len(tiles),inputSha256=src.hexdigest(),
                           samples=samples,sha256=digest(path)))
    folder = out/"dem"
    folder.mkdir(exist_ok=True)
    keys = sorted(keys)
    with ThreadPoolExecutor(6) as pool:
        list(pool.map(lambda k: relief.download_tile(k,cache),keys))
    hashes = hashlib.sha256()
    source_hash = hashlib.sha256()
    repairs = {}
    for z,x,y in keys:
        file = f"{z}-{x}-{y}.png"
        source_hash.update((cache/file).read_bytes())
        count = copy_dem((z,x,y),cache/file,folder/file)
        if count:
            repairs[file] = count
        hashes.update((folder/file).read_bytes())
    meta = dict(sheets=sheets,dem=[f"{z}-{x}-{y}" for z,x,y in keys],demSha256=hashes.hexdigest(),
                demSourceSha256=source_hash.hexdigest(), voidSamplesRepaired=repairs,
                terrainSource=relief.TERRAIN,terrainAttribution="https://github.com/tilezen/joerd/blob/master/docs/attribution.md",
                forestSource="https://www.ysnp.gov.tw/StaticPage/Plant", waterMaskSha256=digest(WATER),
                islandMaskSha256=digest(source_wash), summit=dict(coordinates=list(PEAK),osm="node/3428095932"))
    (out/"index.js").write_text("// Generated by tools/build-taiwan-mountains.py\nexport default "+
                                json.dumps(meta,ensure_ascii=False,indent=2)+";\n")
    print(f"{len(sheets)} mountain sheets, {len(keys)} summit DEM tiles",flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path,default=Path(tempfile.gettempdir())/"pocket-city-taiwan-dem")
    parser.add_argument("--output",type=Path,default=TAIWAN/"mountains")
    args = parser.parse_args()
    build(args.cache,args.output)
