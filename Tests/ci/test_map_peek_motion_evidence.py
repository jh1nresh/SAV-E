import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]


class MapPeekMotionEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="save-map-motion-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ("run-map-peek-motion-evidence.sh", "extract-named-ui-screenshots.py"):
            shutil.copyfile(ROOT / "scripts" / name, scripts / name)
        self.script = scripts / "run-map-peek-motion-evidence.sh"
        self.executable(scripts / "run-ios-xcodebuild-retry.sh", '''
            import os, pathlib, sys, time
            args = sys.argv[1:]
            value = lambda key: args[args.index(key) + 1]
            expected = "-only-testing:SAVEUITests/SAVEScreenshotRailTests/testMapPeekMotionEvidence"
            assert pathlib.Path(value("--only-testing-file")).read_text().strip() == expected
            bundle = pathlib.Path(value("--result-bundle"))
            bundle.mkdir()
            (bundle / "Info.plist").write_text("fixture")
            pathlib.Path(value("--log")).write_text("native test fixture log")
            time.sleep(0.25)
            sys.exit(int(os.environ.get("MOTION_TEST_STATUS", "0")))
        ''')
        binary = self.root / "bin"
        binary.mkdir()
        self.executable(binary / "xcrun", '''
            import json, os, pathlib, signal, sys, time
            args = sys.argv[1:]
            if args[:2] == ["simctl", "io"]:
                video = pathlib.Path(args[-1])
                events = pathlib.Path(os.environ["MOTION_EVENTS"])
                events.write_text("started\\n")
                if os.environ.get("MOTION_EMPTY_VIDEO") != "1":
                    video.write_bytes(b"video fixture")
                if os.environ.get("MOTION_EARLY_EXIT") == "1":
                    sys.exit(0)
                def stop(*_):
                    with events.open("a") as handle:
                        handle.write("stopped\\n")
                    sys.exit(0)
                signal.signal(signal.SIGINT, stop)
                signal.signal(signal.SIGTERM, stop)
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    time.sleep(0.05)
                sys.exit(3)
            assert args[:3] == ["xcresulttool", "export", "attachments"]
            out = pathlib.Path(args[args.index("--output-path") + 1])
            out.mkdir()
            attachments = []
            for mode, enabled in [("normal", "false"), ("reduced", "true")]:
                for state in ["reopened", "switched"]:
                    name = f"peek-motion-{mode}-{state}"
                    filename = f"{name}.png"
                    (out / filename).write_bytes(b"PNG fixture")
                    attachments.append({"exportedFileName": filename,
                                        "suggestedHumanReadableName": f"{name}_0_fixture.png"})
                if mode == "reduced" and os.environ.get("MOTION_MISSING_REDUCED") == "1":
                    continue
                name = f"peek-motion-mode-{mode}"
                filename = f"{name}.txt"
                (out / filename).write_text(f"mode={mode}\\nUIAccessibility.isReduceMotionEnabled={enabled}\\n")
                attachments.append({"exportedFileName": filename,
                                    "suggestedHumanReadableName": f"{name}_0_fixture.txt"})
            (out / "manifest.json").write_text(json.dumps([{"attachments": attachments}]))
        ''')
        self.events = self.root / "events"
        self.env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"],
                        MOTION_EVENTS=str(self.events))
        self.xctestrun = self.root / "fixture.xctestrun"
        self.xctestrun.touch()
        self.output = self.root / "output"

    def executable(self, path, source):
        path.write_text("#!/usr/bin/env python3\n" + textwrap.dedent(source).lstrip())
        path.chmod(0o755)

    def run_fixture(self, **variables):
        return subprocess.run(
            ["bash", str(self.script), "00000000-0000-4000-8000-000000000328",
             str(self.xctestrun), str(self.output), str(self.root / "result.xcresult"),
             str(self.root / "tests.log")],
            env=dict(self.env, **variables), text=True, capture_output=True, timeout=20,
        )

    def assert_recorder_stopped(self):
        self.assertIn("stopped", self.events.read_text())

    def test_requires_both_modes_and_stops_owned_recorder(self):
        result = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_recorder_stopped()
        self.assertTrue((self.output / "production-map-peek.mp4").stat().st_size)
        self.assertEqual(len(list(self.output.glob("peek-motion-*.png"))), 4)
        self.assertEqual(len(list(self.output.glob("peek-motion-mode-*.txt"))), 2)

    def test_native_failure_remains_failure_and_stops_recorder(self):
        result = self.run_fixture(MOTION_TEST_STATUS="23")
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assert_recorder_stopped()

    def test_missing_video_cannot_pass_on_screenshots(self):
        result = self.run_fixture(MOTION_EMPTY_VIDEO="1")
        self.assertNotEqual(result.returncode, 0)
        self.assert_recorder_stopped()

    def test_missing_reduced_motion_receipt_cannot_pass(self):
        result = self.run_fixture(MOTION_MISSING_REDUCED="1")
        self.assertNotEqual(result.returncode, 0)
        self.assert_recorder_stopped()

    def test_early_partial_recording_cannot_pass(self):
        result = self.run_fixture(MOTION_EARLY_EXIT="1")
        self.assertNotEqual(result.returncode, 0)

    def test_unrelated_process_is_untouched(self):
        process = subprocess.Popen(["sleep", "20"])
        try:
            result = self.run_fixture()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIsNone(process.poll())
        finally:
            process.terminate()
            process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
