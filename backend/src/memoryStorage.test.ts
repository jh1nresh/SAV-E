import assert from "node:assert/strict";
import test from "node:test";
import { duplicateCandidateGroups, earliestKnownDate, mergedCaptureText, mergedEvidence, normalizedCaptureURL, sameCandidateIdentity, externalCandidateEvidence, supersededCandidateIDs } from "./memoryStorage.js";

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
  assert.equal(mergedCaptureText({ raw_text: "old caption", title: "old" }, { raw_text: "new caption", title: "new title" }), "old caption\n\nnew caption\n\nnew title");
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
    assert.equal(separate.existing, undefined); assert.equal(separate.body.workflow_run_id, otherRun); assert.equal(separate.body.status, "rejected");
    assert.equal((await client.query("select workflow_run_id from place_candidates where id=$1", [candidate])).rows[0].workflow_run_id, run);
    assert.equal(await reuseCapture(client, foreign, { source_url: "https://fixture.invalid/one" }), undefined);
    const clueCapture = randomUUID(), clue = randomUUID(), named = randomUUID();
    await client.query("insert into captures(id,user_id) values($1,$2)", [clueCapture, owner]);
    await client.query("insert into place_candidates(id,capture_id,name,status) values($1,$2,'Saved link','source_only')", [clue, clueCapture]);
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
