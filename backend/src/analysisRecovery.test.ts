import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { runAnalysisRecovery } from "./analysisRecovery.js";

type Row = { user: string; capture: string; state: string; token: string; expires: number; result: unknown };
class RecoveryDB {
  now = 0;
  rows = new Map<string, Row>();
  calls = 0;
  pool(): Pool {
    return { query: async (sql: string, args: any[]) => {
      this.calls += 1;
      const row = this.rows.get(args[0]);
      if (sql.startsWith("insert")) {
        if (!row || (row.user === args[1] && row.capture === args[2]
          && (row.state === "failed" || row.expires <= this.now))) {
          this.rows.set(args[0], { user: args[1], capture: args[2], state: "running", token: args[3], expires: this.now + 600_000, result: null });
          return { rowCount: 1, rows: [{ lease_token: args[3] }] };
        }
      } else if (sql.startsWith("select")) {
        if (row && row.user === args[1] && row.capture === args[2] && row.state === "completed" && row.expires > this.now) {
          return { rowCount: 1, rows: [{ result: row.result }] };
        }
      } else if (sql.startsWith("update")) {
        if (row && row.token === args[1] && row.state === "running" && row.expires > this.now) {
          row.state = args[2] ?? "failed";
          row.result = args[3] ? JSON.parse(args[3]) : null;
          if (args.length > 2) row.expires = this.now + 300_000;
          return { rowCount: 1, rows: [] };
        }
      } else throw new Error("Unexpected coordinator query");
      return { rowCount: 0, rows: [] };
    } } as unknown as Pool;
  }
}
const capture = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const input = { sourceUrl: "https://fixture.invalid/reel", rawText: "caption", title: "title", suggestedSearchQueries: ["one", "two"], maxQueries: 2, includeMediaEvidence: true, persistedSourceResolution: { status: "resolved", caption: "caption" } };
const success = () => ({ candidates: [{ id: "candidate", name: "Fixture" }], errors: [], receipt: { output: "review_candidate" } });
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(res => { resolve = res; });
  return { promise, resolve };
}

test("recovery joins local concurrent work, isolates result mutation, and cleans the flight", async () => {
  const db = new RecoveryDB(); const pool = db.pool();
  const started = deferred<void>(); const finish = deferred<Record<string, unknown>>();
  let calls = 0;
  const work = async () => { calls += 1; started.resolve(); return finish.promise; };
  const first = runAnalysisRecovery(pool, "owner", capture, input, work);
  await started.promise;
  const queries = db.calls;
  const second = runAnalysisRecovery(pool, "owner", capture, input, work);
  assert.equal(db.calls, queries, "joining local work must not issue a second claim");
  finish.resolve(success());
  const [one, two] = await Promise.all([first, second]);
  assert.equal(calls, 1); assert.equal(one.reused, false); assert.equal(two.reused, true);
  (one.candidates as Array<{ name: string }>)[0].name = "mutated";
  assert.equal((two.candidates as Array<{ name: string }>)[0].name, "Fixture");
  await runAnalysisRecovery(pool, "owner", capture, input, work);
  assert.ok(db.calls > queries + 1, "settled flight must leave subsequent cache access to the database");
});

test("recovery reuses database success across processes and canonical object property order", async () => {
  const db = new RecoveryDB(); let calls = 0;
  const work = async () => { calls += 1; return success(); };
  await runAnalysisRecovery(db.pool(), "owner", capture, input, work);
  const reordered = Object.fromEntries(Object.entries(input).reverse());
  reordered.persistedSourceResolution = { caption: "caption", status: "resolved" };
  const result = await runAnalysisRecovery(db.pool(), "owner", capture, reordered, work);
  assert.equal(result.reused, true); assert.equal(calls, 1);
  assert.match([...db.rows.keys()][0], /^[a-f0-9]{64}$/);
});

test("recovery rejects another process while its lease is running", async () => {
  const db = new RecoveryDB(); const started = deferred<void>(); const finish = deferred<Record<string, unknown>>();
  const first = runAnalysisRecovery(db.pool(), "owner", capture, input, async () => { started.resolve(); return finish.promise; });
  await started.promise;
  await assert.rejects(runAnalysisRecovery(db.pool(), "owner", capture, input, async () => { throw new Error("duplicate provider work"); }),
    { status: 409, code: "analysis_recovery_running" });
  finish.resolve(success()); await first;
});

test("recovery isolates owners captures and every normalized input change", async () => {
  const db = new RecoveryDB(); const pool = db.pool(); let calls = 0;
  const work = async () => { calls += 1; return success(); };
  await runAnalysisRecovery(pool, "owner", capture, input, work);
  await runAnalysisRecovery(pool, "other-owner", capture, input, work);
  await runAnalysisRecovery(pool, "owner", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", input, work);
  const changes = { sourceUrl: "https://fixture.invalid/other", rawText: "changed", title: "changed", suggestedSearchQueries: ["two", "one"], maxQueries: 1, includeMediaEvidence: false, persistedSourceResolution: { status: "blocked_login" } };
  for (const [key, value] of Object.entries(changes)) {
    const result = await runAnalysisRecovery(pool, "owner", capture, { ...input, [key]: value }, work);
    assert.equal(result.reused, false, key);
  }
  assert.equal(calls, 3 + Object.keys(changes).length);
});

test("recovery expires cached results after five minutes", async () => {
  const db = new RecoveryDB(); const pool = db.pool(); let calls = 0;
  const work = async () => { calls += 1; return success(); };
  await runAnalysisRecovery(pool, "owner", capture, input, work);
  db.now = 299_999;
  assert.equal((await runAnalysisRecovery(pool, "owner", capture, input, work)).reused, true);
  db.now = 300_000;
  assert.equal((await runAnalysisRecovery(pool, "owner", capture, input, work)).reused, false);
  assert.equal(calls, 2);
});

test("recovery thrown errors and provider-error results remain retryable", async () => {
  for (const failure of [new Error("failed"), { errors: ["failed"] }, { errors: [], receipt: { failureReason: { kind: "provider_failure", stage: "media" } } }]) {
    const db = new RecoveryDB(); const pool = db.pool();
    const failed = runAnalysisRecovery(pool, "owner", capture, input, async () => {
      if (failure instanceof Error) throw failure;
      return failure;
    });
    if (failure instanceof Error) await assert.rejects(failed, /failed/); else await failed;
    assert.equal([...db.rows.values()][0].state, "failed");
    assert.equal([...db.rows.values()][0].result, null);
    assert.equal((await runAnalysisRecovery(pool, "owner", capture, input, async () => success())).reused, false);
  }
});

test("recovery can cache an insufficient source outcome without errors", async () => {
  const db = new RecoveryDB(); const result = { candidates: [], errors: [], receipt: { failureReason: { kind: "insufficient_source", reason: "caption_missing" } } };
  await runAnalysisRecovery(db.pool(), "owner", capture, input, async () => result);
  const reused = await runAnalysisRecovery(db.pool(), "owner", capture, input, async () => { throw new Error("must not run"); });
  assert.equal(reused.reused, true); assert.deepEqual(reused.receipt, result.receipt);
});

test("recovery fences an expired worker after a newer worker completes", async () => {
  const db = new RecoveryDB(); const started = deferred<void>(); const finish = deferred<Record<string, unknown>>();
  const first = runAnalysisRecovery(db.pool(), "owner", capture, input, async () => { started.resolve(); return finish.promise; });
  await started.promise;
  db.now = 599_999;
  await assert.rejects(runAnalysisRecovery(db.pool(), "owner", capture, input, async () => success()), { code: "analysis_recovery_running" });
  db.now = 600_000;
  await runAnalysisRecovery(db.pool(), "owner", capture, input, async () => ({ ...success(), version: "new" }));
  finish.resolve({ ...success(), version: "old" });
  await assert.rejects(first, { status: 409, code: "analysis_recovery_lease_lost" });
  assert.equal(([...db.rows.values()][0].result as { version: string }).version, "new");
  assert.equal([...db.rows.values()][0].state, "completed");
});

test("recovery refuses publishing after lease expiry without a successor", async () => {
  const db = new RecoveryDB();
  await assert.rejects(runAnalysisRecovery(db.pool(), "owner", capture, input, async () => { db.now = 600_000; return success(); }),
    { code: "analysis_recovery_lease_lost" });
  assert.equal([...db.rows.values()][0].result, null);
});

test("recovery rejects oversized results and allows the next retry", async () => {
  const db = new RecoveryDB(); const pool = db.pool();
  await assert.rejects(runAnalysisRecovery(pool, "owner", capture, input, async () => ({ value: "x".repeat(1_000_000) })),
    { status: 503, code: "analysis_recovery_invalid_result" });
  assert.equal([...db.rows.values()][0].state, "failed");
  assert.equal((await runAnalysisRecovery(pool, "owner", capture, input, async () => success())).reused, false);
});

test("recovery bounds local flights while database leases still reject overflow duplicates", async () => {
  const db = new RecoveryDB(); const pool = db.pool(); const finish = deferred<Record<string, unknown>>();
  let started = 0; const ready = deferred<void>();
  const work = async () => { if (++started === 257) ready.resolve(); return finish.promise; };
  const pending = Array.from({ length: 257 }, (_, n) => runAnalysisRecovery(pool, "owner", capture, { n }, work));
  await ready.promise;
  await assert.rejects(runAnalysisRecovery(pool, "owner", capture, { n: 256 }, work), { code: "analysis_recovery_running" });
  assert.equal(started, 257);
  finish.resolve(success()); await Promise.all(pending);
});

test("recovery accepts the exact response byte bound including its reuse marker", async () => {
  const db = new RecoveryDB(); const pool = db.pool();
  const overhead = Buffer.byteLength(JSON.stringify({ value: "", reused: false }));
  const result = await runAnalysisRecovery(pool, "owner", capture, input, async () => ({ value: "x".repeat(1_000_000 - overhead) }));
  assert.equal(Buffer.byteLength(JSON.stringify(result)), 1_000_000);
  const cached = await runAnalysisRecovery(pool, "owner", capture, input, async () => { throw new Error("must not run"); });
  assert.equal(cached.reused, true);
  assert.ok(Buffer.byteLength(JSON.stringify(cached)) <= 1_000_000);
});

test("recovery rejects oversized persisted results before returning them", async () => {
  const db = new RecoveryDB(); const pool = db.pool();
  await runAnalysisRecovery(pool, "owner", capture, input, async () => success());
  [...db.rows.values()][0].result = { value: "字".repeat(400_000) };
  await assert.rejects(runAnalysisRecovery(pool, "owner", capture, input, async () => success()), { code: "analysis_recovery_invalid_result" });
});
