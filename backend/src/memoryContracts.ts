export const preferenceStatuses = ["proposed", "active", "corrected", "removed"] as const;
export const preferenceSources = ["explicit", "inferred"] as const;
export const preferencePolarities = ["like", "dislike", "constraint"] as const;
export const outcomeLabelSources = ["explicit_user", "evaluator", "deterministic_outcome"] as const;
export const recommendationOutcomeLabels = [
  "correct_place",
  "wrong_place",
  "useful_recommendation",
  "irrelevant_recommendation",
  "missing_evidence",
  "hallucinated_fact",
  "preference_mismatch",
  "stale_place_or_menu",
  "action_overclaim",
] as const;

type JsonBody = Record<string, unknown>;

export class MemoryContractError extends Error {}

export function normalizePreferenceCreate(body: JsonBody): JsonBody {
  const source = oneOf(body.source, preferenceSources, "source");
  const status = oneOf(body.status ?? (source === "explicit" ? "active" : "proposed"), preferenceStatuses, "status");
  if (source === "inferred" && status === "active") {
    throw new MemoryContractError("inferred preferences must be proposed before activation");
  }
  const evidenceRefs = opaqueRefs(body.evidence_refs, "evidence_refs");
  return {
    preference_type: boundedString(body.preference_type, "preference_type", 64),
    normalized_value: normalizedValue(body.normalized_value),
    context: normalizedValue(body.context ?? "general", 120),
    polarity: oneOf(body.polarity, preferencePolarities, "polarity"),
    source,
    evidence_refs: evidenceRefs,
    evidence_count: boundedInteger(body.evidence_count ?? evidenceRefs.length, "evidence_count", 0, 10_000),
    confidence: boundedNumber(body.confidence ?? (source === "explicit" ? 1 : 0.5), "confidence", 0, 1),
    status,
  };
}

export function normalizePreferencePatch(body: JsonBody): JsonBody {
  const output: JsonBody = {};
  if (body.status !== undefined) output.status = oneOf(body.status, preferenceStatuses, "status");
  if (body.normalized_value !== undefined) output.normalized_value = normalizedValue(body.normalized_value);
  if (body.context !== undefined) output.context = normalizedValue(body.context, 120);
  if (body.polarity !== undefined) output.polarity = oneOf(body.polarity, preferencePolarities, "polarity");
  if (Object.keys(output).length === 0) throw new MemoryContractError("no supported preference fields");
  return output;
}

export function normalizeRecommendationOutcome(body: JsonBody): JsonBody {
  const labels = stringArray(body.labels, "labels").map((label) =>
    oneOf(label, recommendationOutcomeLabels, "labels"),
  );
  if (labels.length === 0) throw new MemoryContractError("labels must not be empty");
  return {
    recommendation_id: boundedString(body.recommendation_id, "recommendation_id", 160),
    labels: [...new Set(labels)],
    label_source: oneOf(body.label_source, outcomeLabelSources, "label_source"),
    candidate_ids: uuidArray(body.candidate_ids, "candidate_ids"),
    place_ids: uuidArray(body.place_ids, "place_ids"),
    memory_refs: opaqueRefs(body.memory_refs, "memory_refs"),
    evidence_refs: opaqueRefs(body.evidence_refs, "evidence_refs"),
    correction_class: optionalBoundedString(body.correction_class, "correction_class", 80),
    receipt_ref: optionalOpaqueRef(body.receipt_ref, "receipt_ref"),
    model_version: optionalBoundedString(body.model_version, "model_version", 120),
    retrieval_version: optionalBoundedString(body.retrieval_version, "retrieval_version", 120),
  };
}

function normalizedValue(value: unknown, max = 240): string {
  return boundedString(value, "normalized value", max).toLowerCase().replace(/\s+/g, " ");
}

function boundedString(value: unknown, field: string, max: number): string {
  if (typeof value !== "string" || !value.trim()) throw new MemoryContractError(`${field} is required`);
  const trimmed = value.trim();
  if (trimmed.length > max) throw new MemoryContractError(`${field} is too long`);
  return trimmed;
}

function optionalBoundedString(value: unknown, field: string, max: number): string | null {
  if (value === undefined || value === null || value === "") return null;
  return boundedString(value, field, max);
}

function oneOf<T extends string>(value: unknown, allowed: readonly T[], field: string): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    throw new MemoryContractError(`${field} is invalid`);
  }
  return value as T;
}

function stringArray(value: unknown, field: string): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    throw new MemoryContractError(`${field} must be an array of strings`);
  }
  return value as string[];
}

function uuidArray(value: unknown, field: string): string[] {
  return stringArray(value, field).map((item) => {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(item)) {
      throw new MemoryContractError(`${field} contains an invalid UUID`);
    }
    return item;
  });
}

function opaqueRefs(value: unknown, field: string): string[] {
  return stringArray(value, field).map((item) => optionalOpaqueRef(item, field) as string);
}

function optionalOpaqueRef(value: unknown, field: string): string | null {
  if (value === undefined || value === null || value === "") return null;
  const ref = boundedString(value, field, 180);
  if (/https?:\/\//i.test(ref) || /\+?\d[\d\s().-]{7,}/.test(ref)) {
    throw new MemoryContractError(`${field} must be an opaque identifier, not a URL or phone number`);
  }
  return ref;
}

function boundedInteger(value: unknown, field: string, min: number, max: number): number {
  if (!Number.isInteger(value) || (value as number) < min || (value as number) > max) {
    throw new MemoryContractError(`${field} is invalid`);
  }
  return value as number;
}

function boundedNumber(value: unknown, field: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) {
    throw new MemoryContractError(`${field} is invalid`);
  }
  return value;
}
