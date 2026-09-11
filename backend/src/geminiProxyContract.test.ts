import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

// A fallback shipped in the app must be accepted by the default proxy policy.
// An explicit deployment allowlist remains authoritative.
test("default Gemini proxy accepts every shipped iOS fallback model", () => {
  const client = readFileSync(new URL("../../SAV-EShared/SAVEProductionConfig.swift", import.meta.url), "utf8");
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const clientDefaults = client.match(/defaultGeminiModelFallbacks\s*=\s*\[([^\]]+)\]/)?.[1];
  const proxyDefaults = server.match(/SAVE_GEMINI_PROXY_MODELS\s*\?\?\s*"([^"]+)"/)?.[1];
  assert.ok(clientDefaults, "iOS fallback declaration must be inspectable");
  assert.ok(proxyDefaults, "proxy default allowlist must be inspectable");
  const models = [...clientDefaults.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
  const allowed = new Set(proxyDefaults.split(",").map((model) => model.trim()));
  assert.ok(models.length > 0);
  for (const model of models) assert.ok(allowed.has(model), `proxy rejects shipped fallback ${model}`);
});
