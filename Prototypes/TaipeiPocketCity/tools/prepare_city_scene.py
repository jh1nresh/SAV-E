"""Run Pocket City prep with the empty clipped-water fix for land plots close to the sea."""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("skill", type=Path)
parser.add_argument("folder", type=Path)
args = parser.parse_args()
scripts = args.skill / "scripts"
source = (scripts / "prep.py").read_text()
start = source.index("# a few at anchor further out")
source = source[:start] + source[start:].replace("for i in range(60):", "for i in range(0 if sea.is_empty else 60):", 1)
with tempfile.TemporaryDirectory() as tmp:
    program = Path(tmp) / "prep.py"
    program.write_text(source)
    import os
    env = dict(os.environ, PYTHONPATH=str(scripts))
    subprocess.run([sys.executable, str(program), "--osm", str(args.folder / "osm.json"),
                    "--plot", str(args.folder / "plot.json"), "--out", str(args.folder / "scene.json")], env=env, check=True)
