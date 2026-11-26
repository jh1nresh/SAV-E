"""Deck topology and registration against the shipped Taipei street vector tiles."""
import gzip
import json
from pathlib import Path
import runpy
import unittest

from shapely import STRtree, union_all
from shapely.geometry import LineString, box

CITY = Path(__file__).resolve().parents[1]
G = runpy.run_path(str(CITY/'scripts/build-taipei-road-bridges.py'))


class RoadBridges(unittest.TestCase):
    def test_grade_boundary(self):
        raw = {'highway': 'trunk_link', 'bridge': 'yes', 'layer': '1'}
        self.assertTrue(G['raised'](raw))
        for change in ({'bridge': 'no'}, {'layer': '0'}, {'layer': '-1'}, {'layer': '1;2'},
                       {'railway': 'rail'}, {'tunnel': 'yes'}, {'motor_vehicle': 'no'}):
            self.assertFalse(G['raised'](raw | change))

    def test_requires_shared_node_compatible_grade_direction_and_paint(self):
        joint = [121.57, 25.03]
        data = {1: {'geometry': {'coordinates': [joint, [121.5703, 25.03]]}},
                2: {'geometry': {'coordinates': [joint, [121.5697, 25.03]]}}}
        ways = {1: ({'highway': 'secondary', 'bridge': 'yes', 'layer': '1'}, [21, 22]),
                2: ({'highway': 'secondary'}, [21, 23])}
        junction = {21: [(1, 0), (2, 0)]}
        paint = STRtree([box(19000, 29000, 21000, 31000)])
        tied = lambda graph, surface: G['tied_end'](1, 0, ways, data, graph, surface)
        self.assertTrue(tied(junction, paint))
        self.assertFalse(tied({21: [(1, 0)], 44: [(2, 0)]}, paint))
        self.assertFalse(tied(junction, STRtree([])))
        data[2]['geometry']['coordinates'][1] = [121.57, 25.0303]
        self.assertFalse(tied(junction, paint))
        data[2]['geometry']['coordinates'][1] = [121.5697, 25.03]
        for change in [{'bridge': 'yes'}, {'tunnel': 'yes'}, {'layer': '1'}, {'highway': 'motorway_link'}]:
            ways[2] = ({'highway': 'secondary'} | change, [21, 23])
            self.assertFalse(tied(junction, paint))

    def test_only_complete_unshared_tile_fragments_can_be_hidden(self):
        certify = runpy.run_path(str(CITY/'scripts/bridge-vector-paint.py'))['paint_ids']
        lane = lambda a,b,y=0: LineString([(a,y),(b,y)])
        span = lane(0,100)
        def check(rows):
            ids = list(rows)
            return certify(span, 1, STRtree([g for g,_ in rows.values()]), ids,
                           {k:{grade} for k,(_,grade) in rows.items()})
        self.assertEqual(check({720:(lane(0,60),1), 912:(lane(60,100),1)}), [720,912])
        self.assertEqual(check({720:(union_all([lane(0,60),lane(60,115)]),1)}), [])
        self.assertEqual(check({720:(lane(0,57),1), 912:(lane(66,100),1)}), [])
        self.assertEqual(check({720:(span,2)}), [])
        self.assertEqual(check({720:(span,1), 912:(lane(40,120,.4),3)}), [])

    def test_shipped_decks_match_all_local_tile_fragments_without_hiding_stacked_roads(self):
        tile = runpy.run_path(str(CITY/'scripts/bridge-vector-paint.py'))
        metres = G['GROUND']['metres']
        strokes, grades = tile['bridge_strokes'](CITY/'cities/map-tiles/taipei-bundled', metres)
        ids, tree = list(strokes), STRtree(list(strokes.values()))
        spans = G['read'](CITY/'assets/taipei-road-bridges.json.gz')
        for span in spans:
            raw = metres(LineString(span['line']))
            grade, = grades[span['paintIds'][0]]
            self.assertEqual(tile['paint_ids'](raw, grade, tree, ids, grades), span['paintIds'])
        roads = G['atlas_roads'](CITY/'data')
        way = lambda ident: metres(LineString(roads[ident]['geometry']['coordinates']))
        # The actual base IDs for Wenchang and Sanhe extend outside their mapped
        # deck. Suppressing them would also hide an approach or neighbouring road.
        for ident, extra in [(25976466, 100), (30471090, 30)]:
            self.assertGreater(strokes[ident*10].difference(way(ident).buffer(tile['TOLERANCE'])).length, extra)
        a, b = way(48793403), way(51813001)
        self.assertAlmostEqual(a.distance(b), 1.56, places=2)
        overlap = a.buffer(4.5,cap_style='flat',join_style='mitre').intersection(
            b.buffer(4.5,cap_style='flat',join_style='mitre')).area
        self.assertGreater(overlap, 1700)
        self.assertEqual(grades[487934032], {2})
        self.assertEqual(grades[5525138382], {3})
        self.assertGreater(strokes[5525138382].intersection(a.buffer(tile['TOLERANCE'])).length, 300)

    def test_real_bridge_geometry_survives_the_cell_and_district_edges(self):
        spans = json.loads(gzip.decompress((CITY/'assets/taipei-road-bridges.json.gz').read_bytes()))
        by_id = {s['id']: s for s in spans}
        self.assertEqual(len(by_id), len(spans))
        ramp = by_id['road/way/138265874']
        self.assertEqual(ramp['name'], '信義路入口匝道')
        self.assertEqual(ramp['line'][0], [121.5724354, 25.0328121])
        self.assertEqual(ramp['line'][-1], [121.5715215, 25.0321531])
        self.assertEqual(len(ramp['line']), 17)
        self.assertNotIn('road/way/771835296', by_id)  # embankment
        self.assertNotIn('road/way/49749051', by_id)   # tunnel
        for ident in (48793403, 51813001, 25976466, 30471090):
            self.assertNotIn(f'road/way/{ident}', by_id)
        self.assertEqual(ramp['paintIds'], [1382658742])
        self.assertEqual(by_id['road/way/75258768']['name'], '成功橋')
        self.assertEqual(by_id['road/way/75367779']['name'], '成功橋')
        deck_footprints = [G['GROUND']['metres'](LineString(s['line'])).buffer(s['width']/2,
                           cap_style='flat', join_style='mitre') for s in spans]
        tree = STRtree(deck_footprints)
        for i, deck in enumerate(deck_footprints):
            for j in tree.query(deck, predicate='intersects'):
                if j > i:
                    self.assertLessEqual(deck.intersection(deck_footprints[j]).area, .01)
        for span in spans:
            self.assertEqual(span['box'], list(LineString(span['line']).bounds))
            self.assertGreater(span['width'], 0)


if __name__ == '__main__':
    unittest.main()
