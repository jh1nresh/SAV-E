"""Offline acceptance for exported terrain, georeferencing, masks and Yushan DEM."""
import hashlib
import json
import math
from pathlib import Path
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "taiwan/mountains"
META = json.loads((ROOT/"index.js").read_text().split("export default ")[1].strip().removesuffix(";"))
SUMMIT = (120.957274, 23.469987)


def xy(point, z):
    lon, lat = point
    pixels = 256*2**z
    return (pixels*(lon/360+.5), pixels*(.5-math.asinh(math.tan(math.radians(lat)))/(2*math.pi)))


def sample(image, sheet, point):
    z = sheet["sourceZoom"]
    x, y = xy(point,z)
    a, b = xy(sheet["coordinates"][0],z)
    return image.getpixel((math.floor(x)-round(a), math.floor(y)-round(b)))


class MountainExport(unittest.TestCase):
    def test_images_and_controls(self):
        broad, close = META["sheets"]
        for s in [broad, close]:
            path = ROOT / (s["name"]+".webp")
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),s["sha256"])
            with Image.open(path) as im:
                self.assertEqual(im.size,(s["width"],s["height"]))
                self.assertEqual(im.mode,"RGBA")
                a,b = xy(s["coordinates"][0],s["sourceZoom"])
                c,d = xy(s["coordinates"][2],s["sourceZoom"])
                self.assertEqual((round(c-a),round(d-b)),im.size)
                self.assertGreater(sample(im,s,SUMMIT)[3],240)
                if s is broad:
                    for point in [(121.535,25.04), (121.955,23.47), # Taipei basin, Pacific
                                  (120.919,23.857),(121.605,24.516)]: # Sun Moon Lake, Cuifeng Lake
                        self.assertEqual(sample(im,s,point)[3],0,point)
                    self.assertGreater(sample(im,s,(121.2318,24.3832))[3],240)
                else:
                    a = im.getchannel("A")
                    for box in [(0,0,im.width,1),(0,0,1,im.height),
                                (0,im.height-1,im.width,im.height),(im.width-1,0,im.width,im.height)]:
                        self.assertEqual(a.crop(box).getextrema(),(0,0))
                    r,g,_,_ = sample(im,s,SUMMIT)
                    self.assertGreater(r,g)  # warm rock face at summit
                    r,g,_,_ = sample(im,s,(120.915,23.486))
                    self.assertGreater(g,r)  # wooded lower slope

    def test_dem_and_local_terrain_voids(self):
        digest = hashlib.sha256()
        for key in META["dem"]:
            path = ROOT / "dem" / (key+".png")
            digest.update(path.read_bytes())
            with Image.open(path) as tile:
                self.assertEqual(tile.size,(256,256))
                tile.verify()
        self.assertEqual(digest.hexdigest(), META["demSha256"])
        self.assertGreater(sum(META["voidSamplesRepaired"].values()),0)
        for z in range(10,15):
            x, y = map(math.floor,xy(SUMMIT,z))
            key = f"{z}-{x//256}-{y//256}"
            self.assertIn(key,META["dem"])
            with Image.open(ROOT/"dem"/(key+".png")) as tile:
                r,g,b = tile.convert("RGB").getpixel((x%256,y%256))
                self.assertTrue(3800 < r*256+g+b/256-32768 < 3960)
        for key in META["voidSamplesRepaired"]:
            with Image.open(ROOT/"dem"/key) as tile:
                # These three tiles are entirely inland, in the high mountain catchment.
                self.assertGreaterEqual(tile.getchannel("R").getextrema()[0],128)
        self.assertLess(sum(p.stat().st_size for p in ROOT.rglob("*") if p.is_file()),15*1024**2)


if __name__ == "__main__":
    unittest.main()
