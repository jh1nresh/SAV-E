import { createHash } from "node:crypto";
import type {
  CreditSettlement,
  UserDecisionAction,
} from "./workflowContracts.js";

export class WorkflowConflictError extends Error {}

export interface CurrentAnalysisReceipt {
  id: string;
  attemptNo: number;
  resultRevision: number;
  idempotencyKey: string;
  outputHash: string;
}

export interface ResultTransitionInput {
  currentAttemptNo: number;
  currentCreditSettlement: CreditSettlement;
  requestedAttemptNo?: number;
  resultRevision: number;
  idempotencyKey: string;
  outputHash: string;
  explicitRetry: boolean;
  currentReceipt?: CurrentAnalysisReceipt;
}

export type ResultTransitionPlan =
  | { kind: "idempotent"; receiptId: string }
  | {
    kind: "create";
    attemptNo: number;
    resultRevision: number;
    supersedesReceiptId?: string;
    supersedeCurrent: boolean;
  };

export function planResultTransition(input: ResultTransitionInput): ResultTransitionPlan {
  const attemptNo = input.requestedAttemptNo ?? input.currentAttemptNo;
  const current = input.currentReceipt;

  if (current?.idempotencyKey === input.idempotencyKey) {
    const replayAttemptNo = input.requestedAttemptNo ?? current.attemptNo;
    if (current.outputHash !== input.outputHash
      || current.attemptNo !== replayAttemptNo
      || current.resultRevision !== input.resultRevision
    ) {
      throw new WorkflowConflictError("Result idempotency key was already used with different identity or output");
    }
    return { kind: "idempotent", receiptId: current.id };
  }

  if (input.currentCreditSettlement !== "pending") {
    throw new WorkflowConflictError("Settled workflow runs cannot accept another result");
  }

  if (!current) {
    if (attemptNo !== input.currentAttemptNo || input.resultRevision !== 1) {
      throw new WorkflowConflictError("The first result must target revision 1 of the active attempt");
    }
    return {
      kind: "create",
      attemptNo,
      resultRevision: 1,
      supersedesReceiptId: undefined,
      supersedeCurrent: false,
    };
  }

  if (attemptNo === current.attemptNo) {
    throw new WorkflowConflictError("The active attempt already has a terminal analysis result");
  }

  const retryAlreadyAuthorized = input.currentAttemptNo === current.attemptNo + 1;
  const directExplicitRetry = input.explicitRetry
    && input.currentAttemptNo === current.attemptNo
    && attemptNo === current.attemptNo + 1;
  if ((!retryAlreadyAuthorized && !directExplicitRetry)
    || attemptNo !== current.attemptNo + 1
    || input.resultRevision !== 1
  ) {
    throw new WorkflowConflictError("A retry must start revision 1 of the next sequential attempt");
  }

  return {
    kind: "create",
    attemptNo,
    resultRevision: 1,
    supersedesReceiptId: current.id,
    supersedeCurrent: true,
  };
}

export interface ExistingDecision {
  id: string;
  receiptId: string;
  idempotencyKey: string;
  fingerprint: string;
}

export interface DecisionTransitionInput {
  currentAttemptNo: number;
  currentCreditSettlement: CreditSettlement;
  action: UserDecisionAction;
  creditReserved: number;
  idempotencyKey: string;
  fingerprint: string;
  existingDecision?: ExistingDecision;
}

export type DecisionTransitionPlan =
  | { kind: "idempotent"; decisionId: string; receiptId: string }
  | {
    kind: "create";
    creditSettlement: CreditSettlement;
    refundDelta: number;
    terminal: boolean;
    nextStatus: "completed" | "needs_review" | "running";
    nextAttemptNo: number;
  };

export function planDecisionTransition(input: DecisionTransitionInput): DecisionTransitionPlan {
  const existing = input.existingDecision;
  if (existing) {
    if (existing.fingerprint !== input.fingerprint) {
      throw new WorkflowConflictError("Decision identity was already used with different input");
    }
    return { kind: "idempotent", decisionId: existing.id, receiptId: existing.receiptId };
  }

  if (input.currentCreditSettlement !== "pending") {
    throw new WorkflowConflictError("Settled workflow runs cannot accept another decision");
  }

  const policy = decisionSettlementPolicy(input.action, input.creditReserved);
  return {
    kind: "create",
    ...policy,
    nextStatus: input.action === "investigate_more"
      ? "running"
      : policy.terminal
        ? "completed"
        : "needs_review",
    nextAttemptNo: input.action === "investigate_more"
      ? input.currentAttemptNo + 1
      : input.currentAttemptNo,
  };
}

export function decisionSettlementPolicy(
  action: UserDecisionAction,
  creditReserved: number,
): { creditSettlement: CreditSettlement; refundDelta: number; terminal: boolean } {
  const reserved = Number.isFinite(creditReserved) && creditReserved > 0 ? creditReserved : 1;
  if (action === "reject") {
    return { creditSettlement: "refunded", refundDelta: reserved, terminal: true };
  }
  if (action === "edit"
    || action === "wrong_place"
    || action === "wrong_city"
    || action === "wrong_branch"
    || action === "source_only"
  ) {
    return { creditSettlement: "partial", refundDelta: reserved / 2, terminal: true };
  }
  if (action === "needs_more_evidence" || action === "investigate_more") {
    return { creditSettlement: "pending", refundDelta: 0, terminal: false };
  }
  return { creditSettlement: "consumed", refundDelta: 0, terminal: true };
}

export interface ReputationOutcome {
  runId: string;
  isCurrent: boolean;
  settled: boolean;
  technicalFailure: boolean;
  decisionAction?: UserDecisionAction;
  creditSettlement: CreditSettlement;
  latencyMs?: number;
}

export interface ReputationCounters {
  runCount: number;
  operationalSuccessCount: number;
  technicalFailureCount: number;
  confirmedCount: number;
  editedCount: number;
  rejectedCount: number;
  sourceOnlyCount: number;
  refundCount: number;
  medianLatencyMs: number | null;
  userDecisionCoverage: number;
  operationalSuccessRate: number;
  confirmationRate: number;
  editRate: number;
  rejectionRate: number;
  technicalFailureRate: number;
}

export function reconcileReputation(outcomes: ReputationOutcome[]): ReputationCounters {
  const current = outcomes.filter((outcome) => outcome.isCurrent);
  const settled = current.filter((outcome) => outcome.settled);
  const settledReviewable = settled.filter((outcome) => !outcome.technicalFailure);
  const reviewable = current.filter((outcome) => !outcome.technicalFailure);
  const decided = reviewable.filter((outcome) => outcome.decisionAction !== undefined);
  const editedActions = new Set<UserDecisionAction>(["edit", "wrong_place", "wrong_city", "wrong_branch"]);
  const latencies = settled
    .map((outcome) => outcome.latencyMs)
    .filter((value): value is number => typeof value === "number" && Number.isFinite(value))
    .sort((left, right) => left - right);
  const confirmedCount = settled.filter((outcome) => outcome.decisionAction === "confirm").length;
  const editedCount = settled.filter((outcome) => outcome.decisionAction && editedActions.has(outcome.decisionAction)).length;
  const rejectedCount = settled.filter((outcome) => outcome.decisionAction === "reject").length;
  const technicalFailureCount = settled.filter((outcome) => outcome.technicalFailure).length;
  const runCount = settled.length;

  return {
    runCount,
    operationalSuccessCount: runCount - technicalFailureCount,
    technicalFailureCount,
    confirmedCount,
    editedCount,
    rejectedCount,
    sourceOnlyCount: settled.filter((outcome) => outcome.decisionAction === "source_only").length,
    refundCount: settled.filter((outcome) => outcome.creditSettlement === "refunded").length,
    medianLatencyMs: median(latencies),
    userDecisionCoverage: rate(decided.length, reviewable.length),
    operationalSuccessRate: rate(runCount - technicalFailureCount, runCount),
    confirmationRate: rate(confirmedCount, settledReviewable.length),
    editRate: rate(editedCount, settledReviewable.length),
    rejectionRate: rate(rejectedCount, settledReviewable.length),
    technicalFailureRate: rate(technicalFailureCount, runCount),
  };
}

function median(values: number[]): number | null {
  if (!values.length) return null;
  const middle = Math.floor(values.length / 2);
  return values.length % 2 === 0 ? (values[middle - 1] + values[middle]) / 2 : values[middle];
}

function rate(numerator: number, denominator: number): number {
  return denominator > 0 ? numerator / denominator : 0;
}

export interface ClearingEligibilityInput {
  isCurrent: boolean;
  attemptIsCurrent: boolean;
  receiptHash: string;
  receiptType: "analysis" | "decision";
  settlement: "credit_consumed" | "credit_refunded" | "partial" | "manual_review";
  supersedingReceiptPending: boolean;
  privacyValidated: boolean;
}

export function clearingEligibility(input: ClearingEligibilityInput): { eligible: boolean; reason?: string } {
  if (!input.isCurrent) return { eligible: false, reason: "superseded" };
  if (!input.attemptIsCurrent) return { eligible: false, reason: "retry_pending" };
  if (!input.receiptHash) return { eligible: false, reason: "missing_hash" };
  if (!input.privacyValidated) return { eligible: false, reason: "privacy_not_validated" };
  if (input.supersedingReceiptPending) return { eligible: false, reason: "supersession_pending" };
  if (input.settlement === "manual_review" && input.receiptType !== "analysis") {
    return { eligible: false, reason: "decision_pending" };
  }
  return { eligible: true };
}

const safeOpaqueRef = /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}|opaque:sha256:[0-9a-f]{64})$/i;

export function safeOpaqueRefs(value: unknown, maxItems = 32): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, maxItems)
    .map((item) => safeOpaqueRef.test(item) && item.length <= 256
      ? item
      : `opaque:sha256:${createHash("sha256").update(item).digest("hex")}`
    );
}
