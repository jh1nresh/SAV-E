import type { JsonObject } from "./placeClaims.js";

type Fetcher = (url: string, init: {
  method: string;
  headers: Record<string, string>;
  body?: string;
}) => Promise<{
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
}>;

export interface MaatPublicWebConfig {
  enabled: boolean;
  apiKey?: string;
  model: string;
  googlePlacesApiKey?: string;
  yelpApiKey?: string;
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

const defaultModel = "gemini-2.5-flash";
const geminiEndpointBase = "https://generativelanguage.googleapis.com/v1beta/models";

export function publicWebConfigFromEnv(env: NodeJS.ProcessEnv = process.env): MaatPublicWebConfig {
  return {
    enabled: env.SAVE_ENABLE_MAAT_PUBLIC_WEB !== "false",
    apiKey: env.GEMINI_API_KEY ?? env.GOOGLE_GEMINI_API_KEY,
    model: env.SAVE_MAAT_GEMINI_MODEL ?? defaultModel,
    googlePlacesApiKey: env.GOOGLE_PLACES_API_KEY,
    yelpApiKey: env.YELP_API_KEY,
  };
}

export async function enrichMaatPlaceAnalysisWithPublicWeb(
  input: MaatPublicWebInput,
  config: MaatPublicWebConfig = publicWebConfigFromEnv(),
): Promise<JsonObject> {
  if (!config.enabled) return withPublicWebReceipt(input.analysis, false, false, "disabled");
  let analysis = await enrichMaatPlaceAnalysisWithStructuredSources(input, config);
  if (!config.apiKey) return withPublicWebReceipt(analysis, false, false, "missing_api_key");

  try {
    const response = await callGemini({ ...input, analysis }, config);
    const candidate = response.candidates?.[0];
    const text = candidate?.content?.parts?.map((part) => part.text ?? "").join("\n").trim() ?? "";
    const details = normalizePublicWebDetails(parseJsonObject(text));
    const sources = groundingSources(candidate).slice(0, 5);

    if (!hasMeaningfulDetails(details)) {
      return withPublicWebReceipt(analysis, false, true, "no_structured_details");
    }

    return mergePublicWebDetails(analysis, details, sources, config.model);
  } catch {
    return withPublicWebReceipt(analysis, false, false, "request_failed");
  }
}

export async function enrichMaatPlaceAnalysisWithStructuredSources(
  input: MaatPublicWebInput,
  config: MaatPublicWebConfig = publicWebConfigFromEnv(),
): Promise<JsonObject> {
  const { details, sources, statuses } = await fetchStructuredSourceDetails(input.place, config);
  if (!hasMeaningfulDetails(details)) {
    return withStructuredSourceReceipt(input.analysis, false, statuses);
  }
  return mergeStructuredSourceDetails(input.analysis, details, sources, statuses);
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

export function mergeStructuredSourceDetails(
  analysis: JsonObject,
  sourceDetails: JsonObject,
  sources: JsonObject[] = [],
  statuses: Record<string, string> = {},
): JsonObject {
  const currentDetails = objectValue(analysis.restaurant_details) ?? {};
  const mergedDetails: JsonObject = {
    ...currentDetails,
    platform_scores: mergePlatformScores(arrayValue(currentDetails.platform_scores), arrayValue(sourceDetails.platform_scores)),
    must_try: mergeDishes(arrayValue(currentDetails.must_try), arrayValue(sourceDetails.must_try)),
    warnings: mergeStrings(arrayValue(currentDetails.warnings), arrayValue(sourceDetails.warnings)),
    critical_reviews: preferArray(currentDetails.critical_reviews, sourceDetails.critical_reviews),
    price_range: currentDetails.price_range ?? sourceDetails.price_range ?? null,
    avg_cost: currentDetails.avg_cost ?? sourceDetails.avg_cost ?? null,
    best_for: mergeStrings(arrayValue(currentDetails.best_for), arrayValue(sourceDetails.best_for)).slice(0, 5),
    cuisine: currentDetails.cuisine ?? sourceDetails.cuisine ?? null,
    ambiance: currentDetails.ambiance ?? sourceDetails.ambiance ?? null,
    service_rating: currentDetails.service_rating ?? sourceDetails.service_rating ?? null,
    reservation_tips: currentDetails.reservation_tips ?? sourceDetails.reservation_tips ?? null,
    parking: currentDetails.parking ?? sourceDetails.parking ?? null,
    evidence_gaps: evidenceGapsAfterMerge(currentDetails, sourceDetails),
  };

  return {
    ...analysis,
    restaurant_details: mergedDetails,
    structured_source_sources: sources,
    analysis_receipt: {
      ...(objectValue(analysis.analysis_receipt) ?? {}),
      input_scope: "selected_place_plus_structured_sources",
      structured_source_used: true,
      structured_source_status: "used",
      google_places_status: statuses.google_places ?? "not_configured",
      yelp_status: statuses.yelp ?? "not_configured",
      structured_source_count: sources.length,
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

function withStructuredSourceReceipt(
  analysis: JsonObject,
  used: boolean,
  statuses: Record<string, string>,
): JsonObject {
  return {
    ...analysis,
    analysis_receipt: {
      ...(objectValue(analysis.analysis_receipt) ?? {}),
      structured_source_used: used,
      structured_source_status: used ? "used" : "not_used",
      google_places_status: statuses.google_places ?? "not_configured",
      yelp_status: statuses.yelp ?? "not_configured",
      raw_private_evidence_included: false,
    },
  };
}

interface StructuredSourceFetchResult {
  details: JsonObject;
  sources: JsonObject[];
  statuses: Record<string, string>;
}

async function fetchStructuredSourceDetails(place: JsonObject, config: MaatPublicWebConfig): Promise<StructuredSourceFetchResult> {
  const google = await fetchGooglePlacesStructuredDetails(place, config);
  const yelp = await fetchYelpStructuredDetails(place, config);
  return {
    details: mergeStructuredPayloads(google.details, yelp.details),
    sources: [...google.sources, ...yelp.sources].slice(0, 5),
    statuses: {
      google_places: google.status,
      yelp: yelp.status,
    },
  };
}

async function fetchGooglePlacesStructuredDetails(
  place: JsonObject,
  config: MaatPublicWebConfig,
): Promise<{ details: JsonObject; sources: JsonObject[]; status: string }> {
  if (!config.googlePlacesApiKey) return { details: {}, sources: [], status: "missing_api_key" };
  const fetcher = config.fetcher ?? fetch;
  const fieldMask = [
    "id",
    "displayName",
    "formattedAddress",
    "googleMapsUri",
    "websiteUri",
    "rating",
    "userRatingCount",
    "priceLevel",
    "primaryType",
    "currentOpeningHours",
    "regularOpeningHours",
    "location",
    "parkingOptions",
    "reservable",
    "servesBreakfast",
    "servesLunch",
    "servesDinner",
    "takeout",
    "delivery",
    "dineIn",
    "businessStatus",
    "editorialSummary",
  ].join(",");

  try {
    const googlePlaceId = clippedString(place.google_place_id ?? place.googlePlaceId, 180);
    const headers = {
      "content-type": "application/json",
      "x-goog-api-key": config.googlePlacesApiKey,
      "x-goog-fieldmask": googlePlaceId ? fieldMask : fieldMask.split(",").map((field) => `places.${field}`).join(","),
    };
    const response = googlePlaceId
      ? await fetcher(`https://places.googleapis.com/v1/places/${encodeURIComponent(googlePlaceId)}`, {
        method: "GET",
        headers,
      })
      : await fetcher("https://places.googleapis.com/v1/places:searchText", {
        method: "POST",
        headers,
        body: JSON.stringify(googlePlacesSearchBody(place)),
      });

    if (!response.ok) return { details: {}, sources: [], status: `request_failed_${response.status}` };
    const payload = objectValue(await response.json());
    const searchPlace = googlePlaceId ? undefined : objectValue(arrayValue(payload?.places)[0]);
    const searchedPlaceId = clippedString(searchPlace?.id, 180);
    const googlePlace = googlePlaceId
      ? payload
      : await fetchGooglePlaceDetailsById(searchedPlaceId, fieldMask, config, fetcher) ?? searchPlace;
    if (!googlePlace) return { details: {}, sources: [], status: "not_found" };
    const details = normalizePublicWebDetails(googlePlaceToRestaurantDetails(googlePlace));
    const sources = googlePlaceSource(googlePlace);
    return { details, sources, status: hasMeaningfulDetails(details) ? "used" : "no_structured_details" };
  } catch {
    return { details: {}, sources: [], status: "request_failed" };
  }
}

async function fetchGooglePlaceDetailsById(
  googlePlaceId: string | undefined,
  fieldMask: string,
  config: MaatPublicWebConfig,
  fetcher: Fetcher,
): Promise<JsonObject | undefined> {
  if (!googlePlaceId || !config.googlePlacesApiKey) return undefined;
  try {
    const response = await fetcher(`https://places.googleapis.com/v1/places/${encodeURIComponent(googlePlaceId)}`, {
      method: "GET",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": config.googlePlacesApiKey,
        "x-goog-fieldmask": fieldMask,
      },
    });
    return response.ok ? objectValue(await response.json()) : undefined;
  } catch {
    return undefined;
  }
}

async function fetchYelpStructuredDetails(
  place: JsonObject,
  config: MaatPublicWebConfig,
): Promise<{ details: JsonObject; sources: JsonObject[]; status: string }> {
  if (!config.yelpApiKey) return { details: {}, sources: [], status: "missing_api_key" };
  const name = clippedString(place.name, 160);
  const location = clippedString(place.address ?? place.city, 220);
  if (!name || !location) return { details: {}, sources: [], status: "missing_place_identity" };
  const fetcher = config.fetcher ?? fetch;
  const headers = {
    authorization: `Bearer ${config.yelpApiKey}`,
    accept: "application/json",
  };

  try {
    const searchUrl = new URL("https://api.yelp.com/v3/businesses/search");
    searchUrl.searchParams.set("term", name);
    searchUrl.searchParams.set("location", location);
    searchUrl.searchParams.set("limit", "1");
    const searchResponse = await fetcher(searchUrl.toString(), { method: "GET", headers });
    if (!searchResponse.ok) return { details: {}, sources: [], status: `request_failed_${searchResponse.status}` };
    const searchPayload = objectValue(await searchResponse.json());
    const business = objectValue(arrayValue(searchPayload?.businesses)[0]);
    const businessId = clippedString(business?.id, 160);
    if (!business || !businessId) return { details: {}, sources: [], status: "not_found" };

    const [detailsResponse, reviewsResponse] = await Promise.all([
      fetcher(`https://api.yelp.com/v3/businesses/${encodeURIComponent(businessId)}`, { method: "GET", headers }),
      fetcher(`https://api.yelp.com/v3/businesses/${encodeURIComponent(businessId)}/reviews`, { method: "GET", headers }),
    ]);
    const detailsPayload = (detailsResponse.ok ? objectValue(await detailsResponse.json()) : undefined) ?? business;
    const reviewsPayload = reviewsResponse.ok ? objectValue(await reviewsResponse.json()) : {};
    const details = normalizePublicWebDetails(yelpBusinessToRestaurantDetails(detailsPayload, reviewsPayload));
    const sources = yelpBusinessSource(detailsPayload);
    return { details, sources, status: hasMeaningfulDetails(details) ? "used" : "no_structured_details" };
  } catch {
    return { details: {}, sources: [], status: "request_failed" };
  }
}

function googlePlacesTextQuery(place: JsonObject): string {
  return [
    clippedString(place.name, 160),
    clippedString(place.address, 220),
    clippedString(place.city, 120),
  ].filter(Boolean).join(" ");
}

function googlePlacesSearchBody(place: JsonObject): JsonObject {
  const locationBias = googlePlacesLocationBias(place);
  return {
    textQuery: googlePlacesTextQuery(place),
    languageCode: "zh-TW",
    regionCode: clippedString(place.country_code ?? place.countryCode, 2),
    maxResultCount: 1,
    ...(locationBias ? { locationBias } : {}),
  };
}

function googlePlacesLocationBias(place: JsonObject): JsonObject | undefined {
  const latitude = numberValue(place.latitude ?? place.lat);
  const longitude = numberValue(place.longitude ?? place.lng);
  if (latitude === undefined || longitude === undefined) return undefined;
  return {
    circle: {
      center: { latitude, longitude },
      radius: 1000,
    },
  };
}

function googlePlaceToRestaurantDetails(place: JsonObject): JsonObject {
  const parking = googleParkingText(objectValue(place.parkingOptions));
  const bestFor = [
    place.dineIn === true ? "內用" : undefined,
    place.takeout === true ? "外帶" : undefined,
    place.delivery === true ? "外送" : undefined,
    place.servesBreakfast === true ? "早餐" : undefined,
    place.servesLunch === true ? "午餐" : undefined,
    place.servesDinner === true ? "晚餐" : undefined,
  ].filter(Boolean);
  const rating = numberValue(place.rating);
  return {
    platform_scores: rating === undefined ? [] : [{
      platform: "Google",
      score: rating,
      source: "google_places_api",
    }],
    warnings: place.businessStatus && place.businessStatus !== "OPERATIONAL"
      ? [`Google Places 狀態：${clippedString(place.businessStatus, 60)}`]
      : [],
    price_range: googlePriceLevelToSymbol(place.priceLevel),
    best_for: bestFor,
    cuisine: readablePlaceType(place.primaryType),
    ambiance: clippedString(objectValue(place.editorialSummary)?.text, 240),
    reservation_tips: place.reservable === true ? "Google Places 顯示可訂位；尖峰時段建議先預約。" : undefined,
    parking,
  };
}

function yelpBusinessToRestaurantDetails(business: JsonObject, reviewsPayload: JsonObject | undefined): JsonObject {
  const categories = arrayValue(business.categories)
    .map((category) => clippedString(objectValue(category)?.title, 80))
    .filter(Boolean);
  const reviews = arrayValue(reviewsPayload?.reviews)
    .map((review) => objectValue(review))
    .filter((review): review is JsonObject => Boolean(review));
  return {
    platform_scores: numberValue(business.rating) === undefined ? [] : [{
      platform: "Yelp",
      score: numberValue(business.rating),
      source: "yelp_api",
    }],
    warnings: business.is_closed === true ? ["Yelp 顯示此店可能已停止營業。"] : [],
    critical_reviews: reviews
      .filter((review) => {
        const rating = numberValue(review.rating);
        return rating !== undefined && rating <= 3;
      })
      .map((review) => ({
        issue: clippedString(review.text, 240),
        source: "Yelp",
        frequency: "review excerpt",
      })),
    price_range: clippedString(business.price, 40),
    cuisine: categories.length ? categories.slice(0, 3).join(" / ") : undefined,
  };
}

function googlePlaceSource(place: JsonObject): JsonObject[] {
  const url = publicHttpUrl(place.googleMapsUri ?? place.websiteUri);
  return url ? [{ title: "Google Places", url }] : [];
}

function yelpBusinessSource(business: JsonObject): JsonObject[] {
  const url = publicHttpUrl(business.url);
  return url ? [{ title: "Yelp", url }] : [];
}

function mergeStructuredPayloads(left: JsonObject, right: JsonObject): JsonObject {
  return {
    platform_scores: mergePlatformScores(arrayValue(left.platform_scores), arrayValue(right.platform_scores)),
    must_try: mergeDishes(arrayValue(left.must_try), arrayValue(right.must_try)),
    warnings: mergeStrings(arrayValue(left.warnings), arrayValue(right.warnings)),
    critical_reviews: preferArray(left.critical_reviews, right.critical_reviews),
    price_range: left.price_range ?? right.price_range ?? null,
    avg_cost: left.avg_cost ?? right.avg_cost ?? null,
    best_for: mergeStrings(arrayValue(left.best_for), arrayValue(right.best_for)).slice(0, 5),
    cuisine: left.cuisine ?? right.cuisine ?? null,
    ambiance: left.ambiance ?? right.ambiance ?? null,
    service_rating: left.service_rating ?? right.service_rating ?? null,
    reservation_tips: left.reservation_tips ?? right.reservation_tips ?? null,
    parking: left.parking ?? right.parking ?? null,
  };
}

function googlePriceLevelToSymbol(value: unknown): string | undefined {
  switch (clippedString(value, 60)) {
    case "PRICE_LEVEL_INEXPENSIVE":
      return "$";
    case "PRICE_LEVEL_MODERATE":
      return "$$";
    case "PRICE_LEVEL_EXPENSIVE":
      return "$$$";
    case "PRICE_LEVEL_VERY_EXPENSIVE":
      return "$$$$";
    default:
      return undefined;
  }
}

function googleParkingText(parkingOptions: JsonObject | undefined): string | undefined {
  if (!parkingOptions) return undefined;
  const labels = [
    parkingOptions.freeParkingLot === true ? "免費停車場" : undefined,
    parkingOptions.paidParkingLot === true ? "付費停車場" : undefined,
    parkingOptions.freeStreetParking === true ? "路邊免費停車" : undefined,
    parkingOptions.paidStreetParking === true ? "路邊付費停車" : undefined,
    parkingOptions.valetParking === true ? "代客泊車" : undefined,
    parkingOptions.freeGarageParking === true ? "免費室內停車" : undefined,
    parkingOptions.paidGarageParking === true ? "付費室內停車" : undefined,
  ].filter(Boolean);
  return labels.length ? `Google Places 顯示：${labels.join("、")}。` : undefined;
}

function readablePlaceType(value: unknown): string | undefined {
  const type = clippedString(value, 80);
  return type ? type.replace(/_/g, " ") : undefined;
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

  return `You are Ma'at, a strict restaurant research agent for Savvy.

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

Visible Savvy claim summaries:
${JSON.stringify(visibleClaims)}

Structured source details already found:
${JSON.stringify(objectValue(input.analysis.restaurant_details) ?? {})}

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
    recommended_dishes: incoming.must_try,
    "missing parking evidence": incoming.parking,
    parking: incoming.parking,
    "missing reservation evidence": incoming.reservation_tips,
    reservation_tips: incoming.reservation_tips,
    "missing price evidence": incoming.price_range ?? incoming.avg_cost,
    cost: incoming.price_range ?? incoming.avg_cost,
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
