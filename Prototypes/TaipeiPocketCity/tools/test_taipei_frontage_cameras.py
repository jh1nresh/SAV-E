import gzip
import json
import math
import os
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

import numpy as np

WEB = Path(__file__).resolve().parents[1]
camera = runpy.run_path(str(WEB/'scripts/build-taipei-frontage-cameras.py'))


def curtain(x, y1, y2, height):
    a,b,c,d = [x,y1,0],[x,y2,0],[x,y2,height],[x,y1,height]
    return np.asarray([[a,b,c],[a,c,d]], dtype=float)


class Flat:
    @staticmethod
    def heights(lons, lats):
        return np.zeros(len(lons))


class Site:
    tile_ids = {'tile'}
    terrain = Flat()
    def __init__(self, triangles, trees=()):
        self.tris = triangles
        self.trees = np.asarray(trees)
    def context(self, _row):
        return self.tris, self.trees


row = {'center':[121.55,25.04], 'angle':0, 'width':4, 'groundZ':0,
       'surveyTile':'tile','surveyBase':0,'surveyTop':10}


def artifact():
    raw = (WEB/'taipei-frontage-cameras.js').read_text()
    def field(name):
        return json.loads(raw.split('export const '+name+'=',1)[1].split(';',1)[0])
    return {key:field(key) for key in ('frontageViewPresets','frontageViews','frontageViewHeights','frontageViewMaxZoom','frontagePartialViews')}


class Visibility(unittest.TestCase):
    def test_windows_keep_an_open_view_but_reject_neighbouring_buildings_and_tree_crowns(self):
        code = camera['shop_code']
        self.assertEqual(code(Site(curtain(-2,-100,100,50)),row),0)
        self.assertEqual(code(Site(curtain(2,-100,100,50)),row),-1)
        self.assertGreater(code(Site(curtain(6,-1,1,20)),row),0)
        # Registered crown immediately in front of the display can obscure every camera.
        self.assertEqual(code(Site(curtain(-2,-100,100,50),[[1,0,4,.49,0,0,0]]),row),-1)
        self.assertEqual(code(Site(curtain(-2,-100,100,50),[[1,0,4,.49,20,0,0]]),row),0)

    def test_wood_meshes_keep_height_scale_root_rotation_and_forks(self):
        models=camera['wood_templates']()
        self.assertGreater(len(models['broad']),len(models['palm']))
        self.assertGreater(len(models['column']),len(models['palm']))
        # Rotate the mapped palm's lean by 90 degrees and check the exact first face.
        model=models['palm']
        rows=np.asarray([[3.,4.,7.,.36,12.,3.,math.pi/2]])
        actual=camera['wood_triangles'](rows,np.array([12.]))
        np.testing.assert_allclose(actual[:,:,0],3-model[:,:,1]*7,atol=1e-7)
        np.testing.assert_allclose(actual[:,:,1],4+model[:,:,0]*7,atol=1e-7)
        np.testing.assert_allclose(actual[:,:,2],12+model[:,:,2]*7,atol=1e-7)

    def test_unverified_heights_and_tile_do_not_produce_a_preset(self):
        for override in [{'surveyBase':None},{'surveyTop':1.5},{'groundZ':float('nan')},
                         {'center':None},{'surveyTile':None}]:
            self.assertEqual(camera['shop_code'](Site(curtain(-1,-3,3,7)),{**row,**override}),-2)

    def test_packaged_codes_and_original_preset_are_well_formed(self):
        ledger=artifact()
        presets,codes=ledger['frontageViewPresets'],ledger['frontageViews']
        self.assertEqual(ledger['frontageViewHeights'],camera['VIEW_HEIGHTS'])
        self.assertEqual(ledger['frontageViewMaxZoom'],camera['MAX_ZOOM'])
        self.assertEqual(presets[0],[-5,58,21.4,21.38])
        self.assertEqual(presets,[list(p) for p in camera['PRESETS']])
        self.assertTrue(all(-2<=v<len(presets) for v in codes.values()))
        for key,alternatives in ledger['frontagePartialViews'].items():
            self.assertEqual(codes[key],camera['OCCLUDED'])
            self.assertEqual(len(alternatives),len(camera['VIEWPORTS']))
            self.assertTrue(any(n>=0 for n in alternatives))
            self.assertTrue(all(-1<=n<len(presets) for n in alternatives))
        self.assertLess(len(gzip.compress((WEB/'taipei-frontage-cameras.js').read_bytes())),150*1024)
        self.assertNotEqual(codes['poi/node/3704017725'],0)  # reported Beitou obstruction
        self.assertEqual(codes['poi/node/6835876243'],0)  # open Muzha road

    @unittest.skipUnless(os.getenv('POCKET_TAIPEI_DATA'),'set POCKET_TAIPEI_DATA to the restored atlas')
    def test_full_pack_id_coverage_and_actual_mesh_replay(self):
        data=Path(os.environ['POCKET_TAIPEI_DATA'])
        city=camera['City'](data)
        rows={r['id']:r for r in camera['matched_rows'](data)}
        codes=artifact()['frontageViews']
        self.assertEqual(set(codes),set(rows))
        # Include both observed streets plus every recorded visibility outcome.
        ids={'poi/node/3704017725','poi/node/6835876243'}
        for status in set(codes.values()):
            ids.add(next(k for k,v in codes.items() if v==status))
        for key in sorted(ids):
            self.assertEqual(camera['shop_code'](city,rows[key]),codes[key],key)

    @unittest.skipUnless(os.getenv('POCKET_TAIPEI_DATA'),'set POCKET_TAIPEI_DATA to the restored atlas')
    def test_obstructions_between_old_anchors_against_actual_survey_meshes(self):
        data=Path(os.environ['POCKET_TAIPEI_DATA'])
        city=camera['City'](data)
        rows={r['id']:r for r in camera['matched_rows'](data)}
        ledger=artifact()
        cases = [('poi/node/7211425702',667,'mobile',7),('commerce/36',667,'mobile',6),
                 ('poi/node/9381950248',667,'mobile',12),('poi/node/12088965192',1200,'desktop',0),
                 ('poi/node/6284503804',1200,'desktop',1)]
        for key,height,mode,old_code in cases:
            row=rows[key]
            compact=mode=='mobile'
            active_zoom=3 if compact else 2
            # Reproduce the original false positive at the real CSS-pixel height.
            occluded=camera['shop_code'](city,row,[camera['PRESETS'][old_code]],[(compact,height)])
            self.assertEqual(occluded,camera['OCCLUDED'],key)
            code=ledger['frontageViews'][key]
            self.assertGreaterEqual(code,0,key)
            checked=ledger['frontageViewPresets'][code]
            valid=0
            for reference in ledger['frontageViewHeights'][mode]:
                zoom=checked[active_zoom]+math.log2(height/reference)
                if zoom>ledger['frontageViewMaxZoom']:
                    continue
                adjusted=checked.copy()
                adjusted[active_zoom]=zoom
                self.assertAlmostEqual(height/2**zoom,reference/2**checked[active_zoom])
                self.assertEqual(camera['shop_code'](city,row,[adjusted],[(compact,height)]),0,key)
                valid+=1
            self.assertGreater(valid,0,key)

    @unittest.skipUnless(os.getenv('POCKET_TAIPEI_DATA'),'set POCKET_TAIPEI_DATA to the restored atlas')
    def test_real_shop_windows_hidden_by_trunks_beneath_the_crown(self):
        data=Path(os.environ['POCKET_TAIPEI_DATA'])
        city=camera['City'](data)
        rows={r['id']:r for r in camera['matched_rows'](data)}
        ledger=artifact()
        solver=camera['shop_code']
        for key in ['poi/node/7194693256','poi/node/6314600439']:
            row=rows[key]
            old=[camera['PRESETS'][0]]
            with patch.dict(solver.__globals__,{'wood_triangles':lambda *_: np.empty((0,3,3))}):
                self.assertEqual(solver(city,row,old),0,key)
            self.assertEqual(solver(city,row,old),camera['OCCLUDED'],key)
            code=ledger['frontageViews'][key]
            self.assertNotEqual(code,0)
            if code>=0:
                self.assertEqual(solver(city,row,[camera['PRESETS'][code]]),0,key)
            else:
                self.assertEqual(solver(city,row),camera['OCCLUDED'],key)

    @unittest.skipUnless(os.getenv('POCKET_TAIPEI_DATA'),'set POCKET_TAIPEI_DATA to the restored atlas')
    def test_partial_by_height_and_no_solution_replay_against_survey(self):
        data=Path(os.environ['POCKET_TAIPEI_DATA'])
        city=camera['City'](data)
        rows={r['id']:r for r in camera['matched_rows'](data)}
        ledger=artifact()
        # This street admits several different angles but an obstructed tall desktop remains distinct.
        key='inspection/A-190620017-00002-5'
        row=rows[key]
        self.assertEqual(ledger['frontageViews'][key],-1)
        alternatives=ledger['frontagePartialViews'][key]
        self.assertTrue(any(code>=0 for code in alternatives) and -1 in alternatives)
        geometry=camera['shop_geometry'](city,row)
        for viewport,code in zip(camera['VIEWPORTS'],alternatives):
            self.assertEqual(camera['first_visible'](geometry,row['angle'],camera['PRESETS'],[viewport]),code)
        # The root obstruction at this shop blocks even separately evaluated anchors.
        blocked='poi/node/7194693256'
        self.assertNotIn(blocked,ledger['frontagePartialViews'])
        self.assertEqual(camera['camera_options'](city,rows[blocked]),(-1,[]))


if __name__ == '__main__':
    unittest.main()
