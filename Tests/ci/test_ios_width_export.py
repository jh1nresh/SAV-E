import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class WidthExportTests(unittest.TestCase):
    def test_three_surfaces_keep_separate_manifests_and_named_rasters(self):
        # Model xcresulttool's UUID filenames and refusal to overwrite a
        # manifest. No simulator or Xcode process is launched by this fixture.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            scripts = root / "scripts"
            scripts.mkdir()
            (scripts / "extract-named-ui-screenshots.py").symlink_to(
                ROOT / "scripts/extract-named-ui-screenshots.py"
            )
            retry = scripts / "run-ios-xcodebuild-retry.sh"
            retry.write_text('''#!/usr/bin/env python3
import pathlib, sys
bundle = pathlib.Path(sys.argv[sys.argv.index('--result-bundle') + 1])
bundle.mkdir()
(bundle / 'Info.plist').write_bytes(b'fixture')
''')
            retry.chmod(0o755)
            xcrun = root / "xcrun"
            xcrun.write_text('''#!/usr/bin/env python3
import json, pathlib, sys
args = sys.argv[1:]
if args[:3] == ['simctl', 'list', '-j']:
    print(json.dumps({'devicetypes': [
        {'identifier': 'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation'}
    ]}))
elif args[:2] == ['simctl', 'create']:
    print('width-export-fixture-no-device')
elif args[:2] == ['xcresulttool', 'export']:
    out = pathlib.Path(args[args.index('--output-path') + 1])
    out.mkdir(parents=True, exist_ok=True)
    manifest = out / 'manifest.json'
    if manifest.exists():
        sys.exit('manifest already exists')
    name = pathlib.Path(args[args.index('--path') + 1]).stem.lower()
    (out / 'uuid.png').write_bytes(name.encode())
    manifest.write_text(json.dumps([{'attachments': [{
        'exportedFileName': 'uuid.png',
        'suggestedHumanReadableName': name + '_0_fixture.png'
    }]}]))
''')
            xcrun.chmod(0o755)
            xctestrun = root / "fixture.xctestrun"
            xctestrun.write_bytes(plistlib.dumps({}))
            out = root / "screens"
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}")
            for surface in ("Map", "Friends", "Passport"):
                run = subprocess.run([
                    "bash", str(ROOT / "scripts/run-ios-width-device-test.sh"),
                    "--width", "375",
                    "--test", f"SAVEUITests/SAVEScreenshotRailTests/test{surface}Width375",
                    "--xctestrun", str(xctestrun), "--output-dir", str(out),
                    "--result-bundle", str(root / f"{surface}-375.xcresult"),
                    "--log", str(root / f"{surface}.log"),
                ], cwd=root, env=env, capture_output=True, text=True)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            for surface in ("map", "friends", "passport"):
                self.assertEqual((out / f"{surface}-375.png").read_bytes(),
                                 f"{surface}-375".encode())
            self.assertEqual(len(list(out.glob("*/manifest.json"))), 3)


if __name__ == "__main__":
    unittest.main()
