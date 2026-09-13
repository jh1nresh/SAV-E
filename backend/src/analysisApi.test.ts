import assert from "node:assert/strict";
import test from "node:test";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";

const databaseURL = process.env.SAVE_ANALYSIS_TEST_DATABASE_URL;
const fixtureHook = `
import { appendFileSync } from 'node:fs';
import dns from 'node:dns/promises';
import { syncBuiltinESMExports } from 'node:module';
// Keep the real public-host guard but resolve the one fake search host locally.
dns.lookup = async (hostname, options) => {
  if (hostname !== 'duckduckgo.com') throw new Error('External DNS blocked by analysis API fixture');
  const answer = { address: '93.184.216.34', family: 4 };
  return options?.all ? [answer] : answer;
};
syncBuiltinESMExports();
globalThis.fetch = async (input, init) => {
  const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
  const google = url.hostname === 'maps.googleapis.com' && url.pathname === '/maps/api/place/textsearch/json';
  const gemini = url.hostname === 'generativelanguage.googleapis.com' && url.pathname.startsWith('/v1beta/models/');
  const publicSearch = url.hostname === 'duckduckgo.com' && url.pathname === '/html/';
  if (publicSearch) {
    appendFileSync(process.env.ANALYSIS_FIXTURE_CALLS, JSON.stringify({ provider: 'public_search', failed: false })+'\\n');
    return new Response('<html><body>No fixture matches</body></html>');
  }
  if (!google && !gemini) {
    appendFileSync(process.env.ANALYSIS_FIXTURE_CALLS, JSON.stringify({ provider: 'blocked' })+'\\n');
    throw new Error('External fetch blocked by analysis API fixture');
  }
  const failed = google ? url.searchParams.get('query') === 'fixture-provider-failure' : String(init?.body).includes('fixture-provider-failure');
  appendFileSync(process.env.ANALYSIS_FIXTURE_CALLS, JSON.stringify({ provider: google ? 'google' : 'gemini', failed })+'\\n');
  if (failed) return Response.json({ error: { message: 'synthetic provider failure' } }, { status: 503 });
  return Response.json(google
    ? { status: 'OK', results: [{ place_id: 'fixture-place', name: 'Fixture Cafe', formatted_address: '1 Fixture Street', geometry: { location: { lat: 25, lng: 121 } } }] }
    : { candidates: [{ content: { parts: [{ text: 'Fixture response' }] } }], usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 30, thoughtsTokenCount: 20, totalTokenCount: 150, cachedContentTokenCount: 10 } });
};
`;

test("real HTTP analysis ownership metering and quota enforcement", { skip: !databaseURL, timeout: 60_000 }, async t => {
  const dbURL = new URL(databaseURL!);
  assert.equal(dbURL.pathname, "/save_analysis_fixture", "Only the disposable fixture database is allowed");
  assert.equal(dbURL.searchParams.get("host"), "/tmp/save-analysis-completion/pg-socket");
  assert.equal(dbURL.port, "55437");
  const pool = new Pool({ connectionString: databaseURL, max: 4 });
  await mkdir("/tmp/save-analysis-completion", { recursive: true });
  const fixtureDir = await mkdtemp("/tmp/save-analysis-completion/api-");
  const hookPath = join(fixtureDir, "provider-hook.mjs");
  const callsPath = join(fixtureDir, "provider-calls.jsonl");
  const logPath = join(fixtureDir, "server.log");
  await writeFile(hookPath, fixtureHook); await writeFile(callsPath, "");
  const portLease = createServer(); portLease.listen(0, "127.0.0.1"); await once(portLease, "listening");
  const port = (portLease.address() as { port: number }).port;
  await new Promise<void>((resolve, reject) => portLease.close(error => error ? reject(error) : resolve()));
  const backendDir = dirname(dirname(fileURLToPath(import.meta.url)));
  const compiledServer = fileURLToPath(new URL("./server.js", import.meta.url));
  const serverPath = existsSync(compiledServer) ? compiledServer : fileURLToPath(new URL("./server.ts", import.meta.url));
  const child = spawn(process.execPath, ["--import", hookPath, ...(serverPath.endsWith(".ts") ? ["--import", "tsx"] : []), serverPath], {
    cwd: backendDir,
    env: {
      PATH: process.env.PATH, HOME: process.env.HOME, NODE_ENV: "test", PORT: String(port),
      DATABASE_URL: databaseURL, PGSSLMODE: "disable", PRIVY_APP_ID: "fixture-app", PRIVY_VERIFICATION_KEY: "fixture-unused-key",
      SAVE_GUEST_SESSION_SECRET: "analysis-api-fixture-only", SLLR_NOTIFY_INTERVAL_MS: "0",
      GOOGLE_PLACES_API_KEY: "synthetic-google-key", GEMINI_API_KEY: "synthetic-gemini-key",
      SAVE_ANALYSIS_LIMITS_ENABLED: "true", SAVE_ANALYSIS_ACCOUNT_DAILY_LIMIT: "10000", SAVE_ANALYSIS_REQUEST_LIMIT: "3",
      SAVE_ANALYSIS_ACCOUNT_DAILY_BUDGET_MICROS: "1000000000000", SAVE_ANALYSIS_GLOBAL_DAILY_BUDGET_MICROS: "1000000000000",
      SAVE_ANALYSIS_BUDGET_MICROS: "1000000000", ANALYSIS_FIXTURE_CALLS: callsPath,
    }, stdio: ["ignore", "pipe", "pipe"],
  });
  const exited = once(child, "exit");
  let log = "";
  child.stdout.on("data", chunk => { log = (log + String(chunk)).slice(-30_000); });
  child.stderr.on("data", chunk => { log = (log + String(chunk)).slice(-30_000); });
  const base = `http://127.0.0.1:${port}`;
  type Guest = { guest_id: string; guest_token: string };
  const owners: string[] = [];
  async function api(path: string, body?: unknown, guest?: Guest, headers: Record<string, string> = {}) {
    const response = await fetch(base + path, { method: body === undefined ? "GET" : "POST", signal: AbortSignal.timeout(5_000),
      headers: { "content-type": "application/json", ...(guest ? { "x-save-guest-token": guest.guest_token } : {}), ...headers },
      body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, body: await response.json() as Record<string, any> };
  }
  async function newGuest(): Promise<Guest> {
    const result = await api("/v0/guest-sessions", {}); assert.equal(result.status, 201);
    const guest = result.body as Guest; owners.push(guest.guest_id); return guest;
  }
  async function start(guest: Guest): Promise<string> {
    const id = randomUUID(); const result = await api("/v0/analysis", { id }, guest);
    assert.equal(result.status, 201, JSON.stringify(result.body)); assert.equal(result.body.analysis_id, id); return id;
  }
  async function calls(): Promise<Array<{ provider: string; failed: boolean }>> {
    return (await readFile(callsPath, "utf8")).trim().split("\n").filter(Boolean).map(line => JSON.parse(line));
  }
  const geminiBody = (text = "fixture-caption") => ({ model: "gemini-3.5-flash", contents: [{ parts: [{ text }] }], generationConfig: { maxOutputTokens: 256 } });
  try {
    let ready = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      if (child.exitCode !== null || child.signalCode !== null) throw new Error(`Fixture server exited before ready: ${log}`);
      try { if ((await api("/")).status === 200) { ready = true; break; } } catch {}
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    assert.equal(ready, true, log);
    const owner = await newGuest(); const other = await newGuest();

    await t.test("session routes reject foreign owners and forged analysis context before provider calls", async () => {
      const id = await start(owner); const before = (await calls()).length;
      assert.equal((await api("/v0/analysis", { id }, other)).status, 404);
      assert.equal((await api(`/v0/analysis/${id}`, undefined, other)).status, 404);
      assert.equal((await api(`/v0/analysis/${id}/places`, { query: "fixture" }, other)).status, 404);
      assert.equal((await api(`/v0/analysis/${id}/client-events`, { events: [] }, other)).status, 404);
      assert.equal((await api(`/v0/analysis/${id}/finish`, { outcome: "failed" }, other)).status, 404);
      assert.equal((await api("/v0/llm/gemini-generate-content", geminiBody(), other, { "x-save-analysis-id": id })).status, 404);
      assert.equal((await api("/v0/llm/gemini-generate-content", { ...geminiBody(), analysis_id: randomUUID() }, owner, { "x-save-analysis-id": id })).status, 400);
      assert.equal((await api(`/v0/analysis/${id}`)).status, 401);
      assert.equal((await calls()).length, before);
    });

    await t.test("start and finish are idempotent and only link owned captures", async () => {
      const id = await start(owner);
      assert.equal((await api("/v0/analysis", { id }, owner)).status, 201);
      await start(other);
      const ownedCapture = randomUUID(); const foreignCapture = randomUUID();
      await pool.query("insert into captures(id,user_id,source_type,status) values($1,$2,'note','review'),($3,$4,'note','review')", [ownedCapture, owner.guest_id, foreignCapture, other.guest_id]);
      assert.equal((await api(`/v0/analysis/${id}/finish`, { outcome: "review_candidate", capture_ids: [ownedCapture, foreignCapture] }, owner)).status, 404);
      assert.equal((await pool.query("select finished_at from analysis_sessions where id=$1", [id])).rows[0].finished_at, null);
      assert.equal((await pool.query("select * from analysis_captures where analysis_id=$1", [id])).rowCount, 0);
      assert.equal((await api(`/v0/analysis/${id}/finish`, { outcome: "review_candidate", capture_ids: [ownedCapture, ownedCapture] }, owner)).status, 200);
      assert.equal((await api(`/v0/analysis/${id}/finish`, { outcome: "failed", capture_ids: [ownedCapture] }, owner)).status, 200);
      const links = await pool.query("select * from analysis_captures where analysis_id=$1", [id]);
      assert.equal(links.rowCount, 1); assert.equal(links.rows[0].capture_id, ownedCapture); assert.equal(links.rows[0].user_id, owner.guest_id);
      assert.equal((await pool.query("select outcome from analysis_sessions where id=$1", [id])).rows[0].outcome, "review_candidate");
      const before = (await calls()).length;
      assert.equal((await api(`/v0/analysis/${id}/places`, { query: "fixture" }, owner)).body.code, "analysis_closed");
      assert.equal((await calls()).length, before);
    });

    await t.test("Google and Gemini HTTP requests create scoped operation and token receipts", async () => {
      const id = await start(owner);
      assert.equal((await api(`/v0/analysis/${id}/places`, { query: "fixture" }, owner)).status, 200);
      assert.equal((await api("/v0/llm/gemini-generate-content", geminiBody(), owner, { "x-save-analysis-id": id })).status, 200);
      const rows = (await pool.query("select * from analysis_usage_events where analysis_id=$1 order by operation", [id])).rows;
      assert.equal(rows.length, 2); assert.ok(rows.every(row => row.user_id === owner.guest_id && row.origin === "server" && row.outcome === "success"));
      const gemini = rows.find(row => row.operation === "gemini"); const google = rows.find(row => row.operation === "google_places");
      assert.equal(google.estimated_micros, "32000"); assert.equal(gemini.model, "gemini-3.5-flash");
      assert.equal(Number(gemini.input_tokens), 100); assert.equal(Number(gemini.output_tokens), 30);
      assert.equal(Number(gemini.thinking_tokens), 20); assert.equal(Number(gemini.cached_tokens), 10);
      assert.equal(Number(gemini.total_tokens), 150); assert.ok(Number(gemini.estimated_micros) > 0);
      assert.ok(!JSON.stringify(rows).includes("fixture-caption"));
      const summary = await api(`/v0/analysis/${id}`, undefined, owner); assert.equal(summary.status, 200);
      assert.equal(summary.body.cost_complete, false, "An open analysis has incomplete accounting");
      assert.equal((await api(`/v0/analysis/${id}/places`, { query: "fixture" }, owner)).status, 200);
      const before = (await calls()).length;
      const denied = await api(`/v0/analysis/${id}/places`, { query: "fixture" }, owner);
      assert.equal(denied.status, 429); assert.equal(denied.body.code, "analysis_limit_exceeded");
      const deniedGemini = await api("/v0/llm/gemini-generate-content", geminiBody(), owner, { "x-save-analysis-id": id });
      assert.equal(deniedGemini.status, 429); assert.equal(deniedGemini.body.code, "analysis_limit_exceeded");
      assert.equal((await calls()).length, before, "quota denial must happen before provider fetch");
      assert.equal((await pool.query("select * from analysis_usage_events where analysis_id=$1", [id])).rowCount, 3);
      const finished = await api(`/v0/analysis/${id}/finish`, { outcome: "source_only" }, owner);
      assert.equal(finished.status, 200); assert.equal(finished.body.cost_complete, false, "Expected client events have not arrived");
      assert.equal((await api(`/v0/analysis/${id}/client-events`, { events: [] }, owner)).status, 200);
      assert.equal((await api(`/v0/analysis/${id}`, undefined, owner)).body.cost_complete, true);
    });

    await t.test("provider failures settle their scoped reservations as unknown cost", async () => {
      const id = await start(owner);
      assert.equal((await api(`/v0/analysis/${id}/places`, { query: "fixture-provider-failure" }, owner)).status, 502);
      assert.equal((await api("/v0/llm/gemini-generate-content", geminiBody("fixture-provider-failure"), owner, { "x-save-analysis-id": id })).status, 502);
      const rows = (await pool.query("select * from analysis_usage_events where analysis_id=$1", [id])).rows;
      assert.equal(rows.length, 2); assert.ok(rows.every(row => row.outcome === "failure" && row.estimated_micros === null && Number(row.reserved_micros) > 0));
      assert.equal((await api(`/v0/analysis/${id}/finish`, { outcome: "failed" }, owner)).status, 200);
      assert.equal((await api(`/v0/analysis/${id}/client-events`, { events: [] }, owner)).status, 200);
      const summary = await api(`/v0/analysis/${id}`, undefined, owner); assert.equal(summary.body.cost_complete, false);
    });

    await t.test("recovery cache relinks the requested analysis and separates workflow runs", async () => {
      const firstAnalysis = await start(owner); const secondAnalysis = await start(owner); const thirdAnalysis = await start(owner);
      const captureResponse = await api("/v0/memory/captures", { source_type: "note", raw_text: "A lovely day outside" }, owner, { "x-save-analysis-id": firstAnalysis });
      assert.equal(captureResponse.status, 201, JSON.stringify(captureResponse.body));
      const captureId = captureResponse.body.id;
      const firstWorkflow = randomUUID(); const secondWorkflow = randomUUID();
      await pool.query("insert into workflow_runs(id,workflow_id,listing_id,user_id) values($1,'fixture','fixture',$3),($2,'fixture','fixture',$3)", [firstWorkflow, secondWorkflow, owner.guest_id]);
      const request = { queries: ["fixture recovery"], max_queries: 1, include_media_evidence: false, workflow_run_id: firstWorkflow };
      const path = `/v0/memory/captures/${captureId}/search-recovery`;
      const before = (await calls()).length;
      const first = await api(path, request, owner, { "x-save-analysis-id": firstAnalysis });
      assert.equal(first.status, 200, JSON.stringify(first.body)); assert.equal(first.body.reused, false);
      assert.equal(first.body.analysis_id, firstAnalysis); assert.deepEqual(first.body.errors, []);
      assert.equal((await calls()).length, before + 1);
      const second = await api(path, request, owner, { "x-save-analysis-id": secondAnalysis });
      assert.equal(second.status, 200, JSON.stringify(second.body)); assert.equal(second.body.reused, true);
      assert.equal(second.body.analysis_id, secondAnalysis); assert.equal(second.body.reused_from_analysis_id, firstAnalysis);
      assert.equal((await calls()).length, before + 1, "cached recovery must not repeat provider work");
      const linked = await pool.query("select analysis_id from analysis_captures where capture_id=$1 and analysis_id=any($2::uuid[])", [captureId, [firstAnalysis, secondAnalysis]]);
      assert.deepEqual(linked.rows.map(row => row.analysis_id).sort(), [firstAnalysis, secondAnalysis].sort());
      const third = await api(path, { ...request, workflow_run_id: secondWorkflow }, owner, { "x-save-analysis-id": thirdAnalysis });
      assert.equal(third.status, 200, JSON.stringify(third.body)); assert.equal(third.body.reused, false);
      assert.equal(third.body.analysis_id, thirdAnalysis); assert.equal((await calls()).length, before + 2);
      const count = (await calls()).length;
      assert.equal((await api(path, request, other)).status, 404);
      assert.equal((await calls()).length, count);
    });

    await t.test("denied recovery restores the preserved capture state and remains retryable", async () => {
      const id=await start(owner);
      const captured=await api("/v0/memory/captures",{source_type:"note",raw_text:"A lovely day outside"},owner,{"x-save-analysis-id":id});
      assert.equal(captured.status,201);
      for(let n=0;n<3;n++) assert.equal((await api(`/v0/analysis/${id}/places`,{query:"fixture"},owner)).status,200);
      const before=(await calls()).length;
      const path=`/v0/memory/captures/${captured.body.id}/search-recovery`;
      const body={queries:["fixture recovery"],max_queries:1,include_media_evidence:false};
      const denied=await api(path,body,owner,{"x-save-analysis-id":id});
      assert.equal(denied.status,429);
      assert.equal(denied.body.code,"analysis_limit_exceeded");
      assert.equal((await calls()).length,before);
      assert.equal((await pool.query("select status from captures where id=$1",[captured.body.id])).rows[0].status,"review");
      const fresh=await start(owner);
      const retry=await api(path,body,owner,{"x-save-analysis-id":fresh});
      assert.equal(retry.status,200);
      assert.equal(retry.body.reused,false);
    });

    await t.test("enabled limits reject headerless Gemini instead of using the unmetered path", async () => {
      const before = (await calls()).length;
      const result = await api("/v0/llm/gemini-generate-content", geminiBody(), owner);
      assert.equal(result.status, 400); assert.equal(result.body.code, "analysis_required");
      assert.equal((await calls()).length, before, "missing analysis context must never call Gemini when limits are enabled");
    });
    assert.ok((await calls()).every(call => call.provider !== "blocked"), "No unexpected external fetch was attempted");
  } finally {
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
    const forceStop = setTimeout(() => child.kill("SIGKILL"), 2_000);
    try { await exited; } finally { clearTimeout(forceStop); }
    await writeFile(logPath, log);
    try { if (owners.length) await pool.query("delete from profiles where id=any($1::text[])", [owners]); }
    finally { await pool.end(); }
    assert.ok(child.exitCode !== null || child.signalCode !== null, "Fixture server must be stopped");
    t.diagnostic(`Fixture server ${child.pid} stopped (${child.signalCode ?? child.exitCode}); provider and server logs: ${fixtureDir}`);
  }
});
