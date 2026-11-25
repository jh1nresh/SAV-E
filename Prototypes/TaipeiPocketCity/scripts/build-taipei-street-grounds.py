"""Rebuild all twelve Taipei district street assets.

From TaipeiPocketCity, using the unpacked data/ archive and the pinned Songyan and runway inputs:
    uv run --python 3.12 --with shapely==2.2.0 scripts/build-taipei-street-grounds.py

Use --receipts DIR to record the complete input and output digests per district.
The bundled taipei-street-ground-receipts.json records the shipped geometry and input digests.
Independent districts may run concurrently with --jobs 2. Neighbor input order
and each district's output stay the same for either execution mode.
"""
import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path
import subprocess
import sys

CITY = Path(__file__).resolve().parents[1]
# Every shared administrative edge is handled once by the later district. A
# dependency is included even where a river separates the two road networks.
DISTRICTS = {
    'xinyi': ('信義區', ()),
    'songshan': ('松山區', ('xinyi',)),
    'daan': ('大安區', ('xinyi', 'songshan')),
    'zhongshan': ('中山區', ('songshan', 'daan')),
    'beitou': ('北投區', ()),
    'nangang': ('南港區', ('xinyi', 'songshan')),
    'wanhua': ('萬華區', ()),
    'datong': ('大同區', ('zhongshan', 'wanhua')),
    'shilin': ('士林區', ('zhongshan', 'datong', 'beitou')),
    'neihu': ('內湖區', ('songshan', 'zhongshan', 'shilin', 'nangang')),
    'zhongzheng': ('中正區', ('daan', 'zhongshan', 'datong', 'wanhua')),
    'wenshan': ('文山區', ('daan', 'xinyi', 'zhongzheng', 'nangang')),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--city', type=Path, default=CITY, help='TaipeiPocketCity directory containing unpacked data/')
    parser.add_argument('--out', type=Path, help='output directory; defaults to --city/assets')
    parser.add_argument('--receipts', type=Path)
    parser.add_argument('--jobs', type=int, default=1, choices=(1, 2, 3))
    args = parser.parse_args()
    assets = args.city / 'assets'
    target = args.out or assets
    target.mkdir(parents=True, exist_ok=True)
    if args.receipts:
        args.receipts.mkdir(parents=True, exist_ok=True)
    names = {k: v[0] for k, v in DISTRICTS.items()}

    def build(slug):
        name, neighbors = DISTRICTS[slug]
        command = [sys.executable, str(Path(__file__).with_name('build-xinyi-street-ground.py')),
                   '--city', str(args.city), '--district', name, '--out', str(target / f'{slug}-street-ground.json.gz')]
        legacy = [args.city / 'data' / f'street-{slug}-district.json',
                  args.city / 'data/city-streets' / f'{slug}-district.json.gz']
        for candidate in legacy:
            if candidate.is_file():
                command.extend(['--district-ground', str(candidate)])
                break
        if slug == 'xinyi':
            command.append('--verify-xinyi')
        for neighbor in neighbors:
            command.extend(['--join-ground', names[neighbor], str(target / f'{neighbor}-street-ground.json.gz')])
        if args.receipts:
            command.extend(['--receipt', str(args.receipts / f'{slug}.json')])
        subprocess.run(command, check=True)

    done, pending = set(), dict(DISTRICTS)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        running = {}
        while pending or running:
            for slug, (_, neighbors) in list(pending.items()):
                if len(running) == args.jobs:
                    break
                if done.issuperset(neighbors):
                    running[pool.submit(build, slug)] = slug
                    del pending[slug]
            if not running:
                raise ValueError(f'Unresolved district dependencies: {list(pending)}')
            for result in wait(running, return_when=FIRST_COMPLETED).done:
                result.result()
                done.add(running.pop(result))


if __name__ == '__main__':
    main()
