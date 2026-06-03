export type JsonObject = Record<string, unknown>;

export const proofLevels = [
  "source_backed",
  "user_confirmed_place",
  "visited_self_reported",
  "friend_verified",
  "receipt_backed",
  "merchant_confirmed",
  "network_reputation",
] as const;

export const claimVisibilities = ["private", "link_shared", "public", "permissioned", "paid"] as const;

export type ClaimProofLevel = typeof proofLevels[number];
export type ClaimVisibility = typeof claimVisibilities[number];

export interface ClaimRecommendationRequest {
  intent?: string;
  constraints?: string[];
  proofLevelMin?: ClaimProofLevel;
  limit?: number;
}

export function normalizePlaceClaimCreate(
  body: JsonObject,
  placeId: string,
  userId: string,
): JsonObject {
  const claimType = trimmedString(body.claim_type ?? body.claimType);
  const claim = trimmedString(body.claim);
  if (!claimType) throw new Error("claim_type is required");
  if (!claim) throw new Error("claim is required");

  return {
    user_id: userId,
    place_id: placeId,
    claim_type: claimType,
    claim,
    agent_usable_summary: trimmedString(body.agent_usable_summary ?? body.agentUsableSummary) ?? claim,
    author_type: trimmedString(body.author_type ?? body.authorType) ?? "self",
    author_public_handle: trimmedString(body.author_public_handle ?? body.publicHandle),
    author_relationship: trimmedString(body.author_relationship ?? body.relationship) ?? "self",
    proof_level: parseProofLevel(body.proof_level ?? body.proofLevel, "source_backed"),
    evidence_refs: stringArray(body.evidence_refs ?? body.evidenceRefs) ?? [],
    visibility: parseVisibility(body.visibility, "private"),
    confidence: boundedNumber(body.confidence, 0.5),
    context: objectValue(body.context) ?? {},
    ratings: objectValue(body.ratings) ?? {},
    observed_at: dateString(body.observed_at ?? body.observedAt),
    expires_or_stale_after: dateString(body.expires_or_stale_after ?? body.expiresOrStaleAfter),
  };
}

export function formatPlaceClaim(row: JsonObject, includePrivateEvidence = false): JsonObject {
  const evidenceRefs = stringArray(row.evidence_refs) ?? [];
  const formatted: JsonObject = {
    claim_id: row.id,
    place_id: row.place_id,
    claim_type: row.claim_type,
    claim: row.claim,
    agent_usable_summary: row.agent_usable_summary,
    author: {
      author_type: row.author_type ?? "self",
      public_handle: row.author_public_handle ?? null,
      relationship: row.author_relationship ?? "self",
    },
    proof_level: row.proof_level,
    confidence: row.confidence,
    visibility: row.visibility,
    context: row.context ?? {},
    ratings: row.ratings ?? {},
    evidence_summary: evidenceSummary(row),
    observed_at: row.observed_at ?? null,
    expires_or_stale_after: row.expires_or_stale_after ?? null,
    created_at: row.created_at,
  };

  if (includePrivateEvidence) formatted.evidence_refs = evidenceRefs;
  return formatted;
}

export function buildTrustSummary(placeId: string, claims: JsonObject[]): JsonObject {
  const visibleClaims = claims.filter((claim) => isCallableClaim(claim));
  const strongestProofLevel = strongestProof(visibleClaims);
  const confidence = roundedConfidence(visibleClaims);
  const warnings = trustWarnings(visibleClaims);
  const lastObservedAt = latestDate(visibleClaims.map((claim) => claim.observed_at));

  return {
    place_id: placeId,
    trust_summary: {
      verified_claim_count: visibleClaims.length,
      receipt_backed_count: countAtLeast(visibleClaims, "receipt_backed"),
      friend_verified_count: countAtLeast(visibleClaims, "friend_verified"),
      last_observed_at: lastObservedAt,
      strongest_proof_level: strongestProofLevel,
      confidence,
      recommended_use: recommendedUse(strongestProofLevel),
      warnings,
    },
    agent_answer: trustAgentAnswer(strongestProofLevel, confidence, warnings),
  };
}

export function normalizeRecommendationRequest(body: JsonObject): ClaimRecommendationRequest {
  return {
    intent: trimmedString(body.intent),
    constraints: stringArray(body.constraints) ?? [],
    proofLevelMin: parseProofLevel(body.proof_level_min ?? body.proofLevelMin, "user_confirmed_place"),
    limit: clampLimit(body.limit),
  };
}

export function recommendPlacesByClaims(
  rows: JsonObject[],
  request: ClaimRecommendationRequest,
): JsonObject {
  const minProof = request.proofLevelMin ?? "user_confirmed_place";
  const grouped = new Map<string, JsonObject[]>();
  let skippedLowProof = 0;
  let skippedStale = 0;

  for (const row of rows) {
    if (proofRank(row.proof_level) < proofRank(minProof)) {
      skippedLowProof += 1;
      continue;
    }
    if (isStale(row)) {
      skippedStale += 1;
      continue;
    }
    const placeId = String(row.place_id);
    const claims = grouped.get(placeId) ?? [];
    claims.push(row);
    grouped.set(placeId, claims);
  }

  const results = [...grouped.entries()]
    .map(([placeId, claims]) => recommendationForPlace(placeId, claims, request))
    .sort((a, b) => numberField(b, "_score") - numberField(a, "_score"))
    .slice(0, request.limit ?? 5)
    .map(({ _score: _score, ...result }) => result);

  return {
    results,
    retrieval_receipt: {
      used: [`${grouped.size} owner-scoped places`, `${rows.length - skippedLowProof - skippedStale} verified claims`],
      skipped: [
        skippedLowProof ? `${skippedLowProof} claims below proof threshold` : null,
        skippedStale ? `${skippedStale} stale claims` : null,
      ].filter(Boolean),
      public_web_used: false,
    },
  };
}

export function parseProofLevel(value: unknown, fallback: ClaimProofLevel): ClaimProofLevel {
  return typeof value === "string" && proofLevels.includes(value as ClaimProofLevel)
    ? value as ClaimProofLevel
    : fallback;
}

export function proofRank(value: unknown): number {
  const proofLevel = parseProofLevel(value, "source_backed");
  return proofLevels.indexOf(proofLevel);
}

export function proofLevelsAtLeast(min: ClaimProofLevel): ClaimProofLevel[] {
  return proofLevels.slice(proofRank(min));
}

function recommendationForPlace(
  placeId: string,
  claims: JsonObject[],
  request: ClaimRecommendationRequest,
): JsonObject {
  const strongestProofLevel = strongestProof(claims);
  const supportingClaims = claims
    .sort((a, b) => claimScore(b, request) - claimScore(a, request))
    .slice(0, 3);
  const warnings = trustWarnings(claims);
  const confidence = roundedConfidence(supportingClaims);
  const name = trimmedString(supportingClaims[0]?.place_name) ?? "Saved place";

  return {
    place_id: placeId,
    name,
    why: whyText(supportingClaims, strongestProofLevel),
    proof_level: strongestProofLevel,
    confidence,
    supporting_claims: supportingClaims.map((claim) => claim.id).filter(Boolean),
    warnings,
    next_actions: ["view_card", "get_trust_summary"],
    _score: supportingClaims.reduce((sum, claim) => sum + claimScore(claim, request), 0),
  };
}

function claimScore(claim: JsonObject, request: ClaimRecommendationRequest): number {
  const tokens = [
    ...(request.intent ?? "").split(/\s+/),
    ...(request.constraints ?? []),
  ].map((token) => token.toLowerCase()).filter(Boolean);
  const haystack = [
    claim.claim_type,
    claim.claim,
    claim.agent_usable_summary,
    JSON.stringify(claim.context ?? {}),
    JSON.stringify(claim.ratings ?? {}),
  ].join(" ").toLowerCase();
  const textMatches = tokens.filter((token) => haystack.includes(token)).length;
  return proofRank(claim.proof_level) * 2 +
    numberField(claim, "confidence") +
    textMatches * 0.75;
}

function whyText(claims: JsonObject[], strongestProofLevel: ClaimProofLevel): string {
  const types = [...new Set(claims.map((claim) => trimmedString(claim.claim_type)).filter(Boolean))];
  const typeText = types.length ? types.join(", ") : "saved claims";
  return `matches ${typeText}; strongest proof is ${strongestProofLevel}`;
}

function recommendedUse(proofLevel: ClaimProofLevel): string[] {
  if (proofRank(proofLevel) >= proofRank("receipt_backed")) return ["recommend", "cite", "draft_reservation_message"];
  if (proofRank(proofLevel) >= proofRank("user_confirmed_place")) return ["recommend", "cite"];
  return ["keep_as_context"];
}

function trustAgentAnswer(proofLevel: ClaimProofLevel, confidence: number, warnings: string[]): string {
  const warningText = warnings.length ? ` Warnings: ${warnings.join(", ")}.` : "";
  return `Trust level ${proofLevel}, confidence ${confidence.toFixed(2)}.${warningText}`;
}

function trustWarnings(claims: JsonObject[]): string[] {
  const warnings = new Set<string>();
  for (const claim of claims) {
    const text = [
      claim.claim_type,
      claim.claim,
      claim.agent_usable_summary,
      JSON.stringify(claim.context ?? {}),
    ].join(" ").toLowerCase();
    if (text.includes("long_wait") || text.includes("long wait") || text.includes("peak")) {
      warnings.add("long_wait_peak_hours");
    }
    if (isStale(claim)) warnings.add("stale_claim");
  }
  return [...warnings];
}

function evidenceSummary(row: JsonObject): string[] {
  const refs = stringArray(row.evidence_refs) ?? [];
  if (refs.length === 0) return [];
  return refs.map((ref) => {
    if (ref.startsWith("photo_")) return "photo evidence";
    if (ref.startsWith("receipt_")) return "receipt evidence";
    if (ref.startsWith("source_")) return "saved source evidence";
    return "private evidence";
  });
}

function strongestProof(claims: JsonObject[]): ClaimProofLevel {
  return claims.reduce<ClaimProofLevel>((best, claim) => {
    const proofLevel = parseProofLevel(claim.proof_level, "source_backed");
    return proofRank(proofLevel) > proofRank(best) ? proofLevel : best;
  }, "source_backed");
}

function roundedConfidence(claims: JsonObject[]): number {
  if (claims.length === 0) return 0;
  const weighted = claims.reduce((sum, claim) => {
    return sum + (numberField(claim, "confidence") * (proofRank(claim.proof_level) + 1));
  }, 0);
  const weights = claims.reduce((sum, claim) => sum + proofRank(claim.proof_level) + 1, 0);
  return Math.round((weighted / weights) * 100) / 100;
}

function countAtLeast(claims: JsonObject[], proofLevel: ClaimProofLevel): number {
  return claims.filter((claim) => proofRank(claim.proof_level) >= proofRank(proofLevel)).length;
}

function isCallableClaim(claim: JsonObject): boolean {
  return !isStale(claim);
}

function isStale(claim: JsonObject): boolean {
  const expires = dateString(claim.expires_or_stale_after);
  return expires ? new Date(expires).getTime() < Date.now() : false;
}

function latestDate(values: unknown[]): string | null {
  const dates = values
    .map(dateString)
    .filter((value): value is string => Boolean(value))
    .sort();
  return dates.at(-1) ?? null;
}

function parseVisibility(value: unknown, fallback: ClaimVisibility): ClaimVisibility {
  return typeof value === "string" && claimVisibilities.includes(value as ClaimVisibility)
    ? value as ClaimVisibility
    : fallback;
}

function boundedNumber(value: unknown, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(0, Math.min(1, value));
}

function numberField(row: JsonObject, field: string): number {
  const value = row[field];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function clampLimit(value: unknown): number {
  const parsed = typeof value === "number" ? value : 5;
  if (!Number.isFinite(parsed)) return 5;
  return Math.max(1, Math.min(20, Math.trunc(parsed)));
}

function objectValue(value: unknown): JsonObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as JsonObject
    : undefined;
}

function stringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function trimmedString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

function dateString(value: unknown): string | undefined {
  if (value instanceof Date) return value.toISOString().replace(/\.\d{3}Z$/, "Z");
  if (typeof value !== "string") return undefined;
  const time = Date.parse(value);
  return Number.isFinite(time) ? new Date(time).toISOString().replace(/\.\d{3}Z$/, "Z") : undefined;
}
