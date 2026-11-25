"""Check official shop identity and floor evidence before any wall match."""
from io import StringIO
from pathlib import Path
import runpy
import unittest

source = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'scripts/build-taipei-friendly-frontages.py'))


class FriendlyFrontages(unittest.TestCase):
    def test_only_local_exact_names_with_valid_coordinates_are_indexed(self):
        content = StringIO('友善店家名稱,地址,經度,緯度,電話\n'
                           '咖啡帶,108台北市萬華區大理街131號1樓,121.497,25.034,123456\n'
                           '咖啡帶,新北市板橋區文化路1號1樓,121.461,25.022,234567\n'
                           '咖啡帶美食,台北市萬華區大理街131號1樓,N/A,25.034,345678\n')
        rows = source['source_index'](content)
        self.assertEqual(list(rows), [('咖啡帶', '萬華區')])
        address, position = next(iter(rows['咖啡帶', '萬華區']))
        self.assertEqual(position, (121.497, 25.034))
        self.assertEqual(address.floor, '1樓')

    def test_conflicting_places_and_upper_floors_cannot_get_a_bay(self):
        address = source['A']['Address']
        evidence = source['ground_evidence']
        self.assertIsNone(evidence(address('大理街', '131', '2樓'), None, False))
        self.assertIsNone(evidence(address('大理街', '131', '1樓'), address('大理街', '133', ''), False))
        self.assertIsNone(evidence(address('大理街', '131', ''), None, False))
        self.assertEqual(evidence(address('大理街', '131', '1樓'), None, False), 'city-friendly-store-ground-floor')
        self.assertEqual(evidence(address('大理街', '131', ''), address('大理街', '131', '1樓'), True),
                         'original-ground-floor-and-city-list')


if __name__ == '__main__':
    unittest.main()
