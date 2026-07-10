import assert from "node:assert/strict";
import test from "node:test";
import {
  WorkflowConflictError,
  clearingEligibility,
  decisionSettlementPolicy,
  planDecisionTransition,
  planResultTransition,
  reconcileReputation,
  safeOpaqueRefs,
} from "./workflowLifecycle.js";

test("first result creates one current analysis receipt for the active attempt", () => {
  const plan = planResultTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    requestedAttemptNo: undefined,
    resultRevision: 1,
    idempotencyKey: "result:attempt-1",
    outputHash: "hash-a",
    explicitRetry: false,
  });

  assert.deepEqual(plan, {
    kind: "create",
    attemptNo: 1,
    resultRevision: 1,
    supersedesReceiptId: undefined,
    supersedeCurrent: false,
  });
});

test("result replay returns the existing receipt and conflicting key reuse is rejected", () => {
  const currentReceipt = {
    id: "receipt-1",
    attemptNo: 1,
    resultRevision: 1,
    idempotencyKey: "result:attempt-1",
    outputHash: "hash-a",
  };

  assert.deepEqual(planResultTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    requestedAttemptNo: 1,
    resultRevision: 1,
    idempotencyKey: "result:attempt-1",
    outputHash: "hash-a",
    explicitRetry: false,
    currentReceipt,
  }), { kind: "idempotent", receiptId: "receipt-1" });

  assert.throws(() => planResultTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    requestedAttemptNo: 1,
    resultRevision: 1,
    idempotencyKey: "result:attempt-1",
    outputHash: "hash-b",
    explicitRetry: false,
    currentReceipt,
  }), WorkflowConflictError);

  assert.throws(() => planResultTransition({
    currentAttemptNo: 2,
    currentCreditSettlement: "pending",
    requestedAttemptNo: 2,
    resultRevision: 1,
    idempotencyKey: "result:attempt-1",
    outputHash: "hash-a",
    explicitRetry: true,
    currentReceipt,
  }), WorkflowConflictError);

  assert.throws(() => planResultTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    requestedAttemptNo: 1,
    resultRevision: 2,
    idempotencyKey: "result:attempt-1",
    outputHash: "hash-a",
    explicitRetry: false,
    currentReceipt,
  }), WorkflowConflictError);
});

test("terminal result conflicts unless a new attempt was explicitly authorized", () => {
  const currentReceipt = {
    id: "receipt-1",
    attemptNo: 1,
    resultRevision: 1,
    idempotencyKey: "result:attempt-1",
    outputHash: "hash-a",
  };

  assert.throws(() => planResultTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    requestedAttemptNo: 1,
    resultRevision: 2,
    idempotencyKey: "result:revision-2",
    outputHash: "hash-b",
    explicitRetry: false,
    currentReceipt,
  }), WorkflowConflictError);

  assert.deepEqual(planResultTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    requestedAttemptNo: 2,
    resultRevision: 1,
    idempotencyKey: "result:attempt-2",
    outputHash: "hash-b",
    explicitRetry: true,
    currentReceipt,
  }), {
    kind: "create",
    attemptNo: 2,
    resultRevision: 1,
    supersedesReceiptId: "receipt-1",
    supersedeCurrent: true,
  });
});

test("an investigate-more decision authorizes the next attempt without a second retry flag", () => {
  const plan = planResultTransition({
    currentAttemptNo: 2,
    currentCreditSettlement: "pending",
    requestedAttemptNo: undefined,
    resultRevision: 1,
    idempotencyKey: "result:attempt-2",
    outputHash: "hash-b",
    explicitRetry: false,
    currentReceipt: {
      id: "receipt-1",
      attemptNo: 1,
      resultRevision: 1,
      idempotencyKey: "result:attempt-1",
      outputHash: "hash-a",
    },
  });

  assert.equal(plan.kind, "create");
  if (plan.kind === "create") {
    assert.equal(plan.attemptNo, 2);
    assert.equal(plan.supersedesReceiptId, "receipt-1");
  }
});

test("decision policy conserves fractional credit and keeps pending actions unsettled", () => {
  assert.deepEqual(decisionSettlementPolicy("confirm", 1), {
    creditSettlement: "consumed",
    refundDelta: 0,
    terminal: true,
  });
  assert.deepEqual(decisionSettlementPolicy("edit", 1), {
    creditSettlement: "partial",
    refundDelta: 0.5,
    terminal: true,
  });
  assert.deepEqual(decisionSettlementPolicy("source_only", 1), {
    creditSettlement: "partial",
    refundDelta: 0.5,
    terminal: true,
  });
  assert.deepEqual(decisionSettlementPolicy("reject", 1), {
    creditSettlement: "refunded",
    refundDelta: 1,
    terminal: true,
  });
  assert.deepEqual(decisionSettlementPolicy("merge_existing", 1), {
    creditSettlement: "consumed",
    refundDelta: 0,
    terminal: true,
  });
  assert.deepEqual(decisionSettlementPolicy("needs_more_evidence", 1), {
    creditSettlement: "pending",
    refundDelta: 0,
    terminal: false,
  });
});

test("decision replay is idempotent and a second terminal decision conflicts", () => {
  const existingDecision = {
    id: "decision-1",
    receiptId: "receipt-2",
    idempotencyKey: "decision:confirm-1",
    fingerprint: "fingerprint-a",
  };

  assert.deepEqual(planDecisionTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    action: "confirm",
    creditReserved: 1,
    idempotencyKey: "decision:confirm-1",
    fingerprint: "fingerprint-a",
    existingDecision,
  }), {
    kind: "idempotent",
    decisionId: "decision-1",
    receiptId: "receipt-2",
  });

  assert.deepEqual(planDecisionTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    action: "confirm",
    creditReserved: 1,
    idempotencyKey: "decision:new-key-for-same-id",
    fingerprint: "fingerprint-a",
    existingDecision,
  }), {
    kind: "idempotent",
    decisionId: "decision-1",
    receiptId: "receipt-2",
  });

  assert.throws(() => planDecisionTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    action: "reject",
    creditReserved: 1,
    idempotencyKey: "decision:confirm-1",
    fingerprint: "fingerprint-b",
    existingDecision,
  }), WorkflowConflictError);

  assert.throws(() => planDecisionTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "consumed",
    action: "reject",
    creditReserved: 1,
    idempotencyKey: "decision:reject-2",
    fingerprint: "fingerprint-c",
  }), WorkflowConflictError);
});

test("investigate-more advances the attempt while preserving the reservation", () => {
  assert.deepEqual(planDecisionTransition({
    currentAttemptNo: 1,
    currentCreditSettlement: "pending",
    action: "investigate_more",
    creditReserved: 1,
    idempotencyKey: "decision:retry-1",
    fingerprint: "fingerprint-a",
  }), {
    kind: "create",
    creditSettlement: "pending",
    refundDelta: 0,
    terminal: false,
    nextStatus: "running",
    nextAttemptNo: 2,
  });
});

test("reputation counters use only current settled outcomes", () => {
  const counters = reconcileReputation([
    { runId: "confirm", isCurrent: true, settled: true, technicalFailure: false, decisionAction: "confirm", creditSettlement: "consumed", latencyMs: 100 },
    { runId: "edit", isCurrent: true, settled: true, technicalFailure: false, decisionAction: "wrong_branch", creditSettlement: "partial", latencyMs: 200 },
    { runId: "reject", isCurrent: true, settled: true, technicalFailure: false, decisionAction: "reject", creditSettlement: "refunded", latencyMs: 300 },
    { runId: "source", isCurrent: true, settled: true, technicalFailure: false, decisionAction: "source_only", creditSettlement: "partial", latencyMs: 400 },
    { runId: "failure", isCurrent: true, settled: true, technicalFailure: true, creditSettlement: "refunded", latencyMs: 500 },
    { runId: "superseded", isCurrent: false, settled: true, technicalFailure: true, creditSettlement: "refunded", latencyMs: 1 },
    { runId: "pending", isCurrent: true, settled: false, technicalFailure: false, decisionAction: "needs_more_evidence", creditSettlement: "pending", latencyMs: 1 },
    { runId: "pending-no-decision", isCurrent: true, settled: false, technicalFailure: false, creditSettlement: "pending", latencyMs: 1 },
  ]);

  assert.deepEqual(counters, {
    runCount: 5,
    operationalSuccessCount: 4,
    technicalFailureCount: 1,
    confirmedCount: 1,
    editedCount: 1,
    rejectedCount: 1,
    sourceOnlyCount: 1,
    refundCount: 2,
    medianLatencyMs: 300,
    userDecisionCoverage: 5 / 6,
    operationalSuccessRate: 0.8,
    confirmationRate: 0.25,
    editRate: 0.25,
    rejectionRate: 0.25,
    technicalFailureRate: 0.2,
  });
});

test("clearing excludes missing, superseded, pending-decision, and privacy-invalid receipts", () => {
  const base = {
    isCurrent: true,
    attemptIsCurrent: true,
    receiptHash: "hash-1",
    receiptType: "analysis" as const,
    settlement: "manual_review" as const,
    supersedingReceiptPending: false,
    privacyValidated: true,
  };

  assert.equal(clearingEligibility(base).eligible, true);
  assert.equal(clearingEligibility({ ...base, isCurrent: false }).eligible, false);
  assert.equal(clearingEligibility({ ...base, attemptIsCurrent: false }).eligible, false);
  assert.equal(clearingEligibility({ ...base, receiptHash: "" }).eligible, false);
  assert.equal(clearingEligibility({ ...base, supersedingReceiptPending: true }).eligible, false);
  assert.equal(clearingEligibility({ ...base, privacyValidated: false }).eligible, false);
  assert.equal(clearingEligibility({ ...base, receiptType: "decision" }).eligible, false);
  assert.equal(clearingEligibility({ ...base, receiptType: "decision", settlement: "credit_refunded" }).eligible, true);
});

test("receipt refs are bounded and raw private values become opaque hashes", () => {
  const existingOpaqueRef = `opaque:sha256:${"a".repeat(64)}`;
  const refs = safeOpaqueRefs([
    "candidate:123",
    "source_url:https://private.example/path?token=secret",
    "friend message with private details",
    "Bearer super-secret-access-token",
    "evidence:secret-caption",
    existingOpaqueRef,
  ]);

  assert.match(refs[0], /^opaque:sha256:[a-f0-9]{64}$/);
  assert.match(refs[1], /^opaque:sha256:[a-f0-9]{64}$/);
  assert.match(refs[2], /^opaque:sha256:[a-f0-9]{64}$/);
  assert.match(refs[3], /^opaque:sha256:[a-f0-9]{64}$/);
  assert.match(refs[4], /^opaque:sha256:[a-f0-9]{64}$/);
  assert.equal(refs[5], existingOpaqueRef);
  assert.equal(JSON.stringify(refs).includes("private.example"), false);
  assert.equal(JSON.stringify(refs).includes("friend message"), false);
  assert.equal(JSON.stringify(refs).includes("super-secret-access-token"), false);
  assert.equal(JSON.stringify(refs).includes("secret-caption"), false);
});
