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

export interface MaatPlaceAnalysisRequest {
  includePrivateEvidence?: boolean;
  maxCitedClaims?: number;
}

export const usageReceiptActions = [
  "recommended_to_user",
  "cited",
  "saved_to_vault",
  "adapted_collection",
] as const;

export const usageReceiptOutcomes = ["accepted", "rejected", "unknown"] as const;

export type UsageReceiptAction = typeof usageReceiptActions[number];
export type UsageReceiptOutcome = typeof usageReceiptOutcomes[number];

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
  const reputation = reputationSummary(visibleClaims);

  return {
    place_id: placeId,
    trust_summary: {
      verified_claim_count: visibleClaims.length,
      receipt_backed_count: countAtLeast(visibleClaims, "receipt_backed"),
      friend_verified_count: countAtLeast(visibleClaims, "friend_verified"),
      last_observed_at: lastObservedAt,
      strongest_proof_level: strongestProofLevel,
      confidence,
      reputation,
      recommended_use: recommendedUse(strongestProofLevel),
      warnings,
    },
    agent_answer: trustAgentAnswer(strongestProofLevel, confidence, warnings),
  };
}

export function buildPublicPlaceCard(place: JsonObject, claims: JsonObject[]): JsonObject {
  const publicClaimRows = claims
    .filter((claim) => claim.visibility === "public" || claim.visibility === "link_shared");
  const publicClaims = publicClaimRows.map((claim) => formatPlaceClaim(claim));
  const trustSummary = buildTrustSummary(String(place.id), publicClaimRows).trust_summary;

  return {
    card_id: place.id,
    title: place.name,
    place: {
      id: place.id,
      name: place.name,
      city: place.city ?? "",
      address: place.address ?? "",
      canonical_refs: {
        google_place_id: place.google_place_id ?? null,
      },
      category: place.category ?? null,
    },
    summary: publicSummary(place, publicClaims),
    public_claims: publicClaims,
    trust_summary: trustSummary,
    agent_actions: ["cite_card", "save_to_vault", "adapt_to_user_context"],
    attribution: {
      author_handle: place.owner_handle ?? null,
      source_policy: "raw sources private; proof levels summarized",
    },
  };
}

export function buildMaatPlaceAnalysis(
  place: JsonObject,
  claims: JsonObject[],
  request: MaatPlaceAnalysisRequest = {},
): JsonObject {
  const scopedClaims = claims
    .filter((claim) => request.includePrivateEvidence || claim.visibility !== "private")
    .filter((claim) => !isStale(claim));
  const maxCitedClaims = Math.max(1, Math.min(5, Math.trunc(request.maxCitedClaims ?? 3)));
  const citedClaims = scopedClaims
    .sort((a, b) => analysisEvidenceScore(b) - analysisEvidenceScore(a))
    .slice(0, maxCitedClaims);
  const placeEvidence = placeEvidenceLines(place);
  const citedEvidence = [
    ...placeEvidence,
    ...citedClaims.map(claimEvidenceLine),
  ].filter(Boolean).slice(0, 8);
  const strongestProofLevel = citedClaims.length ? strongestProof(citedClaims) : "source_backed";
  const confidence = citedClaims.length ? roundedConfidence(citedClaims) : (placeEvidence.length ? 0.42 : 0);
  const warnings = analysisWarnings(place, citedClaims, scopedClaims, claims, request);
  const status = citedEvidence.length >= 2 || citedClaims.length > 0 ? "ready" : "not_enough_evidence";
  const title = status === "ready"
    ? `Ma'at analysis for ${trimmedString(place.name) ?? "selected place"}`
    : "Not enough evidence for Ma'at analysis";
  const summary = status === "ready"
    ? analysisSummary(place, citedClaims, strongestProofLevel)
    : "SAV-E has the selected place, but not enough saved notes, claims, receipts, or source evidence to analyze without guessing.";
  const restaurantDetails = buildRestaurantDetails(place, citedClaims, scopedClaims, warnings);

  return {
    place_id: place.id,
    capability: "maat_place_analysis_v0",
    status,
    title,
    summary,
    verdict: status === "ready" ? verdictForProof(strongestProofLevel, confidence) : "insufficient_evidence",
    confidence,
    strongest_proof_level: strongestProofLevel,
    cited_claim_ids: citedClaims.map((claim) => claim.id).filter(Boolean),
    cited_evidence: citedEvidence,
    warnings,
    next_actions: nextAnalysisActions(status, strongestProofLevel, warnings),
    restaurant_details: restaurantDetails,
    analysis_receipt: {
      input_scope: "selected_place_only",
      place_id: place.id,
      claim_count: scopedClaims.length,
      cited_claim_count: citedClaims.length,
      includes_private_claim_summaries: Boolean(request.includePrivateEvidence),
      raw_private_evidence_included: false,
      whole_map_used: false,
      public_web_used: false,
      model_used: false,
    },
  };
}

export function normalizeUsageReceiptCreate(body: JsonObject): JsonObject {
  const claimId = trimmedString(body.claim_id ?? body.claimId);
  if (!claimId) throw new Error("claim_id is required");

  return {
    claim_id: claimId,
    consumer_agent_id: trimmedString(body.consumer_agent_id ?? body.consumerAgentId) ?? "unknown_agent",
    action: parseUsageAction(body.action),
    outcome: parseUsageOutcome(body.outcome),
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
    textMatches * 0.75 +
    reputationBoost(claim);
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

function publicSummary(place: JsonObject, publicClaims: JsonObject[]): string {
  const best = publicClaims[0];
  const claim = trimmedString(best?.agent_usable_summary) ?? trimmedString(best?.claim);
  if (claim) return claim;
  return `${trimmedString(place.name) ?? "This place"} has public SAV-E claims with proof labels.`;
}

function reputationSummary(claims: JsonObject[]): JsonObject {
  const usageCount = claims.reduce((sum, claim) => sum + numberField(claim, "usage_count"), 0);
  const acceptedCount = claims.reduce((sum, claim) => sum + numberField(claim, "accepted_count"), 0);
  return {
    usage_count: usageCount,
    accepted_count: acceptedCount,
    score: usageCount > 0 ? Math.round((acceptedCount / usageCount) * 100) / 100 : 0,
  };
}

function reputationBoost(claim: JsonObject): number {
  const usageCount = numberField(claim, "usage_count");
  const acceptedCount = numberField(claim, "accepted_count");
  if (usageCount <= 0) return 0;
  const acceptanceRate = acceptedCount / usageCount;
  return Math.min(1.5, Math.log1p(usageCount) * 0.15 + acceptanceRate * 0.35);
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

function analysisEvidenceScore(claim: JsonObject): number {
  return proofRank(claim.proof_level) * 2 + numberField(claim, "confidence") + reputationBoost(claim);
}

function placeEvidenceLines(place: JsonObject): string[] {
  const lines = [
    evidenceLine("place name", place.name),
    evidenceLine("address", place.address),
    evidenceLine("saved note", place.note),
    evidenceLine("saved source", place.source_url),
    evidenceLine("google place id", place.google_place_id),
    typeof place.google_rating === "number" ? `google rating: ${place.google_rating}` : undefined,
    evidenceLine("price range", place.price_range),
  ];
  return lines.filter((line): line is string => Boolean(line));
}

function evidenceLine(label: string, value: unknown): string | undefined {
  const text = trimmedString(value);
  return text ? `${label}: ${text}` : undefined;
}

function claimEvidenceLine(claim: JsonObject): string {
  const claimType = trimmedString(claim.claim_type) ?? "claim";
  const summary = trimmedString(claim.agent_usable_summary) ?? trimmedString(claim.claim) ?? "saved claim";
  const proofLevel = parseProofLevel(claim.proof_level, "source_backed");
  return `${claimType}: ${summary} (${proofLevel})`;
}

function analysisWarnings(
  place: JsonObject,
  citedClaims: JsonObject[],
  scopedClaims: JsonObject[],
  allClaims: JsonObject[],
  request: MaatPlaceAnalysisRequest,
): string[] {
  const warnings = new Set<string>(trustWarnings(citedClaims));
  if (!trimmedString(place.source_url) && !trimmedString(place.note) && scopedClaims.length === 0) {
    warnings.add("thin_place_evidence");
  }
  if (!request.includePrivateEvidence && allClaims.some((claim) => claim.visibility === "private")) {
    warnings.add("private_claims_excluded");
  }
  if (citedClaims.length === 0) warnings.add("no_verified_claims_cited");
  return [...warnings];
}

function analysisSummary(place: JsonObject, citedClaims: JsonObject[], strongestProofLevel: ClaimProofLevel): string {
  const name = trimmedString(place.name) ?? "This place";
  const bestClaim = citedClaims[0];
  const bestSummary = trimmedString(bestClaim?.agent_usable_summary) ?? trimmedString(bestClaim?.claim);
  if (bestSummary) return `${name}: ${bestSummary}. Strongest proof is ${strongestProofLevel}.`;
  const note = trimmedString(place.note);
  if (note) return `${name}: ${note}. Analysis is based on selected-place evidence only.`;
  return `${name} has enough selected-place metadata for a lightweight Ma'at analysis, but no verified claims were cited.`;
}

function buildRestaurantDetails(
  place: JsonObject,
  citedClaims: JsonObject[],
  scopedClaims: JsonObject[],
  warnings: string[],
): JsonObject {
  const evidenceTexts = detailEvidenceTexts(place, citedClaims.length ? citedClaims : scopedClaims);
  const mustTry = mustTryItems(place, evidenceTexts);
  const parking = firstMatchingEvidence(evidenceTexts, [
    "parking",
    "park ",
    "valet",
    "garage",
    "停車",
    "車位",
    "代客泊車",
  ]);
  const reservationTips = firstMatchingEvidence(evidenceTexts, [
    "reservation",
    "reserve",
    "book",
    "waitlist",
    "訂位",
    "預約",
  ]);
  const ambiance = firstMatchingEvidence(evidenceTexts, [
    "ambiance",
    "atmosphere",
    "vibe",
    "cozy",
    "date",
    "view",
    "環境",
    "氣氛",
    "氛圍",
    "約會",
    "景觀",
  ]);
  const serviceRating = firstMatchingEvidence(evidenceTexts, [
    "service",
    "staff",
    "server",
    "服務",
    "店員",
  ]);
  const criticalReviews = criticalReviewItems(evidenceTexts, warnings);
  const platformScores = platformScoreItems(place);
  const priceRange = trimmedString(place.price_range);
  const avgCost = averageCost(evidenceTexts);
  const bestFor = bestForTags(place, evidenceTexts);
  const evidenceGaps = detailEvidenceGaps({
    mustTry,
    parking,
    reservationTips,
    priceRange,
    avgCost,
  });

  return {
    platform_scores: platformScores,
    must_try: mustTry,
    warnings: warnings.map((warning) => warning.replace(/_/g, " ")),
    critical_reviews: criticalReviews,
    price_range: priceRange ?? null,
    avg_cost: avgCost,
    best_for: bestFor,
    cuisine: cuisineLabel(place),
    ambiance: ambiance ?? null,
    service_rating: serviceRating ?? null,
    reservation_tips: reservationTips ?? null,
    parking: parking ?? null,
    evidence_gaps: evidenceGaps,
  };
}

function detailEvidenceTexts(place: JsonObject, claims: JsonObject[]): string[] {
  return [
    trimmedString(place.note),
    ...(stringArray(place.extracted_dishes) ?? []),
    ...claims.flatMap((claim) => [
      trimmedString(claim.claim_type),
      trimmedString(claim.claim),
      trimmedString(claim.agent_usable_summary),
      JSON.stringify(claim.context ?? {}),
      JSON.stringify(claim.ratings ?? {}),
    ]),
  ].filter((value): value is string => Boolean(value && value.trim()));
}

function mustTryItems(place: JsonObject, evidenceTexts: string[]): JsonObject[] {
  const items = new Map<string, JsonObject>();
  for (const dish of stringArray(place.extracted_dishes) ?? []) {
    const price = priceNearDish(dish, evidenceTexts);
    items.set(dish.toLowerCase(), {
      name: dish,
      price,
      evidence: "saved place dish",
    });
  }

  for (const text of evidenceTexts) {
    const match = text.match(/(?:recommended item|must try|order|必點|推薦(?:餐點)?)[：:\s-]+([^。.\n,，;；]+)(?:\s+((?:NT\$?|TWD|\$)\s?\d+(?:[.,]\d+)?))?/i);
    if (!match) continue;
    const name = cleanDetailText(match[1]);
    if (!name) continue;
    const key = name.toLowerCase();
    if (!items.has(key)) {
      items.set(key, {
        name,
        price: match[2]?.replace(/\s+/g, "") ?? priceNearDish(name, evidenceTexts),
        evidence: "saved claim",
      });
    }
  }

  return [...items.values()].slice(0, 5);
}

function platformScoreItems(place: JsonObject): JsonObject[] {
  const scores: JsonObject[] = [];
  if (typeof place.google_rating === "number") {
    scores.push({
      platform: "Google",
      score: place.google_rating,
      source: "google_place_metadata",
    });
  }
  if (typeof place.rating === "number" && place.rating !== place.google_rating) {
    scores.push({
      platform: "Saved rating",
      score: place.rating,
      source: "save_place_metadata",
    });
  }
  return scores;
}

function criticalReviewItems(evidenceTexts: string[], warnings: string[]): JsonObject[] {
  const items: JsonObject[] = [];
  const waitText = firstMatchingEvidence(evidenceTexts, [
    "long wait",
    "wait",
    "line",
    "queue",
    "排隊",
    "候位",
    "等很久",
  ]);
  if (waitText || warnings.includes("long_wait_peak_hours")) {
    items.push({
      issue: waitText ?? "Peak-hour waits are mentioned in saved evidence",
      source: "SAV-E evidence",
      frequency: "mentioned",
    });
  }
  const negativeText = firstMatchingEvidence(evidenceTexts, [
    "complaint",
    "warning",
    "bad",
    "avoid",
    "差評",
    "缺點",
    "雷",
    "不推",
  ]);
  if (negativeText && !items.some((item) => item.issue === negativeText)) {
    items.push({
      issue: negativeText,
      source: "SAV-E evidence",
      frequency: "mentioned",
    });
  }
  return items.slice(0, 3);
}

function firstMatchingEvidence(texts: string[], needles: string[]): string | null {
  for (const text of texts) {
    const normalized = text.toLowerCase();
    if (needles.some((needle) => normalized.includes(needle.toLowerCase()))) {
      return cleanDetailText(text);
    }
  }
  return null;
}

function averageCost(texts: string[]): string | null {
  for (const text of texts) {
    const match = text.match(/(?:(?:avg|average) cost|per person|person|人均|平均(?:消費)?)[：:\s-]*((?:NT\$?|TWD|\$|¥|RMB)?\s?\d+(?:[.,]\d+)?(?:\s?[-~]\s?(?:NT\$?|TWD|\$|¥|RMB)?\s?\d+(?:[.,]\d+)?)?)/i);
    if (match?.[1]) return match[1].replace(/\s+/g, " ").trim();
  }
  return null;
}

function priceNearDish(dish: string, texts: string[]): string | null {
  const escaped = dish.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`${escaped}[^\\n。.,，;；]{0,30}((?:NT\\$?|TWD|\\$|¥|RMB)\\s?\\d+(?:[.,]\\d+)?)`, "i");
  for (const text of texts) {
    const match = text.match(pattern);
    if (match?.[1]) return match[1].replace(/\s+/g, "");
  }
  return null;
}

function bestForTags(place: JsonObject, texts: string[]): string[] {
  const joined = [
    trimmedString(place.category),
    ...texts,
  ].join(" ").toLowerCase();
  const tags = new Set<string>();
  if (/(date|約會)/.test(joined)) tags.add("date night");
  if (/(family|kids|家庭|親子)/.test(joined)) tags.add("family");
  if (/(friend|group|聚餐|朋友)/.test(joined)) tags.add("friends");
  if (/(coffee|cafe|work|laptop|咖啡|工作)/.test(joined)) tags.add("coffee/work");
  if (/(quick|solo|lunch|午餐|一個人)/.test(joined)) tags.add("quick solo stop");
  return [...tags].slice(0, 4);
}

function detailEvidenceGaps(values: {
  mustTry: JsonObject[];
  parking: string | null;
  reservationTips: string | null;
  priceRange?: string;
  avgCost: string | null;
}): string[] {
  const gaps: string[] = [];
  if (values.mustTry.length === 0) gaps.push("recommended_dishes");
  if (!values.parking) gaps.push("parking");
  if (!values.reservationTips) gaps.push("reservation_tips");
  if (!values.priceRange && !values.avgCost) gaps.push("cost");
  return gaps;
}

function cuisineLabel(place: JsonObject): string | null {
  const category = trimmedString(place.category);
  if (!category) return null;
  if (category === "food") return "restaurant";
  return category;
}

function cleanDetailText(text: string): string {
  return text
    .replace(/\s+/g, " ")
    .replace(/^highlight:\s*/i, "")
    .trim()
    .slice(0, 180);
}

function verdictForProof(proofLevel: ClaimProofLevel, confidence: number): string {
  if (proofRank(proofLevel) >= proofRank("receipt_backed") && confidence >= 0.7) return "strong_evidence";
  if (proofRank(proofLevel) >= proofRank("user_confirmed_place")) return "usable_with_caveats";
  return "context_only";
}

function nextAnalysisActions(status: string, proofLevel: ClaimProofLevel, warnings: string[]): string[] {
  if (status !== "ready") return ["add_note", "confirm_place", "attach_source_or_receipt"];
  const actions = ["cite_analysis", "open_place_detail"];
  if (proofRank(proofLevel) < proofRank("user_confirmed_place")) actions.push("confirm_place_before_recommending");
  if (warnings.includes("private_claims_excluded")) actions.push("rerun_private_view_if_owner_approved");
  return actions;
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

function parseUsageAction(value: unknown): UsageReceiptAction {
  return typeof value === "string" && usageReceiptActions.includes(value as UsageReceiptAction)
    ? value as UsageReceiptAction
    : "cited";
}

function parseUsageOutcome(value: unknown): UsageReceiptOutcome {
  return typeof value === "string" && usageReceiptOutcomes.includes(value as UsageReceiptOutcome)
    ? value as UsageReceiptOutcome
    : "unknown";
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
