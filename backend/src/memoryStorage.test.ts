import assert from "node:assert/strict";
import test from "node:test";
import { capturedSourceTexts, capturedSourceResolution, completeEmptySourceAnalysis, duplicateCandidateGroups, earliestKnownDate, mergedCaptureText, mergedEvidence, normalizedCaptureURL, sameCandidateIdentity, externalCandidateEvidence, supersededCandidateIDs } from "./memoryStorage.js";

const cafe = { id: "one", name: "Fixture Cafe", address: "1 Fixture Road", latitude: 25, longitude: 121, status: "review" };
test("capture identity drops tracking while preserving meaningful URLs and malformed inputs", () => {
  assert.equal(normalizedCaptureURL(" https://example.invalid/post?utm_source=share&id=42&fbclid=track "), "https://example.invalid/post?id=42");
  assert.equal(normalizedCaptureURL("https://example.invalid/post?b=2&a=1&igsh=track"), "https://example.invalid/post?a=1&b=2");
  for (const input of ["broken", "javascript:alert(1)", "https://name:secret@example.invalid", undefined]) assert.equal(normalizedCaptureURL(input), undefined);
  for (const suffix of ["/", "?id=2", "#another-venue"]) assert.notEqual(normalizedCaptureURL(`https://example.invalid/post${suffix}`), normalizedCaptureURL("https://example.invalid/post"));
});
test("chronology picks the earliest valid known date without inventing missing history", () => {
  assert.equal(earliestKnownDate([undefined, null, "invalid", new Date(NaN)]), undefined);
  const oldCapture = new Date("2025-01-01T00:00:00Z");
  assert.equal(earliestKnownDate(["2026-01-01T00:00:00Z", oldCapture]), oldCapture);
  assert.equal(earliestKnownDate([oldCapture, "2024-01-01T00:00:00Z"]), "2024-01-01T00:00:00Z");
});
test("candidate identity preserves different venues branches and weak evidence", () => {
  assert.equal(sameCandidateIdentity(cafe, { ...cafe, name: "  Ｆｉｘｔｕｒｅ   Cafe " }), true);
  for (const change of [{ address: "2 Fixture Road" }, { name: "Different Cafe" }, { address: "" }, { longitude: 121.1 }, { latitude: 25.1 }]) assert.equal(sameCandidateIdentity(cafe, { ...cafe, ...change }), false);
  assert.equal(sameCandidateIdentity({ ...cafe, place_id: "one" }, { ...cafe, place_id: "two" }), false);
  assert.equal(sameCandidateIdentity({ ...cafe, place_id: "one" }, { ...cafe, place_id: "one", name: "Alias" }), true);
});
test("provider alternatives at one address cannot collapse into one candidate", () => {
  const first = { ...cafe, evidence: [{ google_place_id: "first" }] };
  assert.equal(sameCandidateIdentity(first, { ...cafe, evidence: [{ google_place_id: "second" }] }), false);
  assert.equal(sameCandidateIdentity(first, { ...cafe, evidence: [{ google_place_id: "first" }] }), true);
  assert.equal(sameCandidateIdentity(first, { ...cafe, evidence: [{ text: "Google Place ID: second" }] }), true);
  assert.equal(sameCandidateIdentity({ ...first, place_id: "user-confirmed" }, { ...cafe, place_id: "user-confirmed", evidence: [{ google_place_id: "second" }] }), true, "confirmed user identity outranks old provider evidence");
});
test("source-only reuse stays inside one capture and preserves rejected clue identity", () => {
  const clue = { capture_id: "capture", name: "Saved link", status: "source_only" };
  assert.equal(sameCandidateIdentity(clue, { ...clue }), true);
  assert.equal(sameCandidateIdentity(clue, { ...clue, status: "rejected" }), true);
  assert.equal(sameCandidateIdentity(clue, { ...clue, capture_id: "other" }), false);
  assert.equal(sameCandidateIdentity(clue, { ...clue, status: "review", name: "Partial venue" }), false);
  assert.equal(sameCandidateIdentity(clue, { ...clue, latitude: 25 }), false);
});
test("additional evidence and capture text are retained without resetting prior data", () => {
  assert.deepEqual(mergedEvidence([{ text: "old" }], [{ text: "old" }, { text: "new" }]), [{ text: "old" }, { text: "new" }]);
  assert.equal(mergedCaptureText({ raw_text: "old caption", title: "old" }, { raw_text: "new caption", title: "new title" }), "old caption\n\nnew caption");
});
test("plural successor provenance validates UUID arrays and cannot be imported", () => {
  const first = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", second = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  assert.deepEqual(supersededCandidateIDs({ evidence: [{ superseded_by_candidate_id: first, superseded_by_candidate_ids: [first, second] }] }), [first, second]);
  assert.deepEqual(supersededCandidateIDs({ evidence: [{ superseded_by_candidate_ids: [first, "invalid"] }] }), []);
  assert.deepEqual(supersededCandidateIDs({ evidence: [{ superseded_by_candidate_id: first }] }), [first]);
  const third = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  assert.deepEqual(supersededCandidateIDs({ evidence: [{ superseded_by_candidate_ids: [first, second] }, { superseded_by_candidate_ids: [first, second, third] }] }), [first, second, third], "later complete batches extend earlier provenance");
  assert.deepEqual(externalCandidateEvidence([{ text: "source evidence", superseded_by_candidate_id: first, superseded_by_candidate_ids: [first, second] }]), [{ text: "source evidence" }]);
});
test("read-only audit reports exact old duplicates and existing stamps without grouping multi-place branches", () => {
  const rows = [cafe, { ...cafe, id: "two" }, { ...cafe, id: "branch", address: "2 Fixture Road" }];
  const before = JSON.stringify(rows);
  assert.deepEqual(duplicateCandidateGroups(rows), [{ candidate_ids: ["one", "two"], pending_candidate_ids: ["one", "two"], saved_place_ids: [], reason: "same_place_identity" }]);
  assert.equal(JSON.stringify(rows), before);
  assert.deepEqual(duplicateCandidateGroups([cafe], [{ ...cafe, id: "stamp" }])[0].saved_place_ids, ["stamp"]);
  assert.equal(duplicateCandidateGroups([{ ...cafe, status: "rejected" }, { ...cafe, status: "saved" }]).length, 0);
});

import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { prepareCandidate, reconcileSavedCandidates, reuseCapture, supersedeSourceOnlyCandidates } from "./memoryStorage.js";

const databaseURL = process.env.SAVE_ANALYSIS_TEST_DATABASE_URL;
test("real database preserves workflow ownership chronology and ambiguous source predecessors", { skip: !databaseURL }, async () => {
  const url = new URL(databaseURL!);
  assert.equal(url.pathname, "/save_analysis_fixture"); assert.equal(url.port, "55437");
  assert.equal(url.searchParams.get("host"), "/tmp/save-analysis-completion/pg-socket");
  const pool = new Pool({ connectionString: databaseURL }); const client = await pool.connect();
  try {
    await client.query("begin");
    const owner = `memory-fixture-${randomUUID()}`, foreign = `memory-fixture-${randomUUID()}`;
    await client.query("insert into profiles(id) values($1),($2)", [owner, foreign]);
    const capture = randomUUID(), run = randomUUID(), otherRun = randomUUID(), candidate = randomUUID();
    await client.query("insert into captures(id,user_id,source_url,created_at) values($1,$2,'https://fixture.invalid/one','2025-01-01T00:00:00Z')", [capture, owner]);
    await client.query("insert into workflow_runs(id,workflow_id,listing_id,user_id) values($1,'fixture','fixture',$3),($2,'fixture','fixture',$3)", [run, otherRun, owner]);
    await client.query("insert into place_candidates(id,capture_id,workflow_run_id,name,address,status,evidence,created_at) values($1,$2,$3,'Fixture Cafe','1 Fixture Road','rejected','[{\"text\":\"old\"}]','2025-01-01T00:00:00Z')", [candidate, capture, run]);
    const body = { capture_id: capture, workflow_run_id: run, name: "Fixture Cafe", address: "1 Fixture Road", evidence: [{ text: "new" }], status: "review" };
    const same = await prepareCandidate(client, body);
    assert.equal(same.existing?.id, candidate); assert.equal(same.existing?.status, "rejected"); assert.equal(same.existing?.evidence.length, 2);
    assert.equal(new Date(same.existing!.created_at).getUTCFullYear(), 2025);
    const separate = await prepareCandidate(client, { ...body, workflow_run_id: otherRun });
    assert.equal(separate.existing, undefined); assert.equal(separate.body.workflow_run_id, otherRun); assert.equal(separate.body.status, "review", "a separate pending reservation remains actionable without changing the original rejected row");
    assert.equal((await client.query("select workflow_run_id from place_candidates where id=$1", [candidate])).rows[0].workflow_run_id, run);
    assert.equal(await reuseCapture(client, foreign, { source_url: "https://fixture.invalid/one" }), undefined);
    const alternativesCapture = randomUUID(), firstAlternative = randomUUID();
    await client.query("insert into captures(id,user_id) values($1,$2)", [alternativesCapture, owner]);
    await client.query("insert into place_candidates(id,capture_id,name,address,latitude,longitude,status,evidence) values($1,$2,'Shared Building','1 Road',25,121,'review',$3::jsonb)", [firstAlternative, alternativesCapture, JSON.stringify([{ google_place_id: "first-provider" }])]);
    const alternativeBody = { capture_id: alternativesCapture, name: "Shared Building", address: "1 Road", latitude: 25, longitude: 121, status: "review", evidence: [{ google_place_id: "second-provider" }] };
    assert.equal((await prepareCandidate(client, alternativeBody)).existing, undefined, "distinct provider alternative remains a separate candidate");
    assert.equal((await prepareCandidate(client, { ...alternativeBody, evidence: [{ google_place_id: "first-provider" }] })).existing?.id, firstAlternative, "same provider repeat still reuses its candidate");
    const upgradeCapture = randomUUID(), weak = randomUUID(), rejected = randomUUID();
    await client.query("insert into captures(id,user_id) values($1,$2)", [upgradeCapture, owner]);
    await client.query("insert into place_candidates(id,capture_id,workflow_run_id,name,address,status,missing_info) values($1,$3,$4,'Verified Later','2 Road','needs_more_evidence',array['Verified coordinates']),($2,$3,$5,'Verified Later','2 Road','rejected',array['Verified coordinates'])", [weak, rejected, upgradeCapture, run, otherRun]);
    const verified = { capture_id: upgradeCapture, workflow_run_id: run, name: "Verified Later", address: "2 Road", status: "review", latitude: 25, longitude: 121, confidence: 0.85, missing_info: ["User confirmation before saving as Map Stamp"], evidence: [{ google_place_id: "verified-later", google_types: ["lodging"] }] };
    const promoted = (await prepareCandidate(client, verified)).existing!;
    assert.equal(promoted.id, weak); assert.equal(promoted.workflow_run_id, run);
    assert.equal(promoted.latitude, 25); assert.equal(promoted.longitude, 121); assert.equal(promoted.status, "review");
    assert.deepEqual(promoted.missing_info, verified.missing_info); assert.deepEqual(promoted.evidence, verified.evidence);
    const terminal = (await prepareCandidate(client, { ...verified, workflow_run_id: otherRun })).existing!;
    assert.equal(terminal.id, rejected); assert.equal(terminal.status, "rejected"); assert.equal(terminal.latitude, null);
    const emptyCapture = randomUUID(), emptyCandidate = randomUUID(), independent = randomUUID();
    await client.query("insert into captures(id,user_id,source_url,raw_text) values($1,$2,'https://instagram.com/p/provenance/','Original text')", [emptyCapture, owner]);
    const reusedSource = await reuseCapture(client, owner, { source_url: "https://instagram.com/p/provenance/", raw_text: "Fresh source", title: "Generated label" });
    assert.deepEqual(capturedSourceTexts(reusedSource!), ["Fresh source"]);
    assert.equal(reusedSource!.raw_text, "Original text\n\nFresh source");
    await client.query("insert into place_candidates(id,capture_id,workflow_run_id,name,status,missing_info) values($1,$3,$4,'Saved link','source_only',array['Analysis pending','Exact place needed']),($2,$3,$5,'Other run','source_only',array['Analysis pending'])", [emptyCandidate, independent, emptyCapture, run, otherRun]);
    const emptyRetry = { capture_id: emptyCapture, workflow_run_id: run, name: "Saved link", status: "source_only", missing_info: ["No place evidence in source", "Exact place", "User confirmation"] };
    await prepareCandidate(client, { ...emptyRetry, missing_info: ["Analysis pending"] });
    assert.ok((await client.query("select missing_info from place_candidates where id=$1", [emptyCandidate])).rows[0].missing_info.includes("Analysis pending"));
    const completedRetry = (await prepareCandidate(client, emptyRetry)).existing!;
    assert.equal(completedRetry.id, emptyCandidate); assert.deepEqual(completedRetry.missing_info, ["Exact place needed"]);
    await completeEmptySourceAnalysis(client, emptyCapture, run);
    const completedSource = (await client.query("select * from place_candidates where id=$1", [emptyCandidate])).rows[0];
    assert.deepEqual(completedSource.missing_info, ["Exact place needed"]); assert.equal(completedSource.status, "source_only");
    assert.equal(completedSource.workflow_run_id, run);
    assert.deepEqual((await client.query("select missing_info from place_candidates where id=$1", [independent])).rows[0].missing_info, ["Analysis pending"]);
    const clueCapture = randomUUID(), clue = randomUUID(), named = randomUUID();
    await client.query("insert into captures(id,user_id) values($1,$2)", [clueCapture, owner]);
    await client.query("insert into place_candidates(id,capture_id,name,status) values($1,$2,'Source clue','source_only')", [clue, clueCapture]);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture), []);
    await client.query("insert into place_candidates(id,capture_id,name,address,status) values($1,$2,'Fixture Cafe','1 Fixture Road','review')", [named, clueCapture]);
    const branch = randomUUID();
    await client.query("insert into place_candidates(id,capture_id,name,address,status) values($1,$2,'Fixture Cafe','2 Fixture Road','review')", [branch, clueCapture]);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture), []);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture, []), [], "empty successor batch cannot retire its source");
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture, [named, randomUUID()]), [], "partially persisted batch cannot retire its source");
    const uncertain = randomUUID();
    await client.query("insert into place_candidates(id,capture_id,name,status) values($1,$2,'Named uncertain venue','source_only')", [uncertain, clueCapture]);
    await client.query("update place_candidates set status='rejected' where id=$1", [branch]);
    await client.query("update place_candidates set workflow_run_id=$2 where id=$1", [clue, run]);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture), [], "a visible pending source cannot lose its reservation when successors use another run");
    await client.query("update place_candidates set workflow_run_id=$2 where id=$1", [named, run]);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture), [clue]);
    assert.deepEqual((await client.query("select evidence from place_candidates where id=$1", [uncertain])).rows[0].evidence, [], "named uncertain predecessor is never retired as a generic source");
    const superseded = (await client.query("select * from place_candidates where id=$1", [clue])).rows[0];
    assert.equal(superseded.status, "source_only"); assert.equal(superseded.evidence[0].superseded_by_candidate_id, named);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture), []);
    const originalMarker = (await client.query("select evidence from place_candidates where id=$1", [clue])).rows[0].evidence;
    await client.query("update place_candidates set status='review' where id=$1", [branch]);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture, [named, randomUUID()]), [], "partial extension cannot alter an existing successor set");
    assert.deepEqual((await client.query("select evidence from place_candidates where id=$1", [clue])).rows[0].evidence, originalMarker);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture, [named, branch]), [clue]);
    await client.query("update place_candidates set status='saved' where id=$1", [named]);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, clueCapture, [named, branch]), []);
    const extended = (await client.query("select evidence from place_candidates where id=$1", [clue])).rows[0];
    assert.deepEqual(supersededCandidateIDs(extended), [named, branch]);
    assert.deepEqual(extended.evidence.slice(0, originalMarker.length), originalMarker);
    const newBody = await prepareCandidate(client, { capture_id: capture, name: "Other Venue", address: "3 Fixture Road", created_at: "2026-09-16T00:00:00Z" });
    assert.equal(new Date(newBody.body.created_at).getUTCFullYear(), 2025, "recovered candidates retain the original clue chronology");
    await client.query("update place_candidates set status='confirmed' where id=$1", [named]);
    assert.deepEqual(await reconcileSavedCandidates(client, foreign, named), []);
  } finally { await client.query("rollback"); client.release(); await pool.end(); }
});


test("capture provenance excludes legacy merged titles and survives safe repeated imports", () => {
  const old = { source_url: "https://instagram.com/p/source/", raw_text: "caption\n\nGenerated guess", title: "Generated guess" };
  assert.deepEqual(capturedSourceTexts(old), []);
  const current = { ...old, raw_text: mergedCaptureText(old, { raw_text: "Actual complete caption\naddress", title: "Another guess" }) };
  const recorded = { ...current, source_resolution: capturedSourceResolution(current, "Actual complete caption\naddress") };
  assert.deepEqual(capturedSourceTexts(recorded), ["Actual complete caption\naddress"]);
  assert.equal(recorded.raw_text, "caption\n\nGenerated guess\n\nActual complete caption\naddress", "legacy history is retained, not reclassified as source evidence");
  assert.deepEqual(capturedSourceTexts({ ...recorded, source_url: "https://instagram.com/p/another/" }), []);
  assert.deepEqual(capturedSourceTexts({ ...recorded, raw_text: "edited" }), []);
  const repeat = { ...recorded, raw_text: mergedCaptureText(recorded, { raw_text: "More original context", title: "New guess" }) };
  const updated = { ...repeat, source_resolution: capturedSourceResolution(repeat, "More original context", capturedSourceTexts(recorded)) };
  assert.deepEqual(capturedSourceTexts(updated), ["Actual complete caption\naddress", "More original context"]);
});

test("real database promotes grounded semantic identities and safely links retry successors", { skip: !databaseURL }, async () => {
  const url = new URL(databaseURL!);
  assert.equal(url.pathname, "/save_analysis_fixture"); assert.equal(url.port, "55437");
  assert.equal(url.searchParams.get("host"), "/tmp/save-analysis-completion/pg-socket");
  const pool = new Pool({ connectionString: databaseURL }); const client = await pool.connect();
  try {
    await client.query("begin");
    const owner = `semantic-memory-${randomUUID()}`, run = randomUUID(), retry = randomUUID();
    await client.query("insert into profiles(id) values($1)", [owner]);
    await client.query("insert into workflow_runs(id,workflow_id,listing_id,user_id) values($1,'fixture','fixture',$3),($2,'fixture','fixture',$3)", [run, retry, owner]);
    const evidence = [{ semantic_source: { name: "初泰Pikul", branch: "信義象山門市", address: "臺北市信義區信義路五段122號" } }];
    const original = { name: "初泰Pikul 信義象山門市", address: "臺北市信義區信義路五段122號", status: "review", evidence };
    const canonical = { ...original, name: "初泰 信義店", address: "110台灣台北市信義區信義路五段122號", latitude: 25, longitude: 121, evidence: [...evidence, { google_place_id: "pikul" }] };
    async function capture() {
      const id = randomUUID(); await client.query("insert into captures(id,user_id) values($1,$2)", [id, owner]); return id;
    }
    async function insert(captureId: string, workflow: string | null, row: Record<string, any>) {
      const id = randomUUID();
      await client.query("insert into place_candidates(id,capture_id,workflow_run_id,name,address,status,evidence,latitude,longitude) values($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9)",
        [id, captureId, workflow, row.name, row.address, row.status, JSON.stringify(row.evidence), row.latitude ?? null, row.longitude ?? null]);
      return id;
    }
    const sameCapture = await capture(), originalID = await insert(sameCapture, run, original);
    const promoted = (await prepareCandidate(client, { ...canonical, capture_id: sameCapture, workflow_run_id: run })).existing!;
    assert.equal(promoted.id, originalID); assert.equal(promoted.name, canonical.name); assert.equal(promoted.address, canonical.address);
    assert.equal(promoted.latitude, 25); assert.equal(promoted.workflow_run_id, run);
    const rejectedCapture = await capture(), rejected = await insert(rejectedCapture, run, { ...original, status: "rejected" });
    await prepareCandidate(client, { ...canonical, capture_id: rejectedCapture, workflow_run_id: run });
    const terminal = (await client.query("select * from place_candidates where id=$1", [rejected])).rows[0];
    assert.equal(terminal.status, "rejected"); assert.equal(terminal.name, original.name); assert.equal(terminal.latitude, null);
    const retryCapture = await capture(), predecessor = await insert(retryCapture, run, original);
    const successor = await insert(retryCapture, retry, canonical);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, retryCapture, [successor]), [], "independent pending reservation stays visible");
    await client.query("update workflow_runs set credit_settlement='refunded' where id=$1", [run]);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, retryCapture, [successor]), [predecessor]);
    const old = (await client.query("select * from place_candidates where id=$1", [predecessor])).rows[0];
    assert.equal(old.name, original.name); assert.equal(old.workflow_run_id, run); assert.equal(old.status, "review");
    assert.deepEqual(supersededCandidateIDs(old), [successor]);
    const multiCapture = await capture();
    const secondEvidence = [{ semantic_source: { name: "Second Cafe", address: "20 Main Street" } }];
    const secondOriginal = { ...original, name: "Second Cafe", address: "20 Main Street", evidence: secondEvidence };
    const secondCanonical = { ...secondOriginal, name: "Second Cafe Official", address: "20 Main St, Taipei", latitude: 25.1, longitude: 121.1,
      evidence: [...secondEvidence, { google_place_id: "second-cafe" }] };
    const oldA = await insert(multiCapture, run, original), oldB = await insert(multiCapture, run, secondOriginal);
    const reserved = await insert(multiCapture, retry, original);
    const newA = await insert(multiCapture, null, canonical), newB = await insert(multiCapture, null, secondCanonical);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, multiCapture, [newA, randomUUID()]), [], "incomplete batch leaves both predecessors intact");
    assert.deepEqual(new Set(await supersedeSourceOnlyCandidates(client, multiCapture, [newA, newB])), new Set([oldA, oldB]));
    for (const [oldID, expected] of [[oldA, [newA]], [oldB, [newB]], [reserved, []]] as const) {
      const row = (await client.query("select * from place_candidates where id=$1", [oldID])).rows[0];
      assert.deepEqual(supersededCandidateIDs(row), expected, "each venue links only its own successor and preserves an independent pending reservation");
    }
    const defaultCapture = await capture(), defaultOld = await insert(defaultCapture, null, original);
    const defaultNew = await insert(defaultCapture, null, canonical);
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, defaultCapture), [defaultOld]);
    assert.deepEqual(supersededCandidateIDs((await client.query("select * from place_candidates where id=$1", [defaultOld])).rows[0]), [defaultNew]);
    const ambiguousCapture = await capture(), ambiguousOld = await insert(ambiguousCapture, null, original);
    await insert(ambiguousCapture, null, canonical);
    await insert(ambiguousCapture, null, { ...canonical, evidence: [...evidence, { google_place_id: "different-provider" }] });
    assert.deepEqual(await supersedeSourceOnlyCandidates(client, ambiguousCapture), [], "default selection cannot choose one provider alternative");
    assert.deepEqual(supersededCandidateIDs((await client.query("select * from place_candidates where id=$1", [ambiguousOld])).rows[0]), []);
    for (const changed of [
      { ...canonical, evidence: [{ semantic_source: { ...evidence[0].semantic_source, branch: "Other branch" } }] },
      { ...canonical, evidence: [{ semantic_source: { ...evidence[0].semantic_source, address: "Other road" } }] },
    ]) {
      const unrelatedCapture = await capture(); await insert(unrelatedCapture, null, original);
      assert.equal((await prepareCandidate(client, { ...changed, capture_id: unrelatedCapture })).existing, undefined);
      const unrelated = await insert(unrelatedCapture, null, changed);
      assert.deepEqual(await supersedeSourceOnlyCandidates(client, unrelatedCapture, [unrelated]), []);
    }
    assert.equal(sameCandidateIdentity({ ...original, capture_id: "one" }, { ...canonical, capture_id: "two" }), false);
  } finally { await client.query("rollback"); client.release(); await pool.end(); }
});
