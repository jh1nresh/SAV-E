from pathlib import Path
import runpy
import unittest
import numpy as np

core = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'scripts/build-city170-hydrants.py'))


class HydrantEvidence(unittest.TestCase):
    def test_pillar_only(self):
        node = {'emergency':'fire_hydrant','fire_hydrant:type':'pillar'}
        self.assertTrue(core['eligible'](node))
        for tag in ({'fire_hydrant:type':'wall'}, {'fire_hydrant:type':'underground;pillar'},
                    {'fire_hydrant:type':''}, {'floor':'3'}, {'level':'2'}, {'addr:floor':'2樓'}, {'bridge':'yes'},
                    {'location':'underground'}, {'access':'private'}, {'indoor':'room'}, {'fixme':'unconfirmed'},
                    {'fire_hydrant:type:zh':'地下式消防栓'}, {'disused':'yes'}):
            self.assertFalse(core['eligible']({**node,**tag}))

    def test_street_is_public_and_at_grade(self):
        self.assertTrue(core['ground_street']({'highway':'residential'}))
        for tag in ({'tunnel':'yes'}, {'highway':'motorway'}, {'level':'1'}, {'access':'private'},
                    {'foot':'no'}, {'service':'driveway'}):
            self.assertFalse(core['ground_street']({'highway':'residential',**tag}))

    def test_rejects_under_sloped_roof_on_wall_or_flange_clipping_neighbor(self):
        roof = np.array([[[0.,0.],[5.,0.],[0.,5.]]])
        hit = core['footprint_hits']
        for triangles in [roof, roof[:,::-1,:]]:
            self.assertTrue(hit(triangles,1,1))
            self.assertTrue(hit(triangles,-.26,.12))
            self.assertFalse(hit(triangles,-.5,1))
            self.assertFalse(hit(triangles,4,4))
        vertical = np.array([[[0.,0.],[0.,0.],[0.,3.]]])
        self.assertTrue(hit(vertical,.2,1))
        self.assertFalse(hit(vertical,.4,2))


if __name__ == '__main__':
    unittest.main()
