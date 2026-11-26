"""Run with python3 -B scripts/test-package-pocket-city.py."""
import gzip
import hashlib
import importlib.util
import io
import json
import math
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
                         'taipei101-indoor.js', 'taipei101-indoor-data.js', 'taipei101-indoor.css',
                         'taipei101-floor-guide.js', 'taipei101-directory.js', 'taipei101-mall-tenants.js',
                         'taipei101-wayfinding.js', 'taipei101-wayfinding-data.js',
                         'taipei-metro-exits.js', 'taipei-metro-exit-data.js',
                         'taiwan/mountains/yushan-ridges.webp', 'taiwan/mountains/taiwan-highlands.webp',
                         'taipei-river-art.js', 'assets/taipei-arcade-floors.json.gz', 'assets/taipei-river-art.json.gz',
                         'taipei-frontage-cameras.js', 'taipei-edge-frontages.js', 'city170-bike-docks.js', 'shop-categories.js',
                         'taipei-tree-canopies.js', 'assets/taipei-tree-canopies.json.gz',
                         'taipei-riverside-pavilion-mesh.js', 'city170-riverside-pavilion-points.js',
                         'taipei-bike-rack-mesh.js', 'city170-bike-rack-points.js',
                         'taipei-trail-sign-mesh.js', 'city170-trail-sign-points.js',
                         'taipei-post-box-mesh.js', 'city170-post-box-points.js',
                         'taipei-registered-frontages.js', 'taipei-friendly-frontages.js',
                         'shop-convenience-fascias.js', 'taipei-convenience-art.js',
                         'city170-fountain-water-data.js', 'assets/taipei-streetlights.json.gz',
                         'taipei-eslite-songyan.js', 'assets/taipei101-single-ground.png', 'assets/taipei101-pocket-city-ink.bin.gz', 'assets/taipei101-pocket-city.bin.gz',
                         'assets/taipei-songyan-factory.bin.gz', 'assets/taipei-songyan-factory-terrain.png',
                         'assets/songshan-street-ground.json.gz', 'assets/xinyi-street-ground.json.gz', 'assets/taipei-songyan-waterfront.bin.gz', 'assets/taipei-eslite-songyan.bin.gz',
                         'taipei-market-stalls.js', 'taipei-market-stalls-data.js',
                         'cities/jiufen-shuqi/map-mesh.bin', 'cities/jiufen-shuqi/scene.json',
                         'cities/map-tiles/13737-7010.png', 'cities/map-tiles/13737-7010.pbf'} <= runtime)
        terrain_keys = json.loads((pkg.WEB / 'assets/taipei-street-grade/index.json').read_text())
        self.assertIn('13724/7014', terrain_keys)  # 101 and Songyan share a DEM tile.
        for key in terrain_keys:
            self.assertIn(f"assets/taipei-street-grade/14-{key.replace('/', '-')}.png", runtime)
        for mode in ('cloudy', 'drizzle', 'rain'):
            self.assertIn(f'assets/taipei101-ground-{mode}.png', runtime)
        for directory in ('streets', 'materials'):
            folder = f'taiwan/{directory}'
            index = json.loads((pkg.WEB / folder / 'index.json').read_text())
            self.assertTrue(index['tiles'])
            self.assertTrue(all(f'{folder}/{key}.json.gz' in runtime for key in index['tiles']))
        district_art = {p for p in runtime if p.endswith('-street-ground.json.gz')}
        self.assertEqual(len(district_art), 12)
        terrain_manifest = (pkg.WEB / 'taiwan/taipei-relief/index.js').read_text()
        terrain = json.loads(terrain_manifest.split('export default', 1)[1].strip().rstrip(';'))
        self.assertTrue(terrain['dem'])
        self.assertTrue(all(f'taiwan/taipei-relief/dem/{key}.png' in runtime for key in terrain['dem']))
        self.assertTrue({'taipei-road-bridges.js', 'taipei-bridge-mesh.js', 'assets/taipei-road-bridges.json.gz'} <= runtime)
        self.assertTrue({'assets/xinyi-ridge-relief.png', 'assets/xinyi-ridge-woods.json.gz',
                         'assets/songshan-river-meadow.json.gz', 'xinyi-ridge-woods.js',
                         'songshan-river-meadow.js', 'taipei-street-districts.js'} <= runtime)
        self.assertFalse(any(name.startswith(('examples/', 'bundles/', 'tools/', 'scripts/')) or
                             name.endswith(('.tar.xz', 'source.json.gz', 'osm.json', '.py')) for name in runtime))
        self.assertTrue({'apple-config.js', 'savvy-place-sources.json'}.isdisjoint(runtime))

    def test_default_bundle_covers_taipei_at_every_intermediate_zoom(self):
        root = 'cities/map-tiles/'
        catalog = json.loads((pkg.WEB / root / 'index.json').read_text())
        region = json.loads((pkg.WEB / root / 'taipei-bundled/index.json').read_text())
        packaged = set(pkg.runtime_paths())
        self.assertIn(root + 'taipei-bundled/index.json', packaged)
        self.assertEqual(region['source'], catalog['vectorTemplate'])
        bundled = {(z, x, y) for z, x, y in region['tiles']}
        shared = {(14, x, y) for x, y in catalog['tiles']}
        self.assertEqual(len(bundled), len(region['tiles']))
        for name in pkg.regional_tile_names(region):
            path = root + 'taipei-bundled/' + name
            self.assertIn(path, packaged)
            self.assertEqual(gzip.decompress((pkg.WEB / path).read_bytes())[:1], b'\x1a')

        def tile(z, lon, lat):
            side = 2**z
            return (math.floor((lon + 180) / 360 * side),
                    math.floor((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * side))

        west, south, east, north = 121.43, 24.95, 121.68, 25.211
        self.assertEqual(region['bounds'], [west, south, east, north])
        for z in range(3, 15):
            left, top = tile(z, west, north)
            right, bottom = tile(z, east, south)
            required = {(z, x, y) for x in range(left, right + 1) for y in range(top, bottom + 1)}
            self.assertEqual(required - (bundled | shared), set(), f'missing tiles at zoom {z}')

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
                snapshot = root / 'verified-sources.json'
                snapshot.write_text('{"schemaVersion":1}')
                local = {'SAVVY_LOCAL_POCKET_CITY_SOURCES': str(snapshot),
                         'SAVVY_LOCAL_NATIVE_SOURCES': str(snapshot)}
                with patch.dict(os.environ, {**local, 'CONFIGURATION': 'Debug'}):
                    pkg.package(output)
                    pkg.package(output)
                    self.assertEqual((output / 'savvy-place-sources.json').read_bytes(), snapshot.read_bytes())
                    self.assertEqual((output.parent / 'TaipeiPublicSourceSnapshot.json').read_bytes(), snapshot.read_bytes())
                with patch.dict(os.environ, {**local, 'CONFIGURATION': 'Release'}):
                    pkg.package(output)
                    self.assertFalse((output / 'savvy-place-sources.json').exists())
                    self.assertFalse((output.parent / 'TaipeiPublicSourceSnapshot.json').exists())
                data.unlink()
                pkg.package(output)
                self.assertEqual(gzip.decompress(data.read_bytes()), payload)
                archive.write_bytes(b'broken')
                with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                    pkg.package(output)
                self.assertEqual((output / 'index.html').read_text(), 'second')


if __name__ == '__main__':
    unittest.main()
