"""Load the native artwork client and its ES module graph through the actual HTTP boundary."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Node's module linker follows the same relative imports (including versioned
# URLs) as the WebKit host. No data packs or macOS UI are needed for startup.
CHECK_BRIDGE = """
import assert from 'node:assert/strict';
import vm from 'node:vm';

const base = process.argv[1];
const messages = [];
const context = vm.createContext({ AbortController, addEventListener() {},
  webkit: {messageHandlers: {pocketCityState: {postMessage: value => messages.push(value)}}}
});
const modules = new Map();
async function load(url) {
  if (!modules.has(url)) {
    modules.set(url, (async () => {
      const response = await fetch(url);
      assert.equal(response.status, 200, url);
      assert.match(response.headers.get('content-type'), /javascript/, url);
      return new vm.SourceTextModule(await response.text(), {context, identifier: url});
    })());
  }
  return modules.get(url);
}
const entry = await load(base + '/native/tile-bridge.js');
await entry.link((specifier, parent) => load(new URL(specifier, parent.identifier).href));
await entry.evaluate();
assert.deepEqual(messages, ['bridge']);
assert.equal(typeof context.pocketCityTile, 'function');
assert.equal((await fetch(base + '/app.js')).status, 404);
"""


class NativeArtServerTest(unittest.TestCase):
    def test_native_bridge_imports_only_served_artwork(self):
        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / "port"
            server = subprocess.Popen([
                sys.executable, str(ROOT / "native/art-server.py"), "--root", str(ROOT),
                "--ready", str(ready), "--parent", str(os.getpid()),
            ])
            try:
                deadline = time.monotonic() + 5
                port = ""
                while server.poll() is None and time.monotonic() < deadline:
                    if ready.is_file():
                        port = ready.read_text().strip()
                        if port.isdecimal():
                            break
                    time.sleep(0.02)
                self.assertTrue(port.isdecimal(), "native artwork server did not start")
                base = "http://127.0.0.1:" + port
                subprocess.run([
                    "node", "--experimental-vm-modules",
                    "--input-type=module", "-e", CHECK_BRIDGE, base,
                ], check=True, timeout=15)
            finally:
                server.terminate()
                server.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
