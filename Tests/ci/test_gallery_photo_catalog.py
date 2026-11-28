import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('package_pocket_city', ROOT / 'scripts/package-pocket-city.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PhotoCatalogTests(unittest.TestCase):
    def test_every_reviewed_photo_exists_with_credit_and_dimensions(self):
        rows = package.place_photo_catalog()
        self.assertEqual(len(rows), 9)
        for row in rows:
            photo = package.WEB / 'assets/place-photos' / row['file']
            self.assertTrue(photo.is_file(), row['file'])
            self.assertEqual(photo.read_bytes()[:2], b'\xff\xd8')
            self.assertEqual(len(row['point']), 2)
            self.assertTrue(119 < row['point'][0] < 123)
            self.assertTrue(24 < row['point'][1] < 26)

    def test_same_name_branches_keep_separate_ids_files_and_addresses(self):
        rows = package.place_photo_catalog()
        branches = [row for row in rows if row['name'].startswith('美觀園')]
        self.assertEqual(len(branches), 2)
        for key in ('id', 'file', 'streetAddress'):
            self.assertEqual(len({row[key] for row in branches}), 2)

    def invalid(self, mutate):
        rows = package.place_photo_catalog()
        mutate(rows)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'place-photo-data.js').write_text('export default ' + json.dumps(rows) + ';')
            with patch.object(package, 'WEB', root), self.assertRaises(ValueError):
                package.place_photo_catalog()

    def test_path_escape_rejected(self):
        self.invalid(lambda rows: rows[0].update(file='../other.jpg'))

    def test_duplicate_identity_rejected(self):
        self.invalid(lambda rows: rows.append(rows[0]))

    def test_unattributed_photo_rejected(self):
        self.invalid(lambda rows: rows[0].update(credit=''))

    def test_invalid_dimensions_rejected(self):
        self.invalid(lambda rows: rows[0].update(width=0))


if __name__ == '__main__':
    unittest.main()
