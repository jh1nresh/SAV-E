import assert from "node:assert/strict";
import test from "node:test";
import {
  normalizePlaceRecoveryWorkOrderCreate,
  normalizePlaceRecoveryRunCreate,
  normalizePlaceRecoveryWorkerResult,
  normalizeUserDecision,
  receiptForResult,
} from "./workflowContracts.js";

test("place recovery work order create canonicalizes agent clearing fields", () => {
  const workOrder = normalizePlaceRecoveryWorkOrderCreate({
    source_url: "https://www.instagram.com/reel/example/?igsh=abc#frag",
    credit_reserved: 2,
  });

  assert.equal(workOrder.workflowId, "save_place_recovery_v0");
  assert.equal(workOrder.listingId, "save-place-recovery-agent");
  assert.equal(workOrder.intent, "recover_place_from_source");
  assert.equal(workOrder.inputType, "url");
  assert.equal(workOrder.inputRef, "https://www.instagram.com/reel/example/?igsh=abc");
  assert.equal(workOrder.evaluatorPolicyId, "save_place_recovery_v0");
  assert.equal(workOrder.settlementMode, "credit_after_decision");
  assert.deepEqual(workOrder.budgetPolicy, { credit_reserved: 2 });
});

test("place recovery run create canonicalizes supported source URL and reserves one credit", () => {
  const run = normalizePlaceRecoveryRunCreate({
    work_order_id: "9aebde27-6041-47ef-89a5-a3811b64d419",
    source_url: "https://www.instagram.com/reel/example/?igsh=abc#frag",
  });

  assert.equal(run.workOrderId, "9aebde27-6041-47ef-89a5-a3811b64d419");
  assert.equal(run.workflowId, "save_place_recovery_v0");
  assert.equal(run.listingId, "save-place-recovery-agent");
  assert.equal(run.sourceType, "instagram");
  assert.equal(run.sourceUrl, "https://www.instagram.com/reel/example/?igsh=abc");
  assert.equal(run.creditReserved, 1);
});

test("weak confirmed map stamp is downgraded to review candidate", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "confirmed_map_stamp",
    evidence_tier: "likely",
    confidence: 0.91,
    evidence_refs: ["source_1"],
    candidate_refs: ["candidate_1"],
  });

  assert.equal(result.resultType, "review_candidate");
  assert.equal(result.evidenceTier, "likely");
});

test("technical failure refunds reserved credit", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "technical_failure",
    evidence_tier: "none",
    confidence: 0,
  });
  const receipt = receiptForResult(result);

  assert.equal(receipt.verdict, "refund");
  assert.equal(receipt.settlement, "credit_refunded");
  assert.equal(receipt.creditSettlement, "refunded");
});

test("source-only clue settles as partial without pretending to be a failed place", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "source_only_clue",
    evidence_tier: "weak",
    confidence: 0.38,
    evidence_refs: ["source_1"],
  });
  const receipt = receiptForResult(result);

  assert.equal(receipt.verdict, "partial");
  assert.equal(receipt.settlement, "partial");
  assert.equal(receipt.creditSettlement, "partial");
});

test("user rejecting confirmed result becomes fail and refund", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "confirmed_map_stamp",
    evidence_tier: "confirmed",
    confidence: 0.86,
    evidence_refs: ["source_1", "map_1"],
    candidate_refs: ["candidate_1"],
  });
  const decision = normalizeUserDecision({
    action: "reject",
    reason: "Wrong A Cheng Goose branch",
  }, "run_123");
  const receipt = receiptForResult(result, decision);

  assert.equal(receipt.verdict, "fail");
  assert.equal(receipt.settlement, "credit_refunded");
  assert.equal(receipt.creditSettlement, "refunded");
});
