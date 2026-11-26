#!/usr/bin/env python3
"""Package the reviewed Pocket City web runtime for the native iOS resource server."""
import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path

WEB = Path(__file__).resolve().parents[1] / 'Prototypes/TaipeiPocketCity'
sys.dont_write_bytecode = True
sys.path.insert(0, str(WEB))
import prepare_data

MODULE = re.compile(r"""(?:\bfrom\s*|\bimport\s*|\bnew URL\(\s*)['"](\.{1,2}/[^'"?\s]+?\.m?js)(?:\?[^'"]*)?['"]""")
STARTUP = ('districts.geojson', 'survey-index.json', 'landmark-101.json',
           'city-streets/index.json', 'city170-material.png', 'city-place-index.json.gz')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def runtime_paths():
    """Positive list; authoring inputs, local credentials and shared-post exports never enter the bundle."""
    paths = set()

    def include(name):
        candidate = WEB / name
        real = candidate.resolve()
        if not real.is_relative_to(WEB) or real != candidate or not real.is_file():
            raise ValueError(f'Missing or invalid public map asset: {name}')
        paths.add(name)
        return real

    def document(name):
        return json.loads(include(name).read_text())

    for path in ('index.html', 'style.css', 'taipei101-indoor.css', 'assets/icon.png', 'assets/maplibre-gl.css',
                 'assets/MapLibre-LICENSE.txt', 'assets/Pocket-City-LICENSE.txt', 'assets/base-style.json',
                 'assets/taipei-arcade-floors.json.gz', 'assets/taipei-river-art.json.gz',
                 'assets/taipei-tree-canopies.json.gz', 'assets/taipei-streetlights.json.gz',
                 'assets/taipei101-single-ground.png', 'assets/taipei101-pocket-city-ink.bin.gz', 'assets/taipei101-pocket-city.bin.gz', 'assets/taipei-eslite-songyan.bin.gz'):
        include(path)
    # Start from the iOS entry point and follow static ESM and module-worker references.
    modules = ['app.js', 'assets/maplibre-gl-worker.mjs']
    while modules:
        name = modules.pop()
        if name in paths:
            continue
        text = include(name).read_text()
        for ref in MODULE.findall(text):
            dest = ((WEB / name).parent / ref).resolve()
            modules.append(dest.relative_to(WEB).as_posix())

    for photo in re.findall(r"\bfile:\s*'([\w-]+\.jpg)'", (WEB / 'place-photos.js').read_text()):
        include('assets/place-photos/' + photo)
    for row in document('cities/catalog.json'):
        for filename in ('scene.json', 'map-mesh.json', 'map-mesh.bin'):
            include(f'cities/{row["id"]}/{filename}')
    tiles = document('cities/map-tiles/index.json')
    for x, y in tiles['tiles']:
        for ext in ('pbf', 'png'):
            include(f'cities/map-tiles/{x}-{y}.{ext}')
    for z in range(tiles['overviewMaxZoom'] + 1):
        for x in range(2**z):
            for y in range(2**z):
                include(f'cities/map-tiles/overview/{z}-{x}-{y}.pbf')
    region = 'cities/map-tiles/taipei-bundled/'
    for name in regional_tile_names(document(region + 'index.json')):
        include(region + name)
    for filename in ('cells.json', 'town-index.json', 'townships.geojson.gz', 'places/names.json.gz',
                     'scenery/places.geojson.gz', 'scenery/river-search.json.gz',
                     'scenery/rivers.geojson.gz', 'scenery/waters.geojson.gz'):
        include('taiwan/' + filename)
    for directory in ('places', 'streets', 'materials'):
        for key in document(f'taiwan/{directory}/index.json')['tiles']:
            include(f'taiwan/{directory}/{key}.json.gz')
    for directory in ('relief', 'mountains'):
        root = f'taiwan/{directory}'
        js = include(f'{root}/index.js').read_text()
        relief = json.loads(js.split('export default', 1)[1].strip().rstrip(';'))
        for sheet in relief['sheets']:
            include(f'{root}/{sheet["name"]}.webp')
        for tile in relief['dem']:
            include(f'{root}/dem/{tile}.png')
    return sorted(paths)


def inventory(directory):
    """Fast output validity check. File identities survive hard-link staging and directory renames."""
    result = {}
    pending = [directory] if directory.exists() else []
    while pending:
        with os.scandir(pending.pop()) as entries:
            for entry in entries:
                path = Path(entry.path)
                if entry.is_dir(follow_symlinks=False):
                    pending.append(path)
                    continue
                key = path.relative_to(directory).as_posix()
                st = entry.stat(follow_symlinks=False)
                # Never traverse a stale symlink in a build product.
                result[key] = ['link'] if entry.is_symlink() else [st.st_ino, st.st_size, st.st_mtime_ns]
    return result


def package(output):
    if output.name != 'PocketCity' or output.is_symlink():
        raise ValueError('The output must be the PocketCity resource directory')
    output = output.resolve()
    if output.is_relative_to(WEB) or WEB.is_relative_to(output):
        raise ValueError('Output overlaps the map source tree')
    output.parent.mkdir(parents=True, exist_ok=True)
    # Keep temporary resources, previous versions and build receipts outside the signed app.
    app = next((p for p in output.parents if p.suffix == '.app'), None)
    build_dir = Path(os.environ['TARGET_TEMP_DIR']) if app and os.environ.get('TARGET_TEMP_DIR') else (app.parent if app else output.parent)
    key = hashlib.sha256(os.fsencode(output)).hexdigest()[:12]
    cache = build_dir / ('.pocket-city-build-' + key)
    cache.mkdir(exist_ok=True)
    with (cache / 'package.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        preview = os.environ.get('CONFIGURATION') == 'Debug'
        build(output, cache, preview)
        # Keep the native-only snapshot outside the directory served by WebKit.
        if output.parent.suffix != '.app':
            return
        native = output.parent / 'TaipeiPublicSourceSnapshot.json'
        source = os.environ.get('SAVVY_LOCAL_NATIVE_SOURCES') if preview else None
        if source:
            staged = cache / 'native-snapshot.next'
            shutil.copyfile(source, staged)
            os.replace(staged, native)
        else:
            native.unlink(missing_ok=True)


def build(output, cache, preview):
    staging, previous, stamp = (cache / name for name in ('staging', 'previous', 'receipt.json'))
    if previous.exists() and not output.exists():
        os.rename(previous, output)
    for abandoned in (staging, previous):
        if abandoned.exists():
            shutil.rmtree(abandoned)
    parts = prepare_data.verified_bundles()
    data_version = [digest(WEB / 'prepare_data.py'), parts]
    inputs = {name: WEB / name for name in runtime_paths()}
    if preview:
        if source := os.environ.get('SAVVY_LOCAL_POCKET_CITY_SOURCES'):
            inputs['savvy-place-sources.json'] = Path(source)
        if tiles := os.environ.get('SAVVY_LOCAL_TAIPEI_TILES'):
            inputs.update(preview_tile_inputs(Path(tiles)))
    runtime = {name: digest(path) for name, path in inputs.items()}
    try:
        receipt = json.loads(stamp.read_text())
    except (FileNotFoundError, ValueError):
        receipt = {}

    actual = inventory(output)
    signature = {'runtime': runtime, 'bundles': data_version}
    if signature == receipt.get('inputs') and actual == receipt.get('files'):
        print(f'Pocket City up to date ({len(actual)} files).')
        return
    staging.mkdir()
    old_data = {n: v for n, v in receipt.get('files', {}).items() if n.startswith('data/')}
    current_data = {n: v for n, v in actual.items() if n.startswith('data/')}
    reuse_data = old_data and old_data == current_data and receipt.get('inputs', {}).get('bundles') == data_version
    try:
        if reuse_data:
            shutil.copytree(output / 'data', staging / 'data', copy_function=os.link)
        else:
            prepare_data.restore(staging / 'data', parts=parts)
        for name in STARTUP:
            if not (staging / 'data' / name).is_file():
                raise ValueError(f'Missing required Taipei asset: {name}')
        for name in runtime:
            dest = staging / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(inputs[name], dest)
            if digest(dest) != runtime[name]:
                raise ValueError(f'Asset changed during packaging: {name}')
        files = inventory(staging)
        new_stamp = cache / 'receipt.next'
        new_stamp.write_text(json.dumps({'inputs': signature, 'files': files}, separators=(',', ':')))
        if output.exists():
            os.rename(output, previous)
        try:
            os.rename(staging, output)
        except BaseException:
            if previous.exists():
                os.rename(previous, output)
            raise
        os.replace(new_stamp, stamp)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    if previous.exists():
        shutil.rmtree(previous)
    print(f'Packaged Pocket City ({len(files)} files, {sum(s[1] for s in files.values()):,} bytes).')


def regional_tile_names(manifest):
    for zoom, x, y in manifest['tiles']:
        if (not all(type(n) is int for n in (zoom, x, y)) or not 3 <= zoom <= 14
                or not 0 <= x < 2**zoom or not 0 <= y < 2**zoom):
            raise ValueError(f'Invalid regional tile: {zoom}/{x}/{y}')
        yield f'{zoom}-{x}-{y}.pbf'


def preview_tile_inputs(source):
    manifest = source / 'index.json'
    prefix = 'cities/map-tiles/taipei-preview/'
    names = ('index.json', *regional_tile_names(json.loads(manifest.read_text())))
    return {prefix + name: source / name for name in names}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    package(parser.parse_args().output)
