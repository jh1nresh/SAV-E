"""Verify the illustrated woodland against the unpacked, archived map geometry and DEM."""
import gzip
import json
from pathlib import Path
import runpy
import unittest

import numpy as np
from PIL import Image
import shapely
from shapely.geometry import Point, shape


CITY=Path(__file__).resolve().parents[1]
BUILD=runpy.run_path(str(CITY/'scripts/build-xinyi-ridge-woods.py'))
DATA=json.loads(gzip.decompress((CITY/'assets/xinyi-ridge-woods.json.gz').read_bytes()))


class RidgeWoodland(unittest.TestCase):
    def test_relief_is_transparent_off_the_mountain(self):
        img=Image.open(CITY/'assets/xinyi-ridge-relief.png').convert('RGBA')
        rgba=np.asarray(img)
        self.assertEqual(img.size,(1536,1536))
        self.assertEqual(img.getpixel((0,0))[3],0)
        self.assertTrue(.12 < np.mean(rgba[:,:,3]>0) < .35)
        colors=rgba[rgba[:,:,3]>190][:,:3]
        self.assertGreater(np.max(colors[:,1])-np.min(colors[:,1]),45)

    @unittest.skipUnless((CITY/'data/city170/index.json').is_file(),'requires unpacked Taipei GIS and DEM')
    def test_shipped_relief_leaves_trails_and_protected_areas_transparent(self):
        _,_,rocks,_,_,structures=BUILD['landscape']()
        alpha=np.asarray(Image.open(CITY/'assets/xinyi-ridge-relief.png').convert('RGBA'))[:,:,3].astype(float)
        size=alpha.shape[0]
        west,north=DATA['corners'][0];east,south=DATA['corners'][2]
        def merc(lat):
            return np.arcsinh(np.tan(np.radians(lat)))
        top,bottom=merc(north),merc(south)
        # Sample the actual Web Mercator image placement at metre intervals
        # using the same four texels as bilinear texture filtering.
        lines=[BUILD['local'](shape(f['geometry'])) for f in DATA['trails']]
        points=np.concatenate([shapely.line_interpolate_point(g,np.arange(0,g.length,1)) for g in lines])
        xy=shapely.get_coordinates(points)
        lng=BUILD['LON']+xy[:,0]/BUILD['EAST'];lat=BUILD['LAT']+xy[:,1]/BUILD['NORTH']
        u=(lng-west)/(east-west)*size-.5;v=(top-merc(lat))/(top-bottom)*size-.5
        x,y=np.floor(u).astype(int),np.floor(v).astype(int)
        samples=np.zeros_like(u)
        for dx,dy in ((0,0),(1,0),(0,1),(1,1)):
            col,row=x+dx,y+dy
            ok=(col>=0)&(col<size)&(row>=0)&(row<size)
            samples[ok]+=(1-abs(u[ok]-col[ok]))*(1-abs(v[ok]-row[ok]))*alpha[row[ok],col[ok]]
        self.assertGreater(len(samples),11900)
        self.assertEqual(np.max(samples),0)
        # Include partially opaque pixels and whole protected polygons, not just
        # representative points inside the rocks or structures.
        row,col=np.where(alpha>0)
        px=((west+(col+.5)/size*(east-west))-BUILD['LON'])*BUILD['EAST']
        py=(np.degrees(np.arctan(np.sinh(top-(row+.5)/size*(top-bottom))))-BUILD['LAT'])*BUILD['NORTH']
        for protected in (rocks,structures):
            shapely.prepare(protected)
            self.assertFalse(np.any(shapely.contains_xy(protected,px,py)))

    @unittest.skipUnless((CITY/'data/city170/index.json').is_file(),'requires unpacked Taipei GIS and DEM')
    def test_anchors_stay_on_wooded_terrain_clear_of_paths_rocks_and_existing_crowns(self):
        forest,obstacles,rocks,existing,_,structures=BUILD['landscape']()
        rows=np.asarray(DATA['crowns'])
        points=shapely.points(rows[:,:2])
        self.assertTrue(np.all(shapely.contains(forest,points)))
        # Largest 13.5 m illustrative crown extends less than 6.4 m sideways.
        # The stored root is rounded to 0.1 m after the full-radius clearance test.
        for shape_ in [forest.boundary,obstacles,rocks]:
            self.assertTrue(np.all(shapely.distance(shape_,points)>6.4))
        tree=shapely.STRtree(existing)
        existing_dist=np.array([points[i].distance(existing[j]) for i,j in enumerate(tree.nearest(points))])
        self.assertGreater(np.min(existing_dist),9.9)
        lon=121.55+rows[:,0]/BUILD['EAST'];lat=25.01+rows[:,1]/BUILD['NORTH']
        dem=BUILD['Terrain']()
        self.assertLess(np.max(np.abs(dem.sample(lon,lat)-rows[:,2])),.15)
        self.assertGreater(np.min(rows[:,2]),57)
        # OSM's Xiangshan summit has a spot height of 184.23 m. The displayed
        # DEM at that same location is approximately 161 m; roots follow the DEM.
        summit=(121.575542,25.0265411)
        self.assertAlmostEqual(float(dem.sample(*summit)),161.08,delta=.15)
        center=BUILD['local'](Point(summit))
        self.assertGreater(np.sum(shapely.distance(points,center)<100),30)
        for f in DATA['trails']:
            route=BUILD['local'](shape(f['geometry']))
            self.assertEqual(route.intersection(structures).length,0)
        trail_names={f['properties']['name'] for f in DATA['trails']}
        self.assertTrue(any('象山親山步道' in n for n in trail_names))
        self.assertIn('虎山自然步道',trail_names)


if __name__=='__main__':
    unittest.main()
