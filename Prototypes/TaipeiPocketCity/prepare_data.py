"""Restore Taipei map assets using only the Python standard library."""
import gzip
import hashlib
import json
import os
import shutil
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BUNDLES = ROOT / 'bundles'


def restore():
    output = ROOT / 'data'
    if output.exists():
        raise SystemExit('data already exists. Keep it to run the preview, or move it aside to restore this snapshot.')
    parts = json.loads((BUNDLES / 'index.json').read_text())
    # Publish a complete directory only. Failed or interrupted restores leave the current preview untouched.
    with tempfile.TemporaryDirectory(dir=ROOT, prefix=".restore-") as temporary:
        staging = Path(temporary) / 'data'
        staging.mkdir()
        for part in parts:
            bundle = BUNDLES / part['file']
            if hashlib.sha256(bundle.read_bytes()).hexdigest() != part['sha256']:
                raise ValueError(f'Checksum mismatch: {bundle.name}')
            count = 0
            with tarfile.open(bundle, 'r|xz') as entries:
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
                raise ValueError(f'Incomplete bundle: {bundle.name}')
        os.rename(staging, output)
    print(f'Restored {sum(p["entries"] for p in parts)} Taipei map assets.')


if __name__ == '__main__':
    restore()
