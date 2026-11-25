"""Reproduce alignment and placement decisions at street or path edges."""
from pathlib import Path
import runpy
import unittest

from shapely import LineString, Point, STRtree

D = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'scripts/build-city170-pedestrian-bins.py'))


class PedestrianBinPlacement(unittest.TestCase):
    def test_road_clearance_and_sidewalk_facing(self):
        road = STRtree([LineString([(0, -20), (0, 20)])])
        empty = STRtree([])
        direction = D['direction']
        self.assertIsNone(direction(Point(3.5, 0), road, [3], empty))
        self.assertEqual(direction(Point(5, 0), road, [3], empty), 0)
        self.assertEqual(direction(Point(-5, 0), road, [3], empty), 180)
        self.assertIsNone(direction(Point(-12, 0), road, [3], empty))

    def test_path_is_clear_and_receives_orientation_priority(self):
        road = STRtree([LineString([(0, -20), (0, 20)])])
        path = STRtree([LineString([(5, -20), (5, 20)])])
        direction = D['direction']
        self.assertIsNone(direction(Point(5.3, 0), road, [3], path))
        self.assertEqual(direction(Point(7.2, 0), road, [3], path), 180)
        self.assertIsNone(direction(Point(.5, 0), road, [3], path))


if __name__ == '__main__':
    unittest.main()
