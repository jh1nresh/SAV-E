"""Restore Taipei map assets using only the Python standard library."""
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import io
import json
import os
import shutil
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BUNDLES = ROOT / 'bundles'


def bundle_bytes(part):
    filename = part['file']
    if filename != Path(filename).name or not filename.endswith('.tar.xz'):
        raise ValueError(f'Invalid bundle path: {filename}')
    bundle = BUNDLES / filename
    if bundle.is_symlink():
        raise ValueError(f'Invalid archive: {filename}')
    content = bundle.read_bytes()
    if hashlib.sha256(content).hexdigest() != part['sha256']:
        raise ValueError(f'Checksum mismatch: {filename}')
    return content


def verified_bundles():
    parts = json.loads((BUNDLES / 'index.json').read_text())
    for part in parts:
        bundle_bytes(part)
    return parts


def extract_part(part, staging):
    count = 0
    # Check precisely the bytes being unpacked even if an archive changes during a build.
    with tarfile.open(fileobj=io.BytesIO(bundle_bytes(part)), mode='r|xz') as entries:
        for entry in entries:
            name = Path(entry.name)
            if not entry.isfile() or name.is_absolute() or '..' in name.parts:
                raise ValueError(f'Invalid asset path: {entry.name}')
            target = staging / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with entries.extractfile(entry) as source, target.open('xb') as dest:
                if target.suffix == '.gz':
                    with gzip.GzipFile(filename='', mode='wb', fileobj=dest, compresslevel=1, mtime=0) as compressed:
                        shutil.copyfileobj(source, compressed)
                else:
                    shutil.copyfileobj(source, dest)
            count += 1
    if count != part['entries']:
        raise ValueError(f'Incomplete bundle: {part["file"]}')


def restore(output=ROOT / 'data', *, parts=None):
    if output.exists():
        raise SystemExit('data already exists. Keep it to run the preview, or move it aside to restore this snapshot.')
    parts = verified_bundles() if parts is None else parts
    # Publish a complete directory only. Failed restores leave the current preview untouched.
    with tempfile.TemporaryDirectory(dir=output.parent, prefix=".restore-") as temporary:
        staging = Path(temporary) / 'data'
        staging.mkdir()
        with ThreadPoolExecutor(max_workers=3) as workers:
            list(workers.map(lambda part: extract_part(part, staging), parts))
        os.rename(staging, output)
    print(f'Restored {sum(p["entries"] for p in parts)} Taipei map assets.')


if __name__ == '__main__':
    restore()
