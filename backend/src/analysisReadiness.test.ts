import assert from "node:assert/strict";
import test from "node:test";
import { readAnalysisReadiness } from "./analysisReadiness.js";
const env = { GEMINI_API_KEY: "fixture", GOOGLE_PLACES_API_KEY: "fixture" };

test("missing analysis schema cannot pass readiness despite optional adapters being disabled", async () => {
  const result = await readAnalysisReadiness(async () => { throw Object.assign(new Error("private database detail"), { code: "42P01" }); }, env);
  assert.equal(result.ready, false);
  assert.deepEqual(result.failures, ["analysis_schema_unavailable"]);
  assert.ok(!JSON.stringify(result).includes("private"));
});
test("analysis readiness checks required columns without reading user rows or writing", async () => {
  let sql = "";
  const result = await readAnalysisReadiness(async query => { sql = query; }, env);
  assert.equal(result.ready, true);
  for (const table of ["analysis_sessions", "analysis_usage_events", "analysis_captures", "analysis_recovery_runs"]) assert.ok(sql.includes(table));
  for (const column of ["client_events_expected", "client_events_received", "lease_token", "reserved_micros"]) assert.ok(sql.includes(column));
  assert.match(sql, /^select\s/i); assert.match(sql, /limit 0$/i);
});
test("partial schema, database failure, missing providers and invalid enabled budgets fail closed", async () => {
  for (const code of ["42703", "42501", "ECONNREFUSED"]) {
    assert.equal((await readAnalysisReadiness(async () => { throw { code }; }, env)).ready, false);
  }
  const missing = await readAnalysisReadiness(async () => {}, {});
  assert.deepEqual(missing.failures, ["semantic_provider_unconfigured", "places_provider_unconfigured"]);
  const malformed = await readAnalysisReadiness(async () => {}, { ...env, SAVE_ANALYSIS_LIMITS_ENABLED: "true" });
  assert.deepEqual(malformed.failures, ["analysis_limits_invalid"]);
  assert.equal((await readAnalysisReadiness(async () => {}, { GOOGLE_GEMINI_API_KEY: "fixture", GOOGLE_PLACES_API_KEY: "fixture" })).ready, true);
});
