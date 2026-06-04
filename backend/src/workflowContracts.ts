export type JsonObject = Record<string, unknown>;

export const placeRecoveryWorkflowId = "save_place_recovery_v0";
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
export const userDecisionActions = ["confirm", "edit", "reject", "needs_more_evidence"] as const;

export type WorkflowStatus = typeof workflowStatuses[number];
export type WorkflowResultType = typeof workflowResultTypes[number];
export type EvidenceTier = typeof evidenceTiers[number];
export type CreditSettlement = typeof creditSettlements[number];
export type ReceiptVerdict = typeof receiptVerdicts[number];
export type ReceiptSettlement = typeof receiptSettlements[number];
export type UserDecisionAction = typeof userDecisionActions[number];

export interface PlaceRecoveryRunCreate {
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
}

export interface UserDecisionInput {
  runId: string;
  action: UserDecisionAction;
  editedPayload: JsonObject;
  reason?: string;
}

export interface WorkflowReceiptDraft {
  verdict: ReceiptVerdict;
  settlement: ReceiptSettlement;
  creditSettlement: CreditSettlement;
  evaluatorSummary: string;
  evidenceRefs: string[];
  candidateRefs: string[];
}

export function normalizePlaceRecoveryRunCreate(body: JsonObject): PlaceRecoveryRunCreate {
  const sourceUrl = normalizedURL(body.source_url ?? body.sourceUrl);
  const sourceType = sourceTypeFor(body.source_type ?? body.sourceType, sourceUrl);
  return {
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
  };
}

export function normalizeUserDecision(body: JsonObject, runId: string): UserDecisionInput {
  return {
    runId,
    action: parseEnum(body.action, userDecisionActions, "needs_more_evidence"),
    editedPayload: objectValue(body.edited_payload ?? body.editedPayload) ?? {},
    reason: trimmedString(body.reason),
  };
}

export function receiptForResult(
  result: PlaceRecoveryWorkerResult,
  decision?: UserDecisionInput,
): WorkflowReceiptDraft {
  if (result.technicalFailure || result.resultType === "technical_failure") {
    return {
      verdict: "refund",
      settlement: "credit_refunded",
      creditSettlement: "refunded",
      evaluatorSummary: "Technical recovery failed before useful evidence could be produced.",
      evidenceRefs: result.evidenceRefs,
      candidateRefs: result.candidateRefs,
    };
  }

  if (decision?.action === "reject" && result.resultType === "confirmed_map_stamp") {
    return {
      verdict: "fail",
      settlement: "credit_refunded",
      creditSettlement: "refunded",
      evaluatorSummary: "User rejected a confirmed place result; refund credit and penalize quality.",
      evidenceRefs: result.evidenceRefs,
      candidateRefs: result.candidateRefs,
    };
  }

  if (decision?.action === "confirm" || result.resultType === "confirmed_map_stamp") {
    return {
      verdict: "pass",
      settlement: "credit_consumed",
      creditSettlement: "consumed",
      evaluatorSummary: "Place recovery produced a confirmed map stamp or user accepted the candidate.",
      evidenceRefs: result.evidenceRefs,
      candidateRefs: result.candidateRefs,
    };
  }

  if (result.resultType === "review_candidate") {
    return {
      verdict: "pass",
      settlement: "credit_consumed",
      creditSettlement: "consumed",
      evaluatorSummary: "Place recovery produced a useful review candidate without pretending it was confirmed.",
      evidenceRefs: result.evidenceRefs,
      candidateRefs: result.candidateRefs,
    };
  }

  return {
    verdict: "partial",
    settlement: "partial",
    creditSettlement: "partial",
    evaluatorSummary: "Source produced useful clues but not enough evidence for a place candidate.",
    evidenceRefs: result.evidenceRefs,
    candidateRefs: result.candidateRefs,
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

function parseEnum<const T extends readonly string[]>(value: unknown, allowed: T, fallback: T[number]): T[number] {
  return typeof value === "string" && allowed.includes(value) ? value as T[number] : fallback;
}

function objectValue(value: unknown): JsonObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : undefined;
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
