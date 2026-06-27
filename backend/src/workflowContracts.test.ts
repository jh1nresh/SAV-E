import assert from "node:assert/strict";
import test from "node:test";
import {
  normalizePlaceRecoveryWorkOrderCreate,
  normalizePlaceRecoveryRunCreate,
  normalizePlaceRecoveryWorkerResult,
  normalizeUserDecision,
  receiptForResult,
  analysisReceiptForResult,
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
  assert.equal(result.agentId, "SAV-E");
  assert.deepEqual(result.modelProvenance, {
    claimedProvider: "unknown",
    claimedModel: "unknown",
    observedProvider: null,
    observedModel: null,
    attestationLevel: "self_claim",
    fallbackUsed: "unknown",
    usage: null,
    evidenceRefs: [],
  });
});

test("worker result preserves job id, agent id, and model provenance", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "review_candidate",
    evidence_tier: "likely",
    confidence: 0.74,
    job_id: "job_123",
    agent_id: "SAV-E",
    operator_id: "save-worker",
    requester_id: "00000000-0000-0000-0000-000000000001",
    input_hash: "input_hash_123",
    output_hash: "output_hash_123",
    permission_snapshot: { scopes: ["source_url.read", "place_candidate.write"] },
    tool_trace_refs: ["tool:source-search"],
    latency_ms: 1234,
    cost_estimate: { usd: 0.002 },
    failure_reason: "missing_coordinates",
    model_provenance: {
      claimed_provider: "google",
      claimed_model: "gemini-3.5-flash",
      observed_model: "gemini-3.5-flash",
      attestation_level: "provider_metadata",
      fallback_used: false,
      usage: { inputTokens: 100, outputTokens: 20 },
      evidence_refs: ["provider_response:abc"],
    },
  });

  assert.equal(result.jobId, "job_123");
  assert.equal(result.agentId, "SAV-E");
  assert.equal(result.operatorId, "save-worker");
  assert.equal(result.requesterId, "00000000-0000-0000-0000-000000000001");
  assert.equal(result.inputHash, "input_hash_123");
  assert.equal(result.outputHash, "output_hash_123");
  assert.deepEqual(result.permissionSnapshot, { scopes: ["source_url.read", "place_candidate.write"] });
  assert.deepEqual(result.toolTraceRefs, ["tool:source-search"]);
  assert.equal(result.latencyMs, 1234);
  assert.deepEqual(result.costEstimate, { usd: 0.002 });
  assert.equal(result.failureReason, "missing_coordinates");
  assert.deepEqual(result.modelProvenance, {
    claimedProvider: "google",
    claimedModel: "gemini-3.5-flash",
    observedProvider: null,
    observedModel: "gemini-3.5-flash",
    attestationLevel: "provider_metadata",
    fallbackUsed: false,
    usage: { inputTokens: 100, outputTokens: 20 },
    evidenceRefs: ["provider_response:abc"],
  });
});

test("analysis receipt records review candidate before user decision", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "review_candidate",
    evidence_tier: "likely",
    confidence: 0.74,
    candidate_refs: ["candidate_1"],
    job_id: "job_123",
    agent_id: "SAV-E",
    model: {
      claimedProvider: "google",
      claimedModel: "gemini-3.5-flash",
    },
  });
  const receipt = analysisReceiptForResult(result);

  assert.equal(receipt.receiptType, "analysis");
  assert.equal(receipt.workflowVersion, "v0");
  assert.equal(receipt.verdict, "pass");
  assert.equal(receipt.settlement, "manual_review");
  assert.equal(receipt.creditSettlement, "pending");
  assert.equal(receipt.jobId, "job_123");
  assert.equal(receipt.agentId, "SAV-E");
  assert.deepEqual(receipt.candidateRefs, ["candidate_1"]);
});

test("user confirmation creates final decision receipt", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "review_candidate",
    evidence_tier: "likely",
    confidence: 0.74,
    candidate_refs: ["candidate_1"],
  });
  const decision = normalizeUserDecision({ action: "confirm" }, "run_123");
  const receipt = receiptForResult(result, decision);

  assert.equal(receipt.receiptType, "decision");
  assert.equal(receipt.verdict, "pass");
  assert.equal(receipt.settlement, "credit_consumed");
  assert.equal(receipt.creditSettlement, "consumed");
  assert.equal(receipt.userFeedbackAction, "confirm");
  assert.equal(receipt.qualityDelta, 1);
  assert.equal(receipt.reputationDelta, 1);
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
