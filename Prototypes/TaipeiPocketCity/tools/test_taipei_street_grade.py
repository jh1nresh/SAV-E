"""Check the actual Terrarium texels and pixel-centred MapLibre terrain profiles."""
import gzip
import json
import math
import os
from functools import lru_cache
from pathlib import Path
import runpy
import unittest

import numpy as np
from shapely import STRtree, points
from shapely.geometry import shape

ROOT = Path(__file__).resolve().parents[1]
GEN = runpy.run_path(str(ROOT/'scripts/build-taipei-street-grade.py'))
OUTPUT = Path(os.environ.get('TAIPEI_STREET_GRADE_OUTPUT', ROOT/'assets/taipei-street-grade'))
KEYS = json.loads((OUTPUT/'index.json').read_bytes())


@lru_cache(maxsize=160)
def terrain(x,y,new):
    file = OUTPUT/f'14-{x}-{y}.png' if new and f'{x}/{y}' in KEYS else GEN['source'](x,y)
    return GEN['BASE']['decode'](file)


def sample(lon,lat,new):
    x,y=GEN['screen_xy'](lon,lat)
    x,y=x-.5,y-.5
    i,j=math.floor(x),math.floor(y)
    return sum(terrain((i+a)//256,(j+b)//256,new)[(j+b)%256,(i+a)%256]*wx*wy
               for a,wx in ((0,1-x+i),(1,x-i)) for b,wy in ((0,1-y+j),(1,y-j)))


def road_profile(feature, new):
    coords = np.array(feature['geometry']['coordinates'])
    along = np.r_[0,np.cumsum(np.hypot(np.diff(coords[:,0])*100780,np.diff(coords[:,1])*110800))]
    distance = np.arange(0,along[-1],1)
    lon,lat=[np.interp(distance,along,coords[:,axis]) for axis in (0,1)]
    return np.array([sample(x,y,new) for x,y in zip(lon,lat)]),np.stack([lon,lat],axis=1)


class StreetGrade(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        wanted = {'road/way/48810790','road/way/118880895'}
        cls.examples = {}
        for path in (ROOT/'data/city170').glob('p*.json.gz'):
            for f in json.loads(gzip.decompress(path.read_bytes()))['features']['features']:
                if f['id'] in wanted:
                    cls.examples[f['id']]=f
            if len(cls.examples)==len(wanted):
                break

    def test_measured_streets(self):
        for ident,point,ground in [('48810790',(121.5587193,25.0322674),9.7),
                                   ('118880895',(121.5596177,25.0497738),5.6)]:
            f = self.examples['road/way/'+ident]
            self.assertGreater(abs(sample(*point,False)-ground),20)
            self.assertLess(abs(sample(*point,True)-ground),2.1)
            before,xy = road_profile(f,False)
            after,_ = road_profile(f,True)
            i = np.argmin(np.hypot((xy[:,0]-point[0])*100780,(xy[:,1]-point[1])*110800))
            for section in (slice(None),slice(max(0,i-35),i+36)):
                old,new=before[section],after[section]
                self.assertLess(max(abs(new[12:]-new[:-12])),.75*max(abs(old[12:]-old[:-12])))
            if ident=='48810790':
                self.assertLess(np.ptp(after),2)

    def test_registered_ground_water_hills_and_bridge(self):
        old = GEN['BASE']['decode'](ROOT/'data/city-streets/terrain/14-13724-7014.png')
        registered = terrain(13724,7014,False)
        edited = terrain(13724,7014,True)
        campus = old!=registered
        self.assertGreater(campus.sum(),600)
        self.assertTrue(np.array_equal(edited[campus],registered[campus]))
        for pt in [(121.5648093,25.0336696), # Taipei 101
                   (121.5595571,25.0423741), # Dome
                   (121.5717972,25.0326625), # elevated Xinyi road over a footpath
                   (121.5725144,25.0522820), # MacArthur Bridge over Keelung River
                   (121.5708,25.0273),       # Xiangshan woodland
                   (121.5524,25.0693)]:       # airport runway
            self.assertAlmostEqual(sample(*pt,True),sample(*pt,False),places=5)

    def test_shipped_texels_clear_sensitive_source_geometries(self):
        # Compare final RGB values with the actual previous runtime source. A
        # 0.000123 degree buffer covers a whole Z14 bilinear footprint in Taipei.
        coords=[]
        for key in KEYS:
            x,y=map(int,key.split('/'))
            old,new=terrain(x,y,False),terrain(x,y,True)
            r,c=np.nonzero(old!=new)
            lon=(x*256+c+.5)*360/(2**22)-180
            lat=np.degrees(np.arctan(np.sinh(np.pi*(1-2*(y*256+r+.5)/(2**22)))))
            coords.append(np.column_stack((lon,lat)))
            self.assertFalse(np.any(old[r,c]>=100))
        changed=STRtree(points(np.concatenate(coords)))
        def clear(f):
            protected=shape(f['geometry']).buffer(.000123)
            self.assertEqual(len(changed.query(protected,predicate='intersects')),0,f.get('id'))
        grade=json.loads((ROOT/'city170-grade-ids.js').read_text().split('export default ')[1].rstrip(';\n'))
        excluded={f'{prefix}/{i}' for prefix,ids in grade.items() for i in ids}
        for path in (ROOT/'data/city170').glob('p*.json.gz'):
            for f in json.loads(gzip.decompress(path.read_bytes()))['features']['features']:
                p=f['properties']
                if p['kind'] in ('water','forest') or (p['kind'] in ('road','walk') and
                        (f['id'] in excluded or p.get('layer','0')!='0' or
                         any(p.get(k,'no')!='no' for k in ('bridge','tunnel','indoor')))):
                    clear(f)
        for name in ('city170-airfield','city170-waterways'):
            for f in json.loads(gzip.decompress((ROOT/'data'/f'{name}.json.gz').read_bytes()))['features']:
                clear(f)

    def test_manifest_and_shared_edges(self):
        keys = [tuple(map(int,k.split('/'))) for k in KEYS]
        self.assertEqual(keys,sorted(set(keys)))
        for x,y in keys:
            pre,post=terrain(x,y,False),terrain(x,y,True)
            self.assertEqual(post.shape,(256,256))
            self.assertTrue(np.any(post!=pre))
            for dx,dy,edge,other in [(1,0,np.s_[:,-1],np.s_[:,0]),(0,1,np.s_[-1,:],np.s_[0,:])]:
                if not GEN['source'](x+dx,y+dy).exists():
                    self.assertTrue(np.array_equal(pre[edge],post[edge]))
                    continue
                pre_step=abs(pre[edge]-terrain(x+dx,y+dy,False)[other])
                post_step=abs(post[edge]-terrain(x+dx,y+dy,True)[other])
                limit=np.maximum(.15*GEN['M'],pre_step+.04*GEN['M'])
                self.assertTrue(np.all(post_step<=limit+.01),(x,y,dx,dy))


if __name__=='__main__':
    unittest.main()
