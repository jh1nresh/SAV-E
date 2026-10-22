"""Linux seed/check contract for ./verify. Local and CI must match."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
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
                            for key in ("ok", "page", "sha256", "source")
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
            workspace = Path(temp)
            check = run_cli("check", workspace=workspace)
            self.assertEqual(check.returncode, 0, check.stderr + check.stdout)
            body = load_stdout(check)
            self.assertTrue(body["ok"])
            self.assertFalse(body["passed"])
            for flow in verify.FLOW_DEPS:
                status = body["statuses"][flow]
                self.assertEqual(status, "SKIP", flow)
                self.assertNotEqual(status, "PASS")
                reason = body["flows"][flow]["reason"]
                self.assertTrue(reason.startswith("SKIP："), reason)
            self.assertIn("#290", body["flows"]["V2"]["reason"])
            self.assertIn("#293", body["flows"]["V5"]["reason"])
            self.assertIn("#295", body["flows"]["V5"]["reason"])
            self.assertIn("#307", body["flows"]["V7"]["reason"])
            self.assertIn("U7", body["flows"]["V6"]["reason"])

    def test_v5_and_v7_catalog_assert_saved_50_copy(self):
        with tempfile.TemporaryDirectory() as temp:
            workspace = Path(temp)
            for name in verify.FLOW_SEEDS["V5"] + verify.FLOW_SEEDS["V7"]:
                self.assertEqual(run_cli("seed", name, workspace=workspace).returncode, 0)
            v5 = load_stdout(run_cli("run", "V5", workspace=workspace))
            v7 = load_stdout(run_cli("run", "V7", workspace=workspace))
            v5_ids = [row["id"] for row in v5["assertions"]]
            v7_ids = [row["id"] for row in v7["assertions"]]
            self.assertIn("V5.saved-50-copy", v5_ids)
            self.assertIn("V7.clip-cap50-copy", v7_ids)
            self.assertTrue(any(row["detail"] == "已存 50 個" or "已存 50 個" in row["detail"] for row in v5["assertions"]))
            self.assertTrue(any("已存 50 個" in row["detail"] for row in v7["assertions"]))
            self.assertEqual(v5["status"], "SKIP")
            self.assertEqual(v7["status"], "SKIP")
            self.assertFalse(v5["passed"])
            self.assertFalse(v7["passed"])

    def test_screenshot_reuses_doodle_parity_reference_bytes(self):
        source = ROOT / "Prototypes/AtlasPostcard/Reference/ProductionTargets/home.png"
        expected = hashlib.sha256(source.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as temp:
            workspace = Path(temp)
            self.assertEqual(run_cli("seed", "taipei-12", workspace=workspace).returncode, 0)
            shot = load_stdout(run_cli("screenshot", "home", workspace=workspace))
            copied = workspace / "screenshots" / "home.png"
            self.assertTrue(copied.is_file())
            self.assertEqual(shot["sha256"], expected)
            self.assertEqual(shot["status"], "PASS")
            self.assertEqual(
                shot["source"],
                "Prototypes/AtlasPostcard/Reference/ProductionTargets/home.png",
            )

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
        agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        for command in (
            "python3 -B -m unittest discover -s Tests/ci -p 'test_verify.py' -v",
            "./verify seed taipei-12",
            "./verify run V2",
            "./verify screenshot home",
            "./verify check",
        ):
            self.assertIn(command, workflow)
            self.assertIn(command, agents)
        self.assertIn("runs-on: ubuntu-latest", workflow)
        self.assertNotIn("macos-", workflow)
        self.assertNotIn("actions: write", workflow)
        self.assertIn("workflow_dispatch", workflow)
        self.assertIn("已存 50 個", (ROOT / "scripts/save_verify.py").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
