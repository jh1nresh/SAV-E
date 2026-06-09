import type { JsonObject } from "./placeClaims.js";

type Fetcher = (url: string, init: {
  method: string;
  headers: Record<string, string>;
  body: string;
}) => Promise<{
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
}>;

export interface MaatPublicWebConfig {
  enabled: boolean;
  apiKey?: string;
  model: string;
  fetcher?: Fetcher;
}

export interface MaatPublicWebInput {
  place: JsonObject;
  claims: JsonObject[];
  analysis: JsonObject;
  includePrivateEvidence?: boolean;
}

interface GeminiCandidate {
  content?: {
    parts?: Array<{ text?: string }>;
  };
  groundingMetadata?: {
    groundingChunks?: Array<{
      web?: {
        title?: string;
        uri?: string;
      };
    }>;
  };
}

interface GeminiResponse {
  candidates?: GeminiCandidate[];
}

const defaultModel = "gemini-3.5-flash";
const geminiEndpointBase = "https://generativelanguage.googleapis.com/v1beta/models";

export function publicWebConfigFromEnv(env: NodeJS.ProcessEnv = process.env): MaatPublicWebConfig {
  return {
    enabled: env.SAVE_ENABLE_MAAT_PUBLIC_WEB !== "false",
    apiKey: env.GEMINI_API_KEY ?? env.GOOGLE_GEMINI_API_KEY,
    model: env.SAVE_MAAT_GEMINI_MODEL ?? defaultModel,
  };
}

export async function enrichMaatPlaceAnalysisWithPublicWeb(
  input: MaatPublicWebInput,
  config: MaatPublicWebConfig = publicWebConfigFromEnv(),
): Promise<JsonObject> {
  if (!config.enabled) return withPublicWebReceipt(input.analysis, false, false, "disabled");
  if (!config.apiKey) return withPublicWebReceipt(input.analysis, false, false, "missing_api_key");

  try {
    const response = await callGemini(input, config);
    const candidate = response.candidates?.[0];
    const text = candidate?.content?.parts?.map((part) => part.text ?? "").join("\n").trim() ?? "";
    const details = normalizePublicWebDetails(parseJsonObject(text));
    const sources = groundingSources(candidate).slice(0, 5);

    if (!hasMeaningfulDetails(details)) {
      return withPublicWebReceipt(input.analysis, false, true, "no_structured_details");
    }

    return mergePublicWebDetails(input.analysis, details, sources, config.model);
  } catch {
    return withPublicWebReceipt(input.analysis, false, false, "request_failed");
  }
}

export function mergePublicWebDetails(
  analysis: JsonObject,
  publicDetails: JsonObject,
  sources: JsonObject[] = [],
  model = defaultModel,
): JsonObject {
  const currentDetails = objectValue(analysis.restaurant_details) ?? {};
  const mergedDetails: JsonObject = {
    ...currentDetails,
    platform_scores: mergePlatformScores(arrayValue(currentDetails.platform_scores), arrayValue(publicDetails.platform_scores)),
    must_try: mergeDishes(arrayValue(currentDetails.must_try), arrayValue(publicDetails.must_try)),
    warnings: mergeStrings(arrayValue(currentDetails.warnings), arrayValue(publicDetails.warnings)),
    critical_reviews: preferArray(currentDetails.critical_reviews, publicDetails.critical_reviews),
    price_range: currentDetails.price_range ?? publicDetails.price_range ?? null,
    avg_cost: currentDetails.avg_cost ?? publicDetails.avg_cost ?? null,
    best_for: mergeStrings(arrayValue(currentDetails.best_for), arrayValue(publicDetails.best_for)).slice(0, 5),
    cuisine: currentDetails.cuisine ?? publicDetails.cuisine ?? null,
    ambiance: currentDetails.ambiance ?? publicDetails.ambiance ?? null,
    service_rating: currentDetails.service_rating ?? publicDetails.service_rating ?? null,
    reservation_tips: currentDetails.reservation_tips ?? publicDetails.reservation_tips ?? null,
    parking: currentDetails.parking ?? publicDetails.parking ?? null,
    evidence_gaps: evidenceGapsAfterMerge(currentDetails, publicDetails),
  };

  return {
    ...analysis,
    restaurant_details: mergedDetails,
    public_web_sources: sources,
    analysis_receipt: {
      ...(objectValue(analysis.analysis_receipt) ?? {}),
      input_scope: "selected_place_plus_public_web",
      public_web_used: true,
      model_used: true,
      model_name: model,
      public_web_status: "used",
      public_web_source_count: sources.length,
      raw_private_evidence_included: false,
    },
  };
}

function withPublicWebReceipt(
  analysis: JsonObject,
  publicWebUsed: boolean,
  modelUsed: boolean,
  status: string,
): JsonObject {
  return {
    ...analysis,
    analysis_receipt: {
      ...(objectValue(analysis.analysis_receipt) ?? {}),
      public_web_used: publicWebUsed,
      model_used: modelUsed,
      public_web_status: status,
      raw_private_evidence_included: false,
    },
  };
}

async function callGemini(input: MaatPublicWebInput, config: MaatPublicWebConfig): Promise<GeminiResponse> {
  const fetcher = config.fetcher ?? fetch;
  const url = `${geminiEndpointBase}/${encodeURIComponent(config.model)}:generateContent?key=${encodeURIComponent(config.apiKey ?? "")}`;
  const response = await fetcher(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: publicWebPrompt(input) }] }],
      tools: [{ googleSearch: {} }],
      generationConfig: {
        temperature: 0.2,
        responseMimeType: "application/json",
      },
    }),
  });
  if (!response.ok) throw new Error(`Gemini request failed: ${response.status}`);
  return response.json() as Promise<GeminiResponse>;
}

function publicWebPrompt(input: MaatPublicWebInput): string {
  const place = input.place;
  const visibleClaims = input.claims
    .filter((claim) => input.includePrivateEvidence || claim.visibility !== "private")
    .slice(0, 5)
    .map((claim) => ({
      type: clippedString(claim.claim_type, 80),
      summary: clippedString(claim.agent_usable_summary ?? claim.claim, 220),
      proof_level: clippedString(claim.proof_level, 80),
      visibility: clippedString(claim.visibility, 40),
    }));

  return `You are Ma'at, a strict restaurant research agent for SAV-E.

Search the public web for this exact place and return JSON only. Use English and Chinese queries when helpful.

Rules:
- Do not invent platform scores, review counts, dish names, prices, parking, or complaints.
- If you cannot verify the exact same place, return empty arrays/nulls and put "place_not_verified" in warnings.
- Treat this place object as the identity anchor. Do not analyze another similarly named place.
- Do not include private user evidence, personal notes, or raw source text in the answer.
- Keep all user-facing text in Traditional Chinese.

Place:
${JSON.stringify({
    name: clippedString(place.name, 160),
    address: clippedString(place.address, 220),
    city: clippedString(place.city, 120),
    category: clippedString(place.category, 120),
    google_place_id: clippedString(place.google_place_id, 160),
    google_rating: place.google_rating ?? null,
    price_range: clippedString(place.price_range, 40),
    source_url: clippedString(place.source_url, 240),
  })}

Visible SAV-E claim summaries:
${JSON.stringify(visibleClaims)}

Return this JSON shape:
{
  "platform_scores": [{"platform": "Yelp", "score": 4.1, "source": "public web"}],
  "must_try": [{"name": "dish", "description": "why it is recommended", "price": "$15", "evidence": "public web"}],
  "warnings": ["verified limitation or practical warning"],
  "critical_reviews": [{"issue": "common negative review", "source": "Yelp", "frequency": "common"}],
  "price_range": "$$",
  "avg_cost": "$25-40/人",
  "best_for": ["約會", "朋友聚餐"],
  "cuisine": "台灣料理",
  "ambiance": "short description",
  "service_rating": "short description",
  "reservation_tips": "short description",
  "parking": "short description"
}`;
}

function normalizePublicWebDetails(value: JsonObject | undefined): JsonObject {
  if (!value) return {};
  return {
    platform_scores: arrayValue(value.platform_scores ?? value.platformScores).map(normalizePlatformScore).filter(Boolean),
    must_try: arrayValue(value.must_try ?? value.mustTry).map(normalizeDish).filter(Boolean),
    warnings: stringArray(value.warnings).slice(0, 6),
    critical_reviews: arrayValue(value.critical_reviews ?? value.criticalReviews).map(normalizeCriticalReview).filter(Boolean),
    price_range: clippedString(value.price_range ?? value.priceRange, 40),
    avg_cost: clippedString(value.avg_cost ?? value.avgCost, 80),
    best_for: stringArray(value.best_for ?? value.bestFor).slice(0, 5),
    cuisine: clippedString(value.cuisine, 120),
    ambiance: clippedString(value.ambiance, 240),
    service_rating: clippedString(value.service_rating ?? value.serviceRating, 240),
    reservation_tips: clippedString(value.reservation_tips ?? value.reservationTips, 240),
    parking: clippedString(value.parking, 240),
  };
}

function normalizePlatformScore(value: unknown): JsonObject | undefined {
  const item = objectValue(value);
  if (!item) return undefined;
  const platform = clippedString(item.platform, 80);
  const score = numberValue(item.score);
  if (!platform || score === undefined || score < 0 || score > 5) return undefined;
  return {
    platform,
    score,
    source: clippedString(item.source, 160) ?? "public web",
  };
}

function normalizeDish(value: unknown): JsonObject | undefined {
  const item = objectValue(value);
  const name = clippedString(item?.name, 120);
  if (!item || !name) return undefined;
  return {
    name,
    description: clippedString(item.description, 240),
    price: clippedString(item.price, 60),
    evidence: clippedString(item.evidence, 160) ?? "public web",
  };
}

function normalizeCriticalReview(value: unknown): JsonObject | undefined {
  const item = objectValue(value);
  const issue = clippedString(item?.issue, 240);
  if (!item || !issue) return undefined;
  return {
    issue,
    source: clippedString(item.source, 120),
    frequency: clippedString(item.frequency, 80),
  };
}

function parseJsonObject(text: string): JsonObject | undefined {
  try {
    return objectValue(JSON.parse(text));
  } catch {
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) return undefined;
    try {
      return objectValue(JSON.parse(match[0]));
    } catch {
      return undefined;
    }
  }
}

function groundingSources(candidate: GeminiCandidate | undefined): JsonObject[] {
  return (candidate?.groundingMetadata?.groundingChunks ?? [])
    .map((chunk) => ({
      title: clippedString(chunk.web?.title, 160),
      url: publicHttpUrl(chunk.web?.uri),
    }))
    .filter((source) => source.title || source.url);
}

function hasMeaningfulDetails(details: JsonObject): boolean {
  return [
    details.platform_scores,
    details.must_try,
    details.critical_reviews,
    details.warnings,
    details.avg_cost,
    details.parking,
    details.reservation_tips,
    details.ambiance,
  ].some((value) => Array.isArray(value) ? value.length > 0 : Boolean(value));
}

function mergePlatformScores(existing: unknown[], incoming: unknown[]): JsonObject[] {
  const byPlatform = new Map<string, JsonObject>();
  for (const item of [...incoming, ...existing]) {
    const score = normalizePlatformScore(item);
    if (!score) continue;
    byPlatform.set(String(score.platform).toLowerCase(), score);
  }
  return [...byPlatform.values()].slice(0, 5);
}

function preferArray(existing: unknown, incoming: unknown): unknown[] {
  const existingArray = arrayValue(existing);
  return existingArray.length ? existingArray : arrayValue(incoming).slice(0, 5);
}

function mergeDishes(existing: unknown[], incoming: unknown[]): JsonObject[] {
  const dishes = new Map<string, JsonObject>();
  for (const value of [...existing, ...incoming]) {
    const dish = normalizeDish(value);
    if (!dish) continue;
    const key = String(dish.name).toLowerCase();
    const previous = dishes.get(key);
    dishes.set(key, {
      ...previous,
      ...dish,
      description: previous?.description ?? dish.description,
      price: previous?.price ?? dish.price,
      evidence: previous?.evidence ?? dish.evidence,
    });
  }
  return [...dishes.values()].slice(0, 5);
}

function mergeStrings(existing: unknown[], incoming: unknown[]): string[] {
  const values = new Map<string, string>();
  for (const value of [...existing, ...incoming]) {
    const text = clippedString(value, 160);
    if (text) values.set(text.toLowerCase(), text);
  }
  return [...values.values()];
}

function evidenceGapsAfterMerge(existing: JsonObject, incoming: JsonObject): string[] {
  const missing = new Set(stringArray(existing.evidence_gaps));
  const fieldByGap: Record<string, unknown> = {
    "missing dish evidence": incoming.must_try,
    "missing parking evidence": incoming.parking,
    "missing reservation evidence": incoming.reservation_tips,
    "missing price evidence": incoming.price_range ?? incoming.avg_cost,
  };
  for (const [gap, value] of Object.entries(fieldByGap)) {
    if (Array.isArray(value) ? value.length > 0 : Boolean(value)) missing.delete(gap);
  }
  return [...missing];
}

function objectValue(value: unknown): JsonObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : undefined;
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function stringArray(value: unknown): string[] {
  return arrayValue(value).map((item) => clippedString(item, 160)).filter((item): item is string => Boolean(item));
}

function numberValue(value: unknown): number | undefined {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function clippedString(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== "string" && typeof value !== "number") return undefined;
  const text = String(value).trim().replace(/\s+/g, " ");
  if (!text) return undefined;
  return text.slice(0, maxLength);
}

function publicHttpUrl(value: unknown): string | undefined {
  const url = clippedString(value, 500);
  if (!url) return undefined;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "http:" || parsed.protocol === "https:" ? parsed.toString() : undefined;
  } catch {
    return undefined;
  }
}
