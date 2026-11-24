"""Run with python3 -B scripts/test-package-pocket-city.py."""
import gzip
import hashlib
import importlib.util
import io
import json
import os
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('pocket_package', Path(__file__).with_name('package-pocket-city.py'))
pkg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


class PocketCityPackageTests(unittest.TestCase):
    def test_runtime_includes_scene_worker_and_no_working_inputs(self):
        runtime = set(pkg.runtime_paths())
        self.assertTrue({'ios-map.js', 'taiwan-search-worker.js', 'assets/maplibre-gl-worker.mjs',
                         'taiwan/mountains/yushan-ridges.webp', 'taiwan/mountains/taiwan-highlands.webp',
                         'cities/jiufen-shuqi/map-mesh.bin', 'cities/jiufen-shuqi/scene.json',
                         'cities/map-tiles/13737-7010.png', 'cities/map-tiles/13737-7010.pbf'} <= runtime)
        for directory in ('streets', 'materials'):
            folder = f'taiwan/{directory}'
            index = json.loads((pkg.WEB / folder / 'index.json').read_text())
            self.assertTrue(index['tiles'])
            self.assertTrue(all(f'{folder}/{key}.json.gz' in runtime for key in index['tiles']))
        self.assertFalse(any(name.startswith(('examples/', 'bundles/', 'tools/', 'scripts/')) or
                             name.endswith(('.tar.xz', 'source.json.gz', 'osm.json', '.py')) for name in runtime))
        self.assertTrue({'apple-config.js', 'savvy-place-sources.json'}.isdisjoint(runtime))

    def test_stage_updates_removes_stale_and_recovers_from_interruption(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            web = root / 'prototype'
            bundles = web / 'bundles'
            bundles.mkdir(parents=True)
            output = root / 'Product.app' / 'PocketCity'
            (web / 'prepare_data.py').write_text('fixture')
            (web / 'index.html').write_text('first')
            (web / 'data').mkdir()
            (web / 'data/private.json').write_text('local only')
            archive = bundles / 'chunk.tar.xz'
            payload = b'Taipei survey'
            with tarfile.open(archive, 'w:xz') as stream:
                for name in pkg.STARTUP:
                    member = tarfile.TarInfo(name)
                    member.size = len(payload)
                    stream.addfile(member, io.BytesIO(payload))
            (bundles / 'index.json').write_text(json.dumps([
                {'file': archive.name, 'entries': len(pkg.STARTUP), 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}]))
            with patch.object(pkg, 'WEB', web), patch.object(pkg, 'runtime_paths', return_value=['index.html']), \
                 patch.object(pkg.prepare_data, 'BUNDLES', bundles):
                pkg.package(output)
                data = output / 'data/city-place-index.json.gz'
                inode = data.stat().st_ino
                self.assertEqual(gzip.decompress(data.read_bytes()), payload)
                self.assertFalse((output / 'data/private.json').exists())
                with patch.object(pkg.prepare_data, 'restore', side_effect=AssertionError('unexpected restore')):
                    pkg.package(output)
                    (web / 'index.html').write_text('second')
                    (output / 'stale.png').write_bytes(b'x')
                    (output / 'stale-link').symlink_to(web / 'data/private.json')
                    pkg.package(output)
                    self.assertFalse((output / 'stale.png').exists())
                    self.assertFalse((output / 'stale-link').exists())
                    self.assertEqual((output / 'index.html').read_text(), 'second')
                    self.assertEqual(data.stat().st_ino, inode)
                    cache, = root.glob('.pocket-city-build-*')
                    os.rename(output, cache / 'previous')
                    (cache / 'staging').mkdir()
                    (cache / 'staging/unfinished').touch()
                    pkg.package(output)
                    self.assertEqual(data.stat().st_ino, inode)
                    self.assertFalse((cache / 'staging').exists())
                    self.assertEqual(list(output.parent.iterdir()), [output])
                data.unlink()
                pkg.package(output)
                self.assertEqual(gzip.decompress(data.read_bytes()), payload)
                archive.write_bytes(b'broken')
                with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                    pkg.package(output)
                self.assertEqual((output / 'index.html').read_text(), 'second')


if __name__ == '__main__':
    unittest.main()
