export type JsonObject = Record<string, unknown>;

export const placeRecoveryWorkflowId = "save_place_recovery_v0";
export const placeRecoveryWorkflowVersion = "v0";
export const placeRecoveryListingId = "save-place-recovery-agent";

export const workflowStatuses = ["queued", "running", "completed", "failed", "needs_review"] as const;
export const workflowResultTypes = [
  "confirmed_map_stamp",
  "review_candidate",
  "source_only_clue",
  "technical_failure",
] as const;
export const evidenceTiers = ["none", "weak", "likely", "confirmed"] as const;
export const creditSettlements = ["pending", "consumed", "refunded", "partial"] as const;
export const receiptVerdicts = ["pass", "partial", "fail", "refund", "dispute"] as const;
export const receiptSettlements = ["credit_consumed", "credit_refunded", "partial", "manual_review"] as const;
export const userDecisionActions = ["confirm", "edit", "reject", "save_source_only", "needs_more_evidence"] as const;
export const placeRecoveryWorkOrderIntent = "recover_place_from_source";
export const placeRecoveryEvaluatorPolicyId = "save_place_recovery_v0";
export const placeRecoverySettlementMode = "credit_after_decision";

export type WorkflowStatus = typeof workflowStatuses[number];
export type WorkflowResultType = typeof workflowResultTypes[number];
export type EvidenceTier = typeof evidenceTiers[number];
export type CreditSettlement = typeof creditSettlements[number];
export type ReceiptVerdict = typeof receiptVerdicts[number];
export type ReceiptSettlement = typeof receiptSettlements[number];
export type UserDecisionAction = typeof userDecisionActions[number];

export interface PlaceRecoveryWorkOrderCreate {
  workflowId: typeof placeRecoveryWorkflowId;
  listingId: typeof placeRecoveryListingId;
  intent: typeof placeRecoveryWorkOrderIntent;
  inputType: string;
  inputRef?: string;
  sourceUrl?: string;
  evaluatorPolicyId: typeof placeRecoveryEvaluatorPolicyId;
  settlementMode: typeof placeRecoverySettlementMode;
  budgetPolicy: JsonObject;
}

export interface PlaceRecoveryRunCreate {
  workOrderId?: string;
  workflowId: typeof placeRecoveryWorkflowId;
  listingId: typeof placeRecoveryListingId;
  sourceUrl?: string;
  sourceType: string;
  creditReserved: number;
}

export interface PlaceRecoveryWorkerResult {
  resultType: WorkflowResultType;
  evidenceTier: EvidenceTier;
  confidence: number;
  missingFields: string[];
  evidenceRefs: string[];
  candidateRefs: string[];
  technicalFailure: boolean;
  jobId?: string;
  agentId: string;
  operatorId?: string;
  requesterId?: string;
  inputHash?: string;
  outputHash?: string;
  permissionSnapshot: JsonObject;
  toolTraceRefs: string[];
  latencyMs?: number;
  costEstimate?: JsonObject;
  failureReason?: string;
  modelProvenance: JsonObject;
}

export interface UserDecisionInput {
  runId: string;
  action: UserDecisionAction;
  editedPayload: JsonObject;
  reason?: string;
  qualityDelta: number;
  reputationDelta: number;
}

export interface WorkflowReceiptDraft {
  verdict: ReceiptVerdict;
  settlement: ReceiptSettlement;
  creditSettlement: CreditSettlement;
  evaluatorSummary: string;
  evidenceRefs: string[];
  candidateRefs: string[];
  receiptType: "analysis" | "decision";
  workflowVersion: typeof placeRecoveryWorkflowVersion;
  jobId?: string;
  agentId: string;
  operatorId?: string;
  requesterId?: string;
  inputHash?: string;
  outputHash?: string;
  permissionSnapshot: JsonObject;
  toolTraceRefs: string[];
  latencyMs?: number;
  costEstimate?: JsonObject;
  failureReason?: string;
  userFeedbackAction?: UserDecisionAction;
  qualityDelta: number;
  reputationDelta: number;
  modelProvenance: JsonObject;
}

export function normalizePlaceRecoveryWorkOrderCreate(body: JsonObject): PlaceRecoveryWorkOrderCreate {
  const sourceUrl = normalizedURL(body.source_url ?? body.sourceUrl);
  const inputType = inputTypeFor(body.input_type ?? body.inputType, sourceUrl);
  const inputRef = trimmedString(body.input_ref ?? body.inputRef) ?? sourceUrl;
  return {
    workflowId: placeRecoveryWorkflowId,
    listingId: placeRecoveryListingId,
    intent: placeRecoveryWorkOrderIntent,
    inputType,
    inputRef,
    sourceUrl,
    evaluatorPolicyId: placeRecoveryEvaluatorPolicyId,
    settlementMode: placeRecoverySettlementMode,
    budgetPolicy: objectValue(body.budget_policy ?? body.budgetPolicy) ?? { credit_reserved: boundedCredits(body.credit_reserved ?? body.creditReserved) },
  };
}

export function normalizePlaceRecoveryRunCreate(body: JsonObject): PlaceRecoveryRunCreate {
  const sourceUrl = normalizedURL(body.source_url ?? body.sourceUrl);
  const sourceType = sourceTypeFor(body.source_type ?? body.sourceType, sourceUrl);
  return {
    workOrderId: trimmedString(body.work_order_id ?? body.workOrderId),
    workflowId: placeRecoveryWorkflowId,
    listingId: placeRecoveryListingId,
    sourceUrl,
    sourceType,
    creditReserved: boundedCredits(body.credit_reserved ?? body.creditReserved),
  };
}

export function normalizePlaceRecoveryWorkerResult(body: JsonObject): PlaceRecoveryWorkerResult {
  const resultType = parseEnum(body.result_type ?? body.resultType, workflowResultTypes, "source_only_clue");
  const evidenceTier = parseEnum(body.evidence_tier ?? body.evidenceTier, evidenceTiers, "none");
  const technicalFailure = resultType === "technical_failure" || body.technical_failure === true;

  return {
    resultType: downgradeUnsafeConfirmedResult(resultType, evidenceTier, technicalFailure),
    evidenceTier,
    confidence: boundedConfidence(body.confidence),
    missingFields: stringArray(body.missing_fields ?? body.missingFields),
    evidenceRefs: stringArray(body.evidence_refs ?? body.evidenceRefs),
    candidateRefs: stringArray(body.candidate_refs ?? body.candidateRefs),
    technicalFailure,
    jobId: trimmedString(body.job_id ?? body.jobId),
    agentId: trimmedString(body.agent_id ?? body.agentId) ?? "SAV-E",
    operatorId: trimmedString(body.operator_id ?? body.operatorId),
    requesterId: trimmedString(body.requester_id ?? body.requesterId),
    inputHash: trimmedString(body.input_hash ?? body.inputHash),
    outputHash: trimmedString(body.output_hash ?? body.outputHash),
    permissionSnapshot: objectValue(body.permission_snapshot ?? body.permissionSnapshot) ?? {},
    toolTraceRefs: stringArray(body.tool_trace_refs ?? body.toolTraceRefs),
    latencyMs: boundedOptionalNumber(body.latency_ms ?? body.latencyMs),
    costEstimate: objectValue(body.cost_estimate ?? body.costEstimate),
    failureReason: trimmedString(body.failure_reason ?? body.failureReason),
    modelProvenance: normalizeModelProvenance(body.model_provenance ?? body.modelProvenance ?? body.model),
  };
}

export function normalizeUserDecision(body: JsonObject, runId: string): UserDecisionInput {
  const action = parseEnum(body.action, userDecisionActions, "needs_more_evidence");
  return {
    runId,
    action,
    editedPayload: objectValue(body.edited_payload ?? body.editedPayload) ?? {},
    reason: trimmedString(body.reason),
    qualityDelta: boundedDelta(body.quality_delta ?? body.qualityDelta) ?? qualityDeltaForDecision(action),
    reputationDelta: boundedDelta(body.reputation_delta ?? body.reputationDelta) ?? reputationDeltaForDecision(action),
  };
}

export function isFinalUserDecision(action: UserDecisionAction): boolean {
  return action !== "needs_more_evidence";
}

export function analysisReceiptForResult(result: PlaceRecoveryWorkerResult): WorkflowReceiptDraft {
  if (result.technicalFailure || result.resultType === "technical_failure") {
    return receiptDraft(result, {
      receiptType: "analysis",
      verdict: "fail",
      settlement: "manual_review",
      creditSettlement: "pending",
      evaluatorSummary: "Analysis failed before useful place evidence could be produced.",
    });
  }

  if (result.resultType === "confirmed_map_stamp") {
    return receiptDraft(result, {
      receiptType: "analysis",
      verdict: "pass",
      settlement: "manual_review",
      creditSettlement: "pending",
      evaluatorSummary: "Analysis found confirmed place evidence; user confirmation still records the settlement receipt.",
    });
  }

  if (result.resultType === "review_candidate") {
    return receiptDraft(result, {
      receiptType: "analysis",
      verdict: "pass",
      settlement: "manual_review",
      creditSettlement: "pending",
      evaluatorSummary: "Analysis produced a review candidate without pretending it was confirmed.",
    });
  }

  return receiptDraft(result, {
    receiptType: "analysis",
    verdict: "partial",
    settlement: "manual_review",
    creditSettlement: "pending",
    evaluatorSummary: "Analysis preserved source clues but did not find enough evidence for a review candidate.",
  });
}

export function receiptForResult(
  result: PlaceRecoveryWorkerResult,
  decision?: UserDecisionInput,
): WorkflowReceiptDraft {
  if (result.technicalFailure || result.resultType === "technical_failure") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "refund",
      settlement: "credit_refunded",
      creditSettlement: "refunded",
      evaluatorSummary: "Technical recovery failed before useful evidence could be produced.",
    });
  }

  if (decision?.action === "needs_more_evidence") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "partial",
      settlement: "manual_review",
      creditSettlement: "pending",
      evaluatorSummary: "User requested more evidence; keep the run open without settling reserved credit.",
    });
  }

  if (decision?.action === "save_source_only") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "partial",
      settlement: "partial",
      creditSettlement: "partial",
      evaluatorSummary: "User kept the source as useful private memory without confirming a map place.",
    });
  }

  if (decision?.action === "reject") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "fail",
      settlement: "credit_refunded",
      creditSettlement: "refunded",
      evaluatorSummary: "User rejected a confirmed place result; refund credit and penalize quality.",
    });
  }

  if (decision?.action === "confirm" || result.resultType === "confirmed_map_stamp") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "pass",
      settlement: "credit_consumed",
      creditSettlement: "consumed",
      evaluatorSummary: "Place recovery produced a confirmed map stamp or user accepted the candidate.",
    });
  }

  if (result.resultType === "review_candidate") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "pass",
      settlement: "credit_consumed",
      creditSettlement: "consumed",
      evaluatorSummary: "Place recovery produced a useful review candidate without pretending it was confirmed.",
    });
  }

  return decisionReceiptDraft(result, decision, {
    receiptType: "decision",
    verdict: "partial",
    settlement: "partial",
    creditSettlement: "partial",
    evaluatorSummary: "Source produced useful clues but not enough evidence for a place candidate.",
  });
}

function decisionReceiptDraft(
  result: PlaceRecoveryWorkerResult,
  decision: UserDecisionInput | undefined,
  values: Pick<WorkflowReceiptDraft, "receiptType" | "verdict" | "settlement" | "creditSettlement" | "evaluatorSummary">,
): WorkflowReceiptDraft {
  return {
    ...receiptDraft(result, values),
    userFeedbackAction: decision?.action,
    qualityDelta: decision?.qualityDelta ?? 0,
    reputationDelta: decision?.reputationDelta ?? 0,
  };
}

function receiptDraft(
  result: PlaceRecoveryWorkerResult,
  values: Pick<WorkflowReceiptDraft, "receiptType" | "verdict" | "settlement" | "creditSettlement" | "evaluatorSummary">,
): WorkflowReceiptDraft {
  return {
    ...values,
    evidenceRefs: result.evidenceRefs,
    candidateRefs: result.candidateRefs,
    workflowVersion: placeRecoveryWorkflowVersion,
    jobId: result.jobId,
    agentId: result.agentId,
    operatorId: result.operatorId,
    requesterId: result.requesterId,
    inputHash: result.inputHash,
    outputHash: result.outputHash,
    permissionSnapshot: result.permissionSnapshot,
    toolTraceRefs: result.toolTraceRefs,
    latencyMs: result.latencyMs,
    costEstimate: result.costEstimate,
    failureReason: result.failureReason,
    userFeedbackAction: undefined,
    qualityDelta: 0,
    reputationDelta: 0,
    modelProvenance: result.modelProvenance,
  };
}

function downgradeUnsafeConfirmedResult(
  resultType: WorkflowResultType,
  evidenceTier: EvidenceTier,
  technicalFailure: boolean,
): WorkflowResultType {
  if (technicalFailure) return "technical_failure";
  if (resultType !== "confirmed_map_stamp") return resultType;
  return evidenceTier === "confirmed" ? resultType : "review_candidate";
}

function inputTypeFor(value: unknown, sourceUrl: string | undefined): string {
  const explicit = trimmedString(value);
  if (explicit) return explicit;
  return sourceUrl ? "url" : "text";
}

function sourceTypeFor(value: unknown, sourceUrl: string | undefined): string {
  const explicit = trimmedString(value);
  if (explicit) return explicit;
  if (!sourceUrl) return "text";
  const host = new URL(sourceUrl).hostname.toLowerCase();
  if (host.includes("instagram")) return "instagram";
  if (host.includes("x.com") || host.includes("twitter.com")) return "x";
  return "url";
}

function normalizedURL(value: unknown): string | undefined {
  const text = trimmedString(value);
  if (!text) return undefined;
  try {
    const url = new URL(text);
    if (url.protocol !== "http:" && url.protocol !== "https:") return undefined;
    url.hash = "";
    return url.toString();
  } catch {
    return undefined;
  }
}

function boundedCredits(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0 && value <= 10 ? value : 1;
}

function boundedConfidence(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(1, value));
}

function qualityDeltaForDecision(action: UserDecisionAction): number {
  if (action === "confirm") return 1;
  if (action === "edit") return 0.5;
  if (action === "reject") return -1;
  return 0;
}

function reputationDeltaForDecision(action: UserDecisionAction): number {
  if (action === "confirm") return 1;
  if (action === "edit") return 0.25;
  if (action === "reject") return -1;
  return 0;
}

function boundedOptionalNumber(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) return undefined;
  return value;
}

function boundedDelta(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return Math.max(-1, Math.min(1, value));
}

function parseEnum<const T extends readonly string[]>(value: unknown, allowed: T, fallback: T[number]): T[number] {
  return typeof value === "string" && allowed.includes(value) ? value as T[number] : fallback;
}

function objectValue(value: unknown): JsonObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : undefined;
}

function normalizeModelProvenance(value: unknown): JsonObject {
  const model = objectValue(value) ?? {};
  return {
    claimedProvider: trimmedString(model.claimedProvider ?? model.claimed_provider) ?? "unknown",
    claimedModel: trimmedString(model.claimedModel ?? model.claimed_model) ?? "unknown",
    observedProvider: trimmedString(model.observedProvider ?? model.observed_provider) ?? null,
    observedModel: trimmedString(model.observedModel ?? model.observed_model) ?? null,
    attestationLevel: trimmedString(model.attestationLevel ?? model.attestation_level) ?? "self_claim",
    fallbackUsed: typeof model.fallbackUsed === "boolean"
      ? model.fallbackUsed
      : typeof model.fallback_used === "boolean"
        ? model.fallback_used
        : "unknown",
    usage: objectValue(model.usage) ?? null,
    evidenceRefs: stringArray(model.evidenceRefs ?? model.evidence_refs),
  };
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function trimmedString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}
