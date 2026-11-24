"""Package a prepared city data directory for this review snapshot."""
import argparse
import gzip
import hashlib
import io
import json
import lzma
import tarfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

PART_BYTES = 160 * 1024 * 1024


def chunks(root):
    group, size = [], 0
    for path in sorted(p for p in root.rglob('*') if p.is_file()):
        length = path.stat().st_size
        if path.suffix == '.gz':
            with path.open('rb') as stream:
                stream.seek(-4, 2)
                length = int.from_bytes(stream.read(), 'little')
        if group and size + length > PART_BYTES:
            yield group
            group, size = [], 0
        group.append(path)
        size += length
    if group:
        yield group


def pack(label, paths, root, output):
    target = output / f'taipei-{label}.tar.xz'
    with lzma.open(target, 'wb', preset=2) as compressed:
        with tarfile.open(fileobj=compressed, mode='w|') as archive:
            for path in paths:
                data = path.read_bytes()
                if path.suffix == '.gz':
                    data = gzip.decompress(data)
                entry = tarfile.TarInfo(path.relative_to(root).as_posix())
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
    # Keep checked-in artifacts small enough to transfer and verify independently.
    if target.stat().st_size > 10 * 1024 * 1024 and len(paths) > 1:
        midpoint = len(paths) // 2
        left = pack(label + 'a', paths[:midpoint], root, output)
        right = pack(label + 'b', paths[midpoint:], root, output)
        target.unlink()
        return left + right
    return [{'file': target.name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'entries': len(paths)}]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('data', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        tasks = [pool.submit(pack, f'{n:02d}', group, args.data, args.output) for n, group in enumerate(chunks(args.data), 1)]
        parts = [part for task in tasks for part in task.result()]
    (args.output / 'index.json').write_text(json.dumps(parts, indent=2) + '\n')


if __name__ == '__main__':
    main()
