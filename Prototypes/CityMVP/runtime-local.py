#!/usr/bin/env python3
"""Own one simulator and the City Lab cache through tests and interactive review."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
from uuid import UUID

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
try:
    DEVICE = str(UUID(os.environ.get('SAVVY_CITY_MVP_DEVICE', ''))).upper()
except ValueError:
    sys.exit('Set SAVVY_CITY_MVP_DEVICE to a shutdown iOS simulator UDID from xcrun simctl list devices available.')
BUNDLE = 'local.savvy.city-mvp'
CACHE = ROOT / '.build'
BUILD_LOCK = ROOT / '.build-lock'
DEVICE_LOCK = Path('/tmp') / ('savvy-city-mvp-' + DEVICE + '.lock')
STOP = ROOT / 'runtime-stop.local'
STATE = ROOT / 'runtime-state.local.json'
APP = CACHE / 'Build/Products/Debug-iphonesimulator/SavvyCityMVP.app'
corner_test = '-only-testing:CityMVPVisualTests/CityMVPVisualTests/testTwoXinyiCornerPreviews'
if sys.argv[1:] == ['--street-corners-only']:
    test_selection = [corner_test]
elif sys.argv[1:] == ['--xinyi-only']:
    test_selection = [
        '-only-testing:CityMVPTests',
        '-only-testing:CityMVPVisualTests/CityMVPVisualTests/testNativePinchKeepsLandmarkSelectedAcrossDistrict',
        corner_test,
    ]
elif not sys.argv[1:]:
    test_selection = []
else:
    sys.exit('Usage: runtime-local.py [--xinyi-only | --street-corners-only]')
owned_locks = []
boot_requested = False
child = None
last_cache_check = 0


def resources():
    global last_cache_check
    if shutil.disk_usage(ROOT).free < 2 * 1024**3:
        raise RuntimeError('Free disk below 2 GiB')
    if time.monotonic() - last_cache_check > 20:
        size = 0
        for path in CACHE.rglob('*'):
            try:
                if path.is_file() and not path.is_symlink():
                    size += path.stat().st_blocks * 512
            except FileNotFoundError:
                pass  # Xcode can atomically replace an intermediate file.
        last_cache_check = time.monotonic()
        if size > 3 * 1024**3:
            raise RuntimeError('Task cache exceeds 3 GiB allocated disk')


def stop_child():
    global child
    if child is not None and child.poll() is None:
        os.killpg(child.pid, signal.SIGTERM)
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait(timeout=5)
    child = None


def command(args, timeout, log):
    global child
    resources()
    with (ROOT / log).open('w') as output:
        child = subprocess.Popen(args, cwd=REPO, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + timeout
        try:
            while child.poll() is None:
                resources()
                if time.monotonic() > deadline:
                    raise TimeoutError('Timed out: ' + args[0])
                time.sleep(1)
            result = child.returncode
            child = None
            if result:
                raise RuntimeError(f'Command failed ({result}); see {log}')
        finally:
            stop_child()


def device_state():
    data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j'], timeout=20))
    return next(d['state'] for devices in data['devices'].values() for d in devices if d['udid'] == DEVICE)


def interrupt(_signal, _frame):
    raise InterruptedError('Runtime session interrupted')


for event in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(event, interrupt)

result = 'failed'
error = None
shutdown = None
try:
    if shutil.disk_usage(ROOT).free < 10 * 1024**3:
        raise RuntimeError('At least 10 GiB free is required to start this runtime check')
    resources()
    for lock in (BUILD_LOCK, DEVICE_LOCK):
        lock.mkdir()  # Refuse stale/foreign locks; never steal them.
        owned_locks.append(lock)
    if device_state() != 'Shutdown':
        raise RuntimeError('Device already booted; refusing shared runtime ownership')
    if STOP.exists():
        raise RuntimeError('Previous runtime stop marker exists; use a fresh session marker')
    boot_requested = True
    command(['xcrun', 'simctl', 'boot', DEVICE], 60, 'runtime-boot.log')
    command(['xcrun', 'simctl', 'bootstatus', DEVICE, '-b'], 180, 'runtime-bootstatus.log')
    command(['xcodebuild', '-project', 'SavvyCityMVP.xcodeproj', '-scheme', 'SavvyCityMVP',
             '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + DEVICE,
             '-derivedDataPath', str(CACHE), '-disableAutomaticPackageResolution', '-skipPackageUpdates',
             '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
             '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '180',
             '-maximum-test-execution-time-allowance', '180',
             'CODE_SIGNING_ALLOWED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO', *test_selection, 'test'], 600, 'runtime-tests.log')
    command(['xcrun', 'simctl', 'install', DEVICE, str(APP)], 60, 'runtime-install.log')
    command(['xcrun', 'simctl', 'launch', DEVICE, BUNDLE], 60, 'runtime-launch.log')
    STATE.write_text(json.dumps({'state': 'ready', 'device': DEVICE, 'bundle': BUNDLE, 'pid': os.getpid()}))
    print('READY: tests passed; app launched; ownership and resource monitor remain active.', flush=True)
    deadline = time.monotonic() + 1200
    while not STOP.exists():
        resources()
        if time.monotonic() > deadline:
            raise TimeoutError('Interactive inspection exceeded 20 minutes')
        time.sleep(1)
    result = 'pass'
except Exception as exc:
    error = str(exc)
    print(error, file=sys.stderr, flush=True)
finally:
    # Cleanup is independent of the resource checks that may have triggered it.
    for event in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(event, signal.SIG_IGN)
    stop_child()
    if boot_requested:
        try:
            subprocess.run(['xcrun', 'simctl', 'shutdown', DEVICE], timeout=45, capture_output=True)
            shutdown = device_state()
            if shutdown != 'Shutdown':
                raise RuntimeError('Shutdown verification failed: ' + shutdown)
        except Exception as exc:
            error = (error or '') + '; cleanup: ' + str(exc)
            result = 'failed'
    if not boot_requested or shutdown == 'Shutdown':
        for lock in reversed(owned_locks):
            lock.rmdir()
    if result == 'pass':
        STOP.unlink(missing_ok=True)
    STATE.write_text(json.dumps({'state': result, 'error': error, 'device': DEVICE, 'shutdown': shutdown}, indent=2))
    print('CLOSEOUT: ' + result + '; device=' + str(shutdown), flush=True)
sys.exit(0 if result == 'pass' else 1)
