"""Friends visual-parity import: copy friends.png; skip empty feeds.

Extracts the live `run-visual-parity.sh` case arm and `--screenshots-dir`
copy loop, then executes those fragments in bash. A source-string lock
alone would pass while the import still omitted Friends.
"""

from __future__ import annotations

from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Prototypes/AtlasPostcard/Scripts/run-visual-parity.sh"


def script_text() -> str:
    return SCRIPT.read_text()


def extract_human_name_case(source: str) -> str:
    marker = '            case "$human_name" in\n'
    start = source.index(marker)
    rest = source[start:]
    end = rest.index("\n            esac\n")
    return rest[: end + len("\n            esac\n")]


def extract_screen_arrays(source: str) -> str:
    lines = []
    for line in source.splitlines():
        stripped = line.strip()
        if stripped.startswith("destination_screens=") or stripped.startswith(
            "parity_screens="
        ):
            lines.append(stripped)
    if len(lines) < 2:
        raise AssertionError("run-visual-parity.sh is missing screen arrays")
    skip_at = source.index("should_skip_screen() {")
    skip_end = source.index("\n}", skip_at) + 2
    lines.extend(['SKIP_SCREENS=""', source[skip_at:skip_end]])
    return "\n".join(lines)


def parity_screen_names(source: str) -> list[str]:
    return re.search(r"^parity_screens=\(([^)]+)\)", source, re.MULTILINE).group(1).split()


def extract_screenshots_dir_loop(source: str) -> str:
    marker = '    if [[ ! -d "$SCREENSHOTS_DIR" ]]; then\n'
    start = source.index(marker)
    rest = source[start:]
    loop_at = rest.index("    for screen in ")
    loop = rest[loop_at:]
    done = loop.index("\n    done\n")
    return loop[: done + len("\n    done\n")]


def run_bash(script: str, args: list[str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "-c", script, "parity-test", *(args or [])],
        check=False,
        text=True,
        capture_output=True,
    )


def classify_attachment(human_name: str, timestamp: str = "0") -> str:
    case_block = extract_human_name_case(script_text())
    wrapper = f"""
set -euo pipefail
human_name="$1"
timestamp="$2"
screen=""
priority=""
map_dark_file=""
map_dark_ts=-1
for _once in 1; do
{case_block}
    printf '%s\\t%s\\n' "$screen" "$priority"
    exit 0
done
printf 'SKIP\\n'
"""
    result = run_bash(wrapper, [human_name, timestamp])
    if result.returncode != 0:
        raise AssertionError(
            f"classify {human_name!r} failed: {result.stderr}\n{result.stdout}"
        )
    return result.stdout.strip()


class FriendsVisualParityImportTests(unittest.TestCase):
    def test_populated_friends_attachment_is_classified(self):
        self.assertEqual(classify_attachment("five-tab-friends"), "friends\t1")
        self.assertEqual(classify_attachment("five-tab-friends.png"), "friends\t1")
        self.assertEqual(classify_attachment("atlas-friends"), "friends\t0")

    def test_empty_and_coming_soon_friends_attachments_are_skipped(self):
        self.assertEqual(classify_attachment("five-tab-friends-empty"), "SKIP")
        self.assertEqual(classify_attachment("five-tab-friends-empty-en"), "SKIP")
        self.assertEqual(classify_attachment("five-tab-friends-coming-soon"), "SKIP")

    def test_newer_empty_feed_does_not_win_over_populated_friends(self):
        tab = "\t"
        rows = []
        for name, ts in (
            ("five-tab-friends-empty", "200"),
            ("five-tab-friends", "50"),
            ("atlas-friends", "10"),
        ):
            classified = classify_attachment(name, ts)
            if classified == "SKIP":
                continue
            screen, priority = classified.split("\t")
            rows.append(f"{screen}{tab}{priority}{tab}{ts}{tab}{name}")
        candidates = "\n".join(rows) + "\n"
        self.assertIn("five-tab-friends", candidates)
        self.assertNotIn("five-tab-friends-empty", candidates)
        self.assertTrue(
            any(row.startswith(f"friends{tab}1{tab}50{tab}five-tab-friends") for row in rows),
            candidates,
        )

    def test_screenshots_dir_import_copies_friends_from_parity_screens(self):
        source = script_text()
        arrays = extract_screen_arrays(source)
        loop = extract_screenshots_dir_loop(source)
        self.assertIn('for screen in "${parity_screens[@]}"', loop)
        self.assertIn("friends", arrays)

        with tempfile.TemporaryDirectory() as tmp:
            shots = Path(tmp) / "shots"
            artifacts = Path(tmp) / "art"
            shots.mkdir()
            (artifacts / "output").mkdir(parents=True)
            for screen in parity_screen_names(source):
                (shots / f"{screen}.png").write_bytes(b"fake-png-" + screen.encode())

            runner = f"""
set -euo pipefail
{arrays}
SCREENSHOTS_DIR="{shots}"
ARTIFACT_DIR="{artifacts}"
{loop}
"""
            result = run_bash(runner)
            self.assertEqual(result.returncode, 0, result.stderr)
            copied = artifacts / "output" / "friends.png"
            self.assertTrue(copied.is_file(), "friends.png was not imported")
            self.assertEqual(copied.read_bytes(), b"fake-png-friends")
            for screen in parity_screen_names(source):
                self.assertTrue((artifacts / "output" / f"{screen}.png").is_file())

    def test_screenshots_dir_import_respects_explicit_skipped_screens(self):
        source = script_text()
        with tempfile.TemporaryDirectory() as tmp:
            shots = Path(tmp) / "shots"
            artifacts = Path(tmp) / "art"
            shots.mkdir()
            (artifacts / "output").mkdir(parents=True)
            for screen in parity_screen_names(source):
                if screen not in ("capture", "paywall"):
                    (shots / f"{screen}.png").write_bytes(b"fixture")
            runner = f'''
set -euo pipefail
{extract_screen_arrays(source)}
SKIP_SCREENS="capture,paywall"
SCREENSHOTS_DIR="{shots}"
ARTIFACT_DIR="{artifacts}"
{extract_screenshots_dir_loop(source)}
'''
            result = run_bash(runner)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((artifacts / "output" / "friends.png").is_file())
            self.assertFalse((artifacts / "output" / "capture.png").exists())
            self.assertFalse((artifacts / "output" / "paywall.png").exists())

    def test_screenshots_dir_without_friends_fails_the_import(self):
        source = script_text()
        arrays = extract_screen_arrays(source)
        loop = extract_screenshots_dir_loop(source)

        with tempfile.TemporaryDirectory() as tmp:
            shots = Path(tmp) / "shots"
            artifacts = Path(tmp) / "art"
            shots.mkdir()
            (artifacts / "output").mkdir(parents=True)
            for screen in ("home", "saves", "plan", "map"):
                (shots / f"{screen}.png").write_bytes(b"x")

            runner = f"""
set -euo pipefail
{arrays}
SCREENSHOTS_DIR="{shots}"
ARTIFACT_DIR="{artifacts}"
{loop}
"""
            result = run_bash(runner)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("missing screenshot:", result.stderr)
            self.assertIn("friends.png", result.stderr)
            self.assertFalse((artifacts / "output" / "friends.png").exists())


if __name__ == "__main__":
    unittest.main()
