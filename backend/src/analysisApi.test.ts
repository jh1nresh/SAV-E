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
const fixtureRequestLimit = 4;
const fixtureHook = `
import { appendFileSync } from 'node:fs';
import dns from 'node:dns/promises';
import { syncBuiltinESMExports } from 'node:module';
// Keep the real public-host guard; resolve only hosts served by fake provider fixtures.
dns.lookup = async (hostname, options) => {
  if (!['duckduckgo.com', 'html.duckduckgo.com', 'www.instagram.com'].includes(hostname)) throw new Error('External DNS blocked by analysis API fixture');
  const answer = { address: '93.184.216.34', family: 4 };
  return options?.all ? [answer] : answer;
};
syncBuiltinESMExports();
globalThis.fetch = async (input, init) => {
  const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
  if (url.hostname === 'www.instagram.com' && url.pathname === '/reel/memory-fixture/') return new Response('<meta property="og:title" content="fixture on Instagram: &quot;店名「Fixture Cafe」 📍台北市大安區安和路一段100號&quot;">');
  if (url.hostname === 'www.instagram.com' && url.pathname === '/reel/metadata-outage/') return new Response('Synthetic metadata outage', { status: 503 });
  if (url.hostname === 'www.instagram.com' && url.pathname === '/reel/blocked-semantic/') return new Response('<title>Log in</title>Log in to continue');
  if (url.hostname === 'www.instagram.com' && url.pathname === '/reel/empty-semantic/') return new Response('<meta property="og:description" content="A quiet walk">');
  const google = url.hostname === 'maps.googleapis.com' && url.pathname === '/maps/api/place/textsearch/json';
  const gemini = url.hostname === 'generativelanguage.googleapis.com' && url.pathname.startsWith('/v1beta/models/');
  const publicSearch = ['duckduckgo.com', 'html.duckduckgo.com'].includes(url.hostname) && url.pathname === '/html/';
  if (publicSearch) {
    appendFileSync(process.env.ANALYSIS_FIXTURE_CALLS, JSON.stringify({ provider: 'public_search', failed: false })+'\\n');
    if (url.searchParams.get('q') === 'fixture-recovery-partial-failure') return new Response('Synthetic partial search failure', { status: 503 });
    if (url.searchParams.get('q')?.startsWith('fixture-multi-venue')) return new Response('<div class="result"><a class="result__a" href="https://alpha.invalid/">Alpha Fixture Cafe - Official</a><a class="result__snippet">1111 Park Ave, Tustin, CA 92782</a></div><div class="result"><a class="result__a" href="https://beta.invalid/">Beta Fixture Cafe - Official</a><a class="result__snippet">2222 Park Ave, Tustin, CA 92782</a></div>' + (url.searchParams.get('q').endsWith('-third') ? '<div class="result"><a class="result__a" href="https://gamma.invalid/">Gamma Fixture Cafe - Official</a><a class="result__snippet">3333 Park Ave, Tustin, CA 92782</a></div>' : ''));
    return new Response('<html><body>No fixture matches</body></html>');
  }
  if (!google && !gemini) {
    appendFileSync(process.env.ANALYSIS_FIXTURE_CALLS, JSON.stringify({ provider: 'blocked' })+'\\n');
    throw new Error('External fetch blocked by analysis API fixture');
  }
  const failed = google ? url.searchParams.get('query') === 'fixture-provider-failure' : String(init?.body).includes('fixture-provider-failure');
  appendFileSync(process.env.ANALYSIS_FIXTURE_CALLS, JSON.stringify({ provider: google ? 'google' : 'gemini', failed })+'\\n');
  if (failed) return Response.json({ error: { message: 'synthetic provider failure' } }, { status: 503 });
  const prompt = gemini ? JSON.parse(init.body).contents?.[0]?.parts?.[0]?.text ?? '' : '';
  if (gemini && prompt.includes('SOURCE_JSON')) {
    const source = JSON.parse(prompt.slice(prompt.indexOf('{', prompt.indexOf('SOURCE_JSON'))));
    if (source.caption.includes('Generated guess')) throw new Error('Generated capture label leaked into original evidence');
    const field = value => ({ value, quote: value, source: 'caption' });
    const venues = source.caption.includes('Fixture Cafe') ? [{ name: field('Fixture Cafe'), branch: null, address: field('台北市大安區安和路一段100號'), transport: null }] : [];
    return Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify({ venues }) }] } }], usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 30 } });
  }
  if (google && url.searchParams.get('query')?.includes('台北市大安區安和路一段100號')) return Response.json({ status: 'OK', results: [{ place_id: 'fixture-pikul-flow', name: 'Fixture Cafe', types: ['cafe', 'food', 'point_of_interest'], formatted_address: '台北市大安區安和路一段100號', geometry: { location: { lat: 25, lng: 121 } } }] });
  const multiVenue = google ? /Alpha Fixture Cafe|Beta Fixture Cafe|Gamma Fixture Cafe/.exec(url.searchParams.get('query') ?? '')?.[0] : undefined;
  if (multiVenue) return Response.json({ status: 'OK', results: [{ place_id: 'fixture-' + multiVenue, name: multiVenue, formatted_address: multiVenue.startsWith('Alpha') ? '1111 Park Ave, Tustin, CA 92782' : multiVenue.startsWith('Beta') ? '2222 Park Ave, Tustin, CA 92782' : '3333 Park Ave, Tustin, CA 92782', geometry: { location: { lat: multiVenue.startsWith('Alpha') ? 25 : multiVenue.startsWith('Beta') ? 26 : 27, lng: 121 } } }] });
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
      SAVE_ANALYSIS_LIMITS_ENABLED: "true", SAVE_ANALYSIS_ACCOUNT_DAILY_LIMIT: "10000", SAVE_ANALYSIS_REQUEST_LIMIT: String(fixtureRequestLimit),
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

    await t.test("memory repeats preserve chronology evidence owners branches and terminal reviews", async () => {
      const source = `https://fixture.invalid/memory/${randomUUID()}`;
      const original = "2025-01-02T03:04:05Z";
      const first = await api("/v0/memory/captures", { source_url: source + "?utm_source=one", raw_text: "first evidence", created_at: original }, owner);
      const repeated = await api("/v0/memory/captures", { source_url: source + "?fbclid=two", raw_text: "second evidence", created_at: "2026-01-01T00:00:00Z" }, owner);
      assert.equal(repeated.body.id, first.body.id);
      assert.equal(repeated.body.created_at, original);
      assert.match(repeated.body.raw_text, /first evidence/); assert.match(repeated.body.raw_text, /second evidence/);
      const concurrent = await Promise.all([1, 2, 3].map(n => api("/v0/memory/captures", { source_url: source + "?utm_campaign=" + n }, owner)));
      assert.ok(concurrent.every(result => result.body.id === first.body.id));
      const foreign = await api("/v0/memory/captures", { source_url: source }, other);
      assert.notEqual(foreign.body.id, first.body.id);
      const input = { capture_id: first.body.id, name: "Fixture Memory Cafe", address: "1 Memory Street", latitude: 25, longitude: 121, evidence: [{ text: "first" }], status: "review", created_at: original };
      const candidate = await api("/v0/memory/candidates", input, owner);
      assert.equal(candidate.status, 201);
      const again = await api("/v0/memory/candidates", { ...input, evidence: [{ text: "second" }] }, owner);
      assert.equal(again.status, 200); assert.equal(again.body.id, candidate.body.id); assert.equal(again.body.created_at, original);
      assert.equal(again.body.evidence.length, 2);
      const simultaneous = await Promise.all([1, 2, 3].map(() => api("/v0/memory/candidates", input, owner)));
      assert.ok(simultaneous.every(result => result.status === 200 && result.body.id === candidate.body.id));
      const branch = await api("/v0/memory/candidates", { ...input, address: "2 Memory Street", created_at: "2026-01-01T00:00:00Z" }, owner);
      assert.notEqual(branch.body.id, candidate.body.id);
      assert.equal(branch.body.created_at, original, "new venue from an old capture keeps original chronology");
      assert.equal((await api("/v0/memory/candidates", input, other)).status, 404);
      await pool.query("update place_candidates set status='rejected' where id=$1", [candidate.body.id]);
      assert.equal((await api("/v0/memory/candidates", input, owner)).body.status, "rejected");
      await pool.query("update place_candidates set status='review' where id=$1", [candidate.body.id]);
      const oldCapture = randomUUID(), oldCandidate = randomUUID();
      await pool.query("insert into captures(id,user_id,source_url) values($1,$2,$3)", [oldCapture, owner.guest_id, source]);
      await pool.query("insert into place_candidates(id,capture_id,name,address,latitude,longitude,evidence) values($1,$2,$3,$4,25,121,'[{\"text\":\"old preserved source\"}]')", [oldCandidate, oldCapture, input.name, input.address]);
      const audit = await api("/v0/memory/duplicate-audit", undefined, owner);
      assert.equal(audit.status, 200);
      assert.ok(audit.body.groups.some((group: any) => group.candidate_ids.includes(candidate.body.id) && group.candidate_ids.includes(oldCandidate)));
      const confirmed = await fetch(base + `/v0/memory/candidates/${candidate.body.id}`, { method: "PATCH", headers: { "content-type": "application/json", "x-save-guest-token": owner.guest_token }, body: JSON.stringify({ status: "confirmed" }) });
      assert.equal(confirmed.status, 200);
      const old = (await pool.query("select * from place_candidates where id=$1", [oldCandidate])).rows[0];
      assert.equal(old.status, "confirmed"); assert.equal(old.capture_id, oldCapture); assert.equal(old.evidence[0].text, "old preserved source");
      assert.equal((await pool.query("select status from place_candidates where id=$1", [branch.body.id])).rows[0].status, "review");
      assert.equal((await api("/v0/memory/candidates", input, owner)).body.status, "confirmed");
    });

    await t.test("delayed older imports repair reused capture and candidate dates before stamp confirmation", async () => {
      const delayedOwner = await newGuest();
      const source = `https://fixture.invalid/delayed/${randomUUID()}`;
      const captureInput = { source_url: source, created_at: "2025-06-01T00:00:00Z", raw_text: "June sync" };
      const capture = await api("/v0/memory/captures", captureInput, delayedOwner);
      const input = { capture_id: capture.body.id, name: "Delayed Cafe", address: "1 Delayed Road", latitude: 25, longitude: 121, created_at: captureInput.created_at, evidence: [{ text: "June evidence" }] };
      const candidate = await api("/v0/memory/candidates", input, delayedOwner);
      const olderCapture = await api("/v0/memory/captures", { ...captureInput, created_at: "2025-03-01T00:00:00Z", raw_text: "March offline evidence" }, delayedOwner);
      assert.equal(olderCapture.body.id, capture.body.id);
      assert.equal(olderCapture.body.created_at, "2025-03-01T00:00:00Z");
      assert.match(olderCapture.body.raw_text, /June sync/); assert.match(olderCapture.body.raw_text, /March offline evidence/);
      const inherited = await api("/v0/memory/candidates", input, delayedOwner);
      assert.equal(inherited.body.id, candidate.body.id);
      assert.equal(inherited.body.created_at, "2025-03-01T00:00:00Z", "existing candidates inherit newly discovered earlier capture chronology");
      const delayed = await api("/v0/memory/candidates", { ...input, created_at: "2025-01-01T00:00:00Z", evidence: [{ text: "January offline evidence" }] }, delayedOwner);
      assert.equal(delayed.body.id, candidate.body.id); assert.equal(delayed.body.created_at, "2025-01-01T00:00:00Z");
      assert.deepEqual(delayed.body.evidence, [{ text: "June evidence" }, { text: "January offline evidence" }]);
      for (const created_at of ["2026-01-01T00:00:00Z", "invalid", null]) {
        assert.equal((await api("/v0/memory/captures", { ...captureInput, created_at }, delayedOwner)).body.created_at, "2025-03-01T00:00:00Z");
        assert.equal((await api("/v0/memory/candidates", { ...input, created_at }, delayedOwner)).body.created_at, "2025-01-01T00:00:00Z");
      }
      const place = randomUUID();
      await pool.query("insert into places(id,user_id,name,address,latitude,longitude,created_at) values($1,$2,'Delayed Cafe','1 Delayed Road',25,121,'2025-06-01T00:00:00Z')", [place, delayedOwner.guest_id]);
      const saved = await fetch(base + `/v0/memory/candidates/${candidate.body.id}`, { method: "PATCH", headers: { "content-type": "application/json", "x-save-guest-token": delayedOwner.guest_token }, body: JSON.stringify({ status: "saved", place_id: place }) });
      assert.equal(saved.status, 200);
      const reload = await api("/v0/places", undefined, delayedOwner);
      assert.equal((reload.body as any).find((row: any) => row.id === place).created_at, "2025-01-01T00:00:00Z");
      const pendingDuplicate = randomUUID();
      await pool.query("insert into place_candidates(id,capture_id,name,address,latitude,longitude) values($1,$2,'Delayed Cafe','1 Delayed Road',25,121)", [pendingDuplicate, capture.body.id]);
      const earlierSaved = await api("/v0/memory/candidates", { ...input, created_at: "2024-01-01T00:00:00Z" }, delayedOwner);
      assert.equal(earlierSaved.body.id, candidate.body.id); assert.equal(earlierSaved.body.status, "saved");
      assert.equal(earlierSaved.body.place_id, place);
      assert.equal(earlierSaved.body.created_at, "2024-01-01T00:00:00Z");
      const savedReload = await api("/v0/places", undefined, delayedOwner);
      assert.equal((savedReload.body as any).find((row: any) => row.id === place).created_at, "2024-01-01T00:00:00Z", "earlier saved source history updates the owned Stamp without another decision");
      assert.equal((await pool.query("select status from place_candidates where id=$1", [pendingDuplicate])).rows[0].status, "review", "date-only reuse must not reconcile pending reviews");
      await api("/v0/memory/candidates", { ...input, created_at: "invalid" }, delayedOwner);
      assert.equal((await pool.query("select created_at from places where id=$1", [place])).rows[0].created_at.toISOString(), "2024-01-01T00:00:00.000Z");
    });

    await t.test("duplicate confirmation preserves independent pending workflow reservations and decisions", async () => {
      const duplicateOwner = await newGuest();
      const reviews = [];
      for (const created_at of ["2025-06-01T00:00:00Z", "2025-01-01T00:00:00Z"]) {
        const capture = await api("/v0/memory/captures", { source_type: "note", created_at }, duplicateOwner);
        const run = await api("/v0/workflows/place-recovery/runs", { source_type: "note" }, duplicateOwner);
        assert.equal(run.status, 201, JSON.stringify(run.body));
        const candidate = await api("/v0/memory/candidates", { capture_id: capture.body.id, workflow_run_id: run.body.id, name: "Reserved Cafe", address: "1 Reserved Road", latitude: 25, longitude: 121, evidence: [{ text: created_at }] }, duplicateOwner);
        assert.equal(candidate.status, 201, JSON.stringify(candidate.body));
        assert.equal((await api(`/v0/workflows/place-recovery/runs/${run.body.id}/result`, { result_type: "review_candidate", evidence_tier: "weak", candidate_refs: [candidate.body.id], evidence_refs: [candidate.body.id] }, duplicateOwner)).status, 201);
        reviews.push({ candidate: candidate.body, run: run.body, capture: capture.body });
      }
      const other = reviews[1];
      const snapshot = async () => ({
        run: (await pool.query("select * from workflow_runs where id=$1", [other.run.id])).rows,
        receipts: (await pool.query("select * from workflow_receipts where run_id=$1 order by id", [other.run.id])).rows,
        ledger: (await pool.query("select * from credit_ledger where run_id=$1 order by id", [other.run.id])).rows,
        candidate: (await pool.query("select * from place_candidates where id=$1", [other.candidate.id])).rows,
      });
      const before = await snapshot();
      assert.equal(before.run[0].credit_settlement, "pending");
      assert.equal(before.ledger.filter(row => row.reason === "reserve").length, 1);
      const sameRunDuplicate = randomUUID();
      await pool.query("insert into place_candidates(id,capture_id,workflow_run_id,name,address,latitude,longitude) values($1,$2,$3,'Reserved Cafe','1 Reserved Road',25,121)", [sameRunDuplicate, reviews[0].capture.id, reviews[0].run.id]);
      const place = randomUUID();
      await pool.query("insert into places(id,user_id,name,address,latitude,longitude,created_at) values($1,$2,'Reserved Cafe','1 Reserved Road',25,121,'2025-07-01T00:00:00Z')", [place, duplicateOwner.guest_id]);
      const confirmed = await api(`/v0/workflows/place-recovery/runs/${reviews[0].run.id}/decision`, { action: "confirm", candidate_id: reviews[0].candidate.id, final_place_id: place }, duplicateOwner);
      assert.equal(confirmed.status, 201, JSON.stringify(confirmed.body));
      assert.deepEqual(await snapshot(), before, "a separate pending candidate and its reservation history must stay actionable and unchanged");
      assert.equal((await pool.query("select status from place_candidates where id=$1", [sameRunDuplicate])).rows[0].status, "saved", "the decided run can complete its exact duplicate rows");
      const visible = await api("/v0/memory/candidates", undefined, duplicateOwner);
      assert.ok((visible.body as any).some((row: any) => row.id === other.candidate.id && row.status === "review" && !row.superseded_by_candidate_id));
      assert.equal((await pool.query("select created_at from places where id=$1", [place])).rows[0].created_at.toISOString(), "2025-06-01T00:00:00.000Z", "unconfirmed independent source dates do not change the stamp yet");
      const second = await api(`/v0/workflows/place-recovery/runs/${other.run.id}/decision`, { action: "confirm", candidate_id: other.candidate.id, final_place_id: place }, duplicateOwner);
      assert.equal(second.status, 201, JSON.stringify(second.body));
      assert.equal(second.body.run.credit_settlement, "consumed");
      assert.equal((await pool.query("select created_at from places where id=$1", [place])).rows[0].created_at.toISOString(), "2025-01-01T00:00:00.000Z");
      const after = await snapshot();
      assert.deepEqual(after.receipts.filter(row => row.receipt_type === "analysis"), before.receipts);
      assert.deepEqual(after.ledger.filter(row => row.reason === "reserve"), before.ledger);
      assert.equal(after.ledger.filter(row => row.reason === "consumed").length, 1);
      const thirdRun = await api("/v0/workflows/place-recovery/runs", { source_type: "note" }, duplicateOwner);
      assert.equal(thirdRun.status, 201);
      const independent = await api("/v0/memory/candidates", { capture_id: other.capture.id, workflow_run_id: thirdRun.body.id, name: "Reserved Cafe", address: "1 Reserved Road", latitude: 25, longitude: 121 }, duplicateOwner);
      assert.equal(independent.status, 201, JSON.stringify(independent.body));
      assert.equal(independent.body.status, "review", "a new pending workflow must not inherit an older workflow's saved status");
      assert.equal(independent.body.place_id, null);
      assert.equal(independent.body.workflow_run_id, thirdRun.body.id);
      assert.deepEqual(await snapshot(), after, "original terminal review, receipts and ledger stay unchanged");
      assert.equal((await api(`/v0/workflows/place-recovery/runs/${thirdRun.body.id}/result`, { result_type: "review_candidate", evidence_tier: "weak", candidate_refs: [independent.body.id], evidence_refs: [independent.body.id] }, duplicateOwner)).status, 201);
      const third = await api(`/v0/workflows/place-recovery/runs/${thirdRun.body.id}/decision`, { action: "confirm", candidate_id: independent.body.id, final_place_id: place }, duplicateOwner);
      assert.equal(third.status, 201, JSON.stringify(third.body));
      assert.equal(third.body.run.credit_settlement, "consumed");
    });

    await t.test("correcting a venue or branch completes only duplicates of the final owned place", async () => {
      for (const finalName of ["Corrected Cafe", "Original Cafe"]) {
        const captured = await api("/v0/memory/captures", { source_type: "note" }, owner);
        const input = { capture_id: captured.body.id, name: "Original Cafe", address: "1 Original Road", latitude: 25, longitude: 121, status: "review", evidence: [{ text: "original clue" }] };
        const original = await api("/v0/memory/candidates", input, owner);
        const oldDuplicate = randomUUID(), exactFinal = randomUUID(), place = randomUUID();
        await pool.query("insert into place_candidates(id,capture_id,name,address,latitude,longitude,evidence) values($1,$2,'Original Cafe','1 Original Road',25,121,'[{\"text\":\"original duplicate evidence\"}]'),($3,$2,$4,'2 Correct Road',26,122,'[{\"text\":\"final venue evidence\"}]')", [oldDuplicate, captured.body.id, exactFinal, finalName]);
        await pool.query("insert into places(id,user_id,name,address,latitude,longitude) values($1,$2,$3,'2 Correct Road',26,122)", [place, owner.guest_id, finalName]);
        const confirmed = await fetch(base + `/v0/memory/candidates/${original.body.id}`, { method: "PATCH", headers: { "content-type": "application/json", "x-save-guest-token": owner.guest_token }, body: JSON.stringify({ status: "saved", place_id: place }) });
        assert.equal(confirmed.status, 200);
        const rows = (await pool.query("select * from place_candidates where id=any($1::uuid[])", [[oldDuplicate, exactFinal]])).rows;
        const untouched = rows.find(row => row.id === oldDuplicate)!;
        const finished = rows.find(row => row.id === exactFinal)!;
        assert.equal(untouched.status, "review", "correcting one clue must not confirm its previous identity");
        assert.equal(untouched.place_id, null);
        assert.deepEqual(untouched.evidence, [{ text: "original duplicate evidence" }]);
        assert.equal(finished.status, "saved"); assert.equal(finished.place_id, place);
        assert.equal(finished.evidence[0].text, "final venue evidence");
        assert.equal(finished.evidence[1].completed_by_candidate_id, original.body.id);
        const nextFinalReview = randomUUID();
        await pool.query("insert into place_candidates(id,capture_id,name,address,latitude,longitude) values($1,$2,$3,'2 Correct Road',26,122)", [nextFinalReview, captured.body.id, finalName]);
        const audit = await api("/v0/memory/duplicate-audit", undefined, owner);
        assert.equal(audit.status, 200);
        assert.ok(audit.body.groups.every((group: any) => !group.pending_candidate_ids.includes(oldDuplicate) || !group.saved_place_ids.includes(place)), "old A reviews must not be reported as duplicates of the corrected B Stamp");
        assert.ok(audit.body.groups.some((group: any) => group.pending_candidate_ids.includes(nextFinalReview) && group.saved_place_ids.includes(place)), "actual B reviews remain linked to the corrected saved place");
      }
    });

    await t.test("confirming old clues into an existing stamp persists earliest chronology across reloads", async () => {
      for (const useOlderDuplicate of [false, true]) {
        const originalDate = "2025-01-01T00:00:00Z";
        const captureDate = useOlderDuplicate ? "2025-04-01T00:00:00Z" : originalDate;
        const captured = await api("/v0/memory/captures", { source_type: "note", created_at: captureDate }, owner);
        const candidate = await api("/v0/memory/candidates", { capture_id: captured.body.id, name: "Chronology Cafe", address: "1 Chronology Street", latitude: 25, longitude: 121, status: "review" }, owner);
        const place = randomUUID();
        await pool.query("insert into places(id,user_id,name,address,latitude,longitude,created_at) values($1,$2,'Chronology Cafe','1 Chronology Street',25,121,'2025-06-01T00:00:00Z')", [place, owner.guest_id]);
        if (useOlderDuplicate) {
          const oldCapture = randomUUID();
          await pool.query("insert into captures(id,user_id,created_at) values($1,$2,$3)", [oldCapture, owner.guest_id, originalDate]);
          await pool.query("insert into place_candidates(capture_id,name,address,latitude,longitude,created_at) values($1,'Chronology Cafe','1 Chronology Street',25,121,'2025-03-01T00:00:00Z')", [oldCapture]);
        }
        const patchCandidate = async (candidateID: string) => fetch(base + `/v0/memory/candidates/${candidateID}`, { method: "PATCH", headers: { "content-type": "application/json", "x-save-guest-token": owner.guest_token }, body: JSON.stringify({ status: "saved", place_id: place }) });
        assert.equal((await patchCandidate(candidate.body.id)).status, 200);
        const stamp = (await pool.query("select created_at from places where id=$1", [place])).rows[0];
        assert.equal(stamp.created_at.toISOString(), "2025-01-01T00:00:00.000Z", "cloud stamp keeps the earliest confirmed source time");
        const reload = await api("/v0/places", undefined, owner);
        assert.equal((reload.body as any).find((row: any) => row.id === place).created_at, originalDate, "another client fetches the repaired chronology");
        const laterCapture = await api("/v0/memory/captures", { source_type: "note", created_at: "2025-07-01T00:00:00Z" }, owner);
        const laterCandidate = await api("/v0/memory/candidates", { capture_id: laterCapture.body.id, name: "Chronology Cafe", address: "1 Chronology Street", latitude: 25, longitude: 121 }, owner);
        assert.equal((await patchCandidate(laterCandidate.body.id)).status, 200);
        assert.equal((await pool.query("select created_at from places where id=$1", [place])).rows[0].created_at.toISOString(), "2025-01-01T00:00:00.000Z", "later confirmations cannot move the date forward");
        const laterPatch = await fetch(base + `/v0/places/${place}`, { method: "PATCH", headers: { "content-type": "application/json", "x-save-guest-token": owner.guest_token }, body: JSON.stringify({ created_at: "2030-01-01T00:00:00Z" }) });
        assert.equal(laterPatch.status, 200);
        assert.equal((await laterPatch.json() as any).created_at, originalDate, "ordinary place merges cannot move timestamps later");
      }
    });

    await t.test("ordinary owned stamp merges persist only earlier valid dates", async () => {
      const mergeOwner = await newGuest();
      const place = randomUUID();
      const created = await api("/v0/places", { id: place, name: "Merged Cafe", address: "1 Merge Road", latitude: 25, longitude: 121, created_at: "2025-06-01T00:00:00Z" }, mergeOwner);
      assert.equal(created.status, 201, JSON.stringify(created.body));
      const patch = (body: any, guest = mergeOwner) => fetch(base + `/v0/places/${place}`, { method: "PATCH", headers: { "content-type": "application/json", "x-save-guest-token": guest.guest_token }, body: JSON.stringify(body) });
      assert.equal((await patch({ created_at: "2024-01-01T00:00:00Z" }, other)).status, 404);
      const earlier = await patch({ created_at: "2025-01-01T00:00:00Z", name: "Merged Cafe Updated" });
      assert.equal(earlier.status, 200);
      assert.equal((await earlier.json() as any).created_at, "2025-01-01T00:00:00Z");
      assert.equal((await patch({ created_at: "2026-01-01T00:00:00Z" })).status, 200);
      for (const created_at of ["invalid", null, 0, {}, ""]) {
        assert.equal((await patch({ created_at, name: "Must not write" })).status, 400);
      }
      const reload = await api("/v0/places", undefined, mergeOwner);
      const row = (reload.body as any).find((row: any) => row.id === place);
      assert.equal(row.created_at, "2025-01-01T00:00:00Z"); assert.equal(row.name, "Merged Cafe Updated");
    });

    await t.test("social source provenance and completed-empty state survive real HTTP persistence", async () => {
      for (const failed of [false, true]) {
        const source = `https://www.instagram.com/reel/empty-semantic/?failure=${failed}`;
        const captureId = randomUUID();
        await pool.query("insert into captures(id,user_id,source_url,raw_text,title) values($1,$2,$3,'Old caption\n\nGenerated guess','Generated guess')", [captureId, owner.guest_id, source]);
        const text = failed ? "fixture-provider-failure" : "No venue in this caption";
        const repeated = await api("/v0/memory/captures", { source_url: source, raw_text: text, title: "Generated guess 2" }, owner);
        assert.equal(repeated.status, 201); assert.equal(repeated.body.id, captureId);
        assert.ok(!repeated.body.raw_text.includes("Generated guess 2"));
        assert.deepEqual(repeated.body.source_resolution.captured_text_v1.texts, [text]);
        const run = await api("/v0/workflows/place-recovery/runs", { source_url: source }, owner);
        const independent = await api("/v0/workflows/place-recovery/runs", { source_url: source }, owner);
        const clue = await api("/v0/memory/candidates", { capture_id: captureId, workflow_run_id: run.body.id, name: "Saved link", status: "source_only", missing_info: ["Analysis pending", "Exact place needed"] }, owner);
        const otherClue = await api("/v0/memory/candidates", { capture_id: captureId, workflow_run_id: independent.body.id, name: "Saved link", status: "source_only", missing_info: ["Analysis pending"] }, owner);
        const aid = await start(owner);
        const result = await api(`/v0/memory/captures/${captureId}/search-recovery`, { workflow_run_id: run.body.id, include_media_evidence: false }, owner, { "x-save-analysis-id": aid });
        assert.equal(result.status, 200, JSON.stringify(result.body)); assert.deepEqual(result.body.created_candidates, []);
        assert.equal(result.body.errors.length > 0, failed, JSON.stringify(result.body));
        const persisted = (await pool.query("select * from place_candidates where id=$1", [clue.body.id])).rows[0];
        assert.deepEqual(persisted.missing_info, failed ? ["Analysis pending", "Exact place needed"] : ["Exact place needed"]);
        assert.equal(persisted.status, "source_only"); assert.equal(persisted.workflow_run_id, run.body.id);
        assert.deepEqual((await pool.query("select missing_info from place_candidates where id=$1", [otherClue.body.id])).rows[0].missing_info, ["Analysis pending"]);
        const reloaded = await api(`/v0/memory/captures/${captureId}`, undefined, owner);
        assert.deepEqual(reloaded.body.source_resolution.captured_text_v1.texts, [text]);
        if (failed) {
          const unscoped = await api(`/v0/memory/captures/${captureId}/search-recovery`, { workflow_run_id: run.body.id, include_media_evidence: false, max_queries: 2 }, owner);
          assert.equal(unscoped.status, 200); assert.ok(unscoped.body.errors.length);
          assert.equal((await pool.query("select outcome from analysis_sessions where id=$1", [unscoped.body.analysis_id])).rows[0].outcome, "failed");
        }
      }
    });

    await t.test("URL-only login wall preserves pending state through HTTP reload", async () => {
      const source = "https://www.instagram.com/reel/blocked-semantic/";
      const capture = await api("/v0/memory/captures", { source_url: source, raw_text: source }, owner);
      const run = await api("/v0/workflows/place-recovery/runs", { source_url: source }, owner);
      const clue = await api("/v0/memory/candidates", { capture_id: capture.body.id, workflow_run_id: run.body.id, name: "Source clue", status: "source_only", missing_info: ["Analysis pending"] }, owner);
      const before = (await calls()).filter(call => call.provider === "gemini").length;
      const result = await api(`/v0/memory/captures/${capture.body.id}/search-recovery`, { workflow_run_id: run.body.id, include_media_evidence: false }, owner, { "x-save-analysis-id": await start(owner) });
      assert.equal(result.status, 200, JSON.stringify(result.body)); assert.deepEqual(result.body.created_candidates, []);
      assert.deepEqual(result.body.receipt.failureReason, { kind: "insufficient_source", reason: "login_required" });
      const row = (await pool.query("select * from place_candidates where id=$1", [clue.body.id])).rows[0];
      assert.deepEqual(row.missing_info, ["Analysis pending"]); assert.equal(row.status, "source_only");
      assert.equal((await calls()).filter(call => call.provider === "gemini").length, before);
    });

    await t.test("captured caption recovery supersedes pending clues despite a metadata outage", async () => {
      const id = await start(owner);
      const captured = await api("/v0/memory/captures", { source_url: "https://www.instagram.com/reel/metadata-outage/",
        raw_text: "Fixture Cafe\n台北市大安區安和路一段100號" }, owner);
      const clue = await api("/v0/memory/candidates", { capture_id: captured.body.id, name: "Source clue", status: "source_only", missing_info: ["Analysis pending"] }, owner);
      const recovered = await api(`/v0/memory/captures/${captured.body.id}/search-recovery`, { explicit_retry: true, include_media_evidence: false }, owner, { "x-save-analysis-id": id });
      assert.equal(recovered.status, 200, JSON.stringify(recovered.body));
      assert.equal(recovered.body.created_candidates.length, 1);
      assert.deepEqual(recovered.body.errors, []);
      assert.deepEqual(recovered.body.superseded_candidate_ids, [clue.body.id]);
      const reload = await api(`/v0/memory/candidates?capture_id=${captured.body.id}`, undefined, owner);
      assert.equal(reload.body.find((row: any) => row.id === clue.body.id).superseded_by_candidate_id, recovered.body.created_candidates[0].id);
    });

    await t.test("explicit source retry reuses capture time and persists supersession without changing user truth or receipts", async () => {
      const id = await start(owner);
      const captured = await api("/v0/memory/captures", { source_url: "https://www.instagram.com/reel/memory-fixture/", created_at: "2025-02-03T04:05:06Z" }, owner);
      const run = randomUUID();
      await pool.query("insert into workflow_runs(id,workflow_id,listing_id,user_id,status,credit_settlement) values($1,'fixture','fixture',$2,'completed','consumed')", [run, owner.guest_id]);
      const clue = await api("/v0/memory/candidates", { capture_id: captured.body.id, workflow_run_id: run, name: "Saved link", status: "source_only" }, owner);
      const before = (await pool.query("select * from workflow_runs where id=$1", [run])).rows[0];
      const retry = await api(`/v0/memory/captures/${captured.body.id}/search-recovery`, { workflow_run_id: run, explicit_retry: true, max_queries: 1, include_media_evidence: false }, owner, { "x-save-analysis-id": id });
      assert.equal(retry.status, 200, JSON.stringify(retry.body));
      assert.equal(retry.body.created_candidates.length, 1, JSON.stringify(retry.body));
      assert.deepEqual(retry.body.superseded_candidate_ids, [clue.body.id]);
      const recovered = retry.body.created_candidates[0];
      assert.equal(recovered.evidence[0].text, `Source URL: ${captured.body.source_url}`);
      assert.deepEqual(recovered.evidence.filter((entry: any) => entry.google_place_id), [
        { google_place_id: "fixture-pikul-flow", google_types: ["cafe", "food", "point_of_interest"] },
      ]);
      assert.deepEqual(recovered.evidence.filter((entry: any) => entry.semantic_source), [
        { semantic_source: { name: "Fixture Cafe", branch: null, address: "台北市大安區安和路一段100號" } },
      ]);
      assert.equal(recovered.place_id, null, "provider identity must not replace the app place UUID");
      assert.deepEqual((await pool.query("select evidence from place_candidates where id=$1", [recovered.id])).rows[0].evidence, recovered.evidence);
      assert.equal(recovered.created_at, captured.body.created_at); assert.notEqual(recovered.workflow_run_id, run);
      assert.equal(retry.body.workflow_run_id, recovered.workflow_run_id);
      const reload = await api(`/v0/memory/candidates?capture_id=${captured.body.id}`, undefined, owner);
      const old = (reload.body as any).find((row: any) => row.id === clue.body.id);
      const restored = (reload.body as any).find((row: any) => row.id === recovered.id);
      assert.deepEqual(restored.evidence, recovered.evidence, "provider identity and text evidence survive HTTP reload");
      assert.equal(old.status, "source_only"); assert.equal(old.superseded_by_candidate_id, recovered.id);
      assert.deepEqual((await pool.query("select * from workflow_runs where id=$1", [run])).rows[0], before);
      const second = await api(`/v0/memory/captures/${captured.body.id}/search-recovery`, { workflow_run_id: run, explicit_retry: true, max_queries: 1, include_media_evidence: false }, owner, { "x-save-analysis-id": id });
      assert.equal(second.status, 200); assert.equal(second.body.reused, true);
      const freshAnalysis = await start(owner);
      const fresh = await api(`/v0/memory/captures/${captured.body.id}/search-recovery`, { workflow_run_id: run, explicit_retry: true, max_queries: 1, include_media_evidence: false }, owner, { "x-save-analysis-id": freshAnalysis });
      assert.equal(fresh.status, 200, JSON.stringify(fresh.body)); assert.equal(fresh.body.reused, false);
      assert.equal(fresh.body.created_candidates[0].id, recovered.id);
      assert.equal((await pool.query("select count(*)::int as count from place_candidates where capture_id=$1", [captured.body.id])).rows[0].count, 2);
    });

    await t.test("settled Keep source only retry produces a separately confirmable workflow", async () => {
      const source = "https://www.instagram.com/reel/memory-fixture/?case=settled";
      const capture = await api("/v0/memory/captures", { source_url: source, created_at: "2025-01-01T00:00:00Z" }, owner);
      const run = await api("/v0/workflows/place-recovery/runs", { source_url: source }, owner);
      assert.equal(run.status, 201, JSON.stringify(run.body));
      const clue = await api("/v0/memory/candidates", { capture_id: capture.body.id, workflow_run_id: run.body.id, name: "Saved link", status: "source_only", evidence: [{ text: "original source clue" }] }, owner);
      const analysis = await api(`/v0/workflows/place-recovery/runs/${run.body.id}/result`, { result_type: "source_only_clue", evidence_tier: "weak", candidate_refs: [clue.body.id], evidence_refs: [clue.body.id] }, owner);
      assert.equal(analysis.status, 201, JSON.stringify(analysis.body));
      const kept = await api(`/v0/workflows/place-recovery/runs/${run.body.id}/decision`, { action: "source_only", candidate_id: clue.body.id }, owner);
      assert.equal(kept.status, 201, JSON.stringify(kept.body));
      assert.equal(kept.body.run.credit_settlement, "partial");
      const originalRun = (await pool.query("select * from workflow_runs where id=$1", [run.body.id])).rows;
      const originalReceipts = (await pool.query("select * from workflow_receipts where run_id=$1 order by id", [run.body.id])).rows;
      const originalLedger = (await pool.query("select * from credit_ledger where run_id=$1 order by id", [run.body.id])).rows;
      const aid = await start(owner);
      const retryBody = { workflow_run_id: run.body.id, explicit_retry: true, max_queries: 1, include_media_evidence: false };
      const foreignRun = await api("/v0/workflows/place-recovery/runs", { source_url: source }, other);
      const denied = await api(`/v0/memory/captures/${capture.body.id}/search-recovery`, { ...retryBody, workflow_run_id: foreignRun.body.id }, owner, { "x-save-analysis-id": aid });
      assert.equal(denied.status, 404, "a foreign workflow cannot become a retry parent");
      const retry = await api(`/v0/memory/captures/${capture.body.id}/search-recovery`, retryBody, owner, { "x-save-analysis-id": aid });
      assert.equal(retry.status, 200, JSON.stringify(retry.body));
      const recovered = retry.body.created_candidates[0];
      assert.ok(recovered, JSON.stringify(retry.body));
      const freshAnalysis = await start(owner);
      const fresh = await api(`/v0/memory/captures/${capture.body.id}/search-recovery`, retryBody, owner, { "x-save-analysis-id": freshAnalysis });
      assert.equal(fresh.status, 200, JSON.stringify(fresh.body));
      assert.equal(fresh.body.workflow_run_id, recovered.workflow_run_id);
      assert.equal(fresh.body.created_candidates[0].id, recovered.id);
      assert.equal(fresh.body.reused, false, "new source work may reuse the exact existing actionable workflow result");
      const place = randomUUID();
      await pool.query("insert into places(id,user_id,name,address,latitude,longitude) values($1,$2,'Fixture Cafe','台北市大安區安和路一段100號',25,121)", [place, owner.guest_id]);
      const confirmed = await api(`/v0/workflows/place-recovery/runs/${recovered.workflow_run_id}/decision`, { action: "confirm", candidate_id: recovered.id, final_place_id: place }, owner);
      assert.equal(confirmed.status, 201, JSON.stringify(confirmed.body));
      assert.notEqual(recovered.workflow_run_id, run.body.id);
      assert.equal(retry.body.workflow_run_id, recovered.workflow_run_id);
      assert.equal(confirmed.body.run.credit_settlement, "consumed");
      assert.equal((await pool.query("select status from place_candidates where id=$1", [recovered.id])).rows[0].status, "saved");
      assert.deepEqual((await pool.query("select * from workflow_runs where id=$1", [run.body.id])).rows, originalRun);
      assert.deepEqual((await pool.query("select * from workflow_receipts where run_id=$1 order by id", [run.body.id])).rows, originalReceipts);
      assert.deepEqual((await pool.query("select * from credit_ledger where run_id=$1 order by id", [run.body.id])).rows, originalLedger);
      const oldClue = (await pool.query("select * from place_candidates where id=$1", [clue.body.id])).rows[0];
      assert.equal(oldClue.workflow_run_id, run.body.id); assert.equal(oldClue.status, "source_only"); assert.equal(oldClue.evidence[0].text, "original source clue");
      const newReceipts = (await pool.query("select receipt_type from workflow_receipts where run_id=$1", [recovered.workflow_run_id])).rows;
      assert.deepEqual(newReceipts.map(row => row.receipt_type).sort(), ["analysis", "decision"]);
      const newLedger = (await pool.query("select reason,delta from credit_ledger where run_id=$1", [recovered.workflow_run_id])).rows;
      assert.equal(newLedger.filter(row => row.reason === "reserve").length, 1);
      assert.equal(newLedger.filter(row => row.reason === "consumed").length, 1);
      const retryRuns = await pool.query("select r.id from workflow_runs r join work_orders w on w.id=r.work_order_id where w.user_id=$1 and w.budget_policy->>'retry_of_run_id'=$2", [owner.guest_id, run.body.id]);
      assert.deepEqual(retryRuns.rows.map(row => row.id), [recovered.workflow_run_id]);
      const linked = await pool.query("select analysis_id from analysis_captures where capture_id=$1 and analysis_id=any($2::uuid[])", [capture.body.id, [aid, freshAnalysis]]);
      assert.equal(linked.rows.length, 2, "both explicit analyses retain their owned capture links");
      const replay = await api(`/v0/memory/captures/${capture.body.id}/search-recovery`, retryBody, owner, { "x-save-analysis-id": aid });
      assert.equal(replay.status, 200); assert.equal(replay.body.workflow_run_id, recovered.workflow_run_id); assert.deepEqual(replay.body.created_candidates, []);
    });

    await t.test("two venues recovered from pending or settled clues can each be confirmed in either order", async () => {
      for (const { settled, reversed, generic, partial } of [...[true, false].flatMap(settled => [false, true].map(reversed => ({ settled, reversed, generic: true, partial: false }))), { settled: false, reversed: false, generic: false, partial: false }, { settled: false, reversed: false, generic: true, partial: true }]) {
        const retiresSource = generic && !partial;
        const multiOwner = await newGuest();
        const capture = await api("/v0/memory/captures", { source_type: "note", raw_text: "two venue clues" }, multiOwner);
        const run = await api("/v0/workflows/place-recovery/runs", { source_type: "note" }, multiOwner);
        const clue = await api("/v0/memory/candidates", { capture_id: capture.body.id, workflow_run_id: run.body.id, name: generic ? "Saved source" : "Named uncertain venue", status: "source_only", evidence: [{ text: "two venue clues" }] }, multiOwner);
        assert.equal((await api(`/v0/workflows/place-recovery/runs/${run.body.id}/result`, { result_type: "source_only_clue", evidence_tier: "weak", candidate_refs: [clue.body.id], evidence_refs: [clue.body.id] }, multiOwner)).status, 201);
        if (settled) assert.equal((await api(`/v0/workflows/place-recovery/runs/${run.body.id}/decision`, { action: "source_only", candidate_id: clue.body.id }, multiOwner)).status, 201);
        const originalReceipts = (await pool.query("select * from workflow_receipts where run_id=$1 order by id", [run.body.id])).rows;
        const retryBody = { workflow_run_id: run.body.id, explicit_retry: true, queries: partial ? ["fixture-multi-venue", "fixture-recovery-partial-failure"] : ["fixture-multi-venue"], max_queries: partial ? 2 : 1, include_media_evidence: false };
        const aid = await start(multiOwner);
        const recovered = await api(`/v0/memory/captures/${capture.body.id}/search-recovery`, retryBody, multiOwner, { "x-save-analysis-id": aid });
        assert.equal(recovered.status, 200, JSON.stringify(recovered.body));
        assert.equal(recovered.body.created_candidates.length, 2, JSON.stringify(recovered.body));
        if (partial) assert.ok(recovered.body.errors.length > 0, "fixture persists venues while retaining an explicit partial recovery error");
        const candidates = recovered.body.created_candidates as Array<Record<string, any>>;
        assert.notEqual(candidates[0].name, candidates[1].name);
        assert.deepEqual(recovered.body.superseded_candidate_ids, retiresSource ? [clue.body.id] : []);
        const sourceReload = await api(`/v0/memory/candidates?capture_id=${capture.body.id}`, undefined, multiOwner);
        const sourceRow = (sourceReload.body as any).find((row: any) => row.id === clue.body.id);
        assert.equal(sourceRow.status, "source_only"); assert.equal(sourceRow.workflow_run_id, run.body.id);
        assert.deepEqual(sourceRow.superseded_by_candidate_ids.sort(), retiresSource ? candidates.map(row => row.id).sort() : []);
        assert.equal(sourceRow.evidence[0].text, "two venue clues");
        assert.equal((await api(`/v0/memory/captures/${capture.body.id}`, undefined, multiOwner)).body.raw_text, "two venue clues");
        if (!settled && retiresSource) {
          const staleDecision = await api(`/v0/workflows/place-recovery/runs/${run.body.id}/decision`, { action: "source_only", candidate_id: clue.body.id }, multiOwner);
          assert.equal(staleDecision.status, 409, "stale source-only action cannot settle its successor venue");
          assert.equal((await pool.query("select credit_settlement from workflow_runs where id=$1", [run.body.id])).rows[0].credit_settlement, "pending");
        }
        const fresh = await api(`/v0/memory/captures/${capture.body.id}/search-recovery`, retryBody, multiOwner, { "x-save-analysis-id": await start(multiOwner) });
        assert.equal(fresh.status, 200, JSON.stringify(fresh.body));
        assert.deepEqual(fresh.body.created_candidates.map((row: any) => [row.id, row.workflow_run_id]).sort(), candidates.map(row => [row.id, row.workflow_run_id]).sort());
        const order = reversed ? [...candidates].reverse() : candidates;
        for (let index = 0; index < order.length; index++) {
          const candidate = order[index], place = randomUUID();
          await pool.query("insert into places(id,user_id,name,address,latitude,longitude) values($1,$2,$3,$4,$5,$6)", [place, multiOwner.guest_id, candidate.name, candidate.address, candidate.latitude, candidate.longitude]);
          const confirmed = await api(`/v0/workflows/place-recovery/runs/${candidate.workflow_run_id}/decision`, { action: "confirm", candidate_id: candidate.id, final_place_id: place }, multiOwner);
          assert.equal(confirmed.status, 201, JSON.stringify(confirmed.body));
          if (index === 0) assert.equal((await pool.query("select status from place_candidates where id=$1", [order[1].id])).rows[0].status, "review", "first venue confirmation does not complete the other venue");
        }
        assert.notEqual(candidates[0].workflow_run_id, candidates[1].workflow_run_id);
        assert.equal(recovered.body.workflow_run_id, null, "multi-venue response must not imply one confirmable run");
        for (const candidate of candidates) {
          const receipts = (await pool.query("select receipt_type from workflow_receipts where run_id=$1", [candidate.workflow_run_id])).rows;
          assert.deepEqual(receipts.map(row => row.receipt_type).sort(), candidate.workflow_run_id === run.body.id ? ["analysis", "analysis", "decision"] : ["analysis", "decision"]);
        }
        assert.equal((await pool.query("select count(*)::int as count from place_candidates where capture_id=$1", [capture.body.id])).rows[0].count, 3);
        if (!retiresSource) {
          assert.ok(candidates.every(candidate => candidate.workflow_run_id !== run.body.id), "visible named uncertainty keeps its own pending reservation");
          assert.equal((await pool.query("select credit_settlement from workflow_runs where id=$1", [run.body.id])).rows[0].credit_settlement, "pending");
        }
        const finalParentReceipts = (await pool.query("select * from workflow_receipts where run_id=$1 order by id", [run.body.id])).rows;
        if (settled || !retiresSource) assert.deepEqual(finalParentReceipts, originalReceipts);
        else {
          assert.ok(candidates.some(candidate => candidate.workflow_run_id === run.body.id), "one venue uses the original pending reservation");
          for (const receipt of originalReceipts) assert.deepEqual(finalParentReceipts.find(row => row.id === receipt.id), { ...receipt, is_current: false });
          const reserve = await pool.query("select count(*)::int as count from credit_ledger where run_id=$1 and reason='reserve'", [run.body.id]);
          assert.equal(reserve.rows[0].count, 1, "original pending credit is reused, never stranded or reserved again");
        }
      }
    });

    await t.test("source successor provenance grows from two to three venues and retains settled successors", async () => {
      for (const settleBeforeExtension of [false, true]) {
        const guest = await newGuest();
        const capture = await api("/v0/memory/captures", { source_type: "note", raw_text: "preserved expanding source" }, guest);
        const run = await api("/v0/workflows/place-recovery/runs", { source_type: "note" }, guest);
        const clue = await api("/v0/memory/candidates", { capture_id: capture.body.id, workflow_run_id: run.body.id, name: "Saved source", status: "source_only", evidence: [{ text: "original evidence" }] }, guest);
        await api(`/v0/workflows/place-recovery/runs/${run.body.id}/result`, { result_type: "source_only_clue", evidence_tier: "weak", candidate_refs: [clue.body.id], evidence_refs: [clue.body.id] }, guest);
        await api(`/v0/workflows/place-recovery/runs/${run.body.id}/decision`, { action: "source_only", candidate_id: clue.body.id }, guest);
        const retry = async (query: string) => api(`/v0/memory/captures/${capture.body.id}/search-recovery`, { workflow_run_id: run.body.id, explicit_retry: true, queries: [query], max_queries: 1, include_media_evidence: false }, guest, { "x-save-analysis-id": await start(guest) });
        const first = await retry("fixture-multi-venue");
        assert.equal(first.status, 200, JSON.stringify(first.body)); assert.equal(first.body.created_candidates.length, 2);
        const firstIDs = first.body.created_candidates.map((row: any) => row.id);
        const beforeEvidence = (await pool.query("select evidence from place_candidates where id=$1", [clue.body.id])).rows[0].evidence;
        const confirmFirst = async () => {
          for (const row of first.body.created_candidates) {
            const place = randomUUID();
            await pool.query("insert into places(id,user_id,name,address,latitude,longitude) values($1,$2,$3,$4,$5,$6)", [place, guest.guest_id, row.name, row.address, row.latitude, row.longitude]);
            const result = await api(`/v0/workflows/place-recovery/runs/${row.workflow_run_id}/decision`, { action: "confirm", candidate_id: row.id, final_place_id: place }, guest);
            assert.equal(result.status, 201, JSON.stringify(result.body));
          }
        };
        if (settleBeforeExtension) await confirmFirst();
        const expanded = await retry("fixture-multi-venue-third");
        assert.equal(expanded.status, 200, JSON.stringify(expanded.body));
        const third = expanded.body.created_candidates.find((row: any) => row.name === "Gamma Fixture Cafe");
        assert.ok(third, JSON.stringify(expanded.body));
        if (!settleBeforeExtension) await confirmFirst();
        const reload = await api(`/v0/memory/candidates?capture_id=${capture.body.id}`, undefined, guest);
        const source = (reload.body as any).find((row: any) => row.id === clue.body.id);
        assert.deepEqual(source.superseded_by_candidate_ids.sort(), [...firstIDs, third.id].sort(), "repeat source reaches C even after A and B have settled");
        assert.deepEqual(source.evidence.slice(0, beforeEvidence.length), beforeEvidence, "original evidence and first successor event remain unchanged");
        assert.equal(source.status, "source_only");
        const repeated = await retry("fixture-multi-venue-third");
        assert.equal(repeated.status, 200, JSON.stringify(repeated.body));
        assert.deepEqual(repeated.body.created_candidates.map((row: any) => [row.id, row.workflow_run_id]), [[third.id, third.workflow_run_id]]);
        const finalRows = (await pool.query("select * from place_candidates where capture_id=$1", [capture.body.id])).rows;
        assert.equal(finalRows.length, 4);
        assert.deepEqual(finalRows.find(row => row.id === clue.body.id)!.evidence, source.evidence, "repeat complete batch does not append duplicate provenance");
        assert.equal(finalRows.find(row => row.id === third.id)!.status, "review");
        const sourceURL = `https://fixture.invalid/successor-dates/${capture.body.id}`;
        await pool.query("update captures set source_url=$2 where id=$1", [capture.body.id, sourceURL]);
        const runIDs = [...new Set(finalRows.map(row => row.workflow_run_id))];
        const history = async () => ({
          runs: (await pool.query("select * from workflow_runs where id=any($1::uuid[]) order by id", [runIDs])).rows,
          receipts: (await pool.query("select * from workflow_receipts where run_id=any($1::uuid[]) order by id", [runIDs])).rows,
          ledger: (await pool.query("select * from credit_ledger where run_id=any($1::uuid[]) order by id", [runIDs])).rows,
        });
        const beforeHistory = await history();
        const earlier = await api("/v0/memory/captures", { source_url: sourceURL, created_at: "2020-01-01T00:00:00Z" }, guest);
        assert.equal(earlier.body.id, capture.body.id);
        const backdated = (await pool.query("select * from place_candidates where capture_id=$1", [capture.body.id])).rows;
        for (const row of backdated) {
          assert.equal(row.created_at.toISOString(), "2020-01-01T00:00:00.000Z", "a capture-only repeat backdates every persisted successor and source row");
          const previous = finalRows.find(previous => previous.id === row.id)!;
          assert.deepEqual({ ...row, created_at: previous.created_at, updated_at: previous.updated_at }, previous, "capture date propagation changes no candidate state, evidence or ownership");
        }
        const stampReload = await api("/v0/places", undefined, guest);
        for (const saved of backdated.filter(row => row.status === "saved")) {
          assert.equal((stampReload.body as any).find((row: any) => row.id === saved.place_id).created_at, "2020-01-01T00:00:00Z");
        }
        assert.deepEqual(await history(), beforeHistory, "source chronology cannot rewrite lifecycle or billing history");
        const candidateReload = await api(`/v0/memory/candidates?capture_id=${capture.body.id}`, undefined, guest);
        assert.ok((candidateReload.body as any).every((row: any) => row.created_at === "2020-01-01T00:00:00Z"));
      }
    });

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
      for (let n = 2; n < fixtureRequestLimit; n++) assert.equal((await api(`/v0/analysis/${id}/places`, { query: "fixture" }, owner)).status, 200);
      const before = (await calls()).length;
      const denied = await api(`/v0/analysis/${id}/places`, { query: "fixture" }, owner);
      assert.equal(denied.status, 429); assert.equal(denied.body.code, "analysis_limit_exceeded");
      const deniedGemini = await api("/v0/llm/gemini-generate-content", geminiBody(), owner, { "x-save-analysis-id": id });
      assert.equal(deniedGemini.status, 429); assert.equal(deniedGemini.body.code, "analysis_limit_exceeded");
      assert.equal((await calls()).length, before, "quota denial must happen before provider fetch");
      assert.equal((await pool.query("select * from analysis_usage_events where analysis_id=$1", [id])).rowCount, fixtureRequestLimit);
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
      for(let n=0;n<fixtureRequestLimit;n++) assert.equal((await api(`/v0/analysis/${id}/places`,{query:"fixture"},owner)).status,200);
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
