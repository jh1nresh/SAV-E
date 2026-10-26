"""Linux seed/check contract for ./verify. Local and CI must match."""

from __future__ import annotations

import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "save_verify", ROOT / "scripts/save_verify.py"
)
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)

SHOT_NAME = re.compile(r"^.+-.+-(light|dark)-[A-Za-z0-9-]+\.png$")
REQUIRED_IDS = {
    "V2": ("location-denied", "empty-state", "eat-6", "home.saves"),
    "V5": ("paywall.savedNote", "paywall.retry", "saves.unplaced", "ai.quotaExhausted"),
    "V7": (
        "S1'",
        "SK1",
        "S8",
        "SL1",
        "SL2",
        "SL3",
        "SL4",
        "SL5",
        "SL6",
        "PR5",
        "W1",
        "W2",
        "W3",
        "Z1",
        "clip-cap50-copy",
    ),
}


def run_cli(*args: str, workspace: Path) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env["SAVE_VERIFY_DIR"] = str(workspace)
    env["TZ"] = "UTC"
    env["LANG"] = "C.UTF-8"
    env["LC_ALL"] = "C.UTF-8"
    env["PYTHONHASHSEED"] = "0"
    env["PYTHONUTF8"] = "1"
    return subprocess.run(
        [sys.executable, str(ROOT / "verify"), *args],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def load_stdout(completed: subprocess.CompletedProcess[str]) -> dict:
    return json.loads(completed.stdout)


class VerifyToolTests(unittest.TestCase):
    def test_taipei_12_matches_eat_go_and_visit_counts(self):
        places = verify.taipei_12_places()
        self.assertEqual(len(places), 12)
        self.assertEqual(sum(1 for row in places if row["category"] in verify.EAT), 6)
        self.assertEqual(sum(1 for row in places if row["category"] in verify.GO), 6)
        visited = [row["visitCount"] for row in places if row["visitCount"]]
        self.assertEqual(sorted(visited), [1, 1, 3, 5])
        self.assertEqual(sum(1 for row in places if row["hasUserPhoto"]), 2)
        self.assertTrue(all(row["googlePlaceId"] and "googleapis.com" in row["googlePhotoURL"] for row in places))

    def test_seed_run_screenshot_check_are_deterministic(self):
        with tempfile.TemporaryDirectory() as first_dir, tempfile.TemporaryDirectory() as second_dir:
            payloads = []
            for directory in (first_dir, second_dir):
                workspace = Path(directory)
                seed = run_cli("seed", "taipei-12", workspace=workspace)
                self.assertEqual(seed.returncode, 0, seed.stderr + seed.stdout)
                for name in ("empty-free", "free-49", "free-50", "pro-50", "ai-exhausted"):
                    self.assertEqual(run_cli("seed", name, workspace=workspace).returncode, 0)
                flow = run_cli("run", "V2", workspace=workspace)
                shot = run_cli("screenshot", "home", workspace=workspace)
                check = run_cli("check", workspace=workspace)
                self.assertEqual(flow.returncode, 0, flow.stderr + flow.stdout)
                self.assertEqual(shot.returncode, 0, shot.stderr + shot.stdout)
                self.assertEqual(check.returncode, 0, check.stderr + check.stdout)
                payloads.append(
                    {
                        "seed": load_stdout(seed)["seed"],
                        "flow": {
                            key: load_stdout(flow)[key]
                            for key in ("flow", "status", "reason", "passed")
                        },
                        "shot": {
                            key: load_stdout(shot)[key]
                            for key in ("ok", "page", "planned", "reason", "status")
                        },
                        "check": {
                            key: load_stdout(check)[key]
                            for key in ("clock", "deterministic", "locale", "statuses")
                        },
                    }
                )
                self.assertEqual(seed.stdout, verify.dumps(load_stdout(seed)))
                self.assertEqual(check.stdout, verify.dumps(load_stdout(check)))
            self.assertEqual(payloads[0], payloads[1])

    def test_unmerged_flows_are_skip_never_pass(self):
        with tempfile.TemporaryDirectory() as temp:
            source_root = Path(temp) / "empty-source"
            workspace = Path(temp) / "output"
            code, body = verify.cmd_check(source_root, workspace)
            self.assertEqual(code, 0, body)
            self.assertTrue(body["ok"])
            self.assertFalse(body["passed"])
            for flow in verify.FLOW_DEPS:
                status = body["statuses"][flow]
                self.assertEqual(status, "SKIP", flow)
                self.assertNotEqual(status, "PASS")
                reason = body["flows"][flow]["reason"]
                self.assertTrue(reason.startswith("SKIP："), reason)
                catalog = [f"{flow}.{item}" for item in verify.FLOW_ASSERTIONS[flow]]
                reported = [row["id"] for row in body["flows"][flow]["assertions"]]
                self.assertEqual(reported, catalog, flow)
            self.assertIn("#290", body["flows"]["V2"]["reason"])
            self.assertIn("#293", body["flows"]["V5"]["reason"])
            self.assertIn("#295", body["flows"]["V5"]["reason"])
            self.assertIn("#307", body["flows"]["V7"]["reason"])
            self.assertIn("U7", body["flows"]["V6"]["reason"])

    def test_hop_catalog_includes_named_assertions(self):
        for flow, items in REQUIRED_IDS.items():
            catalog = set(verify.FLOW_ASSERTIONS[flow])
            missing = [item for item in items if item not in catalog]
            self.assertEqual(missing, [], flow)

    def test_v5_and_v7_skip_details_state_skip_reason(self):
        with tempfile.TemporaryDirectory() as temp:
            source_root = Path(temp) / "empty-source"
            workspace = Path(temp) / "output"
            _, v5 = verify.cmd_run(source_root, workspace, "V5")
            _, v7 = verify.cmd_run(source_root, workspace, "V7")
            v5_ids = [row["id"] for row in v5["assertions"]]
            v7_ids = [row["id"] for row in v7["assertions"]]
            self.assertIn("V5.paywall.savedNote", v5_ids)
            self.assertIn("V5.paywall.retry", v5_ids)
            self.assertIn("V5.saves.unplaced", v5_ids)
            self.assertIn("V5.ai.quotaExhausted", v5_ids)
            self.assertIn("V7.clip-cap50-copy", v7_ids)
            self.assertIn("V7.S1'", v7_ids)
            self.assertIn("V7.SK1", v7_ids)
            self.assertIn("V7.S8", v7_ids)
            self.assertIn("V7.SL5", v7_ids)
            self.assertIn("V7.PR5", v7_ids)
            self.assertIn("V7.Z1", v7_ids)
            saved_note = next(row for row in v5["assertions"] if row["id"] == "V5.paywall.savedNote")
            clip_copy = next(row for row in v7["assertions"] if row["id"] == "V7.clip-cap50-copy")
            self.assertEqual(saved_note["detail"], v5["reason"])
            self.assertEqual(clip_copy["detail"], v7["reason"])
            self.assertTrue(saved_note["detail"].startswith("SKIP："), saved_note["detail"])
            self.assertTrue(clip_copy["detail"].startswith("SKIP："), clip_copy["detail"])
            self.assertEqual(saved_note["status"], "SKIP")
            self.assertEqual(clip_copy["status"], "SKIP")
            self.assertEqual(v5["status"], "SKIP")
            self.assertEqual(v7["status"], "SKIP")
            self.assertFalse(v5["passed"])
            self.assertFalse(v7["passed"])

    def test_landed_v5_source_checks_do_not_claim_ui_pass(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "SAV-E/Fixture.swift"
            source.parent.mkdir()
            source.write_text("\n".join((
                "freeSavedPlaceLimit", "paywall.benefit.unlimited",
                "paywall.savedNote", "paywall.retry", "已存 50 個",
                "saves.unplaced", "saves.unplaced.row.", "ai.quotaExhausted",
            )))
            code, result = verify.cmd_run(root, root / "output", "V5")
            self.assertEqual(code, 0, result)
            self.assertEqual(result["status"], "SKIP")
            self.assertFalse(result["passed"])
            rows = {row["id"]: row for row in result["assertions"]}
            self.assertEqual(rows["V5.paywall.savedNote"]["status"], "PASS")
            self.assertEqual(rows["V5.paywall.no-ai-copy"]["status"], "SKIP")
            self.assertNotIn("未合併", result["reason"])

    def test_v7_guard_probe_reads_tests_without_counting_them_as_product(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "Tests/SocialPlacePipelineTests/ShareRouteCodecTests.swift"
            source.parent.mkdir(parents=True)
            source.write_text("func testSharedPublicPayloadsContainNoGoogleDomainURLs() {}\nclip.cap50 clip.signin clip.skoverlay")
            rows = {row["id"]: row for row in verify.evaluate_v7(root, {})}
            self.assertEqual(rows["V7.no-google-payload"]["status"], "PASS")
            self.assertFalse(verify.landed_prs(root)[307])
            source.write_text("// guard missing")
            rows = {row["id"]: row for row in verify.evaluate_v7(root, {})}
            self.assertEqual(rows["V7.no-google-payload"]["status"], "FAIL")

    def test_screenshot_home_skips_until_simulator_is_wired(self):
        parity = ROOT / "Prototypes/AtlasPostcard/Reference/ProductionTargets/home.png"
        with tempfile.TemporaryDirectory() as temp:
            workspace = Path(temp)
            self.assertEqual(run_cli("seed", "taipei-12", workspace=workspace).returncode, 0)
            shot = load_stdout(run_cli("screenshot", "home", workspace=workspace))
            pngs = list((workspace / "screenshots").glob("*.png"))
            self.assertEqual(pngs, [])
            self.assertFalse((workspace / "screenshots" / "home.png").exists())
            self.assertEqual(shot["status"], "SKIP")
            self.assertFalse(shot["ok"])
            self.assertIsNone(shot["source"])
            self.assertIsNone(shot["sha256"])
            self.assertEqual(shot["reason"], verify.SCREENSHOT_SKIP)
            self.assertRegex(shot["planned"], SHOT_NAME)
            self.assertEqual(shot["naming"], verify.SCREENSHOT_NAME)
            self.assertNotEqual(shot["status"], "PASS")
            self.assertTrue(parity.is_file())
            copied = workspace / "screenshots" / "home.png"
            if copied.is_file():
                self.fail("screenshot home must not copy ProductionTargets/home.png")

    def test_unknown_seed_and_flow_are_usage_errors(self):
        with tempfile.TemporaryDirectory() as temp:
            workspace = Path(temp)
            seed = run_cli("seed", "not-a-seed", workspace=workspace)
            flow = run_cli("run", "not-a-hop-flow", workspace=workspace)
            self.assertEqual(seed.returncode, 2)
            self.assertEqual(flow.returncode, 2)
            self.assertIn("empty-free", load_stdout(seed)["seeds"])
            self.assertEqual(load_stdout(flow)["flows"], list(verify.FLOW_DEPS))

    def test_ci_and_local_invoke_the_same_linux_commands(self):
        workflow = (ROOT / ".github/workflows/verify.yml").read_text(encoding="utf-8")
        for command in (
            "python3 -B -m unittest discover -s Tests/ci -p 'test_verify.py' -v",
            "./verify seed taipei-12",
            "./verify run V2",
            "./verify screenshot home",
            "./verify check",
        ):
            self.assertIn(command, workflow)
        self.assertIn("runs-on: ubuntu-latest", workflow)
        self.assertNotIn("macos-", workflow)
        self.assertNotIn("actions: write", workflow)
        self.assertIn("workflow_dispatch", workflow)
        self.assertIn("已存 50 個", (ROOT / "scripts/save_verify.py").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
