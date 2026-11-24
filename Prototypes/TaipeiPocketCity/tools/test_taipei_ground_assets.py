"""Check the archived public ground overlays without needing a live basemap."""
import json
from pathlib import Path
import tarfile
import unittest

BUNDLE = Path(__file__).resolve().parents[1]/'bundles/taipei-hydrology-habitats.tar.xz'


class TaipeiGroundAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tarfile.open(BUNDLE) as bundle:
            cls.layers = {member.name:json.load(bundle.extractfile(member)) for member in bundle}

    def test_waterways_only_include_open_surface_features(self):
        layer = self.layers['city170-waterways.json.gz']
        ids = [f['id'] for f in layer['features']]
        self.assertEqual(len(set(ids)),len(ids))
        self.assertNotIn('waterway/way/1392270702',ids)  # pipeline
        self.assertNotIn('waterway/way/396674703',ids)  # level -1
        self.assertEqual({f['properties']['category'] for f in layer['features']},{'river','stream','canal','drain','ditch'})
        self.assertTrue(all(f['geometry']['type'] in ('LineString','MultiLineString') for f in layer['features']))

    def test_farms_and_open_ground_share_the_verified_atlas(self):
        layer = self.layers['city170-farmland.json.gz']
        self.assertEqual(layer['sourceSHA256'],self.layers['city170-waterways.json.gz']['sourceSHA256'])
        self.assertEqual({f['properties']['category'] for f in layer['features']},{'farmland','orchard'})
        self.assertTrue(all(f['geometry']['type'] in ('Polygon','MultiPolygon') for f in layer['features']))
        roots=self.layers['city170-open-ground.json.gz']
        self.assertGreater(len(roots),0)
        self.assertTrue(all(len(set(map(tuple,points)))==len(points) for points in roots.values()))


if __name__=='__main__':
    unittest.main()
