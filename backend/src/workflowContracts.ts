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
export const userDecisionActions = [
  "confirm",
  "edit",
  "reject",
  "source_only",
  "wrong_place",
  "wrong_city",
  "wrong_branch",
  "merge_existing",
  "needs_more_evidence",
  "investigate_more",
] as const;
export const failureCodes = [
  "invalid_source",
  "unsupported_source",
  "source_fetch_failed",
  "source_auth_blocked",
  "source_rate_limited",
  "source_content_unavailable",
  "extractor_failed",
  "model_provider_failed",
  "model_timeout",
  "model_invalid_output",
  "map_lookup_failed",
  "candidate_persistence_failed",
  "receipt_persistence_failed",
  "configuration_missing",
  "internal_error",
] as const;
export const failedSteps = [
  "validate_input",
  "fetch_source",
  "extract_source",
  "classify_source",
  "recover_candidate",
  "resolve_map_identity",
  "persist_candidate",
  "write_receipt",
  "settle_credit",
] as const;
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
export type FailureCode = typeof failureCodes[number];
export type FailedStep = typeof failedSteps[number];

export class WorkflowContractError extends Error {}

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
  attemptNo?: number;
  resultRevision: number;
  idempotencyKey?: string;
  explicitRetry: boolean;
  failureCode?: FailureCode;
  failedStep?: FailedStep;
  retryable?: boolean;
  jobId?: string;
  agentId: string;
  operatorId?: string;
  permissionSnapshot: JsonObject;
  toolTraceRefs: string[];
  latencyMs?: number;
  costEstimate?: JsonObject;
  failureReason?: string;
  modelProvenance: JsonObject;
}

export interface UserDecisionInput {
  decisionId?: string;
  runId: string;
  action: UserDecisionAction;
  attemptNo?: number;
  candidateId?: string;
  finalPlaceId?: string;
  finalPlace?: JsonObject;
  reasonCode?: string;
  idempotencyKey?: string;
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
  permissionSnapshot: JsonObject;
  toolTraceRefs: string[];
  latencyMs?: number;
  costEstimate?: JsonObject;
  failureReason?: string;
  failureCode?: FailureCode;
  failedStep?: FailedStep;
  retryable?: boolean;
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
  const resultType = parseEnumField(
    body.result_type ?? body.resultType,
    workflowResultTypes,
    "source_only_clue",
    "result_type",
  );
  const evidenceTier = parseEnumField(
    body.evidence_tier ?? body.evidenceTier,
    evidenceTiers,
    "none",
    "evidence_tier",
  );
  const technicalFailure = resultType === "technical_failure" || body.technical_failure === true;
  const failureCode = technicalFailure
    ? requiredEnum(body.failure_code ?? body.failureCode, failureCodes, "failure_code")
    : undefined;
  const failedStep = technicalFailure
    ? requiredEnum(body.failed_step ?? body.failedStep, failedSteps, "failed_step")
    : undefined;
  const retryable = technicalFailure
    ? requiredBoolean(body.retryable, "retryable")
    : undefined;

  return {
    resultType: downgradeUnsafeConfirmedResult(resultType, evidenceTier, technicalFailure),
    evidenceTier,
    confidence: boundedConfidence(body.confidence),
    missingFields: boundedStringArray(body.missing_fields ?? body.missingFields, 32, 128),
    evidenceRefs: boundedStringArray(body.evidence_refs ?? body.evidenceRefs, 32, 512),
    candidateRefs: boundedStringArray(body.candidate_refs ?? body.candidateRefs, 32, 128),
    technicalFailure,
    attemptNo: optionalPositiveInteger(body.attempt_no ?? body.attemptNo, "attempt_no"),
    resultRevision: positiveIntegerOrDefault(body.result_revision ?? body.resultRevision, 1, "result_revision"),
    idempotencyKey: optionalIdempotencyKey(body.idempotency_key ?? body.idempotencyKey),
    explicitRetry: body.retry === true || body.explicit_retry === true || body.explicitRetry === true,
    failureCode,
    failedStep,
    retryable,
    jobId: boundedString(body.job_id ?? body.jobId, 128),
    agentId: "SAV-E",
    operatorId: "save-client",
    permissionSnapshot: { scopes: ["place_recovery.result.submit"] },
    toolTraceRefs: boundedStringArray(body.tool_trace_refs ?? body.toolTraceRefs, 32, 256),
    latencyMs: boundedOptionalNumber(body.latency_ms ?? body.latencyMs),
    costEstimate: safeCostEstimate(body.cost_estimate ?? body.costEstimate),
    failureReason: failureCode,
    modelProvenance: normalizeModelProvenance(body.model_provenance ?? body.modelProvenance ?? body.model),
  };
}

export function normalizeUserDecision(body: JsonObject, runId: string): UserDecisionInput {
  const action = requiredEnum(body.action, userDecisionActions, "action");
  const finalPlaceValue = body.final_place ?? body.finalPlace;
  return {
    decisionId: optionalUuid(body.decision_id ?? body.decisionId, "decision_id"),
    runId,
    action,
    attemptNo: optionalPositiveInteger(body.attempt_no ?? body.attemptNo, "attempt_no"),
    candidateId: optionalUuid(body.candidate_id ?? body.candidateId, "candidate_id"),
    finalPlaceId: optionalUuid(body.final_place_id ?? body.finalPlaceId, "final_place_id"),
    finalPlace: finalPlaceValue === undefined || finalPlaceValue === null
      ? undefined
      : boundedPrivateObject(finalPlaceValue, "final_place"),
    reasonCode: boundedString(body.reason_code ?? body.reasonCode, 64),
    idempotencyKey: optionalIdempotencyKey(body.idempotency_key ?? body.idempotencyKey),
    editedPayload: boundedPrivateObject(body.edited_payload ?? body.editedPayload, "edited_payload"),
    reason: boundedString(body.reason, 512),
    qualityDelta: qualityDeltaForDecision(action),
    reputationDelta: reputationDeltaForDecision(action),
  };
}

export function analysisReceiptForResult(result: PlaceRecoveryWorkerResult): WorkflowReceiptDraft {
  if (result.technicalFailure || result.resultType === "technical_failure") {
    return receiptDraft(result, {
      receiptType: "analysis",
      verdict: "fail",
      settlement: "credit_refunded",
      creditSettlement: "refunded",
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

  if (decision?.action === "reject") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "fail",
      settlement: "credit_refunded",
      creditSettlement: "refunded",
      evaluatorSummary: "User rejected the place result; refund credit and record a negative quality signal.",
    });
  }

  if (decision?.action === "confirm" || decision?.action === "merge_existing") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "pass",
      settlement: "credit_consumed",
      creditSettlement: "consumed",
      evaluatorSummary: decision.action === "merge_existing"
        ? "User resolved the candidate by linking it to an existing place memory."
        : "User accepted the place candidate.",
    });
  }

  if (decision?.action === "needs_more_evidence" || decision?.action === "investigate_more") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "partial",
      settlement: "manual_review",
      creditSettlement: "pending",
      evaluatorSummary: decision.action === "investigate_more"
        ? "User requested another explicit attempt; the original analysis remains auditable."
        : "User requested more evidence before settlement.",
    });
  }

  if (decision?.action === "edit"
    || decision?.action === "wrong_place"
    || decision?.action === "wrong_city"
    || decision?.action === "wrong_branch"
    || decision?.action === "source_only"
  ) {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "partial",
      settlement: "partial",
      creditSettlement: "partial",
      evaluatorSummary: decision.action === "source_only"
        ? "User kept the source as a clue without confirming a place identity."
        : "User corrected the candidate; preserve the useful recovery and record the inaccuracy.",
    });
  }

  if (result.resultType === "review_candidate" || result.resultType === "confirmed_map_stamp") {
    return decisionReceiptDraft(result, decision, {
      receiptType: "decision",
      verdict: "pass",
      settlement: "credit_consumed",
      creditSettlement: "consumed",
      evaluatorSummary: "Place recovery produced a useful review candidate without pretending it was user-confirmed.",
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
    permissionSnapshot: result.permissionSnapshot,
    toolTraceRefs: result.toolTraceRefs,
    latencyMs: result.latencyMs,
    costEstimate: result.costEstimate,
    failureReason: result.failureReason,
    failureCode: result.failureCode,
    failedStep: result.failedStep,
    retryable: result.retryable,
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
  return "review_candidate";
}

function inputTypeFor(value: unknown, sourceUrl: string | undefined): string {
  const explicit = trimmedString(value);
  if (explicit) return explicit;
  return sourceUrl ? "url" : "text";
}

function sourceTypeFor(value: unknown, sourceUrl: string | undefined): string {
  const explicit = trimmedString(value);
  if (explicit) {
    const normalized = explicit
      .toLowerCase()
      .replace(/[^a-z0-9._-]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 80) || "unknown";
    return [
      "instagram", "x", "url", "text", "note", "screenshot", "video", "file",
      "manual", "google_maps", "youtube", "tiktok", "xiaohongshu", "unknown",
    ].includes(normalized) ? normalized : "other";
  }
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
  if (action === "confirm" || action === "merge_existing") return 1;
  if (["edit", "wrong_place", "wrong_city", "wrong_branch"].includes(action)) return 0.5;
  if (action === "source_only") return 0.25;
  if (action === "reject") return -1;
  return 0;
}

function reputationDeltaForDecision(action: UserDecisionAction): number {
  if (action === "confirm") return 1;
  if (action === "merge_existing") return 0.75;
  if (["edit", "wrong_place", "wrong_city", "wrong_branch"].includes(action)) return 0.25;
  if (action === "source_only") return 0.1;
  if (action === "reject") return -1;
  return 0;
}

function boundedOptionalNumber(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) return undefined;
  return value;
}

function parseEnumField<const T extends readonly string[]>(
  value: unknown,
  allowed: T,
  fallback: T[number],
  field: string,
): T[number] {
  if (value === undefined || value === null || value === "") return fallback;
  if (typeof value === "string" && allowed.includes(value)) return value as T[number];
  throw new WorkflowContractError(`${field} is invalid`);
}

function requiredEnum<const T extends readonly string[]>(value: unknown, allowed: T, field: string): T[number] {
  if (typeof value === "string" && allowed.includes(value)) return value as T[number];
  throw new WorkflowContractError(`${field} is required and must be valid`);
}

function requiredBoolean(value: unknown, field: string): boolean {
  if (typeof value === "boolean") return value;
  throw new WorkflowContractError(`${field} is required and must be boolean`);
}

function optionalPositiveInteger(value: unknown, field: string): number | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value === "number" && Number.isInteger(value) && value > 0 && value <= 1000) return value;
  throw new WorkflowContractError(`${field} must be a positive integer`);
}

function positiveIntegerOrDefault(value: unknown, fallback: number, field: string): number {
  return optionalPositiveInteger(value, field) ?? fallback;
}

function optionalIdempotencyKey(value: unknown): string | undefined {
  const key = boundedString(value, 128);
  if (!key) return undefined;
  if (key.startsWith("legacy:") || key.length < 8 || !/^[A-Za-z0-9._:-]+$/.test(key)) {
    throw new WorkflowContractError("idempotency_key must be 8-128 safe characters");
  }
  return key;
}

function optionalUuid(value: unknown, field: string): string | undefined {
  const id = boundedString(value, 64);
  if (!id) return undefined;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    throw new WorkflowContractError(`${field} must be a UUID`);
  }
  return id;
}

function objectValue(value: unknown): JsonObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : undefined;
}

function normalizeModelProvenance(value: unknown): JsonObject {
  const model = objectValue(value) ?? {};
  return {
    claimedProvider: boundedString(model.claimedProvider ?? model.claimed_provider, 80) ?? "unknown",
    claimedModel: boundedString(model.claimedModel ?? model.claimed_model, 120) ?? "unknown",
    observedProvider: null,
    observedModel: null,
    attestationLevel: "self_claim",
    fallbackUsed: typeof model.fallbackUsed === "boolean"
      ? model.fallbackUsed
      : typeof model.fallback_used === "boolean"
        ? model.fallback_used
        : "unknown",
    usage: safeUsage(model.usage),
    evidenceRefs: boundedStringArray(model.evidenceRefs ?? model.evidence_refs, 16, 256),
  };
}

function boundedStringArray(value: unknown, maxItems: number, maxLength: number): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, maxItems)
    .map((item) => item.slice(0, maxLength));
}

function safeCostEstimate(value: unknown): JsonObject | undefined {
  const estimate = objectValue(value);
  const usd = estimate?.usd;
  if (typeof usd !== "number" || !Number.isFinite(usd) || usd < 0 || usd > 1000) return undefined;
  return { usd };
}

function safeUsage(value: unknown): JsonObject | null {
  const usage = objectValue(value);
  if (!usage) return null;
  const inputTokens = boundedTokenCount(usage.inputTokens ?? usage.input_tokens);
  const outputTokens = boundedTokenCount(usage.outputTokens ?? usage.output_tokens);
  return inputTokens === undefined && outputTokens === undefined ? null : { inputTokens, outputTokens };
}

function boundedTokenCount(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > 10_000_000) return undefined;
  return value;
}

function boundedPrivateObject(value: unknown, field: string): JsonObject {
  if (value === undefined || value === null) return {};
  const object = objectValue(value);
  if (!object) throw new WorkflowContractError(`${field} must be an object`);
  const serialized = JSON.stringify(object);
  if (Buffer.byteLength(serialized, "utf8") > 16 * 1024) {
    throw new WorkflowContractError(`${field} is too large`);
  }
  if (containsSensitiveKey(object)) throw new WorkflowContractError(`${field} contains a forbidden secret field`);
  return object;
}

function containsSensitiveKey(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsSensitiveKey);
  const object = objectValue(value);
  if (!object) return false;
  return Object.entries(object).some(([key, nested]) =>
    /(authorization|cookie|password|secret|token|api[_-]?key|credential)/i.test(key) || containsSensitiveKey(nested)
  );
}

function boundedString(value: unknown, maxLength: number): string | undefined {
  const text = trimmedString(value);
  return text ? text.slice(0, maxLength) : undefined;
}

function trimmedString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}
