import assert from "node:assert/strict";
import test from "node:test";
import type { PoolClient } from "pg";
import { analysisReceiptForResult, type PlaceRecoveryWorkerResult } from "./workflowContracts.js";
import { planResultTransition, planDecisionTransition } from "./workflowLifecycle.js";
import { recoverMissingAnalysisReceipt } from "./workflowReceiptRecovery.js";

const runId = "10000000-0000-4000-8000-000000000001";
const candidateId = "20000000-0000-4000-8000-000000000001";
const userId = "guest:fixture";
const initialRun = () => ({ id: runId, user_id: userId, current_attempt_no: 1,
  credit_settlement: "pending", status: "queued", result_type: null });
const candidate = () => ({ id: candidateId, workflow_run_id: runId, user_id: userId,
  name: "Charlie's Tea", address: "Test branch address", status: "review", confidence: 0.72,
  evidence: [{ text: "Venue named in source caption" }], missing_info: ["branch"] });

function fixture(options: { run?: Record<string, unknown>; candidates?: Record<string, unknown>[]; history?: boolean } = {}) {
  const run = options.run ?? initialRun();
  const candidates = options.candidates ?? [candidate()];
  const results: PlaceRecoveryWorkerResult[] = [];
  const queries: { sql: string; values: unknown[] }[] = [];
  let history = options.history ?? false;
  const db = { query: async (sql: string, values: unknown[]) => {
    queries.push({ sql, values });
    if (sql.includes("workflow_receipts")) return { rows: history ? [{ id: "receipt-existing" }] : [] };
    if (sql.includes("place_candidates")) return { rows: candidates.filter((row) =>
      row.workflow_run_id === values[0] && row.user_id === values[1]
      && (values[2] === null || String(row.id).toLowerCase() === String(values[2]).toLowerCase())) };
    throw new Error(`Unexpected query: ${sql}`);
  } } as unknown as Pick<PoolClient, "query">;
  const recordResult = async (result: PlaceRecoveryWorkerResult) => {
    assert.equal(history, false, "must not overwrite any receipt history");
    const plan = planResultTransition({ currentAttemptNo: Number(run.current_attempt_no),
      currentCreditSettlement: "pending", requestedAttemptNo: result.attemptNo,
      resultRevision: result.resultRevision, idempotencyKey: result.idempotencyKey!,
      outputHash: "fixture-hash", explicitRetry: result.explicitRetry });
    assert.equal(plan.kind, "create");
    results.push(result);
    history = true;
    return analysisReceiptForResult(result);
  };
  return { run, candidates, results, queries, db, recordResult };
}

test("interrupted candidate import repairs a missing receipt from persisted evidence before decision", async () => {
  const f = fixture();
  const receipt = await recoverMissingAnalysisReceipt(f.db, f.run, userId, candidateId, f.recordResult);
  assert.ok(receipt, "A current analysis receipt is required before a decision");
  assert.equal(f.results[0].resultType, "review_candidate");
  assert.equal(f.results[0].evidenceTier, "weak");
  assert.deepEqual(f.results[0].candidateRefs, [candidateId]);
  assert.deepEqual(f.results[0].evidenceRefs, [candidateId]);
  assert.equal(f.candidates[0].status, "review", "analysis cannot confirm a candidate");
  assert.equal(f.run.credit_settlement, "pending");
  assert.equal(f.run.current_attempt_no, 1);
  assert.ok(f.queries.some((query) => query.sql.includes("for share")), "persisted candidates remain locked through decision");
});

test("source-only persisted clue stays source-only with no confirmation receipt", async () => {
  const f = fixture({ candidates: [{ ...candidate(), status: "source_only" }] });
  const receipt = await recoverMissingAnalysisReceipt(f.db, f.run, userId, candidateId, f.recordResult);
  assert.ok(receipt);
  assert.equal(f.results[0].resultType, "source_only_clue");
  assert.equal(f.candidates[0].status, "source_only");
});

test("legacy iOS source-only draft persisted as review never becomes a review candidate", async () => {
  const f = fixture({ candidates: [{ ...candidate(), name: "instagram.com", address: "",
    latitude: null, longitude: null, confidence: 0, status: "review",
    evidence: [{ text: "Read source URL; place name and location still missing" }],
    missing_info: ["place name", "address", "coordinates"] }] });
  const receipt = await recoverMissingAnalysisReceipt(f.db, f.run, userId, candidateId, f.recordResult);
  assert.ok(receipt);
  assert.equal(f.results[0].resultType, "source_only_clue");
  assert.equal(receipt.receiptType, "analysis");
  assert.equal(receipt.settlement, "manual_review");
});

test("Swift uppercase UUID selection matches the persisted candidate identity", async () => {
  const id = "abcde000-0000-4000-8000-000000000001";
  const f = fixture({ candidates: [{ ...candidate(), id }] });
  assert.ok(await recoverMissingAnalysisReceipt(f.db, f.run, userId, id.toUpperCase(), f.recordResult));
  assert.deepEqual(f.results[0].candidateRefs, [id]);
});

test("repeated recovery and valid existing result preserve receipt and settlement", async () => {
  const f = fixture();
  await recoverMissingAnalysisReceipt(f.db, f.run, userId, candidateId, f.recordResult);
  assert.equal(await recoverMissingAnalysisReceipt(f.db, f.run, userId, candidateId, f.recordResult), undefined);
  assert.equal(f.results.length, 1);
  const existing = fixture({ history: true });
  assert.equal(await recoverMissingAnalysisReceipt(existing.db, existing.run, userId, candidateId, existing.recordResult), undefined);
  assert.equal(existing.results.length, 0);
  const first = planDecisionTransition({ currentAttemptNo: 1, currentCreditSettlement: "pending", action: "confirm",
    creditReserved: 1, idempotencyKey: "decision:fixture", fingerprint: "fixture" });
  assert.equal(first.kind, "create");
  if (first.kind === "create") assert.equal(first.refundDelta, 0);
  assert.equal(planDecisionTransition({ currentAttemptNo: 1, currentCreditSettlement: "consumed", action: "confirm",
    creditReserved: 1, idempotencyKey: "decision:fixture", fingerprint: "fixture",
    existingDecision: { id: "decision", receiptId: "receipt", idempotencyKey: "decision:fixture", fingerprint: "fixture" },
  }).kind, "idempotent");
});

const negativeCases: [string, Parameters<typeof fixture>[0], string, string | undefined][] = [
  ["another user", {}, "guest:other", candidateId],
  ["another run", { candidates: [{ ...candidate(), workflow_run_id: "other-run" }] }, userId, candidateId],
  ["another candidate", {}, userId, "20000000-0000-4000-8000-000000000002"],
  ["empty result", { candidates: [] }, userId, candidateId],
  ["missing evidence", { candidates: [{ ...candidate(), evidence: [] }] }, userId, candidateId],
  ["already saved", { candidates: [{ ...candidate(), status: "saved" }] }, userId, candidateId],
  ["technical failure", { run: { ...initialRun(), result_type: "technical_failure" } }, userId, candidateId],
  ["refunded", { run: { ...initialRun(), credit_settlement: "refunded" } }, userId, candidateId],
  ["consumed", { run: { ...initialRun(), credit_settlement: "consumed" } }, userId, candidateId],
  ["failed", { run: { ...initialRun(), status: "failed" } }, userId, candidateId],
  ["retry pending", { run: { ...initialRun(), current_attempt_no: 2 } }, userId, candidateId],
  ["superseded history", { history: true }, userId, candidateId],
  ["ambiguous inference", { candidates: [candidate(), { ...candidate(), id: "20000000-0000-4000-8000-000000000002" }] }, userId, undefined],
];
for (const [label, options, requestedUser, requestedCandidate] of negativeCases) {
  test(`missing receipt guard remains for ${label}`, async () => {
    const f = fixture(options);
    assert.equal(await recoverMissingAnalysisReceipt(f.db, f.run, requestedUser, requestedCandidate, f.recordResult), undefined);
    assert.equal(f.results.length, 0);
  });
}
