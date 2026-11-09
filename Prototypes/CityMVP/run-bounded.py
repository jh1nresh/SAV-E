#!/usr/bin/env python3
"""Run one owned command with a disk floor and allocated-cache limit."""
import os, shutil, signal, subprocess, sys, time
from pathlib import Path
root = Path(__file__).resolve().parent
floor = 2 * 1024**3
limit = 3 * 1024**3
if len(sys.argv) < 2:
    raise SystemExit('usage: run-bounded.py COMMAND [ARGS]')
if shutil.disk_usage(root).free < floor:
    raise SystemExit('BLOCKED: less than 2 GiB free, no command started')
process = None

def interrupted(signum, frame):
    raise InterruptedError('Build monitor interrupted')

for event in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(event, interrupted)
result = 75
try:
    process = subprocess.Popen(sys.argv[1:], start_new_session=True)
    last_size_check = 0
    while process.poll() is None:
        if shutil.disk_usage(root).free < floor:
            raise RuntimeError('free disk fell below 2 GiB')
        if time.monotonic() - last_size_check > 20:
            size = 0
            for path in (root / '.build').rglob('*'):
                try:
                    if path.is_file() and not path.is_symlink():
                        size += path.stat().st_blocks * 512
                except FileNotFoundError:
                    pass
            last_size_check = time.monotonic()
            if size > limit:
                raise RuntimeError('task cache exceeded 3 GiB allocated disk bound')
        time.sleep(1)
    result = process.returncode
except Exception as exc:
    print('BLOCKED:', exc, file=sys.stderr)
finally:
    for event in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(event, signal.SIG_IGN)
    if process is not None and process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
raise SystemExit(result)
