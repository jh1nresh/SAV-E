"""Build the Songyan terrain and grounded waterfront from the packaged Taipei data.

Run from TaipeiPocketCity after unpacking the continuous map data:
    uv run --with Pillow==13.0.0 --with shapely==2.2.0 scripts/build-songyan-campus-ground.py
"""
import argparse
import gzip
import hashlib
import io
import json
import math
import struct
from pathlib import Path

from PIL import Image
from shapely.geometry import Point, shape
from shapely.ops import transform


TILE_X, TILE_Y, ZOOM = 13724, 7014, 14
MX, MY, METRE = 0.8376716111111111, 0.4281076140692883, 2.754257127884696e-08
SIZE = 256 * 2**ZOOM
TERRAIN = 'city-streets/terrain/14-13724-7014.png'
WATERFRONT = 'city-streets/landmark/songyan-v5.bin.gz'
DIGEST = {
    TERRAIN: 'dfaf2def054a553d761a88ef97f74f266bd8e5fdc89f575f8514de3cd0c0f3e8',
    WATERFRONT: 'b038cd2764f0c22e69ffa44000fe80767b061d7026a2e17fb5cd109c6a4d6e08',
}


def source_bytes(data, name):
    payload = (data / name).read_bytes()
    if hashlib.sha256(payload).hexdigest() != DIGEST[name]:
        raise ValueError(f'Changed source {name}; review terrain or geometry registration')
    return payload


def local(lon, lat):
    mx = (lon + 180) / 360
    my = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2
    return (mx - MX) / METRE, (MY - my) / METRE


def decode(color):
    r, g, b = color
    return r * 256 + g + b / 256 - 32768


def encode(z):
    n = round((z + 32768) * 256)
    return n >> 16, (n >> 8) & 255, n & 255


def raster_point(x, y):
    return ((x + TILE_X * 256 + .5) / SIZE - MX) / METRE, (MY - (y + TILE_Y * 256 + .5) / SIZE) / METRE


def sample(image, x, y):
    # The bundled MapLibre DEM sampler uses pixel-centred bilinear interpolation.
    px = (MX + x * METRE) * SIZE - .5 - TILE_X * 256
    py = (MY - y * METRE) * SIZE - .5 - TILE_Y * 256
    i, j = math.floor(px), math.floor(py)
    a, b = px - i, py - j
    return sum(decode(image.getpixel((i + dx, j + dy))) * wx * wy
               for dx, wx in ((0, 1-a), (1, a)) for dy, wy in ((0, 1-b), (1, b)))


def calibrated_terrain(source, footprints):
    result = source.copy()
    forms = [(transform(local, shape(f['geometry'])).buffer(0), f['properties']['surveyBase'])
             for f in footprints['features']]
    west = min(poly.bounds[0] for poly, _ in forms) - 20
    south = min(poly.bounds[1] for poly, _ in forms) - 20
    east = max(poly.bounds[2] for poly, _ in forms) + 20
    north = max(poly.bounds[3] for poly, _ in forms) + 20
    for y in range(256):
        for x in range(256):
            point = Point(raster_point(x, y))
            if not (west <= point.x <= east and south <= point.y <= north):
                continue
            distance, grade = min((poly.distance(point), grade) for poly, grade in forms)
            if distance >= 20:
                continue
            # Eleven metres cover the contributing DEM samples under the wall.
            # The remaining nine metres blend into the original raster.
            t = min(1, (20 - distance) / 9)
            blend = t*t*(3-2*t)
            before = decode(source.getpixel((x, y)))
            result.putpixel((x, y), encode(before + (grade-before)*blend))
    return result


def grounded_waterfront(payload, source, terrain):
    # Ordering and sizes come from build-songyan-detail.py, pinned by the input hash.
    # Translate each anchored object rigidly so its surface and foliage retain their shape.
    output = bytearray(payload)
    def vertex(i):
        return struct.unpack_from('<3f', payload, i*24)
    def translate(first, count, x, y):
        offset = round(sample(terrain, x, y) - sample(source, x, y), 5)
        if abs(offset) <= .0001:
            return
        for i in range(first, first+count):
            struct.pack_into('<f', output, i*24+8, vertex(i)[2] + offset)
    fountain = 29766
    translate(fountain, 864, *vertex(fountain+144)[:2])
    for i in range(32):
        first = fountain+23097+1014*i
        ring = [vertex(first+6*j) for j in range(7)]
        translate(first, 1014, *(sum(row[k] for row in ring)/7 for k in (0,1)))
    # The pond surface, ripples, shoreline planting and bridge use the original ground.
    for start, end in ((fountain+864,fountain+23097),(fountain+55545,91908)):
        for i in range(start,end):
            x, y, _ = vertex(i)
            if abs(sample(terrain, x, y)-sample(source, x, y)) > .001:
                raise ValueError(f'Calibration changes waterfront vertex {i}')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, default=Path('data'))
    parser.add_argument('--out', type=Path, default=Path('assets'))
    args = parser.parse_args()
    coverage = json.loads(Path(__file__).with_name('songyan-campus-footprints.geojson').read_text())
    source = Image.open(io.BytesIO(source_bytes(args.data, TERRAIN))).convert('RGB')
    terrain = calibrated_terrain(source, coverage)
    mesh = grounded_waterfront(gzip.decompress(source_bytes(args.data, WATERFRONT)), source, terrain)
    args.out.mkdir(parents=True, exist_ok=True)
    terrain.save(args.out/'taipei-songyan-factory-terrain.png')
    (args.out/'taipei-songyan-waterfront.bin.gz').write_bytes(gzip.compress(mesh, mtime=0))


if __name__ == '__main__':
    main()
