import assert from "node:assert/strict";
import test from "node:test";
import {
  WorkflowContractError,
  failedSteps,
  failureCodes,
  normalizePlaceRecoveryWorkOrderCreate,
  normalizePlaceRecoveryRunCreate,
  normalizePlaceRecoveryWorkerResult,
  normalizeUserDecision,
  receiptForResult,
  analysisReceiptForResult,
  userDecisionActions,
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

test("place recovery run bounds explicit source types to a safe reputation dimension", () => {
  const run = normalizePlaceRecoveryRunCreate({ source_type: "  Instagram Reels / Private  " });

  assert.equal(run.sourceType, "other");
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

test("worker result keeps bounded metadata but treats identity and provenance as self-claimed", () => {
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
  assert.equal(result.operatorId, "save-client");
  assert.equal("requesterId" in result, false);
  assert.equal("inputHash" in result, false);
  assert.equal("outputHash" in result, false);
  assert.deepEqual(result.permissionSnapshot, { scopes: ["place_recovery.result.submit"] });
  assert.deepEqual(result.toolTraceRefs, ["tool:source-search"]);
  assert.equal(result.latencyMs, 1234);
  assert.deepEqual(result.costEstimate, { usd: 0.002 });
  assert.equal(result.failureReason, undefined);
  assert.deepEqual(result.modelProvenance, {
    claimedProvider: "google",
    claimedModel: "gemini-3.5-flash",
    observedProvider: null,
    observedModel: null,
    attestationLevel: "self_claim",
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
    failure_code: "model_timeout",
    failed_step: "recover_candidate",
    retryable: true,
  });
  const analysisReceipt = analysisReceiptForResult(result);
  const receipt = receiptForResult(result);

  assert.equal(analysisReceipt.verdict, "fail");
  assert.equal(analysisReceipt.settlement, "credit_refunded");
  assert.equal(analysisReceipt.creditSettlement, "refunded");
  assert.equal(receipt.verdict, "refund");
  assert.equal(receipt.settlement, "credit_refunded");
  assert.equal(receipt.creditSettlement, "refunded");
});

test("technical failures require a structured code, failed step, and retryability", () => {
  assert.throws(() => normalizePlaceRecoveryWorkerResult({
    result_type: "technical_failure",
  }), WorkflowContractError);

  for (const failureCode of failureCodes) {
    const result = normalizePlaceRecoveryWorkerResult({
      result_type: "technical_failure",
      failure_code: failureCode,
      failed_step: "recover_candidate",
      retryable: false,
    });
    assert.equal(result.failureCode, failureCode);
  }

  for (const failedStep of failedSteps) {
    const result = normalizePlaceRecoveryWorkerResult({
      result_type: "technical_failure",
      failure_code: "internal_error",
      failed_step: failedStep,
      retryable: true,
    });
    assert.equal(result.failedStep, failedStep);
  }

  assert.throws(() => normalizePlaceRecoveryWorkerResult({
    result_type: "technical_failure",
    failure_code: "made_up_failure",
    failed_step: "recover_candidate",
    retryable: true,
  }), WorkflowContractError);
});

test("worker result normalizes attempt identity without trusting requester or supplied hashes", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "review_candidate",
    attempt_no: 2,
    result_revision: 1,
    idempotency_key: "result:attempt-2",
    retry: true,
    requester_id: "attacker",
    input_hash: "client-input-hash",
    output_hash: "client-output-hash",
  });

  assert.equal(result.attemptNo, 2);
  assert.equal(result.resultRevision, 1);
  assert.equal(result.idempotencyKey, "result:attempt-2");
  assert.equal(result.explicitRetry, true);
  assert.equal("requesterId" in result, false);
  assert.equal("inputHash" in result, false);
  assert.equal("outputHash" in result, false);
  assert.throws(() => normalizePlaceRecoveryWorkerResult({
    result_type: "source_only_clue",
    idempotency_key: "legacy:caller-controlled",
  }), WorkflowContractError);
});

test("full Inbox decision taxonomy is strict and client deltas are ignored", () => {
  const expectedDeltas = {
    confirm: [1, 1],
    edit: [0.5, 0.25],
    reject: [-1, -1],
    source_only: [0.25, 0.1],
    wrong_place: [0.5, 0.25],
    wrong_city: [0.5, 0.25],
    wrong_branch: [0.5, 0.25],
    merge_existing: [1, 0.75],
    needs_more_evidence: [0, 0],
    investigate_more: [0, 0],
  } as const;
  for (const action of userDecisionActions) {
    const decision = normalizeUserDecision({
      action,
      idempotency_key: `decision:${action}`,
      quality_delta: action === "reject" ? 0.9 : -0.9,
      reputation_delta: action === "reject" ? 0.9 : -0.9,
    }, "run_123");
    assert.equal(decision.action, action);
    assert.equal(decision.idempotencyKey, `decision:${action}`);
    assert.equal(decision.qualityDelta, expectedDeltas[action][0]);
    assert.equal(decision.reputationDelta, expectedDeltas[action][1]);
  }

  assert.throws(() => normalizeUserDecision({ action: "charge_anyway" }, "run_123"), WorkflowContractError);
});

test("decision normalization keeps a bounded final place draft for atomic save", () => {
  const finalPlaceId = "cb6a7108-a247-4d7d-94da-312c9e98ce34";
  const decision = normalizeUserDecision({
    action: "confirm",
    final_place_id: finalPlaceId,
    final_place: {
      id: finalPlaceId,
      name: "Atomic Cafe",
      address: "1 Receipt Way",
      latitude: 33.7,
      longitude: -117.8,
    },
  }, "run_123");

  assert.equal(decision.finalPlaceId, finalPlaceId);
  assert.equal(decision.finalPlace?.name, "Atomic Cafe");
  assert.throws(() => normalizeUserDecision({
    action: "confirm",
    final_place: { id: finalPlaceId, api_key: "must-not-pass" },
  }, "run_123"), WorkflowContractError);
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

test("requesting more evidence keeps credit pending", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "review_candidate",
    evidence_tier: "likely",
    confidence: 0.72,
  });
  const decision = normalizeUserDecision({ action: "needs_more_evidence" }, "run_123");
  const receipt = receiptForResult(result, decision);

  assert.equal(receipt.verdict, "partial");
  assert.equal(receipt.settlement, "manual_review");
  assert.equal(receipt.creditSettlement, "pending");
});

test("saving source only creates a final partial settlement", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "review_candidate",
    evidence_tier: "weak",
    confidence: 0.42,
  });
  const decision = normalizeUserDecision({ action: "source_only" }, "run_123");
  const receipt = receiptForResult(result, decision);

  assert.equal(receipt.verdict, "partial");
  assert.equal(receipt.settlement, "partial");
  assert.equal(receipt.creditSettlement, "partial");
  assert.equal(receipt.userFeedbackAction, "source_only");
});

test("rejecting a review candidate refunds reserved credit", () => {
  const result = normalizePlaceRecoveryWorkerResult({
    result_type: "review_candidate",
    evidence_tier: "likely",
    confidence: 0.72,
  });
  const decision = normalizeUserDecision({ action: "reject" }, "run_123");
  const receipt = receiptForResult(result, decision);

  assert.equal(receipt.verdict, "fail");
  assert.equal(receipt.settlement, "credit_refunded");
  assert.equal(receipt.creditSettlement, "refunded");
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
