import json
import os
import plistlib
import subprocess
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
SURFACES = ("Map", "Friends", "Passport")
DEVICE_TYPES = {
    375: "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation",
    390: "com.apple.CoreSimulator.SimDeviceType.iPhone-14",
    430: "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max",
}


class WidthExportTests(unittest.TestCase):
    @contextmanager
    def fixture(self, mode=""):
        # Fake only the native boundaries. Execute the real width runner,
        # manifest extractor and (in the batch test) workflow shell command.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts = root / "scripts"
            scripts.mkdir()
            for name in ("extract-named-ui-screenshots.py", "run-ios-width-device-test.sh"):
                (scripts / name).symlink_to(ROOT / "scripts" / name)
            retry = scripts / "run-ios-xcodebuild-retry.sh"
            retry.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['WIDTH_FIXTURE_ROOT'])
args = sys.argv[1:]
selectors = pathlib.Path(args[args.index('--only-testing-file') + 1]).read_text().splitlines()
with (root / 'retry.jsonl').open('a') as f:
    f.write(json.dumps(selectors) + '\\n')
bundle = pathlib.Path(args[args.index('--result-bundle') + 1])
bundle.mkdir()
(bundle / 'Info.plist').write_bytes(b'fixture')
(bundle / 'selectors.json').write_text(json.dumps(selectors))
if os.environ.get('WIDTH_FIXTURE_MODE') == 'native_failure': sys.exit(7)
''')
            retry.chmod(0o755)
            xcrun = root / "xcrun"
            xcrun.write_text('''#!/usr/bin/env python3
import json, os, pathlib, re, sys
root = pathlib.Path(os.environ['WIDTH_FIXTURE_ROOT'])
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as f:
    f.write(json.dumps(args) + '\\n')
statefile = root / 'devices.json'
state = json.loads(statefile.read_text()) if statefile.exists() else {}
mode = os.environ.get('WIDTH_FIXTURE_MODE', '')
if args[:3] == ['simctl', 'list', '-j']:
    print(json.dumps({'devicetypes': [{'identifier': name} for name in (
        'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation',
        'com.apple.CoreSimulator.SimDeviceType.iPhone-14',
        'com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max')]}))
elif args[:2] == ['simctl', 'create']:
    countfile = root / 'device-count'
    count = int(countfile.read_text()) + 1 if countfile.exists() else 1
    countfile.write_text(str(count))
    udid = 'width-export-fixture-no-device-' + str(count)
    state[udid] = 'Shutdown'
    statefile.write_text(json.dumps(state))
    print(udid)
elif args[:2] == ['simctl', 'bootstatus']:
    state[args[2]] = 'Booted'
    statefile.write_text(json.dumps(state))
elif args[:2] == ['simctl', 'shutdown']:
    if mode == 'shutdown_failure': sys.exit(1)
    state[args[2]] = 'Shutdown'
    statefile.write_text(json.dumps(state))
elif args[:3] == ['simctl', 'list', 'devices']:
    for udid, status in state.items(): print(udid + ' (' + status + ')')
elif args[:2] == ['simctl', 'delete']:
    state.pop(args[2], None)
    statefile.write_text(json.dumps(state))
elif args[:2] == ['xcresulttool', 'export']:
    out = pathlib.Path(args[args.index('--output-path') + 1])
    out.mkdir(parents=True, exist_ok=True)
    manifest = out / 'manifest.json'
    if manifest.exists(): sys.exit('manifest already exists')
    selectors = json.loads((pathlib.Path(args[args.index('--path') + 1]) / 'selectors.json').read_text())
    attachments = []
    for i, selector in enumerate(selectors):
        if mode == 'missing_raster' and i == len(selectors) - 1: continue
        match = re.search(r'test(Map|Friends|Passport)Width(375|390|430)$', selector)
        name = match[1].lower() + '-' + match[2]
        exported = 'uuid-' + str(i) + '.png'
        (out / exported).write_bytes(name.encode())
        attachments.append({'exportedFileName': exported,
                            'suggestedHumanReadableName': name + '_0_fixture.png'})
    manifest.write_text(json.dumps([{'attachments': attachments}]))
else:
    sys.exit('unexpected native operation: ' + repr(args))
''')
            xcrun.chmod(0o755)
            xctestrun = root / "fixture.xctestrun"
            xctestrun.write_bytes(plistlib.dumps({}))
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       WIDTH_FIXTURE_ROOT=str(root), WIDTH_FIXTURE_MODE=mode)
            yield SimpleNamespace(root=root, xctestrun=xctestrun, env=env)

    def calls(self, fixture):
        path = fixture.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run_selectors(self, fixture, selectors, width=375, name="width"):
        args = ["bash", str(ROOT / "scripts/run-ios-width-device-test.sh"), "--width", str(width)]
        for selector in selectors:
            args += ["--test", selector]
        args += ["--xctestrun", str(fixture.xctestrun), "--output-dir", str(fixture.root / "screens"),
                 "--result-bundle", str(fixture.root / f"{name}.xcresult"),
                 "--log", str(fixture.root / f"{name}.log")]
        return subprocess.run(args, cwd=fixture.root, env=fixture.env, capture_output=True, text=True, timeout=30)

    def selectors(self, width):
        return [f"SAVEUITests/SAVEScreenshotRailTests/test{surface}Width{width}" for surface in SURFACES]

    def assert_cleaned(self, fixture, count=1):
        calls = self.calls(fixture)
        self.assertEqual(sum(args[:2] == ["simctl", "shutdown"] for args in calls), count)
        self.assertEqual(sum(args[:2] == ["simctl", "delete"] for args in calls), count)
        self.assertEqual(json.loads((fixture.root / "devices.json").read_text()), {})

    def test_three_legacy_calls_keep_separate_manifests_and_named_rasters(self):
        with self.fixture() as fixture:
            for surface, selector in zip(SURFACES, self.selectors(375)):
                run = self.run_selectors(fixture, [selector], name=surface)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            for surface in SURFACES:
                name = f"{surface.lower()}-375"
                self.assertEqual((fixture.root / "screens" / f"{name}.png").read_bytes(), name.encode())
            self.assertEqual(len(list((fixture.root / "screens").glob("*/manifest.json"))), 3)
            self.assert_cleaned(fixture, count=3)

    def test_workflow_batch_runs_every_selector_once_on_one_genuine_width_device(self):
        workflow = (ROOT / ".github/workflows/ios.yml").read_text()
        step = workflow.split("      - name: Capture Map, Friends, and Passport width evidence\n", 1)[1]
        step = step.split("      - name: Require every width raster\n", 1)[0]
        script = step.split("        run: |\n", 1)[1]
        script = "\n".join(line[10:] for line in script.splitlines() if line.startswith("          "))
        for width, device_type in DEVICE_TYPES.items():
            with self.subTest(width=width), self.fixture() as fixture:
                env = dict(fixture.env, WIDTH=str(width), MAP_TEST=f"testMapWidth{width}",
                           FRIENDS_TEST=f"testFriendsWidth{width}", PASSPORT_TEST=f"testPassportWidth{width}",
                           XCTESTRUN_PATH=str(fixture.xctestrun), RUNNER_TEMP=str(fixture.root))
                run = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script], cwd=fixture.root,
                                     env=env, capture_output=True, text=True, timeout=30)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                requests = [json.loads(line) for line in (fixture.root / "retry.jsonl").read_text().splitlines()]
                self.assertEqual(requests, [["-only-testing:" + selector for selector in self.selectors(width)]])
                creates = [args for args in self.calls(fixture) if args[:2] == ["simctl", "create"]]
                self.assertEqual(len(creates), 1)
                self.assertEqual(creates[0][3], device_type)
                self.assertEqual(sum(args[:2] == ["simctl", "bootstatus"] for args in self.calls(fixture)), 1)
                out = fixture.root / "SAVE-First-Run"
                for surface in SURFACES:
                    name = f"{surface.lower()}-{width}"
                    self.assertEqual((out / f"{name}.png").read_bytes(), name.encode())
                self.assertEqual(len(list(out.glob("*/manifest.json"))), 1)
                self.assert_cleaned(fixture)

    def test_incomplete_duplicate_and_wrong_width_groups_fail_before_device_creation(self):
        selectors = self.selectors(375)
        for bad in [[], selectors[:2], [selectors[0], selectors[0], selectors[2]], self.selectors(390)]:
            with self.subTest(selectors=bad), self.fixture() as fixture:
                run = self.run_selectors(fixture, bad)
                self.assertEqual(run.returncode, 2, run.stdout + run.stderr)
                self.assertFalse(self.calls(fixture))

    def test_native_failure_or_missing_raster_cannot_pass_and_still_cleans_device(self):
        for mode, expected in [("native_failure", 7), ("missing_raster", 1), ("shutdown_failure", 1)]:
            with self.subTest(mode=mode), self.fixture(mode) as fixture:
                run = self.run_selectors(fixture, self.selectors(375))
                self.assertEqual(run.returncode, expected, run.stdout + run.stderr)
                self.assert_cleaned(fixture)


if __name__ == "__main__":
    unittest.main()
