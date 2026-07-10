import { createHash, randomUUID } from "node:crypto";

export type JsonObject = Record<string, unknown>;

export const receiptProduct = "save";
export const recommendationAnalysisReceiptType = "recommendation_analysis";
export const recommendationAnalysisCapability = "place_claim_recommendation";

export const evaluatorVerdicts = ["pass", "partial", "fail", "manual_review"] as const;
export const settlementStates = ["not_settled", "pending", "settled", "refunded", "manual_review"] as const;

export type EvaluatorVerdict = typeof evaluatorVerdicts[number];
export type SettlementState = typeof settlementStates[number];

export interface RecommendationAnalysisPublicSummary extends JsonObject {
  summary: string;
  capability: typeof recommendationAnalysisCapability;
  result_count: number;
  saved_result_count: number;
  public_result_count: number;
  proof_level_min: string | null;
  public_web_used: boolean;
}

export interface AgentShackReceiptEnvelope extends JsonObject {
  product: typeof receiptProduct;
  receipt_type: typeof recommendationAnalysisReceiptType;
  user_id: string;
  agent_id: string;
  capability: typeof recommendationAnalysisCapability;
  input_hash: string;
  output_hash: string;
  private_payload_ref: string;
  public_summary: RecommendationAnalysisPublicSummary;
  preference_signals: string[];
  evaluator_verdict: EvaluatorVerdict;
  settlement_state: SettlementState;
  created_at: string;
}

export interface RecommendationAnalysisReceiptDraft extends JsonObject {
  id: string;
  user_id: string;
  product: typeof receiptProduct;
  receipt_type: typeof recommendationAnalysisReceiptType;
  agent_id: string;
  capability: typeof recommendationAnalysisCapability;
  input_hash: string;
  output_hash: string;
  private_payload_ref: string;
  private_payload: JsonObject;
  public_summary: RecommendationAnalysisPublicSummary;
  preference_signals: string[];
  evaluator_verdict: EvaluatorVerdict;
  settlement_state: SettlementState;
  created_at: string;
}

export interface RecommendationAnalysisReceiptInput {
  userId: string;
  agentId?: string;
  request: JsonObject;
  output: JsonObject;
  createdAt?: string;
}

export interface BoundedRecommendationAnalysisReceiptPayload {
  agentId?: string;
  request: JsonObject;
  output: JsonObject;
}

export class RecommendationAnalysisReceiptPayloadError extends Error {}

export const recommendationAnalysisReceiptPayloadMaxBytes = 64 * 1024;
const recommendationAnalysisReceiptMaxResults = 50;
const recommendationAnalysisReceiptMaxSignals = 64;
const recommendationAnalysisReceiptMaxConstraints = 64;
const recommendationAnalysisReceiptMaxStringLength = 2048;

export function buildRecommendationAnalysisReceiptDraft(
  input: RecommendationAnalysisReceiptInput,
): RecommendationAnalysisReceiptDraft {
  const id = randomUUID();
  const createdAt = input.createdAt ?? new Date().toISOString();
  const publicSummary = publicSummaryFor(input.request, input.output);
  const preferenceSignals = preferenceSignalsFor(input.request, input.output);
  const evaluatorVerdict = evaluatorVerdictFor(input.output);

  return {
    id,
    user_id: input.userId,
    product: receiptProduct,
    receipt_type: recommendationAnalysisReceiptType,
    agent_id: cleanText(input.agentId) ?? "save-ios",
    capability: recommendationAnalysisCapability,
    input_hash: sha256CanonicalJson(input.request),
    output_hash: sha256CanonicalJson(input.output),
    private_payload_ref: `save://receipts/recommendation_analysis/${id}`,
    private_payload: {
      receipt_type: recommendationAnalysisReceiptType,
      request: input.request,
      output: input.output,
    },
    public_summary: publicSummary,
    preference_signals: preferenceSignals,
    evaluator_verdict: evaluatorVerdict,
    settlement_state: "not_settled",
    created_at: createdAt,
  };
}

export function normalizeRecommendationAnalysisReceiptPayload(
  body: JsonObject,
): BoundedRecommendationAnalysisReceiptPayload {
  if (Buffer.byteLength(JSON.stringify(body), "utf8") > recommendationAnalysisReceiptPayloadMaxBytes) {
    throw new RecommendationAnalysisReceiptPayloadError("Recommendation analysis receipt payload is too large");
  }

  assertBoundedStrings(body);
  const request = optionalJsonObject(body.request, "request");
  const output = optionalJsonObject(body.output, "output");
  assertArrayLength(output.results, recommendationAnalysisReceiptMaxResults, "output.results");
  assertArrayLength(output.preference_signals, recommendationAnalysisReceiptMaxSignals, "output.preference_signals");
  assertArrayLength(request.constraints, recommendationAnalysisReceiptMaxConstraints, "request.constraints");

  return {
    agentId: cleanText(body.agent_id),
    request,
    output,
  };
}

export function envelopeForRecommendationAnalysisReceipt(row: JsonObject): AgentShackReceiptEnvelope {
  return {
    product: receiptProduct,
    receipt_type: recommendationAnalysisReceiptType,
    user_id: requiredString(row.user_id, "user_id"),
    agent_id: requiredString(row.agent_id, "agent_id"),
    capability: recommendationAnalysisCapability,
    input_hash: requiredString(row.input_hash, "input_hash"),
    output_hash: requiredString(row.output_hash, "output_hash"),
    private_payload_ref: requiredString(row.private_payload_ref, "private_payload_ref"),
    public_summary: asPublicSummary(row.public_summary),
    preference_signals: stringArray(row.preference_signals),
    evaluator_verdict: parseEnum(row.evaluator_verdict, evaluatorVerdicts, "manual_review"),
    settlement_state: parseEnum(row.settlement_state, settlementStates, "manual_review"),
    created_at: requiredString(row.created_at, "created_at"),
  };
}

export function sha256CanonicalJson(value: unknown): string {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

export function sha256ImmutableWorkflowReceipt(receipt: JsonObject): string {
  const {
    id: _databaseId,
    is_current: _isCurrent,
    anchor_status: _anchorStatus,
    privacy_validated: _privacyValidated,
    private_url: _privateUrl,
    receipt_hash: _receiptHash,
    created_at: _createdAt,
    ...immutable
  } = receipt;
  return sha256CanonicalJson({
    ...immutable,
    quality_delta: canonicalNumeric(immutable.quality_delta),
    reputation_delta: canonicalNumeric(immutable.reputation_delta),
  });
}

function canonicalNumeric(value: unknown): unknown {
  if (typeof value !== "string" || value.trim() === "") return value;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : value;
}

function publicSummaryFor(request: JsonObject, output: JsonObject): RecommendationAnalysisPublicSummary {
  const results = Array.isArray(output.results) ? output.results : [];
  const receipt = objectValue(output.retrieval_receipt) ?? {};
  const savedResultCount = countResultsBySource(results, "saved");
  const publicResultCount = countResultsBySource(results, "public");

  return {
    summary: "SAV-E analyzed owner-scoped saved places and kept public discovery separate.",
    capability: recommendationAnalysisCapability,
    result_count: results.length,
    saved_result_count: savedResultCount ?? results.length,
    public_result_count: publicResultCount ?? 0,
    proof_level_min: cleanText(request.proof_level_min ?? request.proofLevelMin) ?? null,
    public_web_used: receipt.public_web_used === true || output.public_fallback_used === true,
  };
}

function preferenceSignalsFor(request: JsonObject, output: JsonObject): string[] {
  const text = [
    cleanText(request.intent),
    ...stringArray(request.constraints),
  ].filter(Boolean).join(" ");
  const signals = new Set<string>();

  addSignal(signals, text, "coffee", /coffee|cafe|café|咖啡|咖啡廳/i);
  addSignal(signals, text, "milk_tea", /boba|milk tea|bubble tea|奶茶|珍奶/i);
  addSignal(signals, text, "restaurant", /restaurant|dinner|lunch|food|餐廳|晚餐|午餐|吃/i);
  addSignal(signals, text, "brunch", /brunch|早餐|早午餐/i);
  addSignal(signals, text, "dessert", /dessert|甜點|蛋糕/i);
  addSignal(signals, text, "bar", /bar|cocktail|wine|酒吧|調酒|葡萄酒/i);
  addSignal(signals, text, "saved_memory", /saved|memory|存過|記憶/i);
  addSignal(signals, text, "nearby", /nearby|near me|附近/i);

  for (const signal of stringArray(output.preference_signals).map(safePreferenceSignal).filter(isString)) {
    signals.add(signal);
  }
  const proofSignal = `proof_level:${safeProofLevel(request.proof_level_min ?? request.proofLevelMin)}`;
  return [
    ...[...signals].filter((signal) => !signal.startsWith("proof_level:")).slice(0, 11),
    proofSignal,
  ];
}

function countResultsBySource(results: unknown[], source: "saved" | "public"): number | undefined {
  let matched = 0;
  let sawTypedResult = false;
  for (const result of results) {
    const object = objectValue(result);
    const type = cleanText(object?.object_type ?? object?.objectType);
    if (!type) continue;
    sawTypedResult = true;
    if (source === "saved" && ["saved_place", "tried_memory", "review", "trip_stop"].includes(type)) matched += 1;
    if (source === "public" && ["map_visible_unsaved_place", "new_recommendation"].includes(type)) matched += 1;
  }
  return sawTypedResult ? matched : undefined;
}

function safePreferenceSignal(value: string): string | undefined {
  const signal = cleanText(value)?.toLowerCase();
  if (!signal || signal.length > 80) return undefined;
  if (safeExactPreferenceSignals.has(signal)) return signal;

  const parts = signal.split(":");
  if (parts.length !== 2) return undefined;
  const [prefix, suffix] = parts;
  if (!prefix || !suffix) return undefined;
  return safePreferenceSignalPrefixes[prefix]?.has(suffix) === true ? signal : undefined;
}

const safeExactPreferenceSignals = new Set([
  "coffee",
  "milk_tea",
  "restaurant",
  "brunch",
  "dessert",
  "bar",
  "saved_memory",
  "visited_memory",
  "nearby",
]);

const safePreferenceSignalPrefixes: Record<string, Set<string>> = {
  category: new Set(["food", "cafe", "bar", "attraction", "stay", "shopping"]),
  source: new Set(["saved_memory", "visited_memory", "review_candidate", "public_quality"]),
  rating: new Set(["high", "positive"]),
};

const safeProofLevels = new Set([
  "source_backed",
  "user_confirmed_place",
  "visited_self_reported",
  "friend_verified",
  "receipt_backed",
  "merchant_confirmed",
  "network_reputation",
]);

function safeProofLevel(value: unknown): string {
  const proofLevel = cleanText(value);
  return proofLevel && safeProofLevels.has(proofLevel) ? proofLevel : "user_confirmed_place";
}

function isString(value: string | undefined): value is string {
  return typeof value === "string";
}

function evaluatorVerdictFor(output: JsonObject): EvaluatorVerdict {
  const results = Array.isArray(output.results) ? output.results : [];
  return results.length > 0 ? "pass" : "partial";
}

function addSignal(signals: Set<string>, text: string, signal: string, pattern: RegExp): void {
  if (pattern.test(text)) signals.add(signal);
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(canonicalValue(value));
}

function canonicalValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (!value || typeof value !== "object") return value;

  return Object.fromEntries(
    Object.entries(value as JsonObject)
      .filter(([, nested]) => nested !== undefined)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, nested]) => [key, canonicalValue(nested)]),
  );
}

function asPublicSummary(value: unknown): RecommendationAnalysisPublicSummary {
  const object = objectValue(value) ?? {};
  return {
    summary: cleanText(object.summary) ?? "SAV-E analyzed a recommendation request.",
    capability: recommendationAnalysisCapability,
    result_count: numberValue(object.result_count),
    saved_result_count: numberValue(object.saved_result_count),
    public_result_count: numberValue(object.public_result_count),
    proof_level_min: cleanText(object.proof_level_min) ?? null,
    public_web_used: object.public_web_used === true,
  };
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0;
}

function objectValue(value: unknown): JsonObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : undefined;
}

function optionalJsonObject(value: unknown, field: string): JsonObject {
  if (value === undefined || value === null) return {};
  const object = objectValue(value);
  if (!object) throw new RecommendationAnalysisReceiptPayloadError(`${field} must be a JSON object`);
  return object;
}

function assertArrayLength(value: unknown, max: number, field: string): void {
  if (value === undefined || value === null) return;
  if (!Array.isArray(value)) throw new RecommendationAnalysisReceiptPayloadError(`${field} must be an array`);
  if (value.length > max) throw new RecommendationAnalysisReceiptPayloadError(`${field} has too many items`);
}

function assertBoundedStrings(value: unknown): void {
  if (typeof value === "string") {
    if (value.length > recommendationAnalysisReceiptMaxStringLength) {
      throw new RecommendationAnalysisReceiptPayloadError("Recommendation analysis receipt string is too long");
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) assertBoundedStrings(item);
    return;
  }
  const object = objectValue(value);
  if (!object) return;
  for (const item of Object.values(object)) assertBoundedStrings(item);
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 12);
}

function cleanText(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim().replace(/\s+/g, " ");
  return trimmed || undefined;
}

function requiredString(value: unknown, field: string): string {
  const text = cleanText(value);
  if (!text) throw new Error(`Missing receipt envelope field: ${field}`);
  return text;
}

function parseEnum<const T extends readonly string[]>(value: unknown, allowed: T, fallback: T[number]): T[number] {
  return typeof value === "string" && allowed.includes(value as T[number]) ? value as T[number] : fallback;
}
