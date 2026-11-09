import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PhotoEvidencePathTests(unittest.TestCase):
    def test_injected_path_and_simulator_copyout_agree(self):
        workflow = (ROOT / '.github/workflows/ios.yml').read_text()
        value = re.search(r'export SAVE_GOOGLE_PHOTO_EVIDENCE_DIR="([^"]+)"', workflow).group(1)
        self.assertEqual(value, '/tmp/pr306-google-photo-attribution')
        start = workflow.index('          python3 - <<\'PY\'', workflow.index('export XCTESTRUN_PATH='))
        program = workflow[start:].split("\n", 1)[1].split('\n          PY', 1)[0]
        program = textwrap.dedent(program)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plist = root / 'tests.xctestrun'
            plist.write_bytes(plistlib.dumps({'TestConfigurations': [{'TestTargets': [{'BlueprintName': 'SAVEUITests'}]}]}))
            env = dict(os.environ, XCTESTRUN_PATH=str(plist), SAVE_GOOGLE_PHOTO_EVIDENCE_DIR=value)
            subprocess.run(['python3', '-c', program], env=env, check=True, capture_output=True)
            target = plistlib.loads(plist.read_bytes())['TestConfigurations'][0]['TestTargets'][0]
            self.assertEqual(target['EnvironmentVariables']['SAVE_GOOGLE_PHOTO_EVIDENCE_DIR'], value)
            self.assertEqual(target['TestingEnvironmentVariables']['SAVE_GOOGLE_PHOTO_EVIDENCE_DIR'], value)
            sim = root / 'Library/Developer/CoreSimulator/Devices/fixture/data/tmp/pr306-google-photo-attribution'
            sim.mkdir(parents=True)
            (sim / 'evidence.png').write_bytes(b'fixture raster bytes')
            output = root / 'runner'
            output.mkdir()
            copy = workflow[workflow.index('          SIM_PHOTOS='):].split('\n          fi', 1)[0] + '\n          fi'
            env = dict(os.environ, HOME=str(root), RUNNER_TEMP=str(output), SIM_UDID='fixture')
            subprocess.run(['bash', '-e', '-c', textwrap.dedent(copy)], env=env, check=True)
            self.assertEqual((output / 'pr306-google-photo-attribution/evidence.png').read_bytes(), b'fixture raster bytes')
