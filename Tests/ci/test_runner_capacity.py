import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RunnerCapacityTests(unittest.TestCase):
    def test_build_and_consumers_use_the_same_alternate_pool(self):
        expected = {
            "ci.yml": {"ios-build", "ios-fast", "appclip-screenshots"},
            "ios.yml": {"ios-build", "ios-tests", "ios-supplemental"},
        }
        for filename, jobs in expected.items():
            workflow = (ROOT / ".github/workflows" / filename).read_text()
            sections = re.split(r"^  ([a-z][a-z0-9-]*):\n", workflow.split("jobs:\n", 1)[1], flags=re.M)
            runners = {
                sections[index]: re.search(r"^    runs-on: (.+)$", sections[index + 1], re.M).group(1)
                for index in range(1, len(sections), 2)
                if re.search(r"^    runs-on: macos-", sections[index + 1], re.M)
            }
            self.assertEqual(runners, dict.fromkeys(jobs, "macos-26-intel"), filename)

    def test_compiled_package_and_build_caches_never_restore_another_architecture(self):
        for filename in ("ci.yml", "ios.yml"):
            workflow = (ROOT / ".github/workflows" / filename).read_text()
            caches = re.findall(
                r"^          key: ((?:spm|clip-spm|deriveddata)-.+)\n          restore-keys: \|\n((?:            .+\n)+)",
                workflow, re.M,
            )
            self.assertGreaterEqual(len(caches), 3, filename)
            for key, restore in caches:
                def expand(value, architecture):
                    return value.replace("${{ runner.os }}", "macOS").replace("${{ runner.arch }}", architecture)
                for architecture, other in (("X64", "ARM64"), ("ARM64", "X64")):
                    own_key, foreign_key = expand(key, architecture), expand(key, other)
                    self.assertNotEqual(own_key, foreign_key, key)
                    for prefix in restore.splitlines():
                        prefix = expand(prefix.strip(), architecture)
                        self.assertTrue(own_key.startswith(prefix), prefix)
                        self.assertFalse(foreign_key.startswith(prefix), prefix)


if __name__ == "__main__":
    unittest.main()
