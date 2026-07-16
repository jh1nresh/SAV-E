import { createHash } from "node:crypto";
import { lookup } from "node:dns/promises";
import { isIP } from "node:net";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export type SourceSearchInput = {
  sourceUrl?: string | null;
  rawText?: string | null;
  title?: string | null;
  suggestedSearchQueries?: string[];
  maxQueries?: number;
};

export type SourceSearchResult = {
  query: string;
  title: string;
  url?: string;
  snippet?: string;
};

export type SourceSearchCandidate = {
  name: string;
  address: string;
  latitude?: number;
  longitude?: number;
  placeId?: string;
  evidence: string[];
  confidence: number;
  missingInfo: string[];
};

export type SourceRecoveryReceipt = {
  input: "social_url" | "web_url" | "text";
  capabilityLevel: "metadata_enrichment" | "public_search_recovery" | "media_evidence_recovery";
  found: string[];
  tried: string[];
  missing: string[];
  output: "review_candidate" | "source_only_clue" | "diagnostic_only";
  nextBestClue: string;
};

export type SourceMediaEvidence = {
  kind: "thumbnail" | "video" | "video_keyframe";
  url: string;
  contentType?: string;
  byteLength?: number;
  sha256?: string;
  frameSecond?: number;
  text?: string;
  textSource?: "ocr" | "asr";
};

export type SourceResolutionStatus = "resolved" | "blocked_login" | "expired" | "opaque_unresolved";

export type SourceResolution = {
  originalURL: string;
  resolvedURL: string;
  redirectChain: string[];
  canonicalContentID?: string;
  status: SourceResolutionStatus;
  title?: string;
  caption?: string;
  thumbnailURL?: string;
};

export type ResolvedSourceDocument = {
  html: string;
  resolution: SourceResolution;
};

export type SourceSearchOutput = {
  queries: string[];
  searchResults: SourceSearchResult[];
  candidates: SourceSearchCandidate[];
  mediaEvidence: SourceMediaEvidence[];
  sourceResolution?: SourceResolution;
  errors: string[];
  receipt: SourceRecoveryReceipt;
};

export type SourceMetadata = {
  resolvedURL?: string;
  title?: string;
  description?: string;
  imageURL?: string;
  videoURL?: string;
};

type FetchText = (url: string) => Promise<string>;
type FetchMediaEvidence = (metadata: SourceMetadata) => Promise<SourceMediaEvidence[]>;
type SourceDocumentResolver = (url: string) => Promise<ResolvedSourceDocument>;
type SourceDocumentFetchResult = {
  metadata?: SourceMetadata;
  resolution: SourceResolution;
};
type PlacesCorroborator = (candidate: SourceSearchCandidate) => Promise<PlacesCorroboration | undefined>;
type EvidenceRubricEvaluator = (input: EvidenceRubricInput) => EvidenceRubricVerdict | Promise<EvidenceRubricVerdict>;

export type SourceSearchWorkerOptions = {
  placesCorroborator?: PlacesCorroborator;
  rubricEvaluator?: EvidenceRubricEvaluator;
  sourceDocumentResolver?: SourceDocumentResolver;
};

type PlacesCorroboration = {
  name?: string;
  address?: string;
  latitude?: number;
  longitude?: number;
  placeId?: string;
  confidenceBoost?: number;
  evidence?: string[];
};

type EvidenceRubricInput = {
  sourceMetadata?: SourceMetadata;
  mediaEvidence: SourceMediaEvidence[];
  searchResults: SourceSearchResult[];
  candidate: SourceSearchCandidate;
};

type EvidenceRubricVerdict = {
  confidenceReason: string;
  evidenceTier: "source_only" | "weak" | "likely" | "corroborated";
  missingInfo: string[];
};

const defaultMaxQueries = 4;
const maxResultsPerQuery = 5;
const maxTextFetchBytes = 1_000_000;
const maxMetadataRedirects = 3;
const sourceResolutionCacheTTL = 24 * 60 * 60 * 1_000;
const sourceResolutionCacheLimit = 100;
const sourceResolutionCache = new Map<string, { expiresAt: number; document: ResolvedSourceDocument }>();

export async function runSourceSearchRecovery(
  input: SourceSearchInput,
  fetchText: FetchText = defaultFetchText,
  fetchMediaEvidence: FetchMediaEvidence = defaultFetchMediaEvidence,
  options: SourceSearchWorkerOptions = {},
): Promise<SourceSearchOutput> {
  const errors: string[] = [];
  const sourceDocument = await fetchSourceDocument(
    input.sourceUrl,
    fetchText,
    errors,
    options.sourceDocumentResolver,
  );
  const sourceMetadata = sourceDocument?.metadata;
  const sourceResolution = sourceDocument?.resolution;
  const mediaEvidence = await recoverSourceMediaEvidence(sourceMetadata, fetchMediaEvidence, errors);
  const enrichedInput = inputWithSourceMetadata(input, sourceMetadata, sourceResolution);
  const queries = buildSourceRecoveryQueries(enrichedInput).slice(0, input.maxQueries ?? defaultMaxQueries);
  const searchResults: SourceSearchResult[] = [];

  for (const query of queries) {
    try {
      const html = await fetchText(duckDuckGoHTMLURL(query));
      searchResults.push(...parseDuckDuckGoResults(html, query).slice(0, maxResultsPerQuery));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown search error";
      errors.push(`${query}: ${message}`);
    }
  }

  const candidateDrafts = dedupeCandidates([
    ...candidatesFromSourceMetadata(sourceMetadata),
    ...candidatesFromMediaEvidence(mediaEvidence, sourceMetadata),
    ...candidatesFromSearchResults(searchResults),
  ]);
  const candidates = await finalizeCandidates(
    candidateDrafts,
    {
      sourceMetadata,
      mediaEvidence,
      searchResults,
      placesCorroborator: options.placesCorroborator ?? defaultPlacesCorroborator,
      rubricEvaluator: options.rubricEvaluator ?? defaultEvidenceRubricEvaluator,
    },
    errors,
  );

  return {
    queries,
    searchResults,
    candidates,
    mediaEvidence,
    sourceResolution,
    errors,
    receipt: buildSourceRecoveryReceipt(
      input,
      sourceMetadata,
      sourceResolution,
      queries,
      searchResults,
      candidates,
      mediaEvidence,
      errors,
    ),
  };
}

export function buildSourceRecoveryQueries(input: SourceSearchInput): string[] {
  const queries: string[] = [];
  queries.push(...(input.suggestedSearchQueries ?? []));

  const sourceUrl = input.sourceUrl?.trim();
  const url = sourceUrl ? safeURL(sourceUrl) : undefined;
  const reelId = instagramReelID(url);
  const rawText = cleanText([input.title, input.rawText].filter(Boolean).join(" "));
  const handle = firstSocialHandle(rawText);
  const cityVenue = cityQualifiedVenueClue(rawText);

  if (cityVenue) {
    queries.push(`${cityVenue.name} ${cityVenue.city} 地址`);
    if (handle) queries.push(`${handle} ${cityVenue.name}`);
    queries.push(`${cityVenue.name} 官方 餐廳 訂位`);
  }

  if (reelId) {
    queries.push(`instagram reel ${reelId} place`);
    queries.push(`${reelId} restaurant venue`);
  } else if (url?.host) {
    queries.push(`${url.host} ${url.pathname.split("/").filter(Boolean).at(-1) ?? ""} place`.trim());
  }

  if (handle) queries.push(`@${handle} address`);

  if (rawText) queries.push(`"${rawText.slice(0, 80)}" place`);

  const canonicalURL = canonicalSearchURL(url);
  if (canonicalURL) queries.push(`"${canonicalURL}"`);

  return unique(queries).filter(Boolean).slice(0, defaultMaxQueries);
}

function inputWithSourceMetadata(
  input: SourceSearchInput,
  metadata: SourceMetadata | undefined,
  resolution: SourceResolution | undefined,
): SourceSearchInput {
  if (!metadata && !resolution) return input;
  const metadataText = [metadata?.title, metadata?.description].filter(Boolean).join("\n");
  return {
    ...input,
    sourceUrl: resolution?.resolvedURL ?? metadata?.resolvedURL ?? input.sourceUrl,
    title: [input.title, metadata?.title].filter(Boolean).join(" "),
    rawText: [input.rawText, metadataText].filter(Boolean).join("\n"),
  };
}

export function parseDuckDuckGoResults(html: string, query: string): SourceSearchResult[] {
  const results: SourceSearchResult[] = [];
  const blocks = html.match(/<div[^>]+class="[^"]*result[^"]*"[\s\S]*?(?=<div[^>]+class="[^"]*result[^"]*"|$)/gi) ?? [];

  for (const block of blocks) {
    const linkMatch = block.match(/<a[^>]+class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (!linkMatch) continue;

    const snippetMatch = block.match(/<a[^>]+class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/a>/i) ??
      block.match(/<div[^>]+class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)<\/div>/i);

    const title = cleanText(stripTags(linkMatch[2]));
    if (!title) continue;

    results.push({
      query,
      title,
      url: normalizeDuckDuckGoURL(decodeHTML(linkMatch[1])),
      snippet: snippetMatch ? cleanText(stripTags(snippetMatch[1])) : undefined,
    });
  }

  return results;
}

function candidatesFromSourceMetadata(metadata: SourceMetadata | undefined): SourceSearchCandidate[] {
  if (!metadata) return [];
  const evidenceText = decodedMetadataText(metadata);
  const address = addressFromText(evidenceText);
  if (!address) return [];

  const name = sourceMetadataPlaceName(evidenceText, address);
  if (!name || !isUsableCandidateName(name)) return [];

  return [{
    name,
    address,
    evidence: [
      "Source metadata contains explicit place/address evidence",
      metadata.title ? `Source metadata title: ${cleanText(metadata.title)}` : "",
      metadata.description ? `Source metadata description: ${cleanText(metadata.description)}` : "",
      metadata.resolvedURL ? `Source metadata URL: ${metadata.resolvedURL}` : "",
    ].filter(Boolean),
    confidence: 0.62,
    missingInfo: [
      "Confirm exact address",
      "Verified coordinates",
      "Source metadata-derived candidate; verify before saving",
    ],
  }];
}

function candidatesFromMediaEvidence(
  mediaEvidence: SourceMediaEvidence[],
  metadata: SourceMetadata | undefined,
): SourceSearchCandidate[] {
  const candidates: SourceSearchCandidate[] = [];
  const evidenceText = mediaEvidence
    .map((item) => item.text)
    .filter(Boolean)
    .join("\n");
  if (!evidenceText) return candidates;

  const address = addressFromText(evidenceText);
  const name = mediaEvidencePlaceName(evidenceText, address);
  if (!name || !isUsableCandidateName(name)) return candidates;

  candidates.push({
    name,
    address: address ?? "",
    evidence: [
      "Server media analysis produced place-bearing text",
      ...mediaEvidenceTextEvidence(mediaEvidence),
      metadata?.imageURL ? `Source thumbnail URL: ${metadata.imageURL}` : "",
      metadata?.videoURL ? `Source video URL: ${metadata.videoURL}` : "",
    ].filter(Boolean),
    confidence: address ? 0.58 : 0.44,
    missingInfo: [
      address ? "Confirm exact address" : "Verified address",
      "Verified coordinates",
      "Media-derived candidate; corroborate with Places before saving",
    ],
  });

  return candidates;
}

function buildSourceRecoveryReceipt(
  input: SourceSearchInput,
  metadata: SourceMetadata | undefined,
  sourceResolution: SourceResolution | undefined,
  queries: string[],
  searchResults: SourceSearchResult[],
  candidates: SourceSearchCandidate[],
  mediaEvidence: SourceMediaEvidence[],
  errors: string[],
): SourceRecoveryReceipt {
  const found: string[] = [];
  const tried: string[] = [];
  const missing = new Set<string>();

  const sourceURL = input.sourceUrl?.trim();
  const parsedURL = sourceURL ? safeURL(sourceURL) : undefined;
  const inputKind = parsedURL && isPlacePlatformURL(parsedURL)
    ? "social_url"
    : parsedURL
      ? "web_url"
      : "text";

  if (sourceURL) found.push("source_url");
  if (sourceResolution?.status === "resolved") found.push("source_resolution");
  if (input.rawText?.trim()) found.push("user_shared_text");
  if (metadata?.title || metadata?.description) found.push("public_metadata");
  if (metadata?.imageURL) found.push("public_thumbnail_url");
  if (metadata?.videoURL) found.push("public_video_url");
  if (mediaEvidence.some((item) => item.kind === "thumbnail")) found.push("public_thumbnail_fetch");
  if (mediaEvidence.some((item) => item.kind === "video_keyframe")) found.push("server_keyframe_extraction");
  if (searchResults.length > 0) found.push("search_results");
  if (candidates.some((candidate) => candidate.address)) found.push("explicit_address");
  if (candidates.length > 0) found.push("review_candidate");

  if (sourceURL) {
    tried.push("source_resolution");
    tried.push("public_source_metadata");
  }
  if (metadata?.imageURL || metadata?.videoURL) tried.push("public_media_fetch");
  if (metadata?.videoURL) tried.push("server_keyframe_extraction");
  if (queries.length > 0) tried.push("public_search");
  if (candidates.length > 0) tried.push("candidate_quality_gate");
  if (errors.length > 0) tried.push("error_capture");

  for (const candidate of candidates) {
    for (const item of candidate.missingInfo) missing.add(item);
  }

  if (candidates.length === 0) {
    missing.add("Verified venue name");
    missing.add("Verified address");
    missing.add("Verified coordinates");
  } else if (candidates.every((candidate) => !candidate.address)) {
    missing.add("Verified address");
    missing.add("Verified coordinates");
  }

  if (sourceResolution?.status === "blocked_login") missing.add("Public page without a login wall");
  if (sourceResolution?.status === "expired") missing.add("Unexpired source link");
  if (sourceResolution?.status === "opaque_unresolved") missing.add("Canonical source URL or readable share evidence");

  return {
    input: inputKind,
    capabilityLevel: mediaEvidence.some((item) => item.kind === "video_keyframe")
      ? "media_evidence_recovery"
      : candidates.some((candidate) =>
        candidate.evidence.some((item) => item.startsWith("Source metadata contains")),
      )
        ? "metadata_enrichment"
        : "public_search_recovery",
    found: unique(found),
    tried: unique(tried),
    missing: unique([...missing]),
    output: candidates.length > 0
      ? "review_candidate"
      : sourceURL || searchResults.length > 0 || errors.length > 0
        ? "source_only_clue"
        : "diagnostic_only",
    nextBestClue: nextBestClue(candidates),
  };
}

function isPlacePlatformURL(url: URL): boolean {
  const host = url.hostname.toLowerCase();
  return [
    "instagram.com",
    "tiktok.com",
    "xiaohongshu.com",
    "xhslink.com",
    "douyin.com",
    "iesdouyin.com",
    "dianping.com",
    "dpurl.cn",
    "meituan.com",
    "ele.me",
  ].some((domain) => host === domain || host.endsWith(`.${domain}`));
}

function nextBestClue(candidates: SourceSearchCandidate[]): string {
  if (candidates.length === 0) {
    return "Share a screenshot, caption text, or map link that shows the venue name or address.";
  }
  if (candidates.every((candidate) => !candidate.address)) {
    return "Confirm with a Google Maps or Apple Maps link before saving this place.";
  }
  if (candidates.some((candidate) => candidate.missingInfo.includes("Verified coordinates"))) {
    return "Review the candidate and run Places refine before turning it into a saved map memory.";
  }
  return "Review the evidence before saving.";
}

export function candidatesFromSearchResults(results: SourceSearchResult[]): SourceSearchCandidate[] {
  const candidates: SourceSearchCandidate[] = [];
  const seen = new Set<string>();

  for (const result of results) {
    if (!isReviewableSearchResult(result)) continue;

    const name = candidateNameFromResult(result);
    if (!name) continue;

    const address = addressFromText(`${result.title}\n${result.snippet ?? ""}`) ?? "";
    const key = `${canonicalName(name)}|${canonicalName(address)}`;
    if (seen.has(key)) continue;
    seen.add(key);

    const evidence = [
      `Search query: ${result.query}`,
      `Search result title: ${result.title}`,
      result.snippet ? `Search result snippet: ${result.snippet}` : "",
      result.url ? `Search result URL: ${result.url}` : "",
    ].filter(Boolean);

    candidates.push({
      name,
      address,
      evidence,
      confidence: address ? 0.52 : 0.38,
      missingInfo: [
        address ? "Confirm exact address" : "Verified address",
        "Verified coordinates",
        "Search-derived candidate; verify source before saving",
      ],
    });
  }

  return candidates.slice(0, 5);
}

function dedupeCandidates(candidates: SourceSearchCandidate[]): SourceSearchCandidate[] {
  const seen = new Set<string>();
  const result: SourceSearchCandidate[] = [];
  for (const candidate of candidates) {
    const key = `${canonicalName(candidate.name)}|${canonicalName(candidate.address)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(candidate);
  }
  return result.slice(0, 5);
}

async function finalizeCandidates(
  candidates: SourceSearchCandidate[],
  context: {
    sourceMetadata?: SourceMetadata;
    mediaEvidence: SourceMediaEvidence[];
    searchResults: SourceSearchResult[];
    placesCorroborator: PlacesCorroborator;
    rubricEvaluator: EvidenceRubricEvaluator;
  },
  errors: string[],
): Promise<SourceSearchCandidate[]> {
  const finalized: SourceSearchCandidate[] = [];

  for (const candidate of candidates) {
    let next = { ...candidate, evidence: [...candidate.evidence], missingInfo: [...candidate.missingInfo] };
    try {
      const places = await context.placesCorroborator(next);
      if (places) next = applyPlacesCorroboration(next, places);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown Places corroboration error";
      errors.push(`places corroboration ${candidate.name}: ${message}`);
    }

    const verdict = await context.rubricEvaluator({
      sourceMetadata: context.sourceMetadata,
      mediaEvidence: context.mediaEvidence,
      searchResults: context.searchResults,
      candidate: next,
    });
    next = applyRubricVerdict(next, verdict);
    finalized.push(next);
  }

  return finalized.slice(0, 5);
}

function applyPlacesCorroboration(
  candidate: SourceSearchCandidate,
  places: PlacesCorroboration,
): SourceSearchCandidate {
  const evidence = [
    ...candidate.evidence,
    ...(places.evidence ?? []),
    places.placeId ? `Places corroboration place_id: ${places.placeId}` : "",
    places.address ? `Places corroboration address: ${places.address}` : "",
  ].filter(Boolean);
  const hasCoordinates = typeof places.latitude === "number" && typeof places.longitude === "number";
  return {
    ...candidate,
    name: places.name?.trim() || candidate.name,
    address: places.address?.trim() || candidate.address,
    latitude: hasCoordinates ? places.latitude : candidate.latitude,
    longitude: hasCoordinates ? places.longitude : candidate.longitude,
    placeId: places.placeId ?? candidate.placeId,
    evidence: unique(evidence),
    confidence: Math.min(0.95, candidate.confidence + (places.confidenceBoost ?? 0.18)),
    missingInfo: candidate.missingInfo.filter((item) => {
      if (places.address && item === "Verified address") return false;
      if (hasCoordinates && item === "Verified coordinates") return false;
      return true;
    }),
  };
}

function applyRubricVerdict(
  candidate: SourceSearchCandidate,
  verdict: EvidenceRubricVerdict,
): SourceSearchCandidate {
  const missing = unique([...candidate.missingInfo, ...verdict.missingInfo]);
  return {
    ...candidate,
    evidence: unique([
      ...candidate.evidence,
      `Rubric verdict: ${verdict.evidenceTier}`,
      `Confidence reason: ${verdict.confidenceReason}`,
    ]),
    missingInfo: missing,
  };
}

async function defaultEvidenceRubricEvaluator(input: EvidenceRubricInput): Promise<EvidenceRubricVerdict> {
  const externalVerdict = await externalEvidenceRubricEvaluator(input);
  return externalVerdict ?? deterministicEvidenceRubricEvaluator(input);
}

function deterministicEvidenceRubricEvaluator(input: EvidenceRubricInput): EvidenceRubricVerdict {
  const evidenceText = input.candidate.evidence.join("\n");
  const hasMetadata = input.candidate.evidence.some((item) => item.includes("Source metadata"));
  const hasMediaText = input.mediaEvidence.some((item) => item.text?.trim());
  const hasSearch = input.candidate.evidence.some((item) => item.includes("Search result"));
  const hasPlaces = input.candidate.evidence.some((item) => item.includes("Places corroboration"));
  const hasAddress = Boolean(input.candidate.address);
  const hasCoordinates = typeof input.candidate.latitude === "number" && typeof input.candidate.longitude === "number";

  if (hasPlaces && hasAddress && hasCoordinates) {
    return {
      evidenceTier: "corroborated",
      confidenceReason: "source evidence produced a candidate and Places corroborated address/coordinates",
      missingInfo: ["User confirmation before saving as Map Stamp"],
    };
  }

  if ((hasMetadata || hasMediaText || hasSearch) && hasAddress) {
    return {
      evidenceTier: "likely",
      confidenceReason: "place name and address are cited, but coordinates still need Places verification",
      missingInfo: ["Verified coordinates", "User confirmation before saving as Map Stamp"],
    };
  }

  if (hasMetadata || hasMediaText || hasSearch || evidenceText) {
    return {
      evidenceTier: "weak",
      confidenceReason: "SAV-E found place-bearing clues, but not enough proof for a map-ready candidate",
      missingInfo: ["Verified address", "Verified coordinates", "User confirmation before saving as Map Stamp"],
    };
  }

  return {
    evidenceTier: "source_only",
    confidenceReason: "source was preserved, but no reliable place evidence was extracted",
    missingInfo: ["Verified venue name", "Verified address", "Verified coordinates"],
  };
}

async function externalEvidenceRubricEvaluator(input: EvidenceRubricInput): Promise<EvidenceRubricVerdict | undefined> {
  const rawURL = process.env.SAVE_EVIDENCE_RUBRIC_URL?.trim();
  if (!rawURL) return undefined;
  const url = safeURL(rawURL);
  if (!url || !(await isSafePublicHTTPURL(url))) return undefined;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    const response = await fetch(url.toString(), {
      method: "POST",
      headers: {
        "User-Agent": "SAV-E evidence rubric/1.0",
        "Accept": "application/json",
        "Content-Type": "application/json",
        ...(process.env.SAVE_EVIDENCE_RUBRIC_TOKEN
          ? { "Authorization": `Bearer ${process.env.SAVE_EVIDENCE_RUBRIC_TOKEN}` }
          : {}),
      },
      redirect: "manual",
      signal: controller.signal,
      body: JSON.stringify(evidenceRubricProjection(input)),
    });
    if (isRedirectResponse(response) || !response.ok) return undefined;
    const body = JSON.parse(await boundedResponseText(response, 64_000)) as unknown;
    return normalizeRubricVerdict(body);
  } catch {
    return undefined;
  } finally {
    clearTimeout(timeout);
  }
}

function evidenceRubricProjection(input: EvidenceRubricInput): object {
  return {
    source: {
      title: input.sourceMetadata?.title?.slice(0, 500),
      description: input.sourceMetadata?.description?.slice(0, 1_000),
      resolved_url_host: input.sourceMetadata?.resolvedURL ? safeURL(input.sourceMetadata.resolvedURL)?.host : undefined,
      has_image: Boolean(input.sourceMetadata?.imageURL),
      has_video: Boolean(input.sourceMetadata?.videoURL),
    },
    candidate: {
      name: input.candidate.name,
      address: input.candidate.address,
      has_coordinates: typeof input.candidate.latitude === "number" && typeof input.candidate.longitude === "number",
      evidence: input.candidate.evidence.slice(0, 12).map((item) => redactURLs(item).slice(0, 500)),
      missing_info: input.candidate.missingInfo.slice(0, 12),
    },
    media_evidence: input.mediaEvidence
      .filter((item) => item.text?.trim())
      .slice(0, 6)
      .map((item) => ({
        kind: item.kind,
        text_source: item.textSource,
        frame_second: item.frameSecond,
        text: redactURLs(cleanText(item.text ?? "")).slice(0, 1_000),
      })),
    search_results: input.searchResults.slice(0, 6).map((item) => ({
      title: item.title.slice(0, 300),
      url_host: item.url ? safeURL(item.url)?.host : undefined,
      snippet: item.snippet ? redactURLs(item.snippet).slice(0, 500) : undefined,
    })),
  };
}

function redactURLs(value: string): string {
  return value.replace(/https?:\/\/[^\s)]+/gi, "[redacted_url]");
}

function normalizeRubricVerdict(value: unknown): EvidenceRubricVerdict | undefined {
  if (!value || typeof value !== "object") return undefined;
  const record = value as Record<string, unknown>;
  const tier = typeof record.evidence_tier === "string"
    ? record.evidence_tier
    : typeof record.evidenceTier === "string"
      ? record.evidenceTier
      : undefined;
  if (tier !== "source_only" && tier !== "weak" && tier !== "likely" && tier !== "corroborated") return undefined;
  const reason = typeof record.confidence_reason === "string"
    ? record.confidence_reason
    : typeof record.confidenceReason === "string"
      ? record.confidenceReason
      : undefined;
  if (!reason?.trim()) return undefined;
  const missing = Array.isArray(record.missing_info)
    ? record.missing_info
    : Array.isArray(record.missingInfo)
      ? record.missingInfo
      : [];
  return {
    evidenceTier: tier,
    confidenceReason: cleanText(reason).slice(0, 500),
    missingInfo: unique(missing.filter((item): item is string => typeof item === "string").map(cleanText).filter(Boolean)).slice(0, 12),
  };
}

async function defaultPlacesCorroborator(candidate: SourceSearchCandidate): Promise<PlacesCorroboration | undefined> {
  const key = process.env.GOOGLE_PLACES_API_KEY;
  if (!key) return undefined;
  const query = [candidate.name, candidate.address].filter(Boolean).join(" ");
  if (!query.trim()) return undefined;
  const params = new URLSearchParams({
    query,
    key,
    fields: "place_id,name,formatted_address,geometry",
  });
  const url = `https://maps.googleapis.com/maps/api/place/textsearch/json?${params.toString()}`;
  const response = await fetch(url, {
    headers: {
      "User-Agent": "SAV-E Places corroborator/1.0",
      "Accept": "application/json",
    },
    redirect: "manual",
  });
  if (isRedirectResponse(response) || !response.ok) return undefined;
  const body = JSON.parse(await boundedResponseText(response, 512_000)) as {
    results?: Array<{
      place_id?: string;
      name?: string;
      formatted_address?: string;
      geometry?: { location?: { lat?: number; lng?: number } };
    }>;
  };
  const result = body.results?.[0];
  if (!result) return undefined;
  const latitude = result.geometry?.location?.lat;
  const longitude = result.geometry?.location?.lng;
  return {
    name: result.name,
    address: result.formatted_address,
    latitude: typeof latitude === "number" ? latitude : undefined,
    longitude: typeof longitude === "number" ? longitude : undefined,
    placeId: result.place_id,
    confidenceBoost: 0.22,
    evidence: ["Places resolver matched the candidate by name/address query"],
  };
}

function mediaEvidencePlaceName(text: string, address?: string): string | undefined {
  const lines = text
    .split(/\n|\r|[。！？!?]/)
    .map(cleanMetadataPlaceLine)
    .filter((line) => line && !looksLikeHours(line));
  if (address) {
    const addressLineIndex = lines.findIndex((line) => line.includes(address) || address.includes(line));
    const beforeAddress = addressLineIndex >= 0 ? lines.slice(0, addressLineIndex) : lines;
    return beforeAddress.reverse().find((line) => isUsableCandidateName(line));
  }
  return lines.find((line) => isUsableCandidateName(line));
}

function mediaEvidenceTextEvidence(mediaEvidence: SourceMediaEvidence[]): string[] {
  return mediaEvidence.flatMap((item) => {
    if (!item.text?.trim()) return [];
    const label = item.textSource === "asr" ? "ASR transcript" : "Keyframe OCR";
    const frame = typeof item.frameSecond === "number" ? ` at ${item.frameSecond}s` : "";
    return [`${label}${frame}: ${cleanText(item.text).slice(0, 240)}`];
  });
}

function sourceMetadataPlaceName(text: string, address: string): string | undefined {
  const addressIndex = metadataAddressIndex(text, address);
  if (addressIndex < 0) return undefined;

  const beforeAddress = text.slice(0, addressIndex);
  const candidates = beforeAddress
    .split(/\n|["“”]/)
    .map(cleanMetadataPlaceLine)
    .filter((line) => line && isUsableCandidateName(line) && !looksLikeHours(line));

  const candidate = candidates.at(-1);
  const handleName = instagramCaptionVenueHandleName(beforeAddress);
  if (handleName && (!candidate || looksLikeContextCandidateLine(candidate))) return handleName;
  return candidate;
}

function metadataAddressIndex(text: string, address: string): number {
  const exact = text.indexOf(address);
  if (exact >= 0) return exact;
  const firstAddressLine = address.split(/\n|\r|,/)[0]?.trim();
  return firstAddressLine ? text.indexOf(firstAddressLine) : -1;
}

function instagramCaptionVenueHandleName(beforeAddress: string): string | undefined {
  const caption = beforeAddress.match(/\bon\s+Instagram:\s*["“]?([\s\S]*)/i)?.[1];
  if (!caption) return undefined;

  const firstHandle = [...caption.matchAll(/@([A-Za-z0-9._]{3,30})/g)]
    .map((match) => match[1])
    .find((handle) => !isContextSocialHandle(handle));
  return firstHandle ? venueNameFromHandle(firstHandle) : undefined;
}

function isContextSocialHandle(handle: string): boolean {
  const lowered = handle.toLowerCase();
  if (["instagram", "reels", "reel", "explore", "threads", "tiktok"].includes(lowered)) return true;
  if (/\d{5,}/.test(lowered)) return true;
  return false;
}

function venueNameFromHandle(handle: string): string | undefined {
  const localitySuffixes = new Set(["la", "nyc", "oc", "sf", "sd", "usa", "us"]);
  const parts = handle
    .toLowerCase()
    .split(/[._-]+/)
    .filter(Boolean);
  if (parts.length > 1 && localitySuffixes.has(parts.at(-1) ?? "")) parts.pop();
  const name = parts.join(" ");
  if (!name || name.length < 3) return undefined;
  return name.replace(/\b[a-z]/g, (char) => char.toUpperCase());
}

function looksLikeContextCandidateLine(value: string): boolean {
  return /^(located|inside|on the|at the)\b/i.test(value) ||
    /\b(operated by|chef|hotel|koreatown|second floor|culinary haven)\b/i.test(value);
}

function cleanMetadataPlaceLine(value: string): string {
  let line = cleanText(value);
  const pinIndex = line.lastIndexOf("📍");
  if (pinIndex >= 0) line = line.slice(pinIndex + 2);
  line = line
    .replace(/^[^:]{1,80}\bon\s+Instagram:\s*/i, "")
    .replace(/^.*?:\s*(?=[^:]{2,90}$)/, "")
    .replace(/^[^\p{L}\p{N}]+/u, "")
    .replace(/\s+[@#][A-Za-z0-9._-]{3,30}\b/g, "")
    .replace(/\s+/g, " ")
    .trim();
  return line;
}

function isReviewableSearchResult(result: SourceSearchResult): boolean {
  const title = cleanText(result.title);
  const snippet = cleanText(result.snippet ?? "");
  const url = result.url ? safeURL(result.url) : undefined;
  const address = addressFromText(`${title}\n${snippet}`);
  const name = candidateNameFromResult(result);

  if (!name) return false;
  if (isGenericSearchResult(title, url)) return false;
  if (address && !looksLikeListPage(title, url)) return true;
  return hasOfficialVenueSignal(title, url);
}

function candidateNameFromResult(result: SourceSearchResult): string | undefined {
  let title = cleanText(result.title)
    .replace(/\s+[@#][A-Za-z0-9._-]{3,30}\b/g, "")
    .replace(/\s*[|｜]\s*.*$/g, "")
    .replace(/\s+[–-]\s+(?:Google Maps|Yelp|Tripadvisor|OpenTable|Instagram|Facebook|TikTok).*$/gi, "")
    .replace(/\s+[–-]\s+Official(?:\s+Site)?$/gi, "")
    .replace(/[–—-][^-–—|｜]{2,40}$/g, "")
    .replace(/\s*•\s*Instagram.*$/gi, "")
    .replace(/\s+on Instagram.*$/gi, "")
    .trim();

  title = title.split(/\s+(?:menu|reviews?|photos?|reservations?)\b/i)[0]?.trim() ?? title;
  title = title.replace(/^official\s+/i, "").trim();

  if (!isUsableCandidateName(title)) return undefined;
  return title;
}

function isUsableCandidateName(value: string): boolean {
  const lowered = value.toLowerCase();
  if (value.length < 2 || value.length > 90) return false;
  if (/\b(instagram|reel|reels|tiktok|facebook|login|explore|hashtag|comments?|likes?)\b/i.test(value)) return false;
  if (/^\d+$/.test(value)) return false;
  if (!/[A-Za-z\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]/.test(value)) return false;
  if (/^(home|help center|restaurant|restaurants?|venue|venues?|place|travel|food|coffee|hotel|google maps|directions)$/i.test(value)) return false;
  if (lowered.startsWith("the best ") || lowered.startsWith("best ")) return false;
  return !looksLikeAddress(value);
}

function isGenericSearchResult(title: string, url?: URL): boolean {
  const loweredTitle = title.toLowerCase();
  const host = url?.host.toLowerCase().replace(/^www\./, "") ?? "";
  const path = url?.pathname.toLowerCase() ?? "";

  if (/^(instagram|google maps|help center|directions, traffic & transit)$/i.test(title)) return true;
  if (/\b(instagram reel size|create & share short videos|popular place reels|reels search|from instagram reel to google maps)\b/i.test(title)) return true;
  if (looksLikeListPage(title, url)) return true;

  if (host === "instagram.com" && !path.match(/^\/[A-Za-z0-9._-]+\/?$/)) return true;
  if (host === "maps.google.com" || (host === "google.com" && path.startsWith("/maps"))) return true;

  return false;
}

function looksLikeListPage(title: string, url?: URL): boolean {
  const loweredTitle = title.toLowerCase();
  const host = url?.host.toLowerCase().replace(/^www\./, "") ?? "";
  const path = url?.pathname.toLowerCase() ?? "";

  if (/\b(the best|best\s+\d+|top\s+\d+|venues? for rent|party venues?|event spaces?|restaurants? in|places to eat)\b/i.test(title)) {
    return true;
  }
  if ((host === "yelp.com" || host.endsWith(".yelp.com")) && (path.startsWith("/search") || loweredTitle.includes("best 10"))) {
    return true;
  }
  if (host.includes("tagvenue") || host.includes("eventective")) return true;
  return false;
}

function hasOfficialVenueSignal(title: string, url?: URL): boolean {
  const host = url?.host.toLowerCase().replace(/^www\./, "") ?? "";
  if (!host || blockedOfficialHosts.has(host)) return false;
  if (title.match(/\bOfficial(?:\s+Site)?\b/i) && !looksLikeListPage(title, url)) return true;
  return false;
}

const blockedOfficialHosts = new Set([
  "instagram.com",
  "facebook.com",
  "tiktok.com",
  "maps.google.com",
  "google.com",
  "about.instagram.com",
  "help.instagram.com",
]);

function addressFromText(text: string): string | undefined {
  const lineAddress = usAddressFromLines(text);
  if (lineAddress) return lineAddress;

  const patterns = [
    /\b\d{1,6}\s+[A-Za-z0-9 .'-]{2,80}\b(?:Street|St\.?|Road|Rd\.?|Avenue|Ave\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Way|Highway|Hwy\.?|Coast Hwy)\b(?:,\s*[A-Za-z .'-]{2,40})?/i,
    /[\u4e00-\u9fff]{2,}(?:市|区|區|路|街|道)[\u4e00-\u9fffA-Za-z0-9\-－\s]{0,40}\d{1,6}\s*(?:号|號)?(?:B\d|[0-9一二三四五六七八九十]+樓)?/,
  ];
  return patterns.map((pattern) => text.match(pattern)?.[0]?.trim()).find(Boolean);
}

function usAddressFromLines(text: string): string | undefined {
  const lines = text.split(/\n|\r/).map(cleanText).filter(Boolean);
  const streetPattern = /\b\d{1,6}\s+[A-Za-z0-9 .'-]{2,80}\b(?:Street|St\.?|Road|Rd\.?|Avenue|Ave\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Way|Highway|Hwy\.?|Coast Hwy)\b/i;
  const cityStatePattern = /^[A-Za-z .'-]{2,40},?\s+[A-Z]{2}(?:\s+\d{5})?$/;
  for (let index = 0; index < lines.length; index += 1) {
    const street = lines[index].match(streetPattern)?.[0]?.trim();
    if (!street) continue;
    const cityState = lines[index + 1]?.match(cityStatePattern)?.[0]?.trim();
    if (cityState) return `${street}, ${cityState}`;
  }
  return undefined;
}

function looksLikeAddress(value: string): boolean {
  return addressFromText(value) !== undefined;
}

function looksLikeHours(value: string): boolean {
  return /\b\d{1,2}:\d{2}\s*[-–]\s*\d{1,2}:\d{2}\b/.test(value);
}

function instagramReelID(url?: URL): string | undefined {
  if (!url?.host.toLowerCase().includes("instagram")) return undefined;
  const parts = url.pathname.split("/").filter(Boolean);
  const markerIndex = parts.findIndex((part) => part.toLowerCase() === "reel" || part.toLowerCase() === "reels");
  return markerIndex >= 0 ? parts[markerIndex + 1] : undefined;
}

function firstSocialHandle(text: string): string | undefined {
  const ignored = new Set(["instagram", "reels", "reel", "explore", "threads", "tiktok", "save", "save"]);
  for (const match of text.matchAll(/@([A-Za-z0-9._]{3,30})/g)) {
    const handle = match[1].toLowerCase();
    if (!ignored.has(handle) && !handle.includes("instagram") && !/\d{5,}/.test(handle)) return handle;
  }
  return undefined;
}

function cityQualifiedVenueClue(text: string): { city: string; name: string } | undefined {
  const genericNames = new Set(["那間店", "那家店", "這間店", "这间店", "這家店", "这家店", "那個地方", "那个地方"]);
  const match = text.match(/(台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)的([^\n\r，,。！!？?@#]{2,24})/);
  if (!match) return undefined;
  const city = normalizeTaiwanCity(match[1]);
  const name = cleanText(match[2]).replace(/[「」『』"']/g, "").trim();
  if (!name || genericNames.has(name) || looksLikeAddress(name)) return undefined;
  if (!isUsableCandidateName(name)) return undefined;
  return { city, name };
}

function normalizeTaiwanCity(city: string): string {
  if (city === "臺南") return "台南";
  if (city === "臺北") return "台北";
  if (city === "臺中") return "台中";
  return city;
}

function duckDuckGoHTMLURL(query: string): string {
  const params = new URLSearchParams({ q: query });
  return `https://duckduckgo.com/html/?${params.toString()}`;
}

export async function defaultFetchText(url: string): Promise<string> {
  const parsed = safeURL(url);
  if (!parsed || !(await isSafePublicHTTPURL(parsed))) throw new Error("Blocked non-public URL");

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    const response = await fetch(parsed.toString(), {
      headers: {
        "User-Agent": "SAV-E source recovery worker/1.0",
        "Accept": "text/html,application/xhtml+xml",
      },
      redirect: "manual",
      signal: controller.signal,
    });
    if (isRedirectResponse(response)) throw new Error("Blocked redirect response");
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return await boundedResponseText(response, maxTextFetchBytes);
  } finally {
    clearTimeout(timeout);
  }
}

export async function defaultFetchMetadataHTML(
  url: string,
  maxBytes = 512_000,
  fetchImpl: typeof fetch = fetch,
): Promise<string> {
  return (await resolveSourceDocument(url, maxBytes, fetchImpl)).html;
}

export async function resolveSourceDocument(
  url: string,
  maxBytes = 512_000,
  fetchImpl: typeof fetch = fetch,
): Promise<ResolvedSourceDocument> {
  let parsed = safeURL(url);
  if (!parsed || !(await isSafePublicHTTPURL(parsed))) throw new Error("Blocked non-public URL");

  const originalURL = parsed.toString();
  // Query and fragment can carry the only merchant/content identifier.
  const cacheKey = originalURL;
  const cached = sourceResolutionCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.document;
  if (cached) sourceResolutionCache.delete(cacheKey);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    let response: Response | undefined;
    const redirectChain = [originalURL];
    for (let redirectCount = 0; redirectCount <= maxMetadataRedirects; redirectCount += 1) {
      response = await fetchImpl(parsed.toString(), {
        headers: {
          "User-Agent": "SAV-E social metadata fetcher/1.0",
          "Accept": "text/html,application/xhtml+xml",
        },
        redirect: "manual",
        signal: controller.signal,
      });
      if (!isRedirectResponse(response)) break;

      const location = response.headers.get("location");
      if (!location || redirectCount === maxMetadataRedirects) throw new Error("Blocked redirect response");
      parsed = safeURL(new URL(location, parsed).toString());
      if (!parsed || !(await isSafePublicHTTPURL(parsed))) throw new Error("Blocked non-public URL");
      redirectChain.push(parsed.toString());
    }

    if (!response) throw new Error("No response");
    if (isRedirectResponse(response)) throw new Error("Blocked redirect response");
    if (!response.ok && ![401, 403, 404, 410].includes(response.status)) {
      throw new Error(`HTTP ${response.status}`);
    }

    const html = await boundedHeadResponseText(response, maxBytes);
    const networkURL = parsed.toString();
    const canonicalURL = canonicalSourceURL(html, parsed) ?? recoveredOriginalURL(parsed) ?? parsed;
    const resolvedURL = canonicalURL.toString();
    const metadata = sourceMetadataFromHTML(html, resolvedURL);
    const resolution = buildSourceResolution({
      originalURL,
      resolvedURL,
      redirectChain,
      responseStatus: response.status,
      html,
      metadata,
      networkURL,
    });
    const document = { html, resolution };

    if (resolution.status === "resolved") {
      cacheResolvedSourceDocument(cacheKey, document);
    }
    return document;
  } finally {
    clearTimeout(timeout);
  }
}

export function sourceResolutionResponseBody(resolution: SourceResolution): Record<string, unknown> {
  return {
    original_url: resolution.originalURL,
    resolved_url: resolution.resolvedURL,
    redirect_chain: resolution.redirectChain,
    ...(resolution.canonicalContentID ? { canonical_content_id: resolution.canonicalContentID } : {}),
    status: resolution.status,
    ...(resolution.title ? { title: resolution.title } : {}),
    ...(resolution.caption ? { caption: resolution.caption } : {}),
    ...(resolution.thumbnailURL ? { thumbnail_url: resolution.thumbnailURL } : {}),
  };
}

async function fetchSourceDocument(
  sourceUrl: string | null | undefined,
  fetchText: FetchText,
  errors: string[],
  resolver?: SourceDocumentResolver,
): Promise<SourceDocumentFetchResult | undefined> {
  const source = sourceUrl?.trim();
  const url = source ? safeURL(source) : undefined;
  if (!url || !isSafePublicHTTPURLByHostname(url)) return undefined;

  try {
    let document: ResolvedSourceDocument;
    if (resolver) {
      document = await resolver(url.toString());
    } else if (fetchText === defaultFetchText) {
      document = await resolveSourceDocument(url.toString());
    } else {
      const html = await fetchText(url.toString());
      const metadata = sourceMetadataFromHTML(html, url.toString());
      document = {
        html,
        resolution: buildSourceResolution({
          originalURL: url.toString(),
          resolvedURL: url.toString(),
          redirectChain: [url.toString()],
          responseStatus: 200,
          html,
          metadata,
          networkURL: url.toString(),
        }),
      };
    }

    const metadata = document.resolution.status === "resolved"
      ? sourceMetadataFromHTML(document.html, document.resolution.resolvedURL)
      : undefined;
    return { metadata, resolution: document.resolution };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown source metadata error";
    errors.push(`source metadata ${url.toString()}: ${message}`);
    return undefined;
  }
}

function cacheResolvedSourceDocument(cacheKey: string, document: ResolvedSourceDocument): void {
  if (sourceResolutionCache.size >= sourceResolutionCacheLimit) {
    const oldestKey = sourceResolutionCache.keys().next().value;
    if (oldestKey) sourceResolutionCache.delete(oldestKey);
  }
  sourceResolutionCache.set(cacheKey, {
    expiresAt: Date.now() + sourceResolutionCacheTTL,
    document,
  });
}

export function sourceMetadataFromHTML(html: string, resolvedURL?: string): SourceMetadata {
  const baseURL = resolvedURL ? safeURL(resolvedURL) : undefined;
  return {
    resolvedURL,
    title: metadataValue(html, ["og:title", "twitter:title"]) ?? htmlTitle(html),
    description: metadataValue(html, ["og:description", "twitter:description", "description"]),
    imageURL: safePublicMediaURL(metadataValue(html, ["og:image:secure_url", "og:image", "twitter:image"]), baseURL),
    videoURL: safePublicMediaURL(metadataValue(html, ["og:video:secure_url", "og:video", "og:video:url", "twitter:player:stream"]), baseURL),
  };
}

function buildSourceResolution(input: {
  originalURL: string;
  resolvedURL: string;
  redirectChain: string[];
  responseStatus: number;
  html: string;
  metadata: SourceMetadata;
  networkURL: string;
}): SourceResolution {
  const title = cleanOptionalText(input.metadata.title);
  const caption = cleanOptionalText(input.metadata.description);
  const thumbnailURL = input.metadata.imageURL;
  const resolved = safeURL(input.resolvedURL);
  const canonicalContentID = canonicalContentIDFromURL(resolved);
  const diagnosticText = cleanText([title, caption, stripTags(input.html.slice(0, 4_000))].filter(Boolean).join(" "));

  let status: SourceResolutionStatus;
  if (isExpiredSource(input.responseStatus, diagnosticText)) {
    status = "expired";
  } else if (isBlockedLoginDocument(input.responseStatus, title, diagnosticText)) {
    status = "blocked_login";
  } else if (
    canonicalContentID ||
    hasUsableSourceTitle(title) ||
    hasUsableSourceCaption(caption) ||
    thumbnailURL ||
    input.resolvedURL !== input.originalURL ||
    input.networkURL !== input.originalURL
  ) {
    status = "resolved";
  } else {
    status = "opaque_unresolved";
  }

  return {
    originalURL: input.originalURL,
    resolvedURL: input.resolvedURL,
    redirectChain: input.redirectChain,
    canonicalContentID,
    status,
    title,
    caption,
    thumbnailURL,
  };
}

function canonicalSourceURL(html: string, baseURL: URL): URL | undefined {
  const tags = html.match(/<link\b[^>]*>/gi) ?? [];
  for (const tag of tags) {
    const rel = attrValue(tag, "rel")?.toLowerCase().split(/\s+/) ?? [];
    if (!rel.includes("canonical")) continue;
    const href = attrValue(tag, "href");
    if (!href) continue;
    let candidate: URL | undefined;
    try {
      candidate = safeURL(new URL(href, baseURL).toString());
    } catch {
      continue;
    }
    if (candidate && isSafePublicHTTPURLByHostname(candidate) && sameDomainFamily(candidate, baseURL)) {
      return candidate;
    }
  }
  return undefined;
}

function recoveredOriginalURL(url: URL): URL | undefined {
  const value = url.searchParams.get("originalUrl") ?? url.searchParams.get("original_url");
  if (!value) return undefined;
  const candidate = safeURL(value);
  if (!candidate || !isSafePublicHTTPURLByHostname(candidate) || !sameDomainFamily(candidate, url)) return undefined;
  return candidate;
}

function sameDomainFamily(lhs: URL, rhs: URL): boolean {
  const left = normalizedHostname(lhs).replace(/^www\./, "");
  const right = normalizedHostname(rhs).replace(/^www\./, "");
  return left === right || left.endsWith(`.${right}`) || right.endsWith(`.${left}`);
}

function canonicalContentIDFromURL(url: URL | undefined): string | undefined {
  if (!url) return undefined;
  const recovered = recoveredOriginalURL(url);
  if (recovered && recovered.toString() !== url.toString()) return canonicalContentIDFromURL(recovered);

  const parameterKeys = new Set([
    "id", "noteid", "note_id", "videoid", "video_id", "feedid", "feed_id",
    "shopid", "shop_id", "merchantid", "merchant_id", "poi_id", "poiid",
  ]);
  if (isPlacePlatformURL(url)) {
    const queryItems = [...url.searchParams.entries()];
    const fragmentItems = url.hash.startsWith("#")
      ? [...new URLSearchParams(url.hash.slice(1)).entries()]
      : [];
    for (const [key, value] of [...queryItems, ...fragmentItems]) {
      if (parameterKeys.has(key.toLowerCase()) && isCanonicalContentToken(value)) return value;
    }
  }

  const host = normalizedHostname(url);
  const parts = url.pathname.split("/").filter(Boolean);
  const markers: string[] = [];
  if (hostMatchesDomain(host, "xiaohongshu.com")) markers.push("item", "explore");
  if (hostMatchesDomain(host, "douyin.com") || hostMatchesDomain(host, "iesdouyin.com")) markers.push("video", "note");
  if (hostMatchesDomain(host, "dianping.com")) markers.push("shop", "feed", "review");
  if (hostMatchesDomain(host, "meituan.com")) markers.push("restaurant", "shop", "poi");
  if (hostMatchesDomain(host, "instagram.com")) markers.push("reel", "reels", "p", "tv");
  if (hostMatchesDomain(host, "tiktok.com")) markers.push("video");

  for (const marker of markers) {
    const markerIndex = parts.findIndex((part) => part.toLowerCase() === marker);
    const value = markerIndex >= 0 ? parts[markerIndex + 1] : undefined;
    if (value && isCanonicalContentToken(value)) return value;
  }
  return undefined;
}

function isCanonicalContentToken(value: string): boolean {
  return /^[A-Za-z0-9_-]{5,100}$/.test(value) && !/^(login|signin|share|detail|index|home)$/i.test(value);
}

function hostMatchesDomain(host: string, domain: string): boolean {
  return host === domain || host.endsWith(`.${domain}`);
}

function cleanOptionalText(value: string | undefined): string | undefined {
  const cleaned = value ? cleanText(value) : "";
  return cleaned || undefined;
}

function isExpiredSource(status: number, text: string): boolean {
  if (status === 404 || status === 410) return true;
  return /(链接|連結|页面|頁面|内容|內容).{0,12}(失效|不存在|已删除|已刪除|过期|過期)|\b(page|content|link)\s+(?:was\s+)?(?:not found|expired|removed)\b/i.test(text);
}

function isBlockedLoginDocument(status: number, title: string | undefined, text: string): boolean {
  if (status === 401 || status === 403) return true;
  const loginSignal = /(请先|請先)?(?:登录|登入)|\b(?:log\s*in|sign\s*in|login required)\b|安全验(?:证|證)|安全驗證|访问受限|訪問受限/i;
  const openAppSignal = /(?:打开|打開).{0,16}(?:App|应用|應用)|\bopen (?:this )?(?:in|with) (?:the )?app\b/i;
  const genericTitle = /^(?:美团|美團|美团外卖|美團外賣|淘宝|淘寶|淘宝闪购|淘寶閃購|饿了么|餓了麼|小红书|小紅書|抖音|大众点评|大眾點評|Ele\.me|Instagram|TikTok)$/i;
  return loginSignal.test(title ?? "") ||
    (!hasUsableSourceTitle(title) && loginSignal.test(text)) ||
    (genericTitle.test(title ?? "") && openAppSignal.test(text));
}

function hasUsableSourceTitle(value: string | undefined): boolean {
  if (!value || value.length < 2) return false;
  return !/^(?:登录|登入|log\s*in|sign\s*in|美团|美團|美团外卖|美團外賣|淘宝|淘寶|淘宝闪购|淘寶閃購|饿了么|餓了麼|小红书|小紅書|抖音|大众点评|大眾點評|Ele\.me|Instagram|TikTok)$/i.test(value);
}

function hasUsableSourceCaption(value: string | undefined): boolean {
  if (!value || value.length < 4) return false;
  return !/(请先|請先)?(?:登录|登入)|\b(?:log\s*in|sign\s*in|login required)\b/i.test(value);
}

function metadataValue(html: string, keys: string[]): string | undefined {
  const keySet = new Set(keys.map((key) => key.toLowerCase()));
  const tags = html.match(/<meta\b[^>]*>/gi) ?? [];
  for (const tag of tags) {
    const property = attrValue(tag, "property") ?? attrValue(tag, "name");
    if (!property || !keySet.has(property.toLowerCase())) continue;
    const content = attrValue(tag, "content");
    if (content) return content;
  }
  return undefined;
}

function attrValue(tag: string, name: string): string | undefined {
  const pattern = new RegExp(`\\b${name}\\s*=\\s*([\"'])([\\s\\S]*?)\\1`, "i");
  return tag.match(pattern)?.[2];
}

function htmlTitle(html: string): string | undefined {
  return html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1];
}

function decodedMetadataText(metadata: SourceMetadata): string {
  return [metadata.title, metadata.description]
    .filter(Boolean)
    .map((value) => decodeHTML(value ?? ""))
    .join("\n");
}


async function recoverSourceMediaEvidence(
  metadata: SourceMetadata | undefined,
  fetchMediaEvidence: FetchMediaEvidence,
  errors: string[],
): Promise<SourceMediaEvidence[]> {
  if (!metadata?.imageURL && !metadata?.videoURL) return [];
  try {
    return await fetchMediaEvidence(metadata);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown source media error";
    errors.push(`source media recovery: ${message}`);
    return [];
  }
}

async function defaultFetchMediaEvidence(metadata: SourceMetadata): Promise<SourceMediaEvidence[]> {
  const evidence: SourceMediaEvidence[] = [];
  if (metadata.imageURL) {
    const image = await fetchBoundedMedia(metadata.imageURL, 6_000_000);
    if (image) {
      evidence.push({
        kind: "thumbnail",
        url: metadata.imageURL,
        contentType: image.contentType,
        byteLength: image.data.byteLength,
        sha256: sha256(image.data),
      });
    }
  }

  // Keep server-side keyframe extraction opt-in because many social video URLs are
  // signed, large, or rate-limited. The code path is deterministic and bounded so
  // production can enable it without letting a Reel fetch consume the worker.
  if (metadata.videoURL && process.env.SAVE_ENABLE_SERVER_KEYFRAME_EXTRACTION === "true") {
    const video = await fetchBoundedMedia(metadata.videoURL, 24_000_000);
    if (video) {
      const transcript = await extractASRTranscript(video.data);
      evidence.push({
        kind: "video",
        url: metadata.videoURL,
        contentType: video.contentType,
        byteLength: video.data.byteLength,
        sha256: sha256(video.data),
        text: transcript,
        textSource: transcript ? "asr" : undefined,
      });
      const frame = await extractFirstKeyframe(video.data, metadata.videoURL);
      if (frame) evidence.push(frame);
    }
  }
  return evidence;
}

async function fetchBoundedMedia(url: string, maxBytes: number): Promise<{ data: Uint8Array; contentType?: string } | undefined> {
  const parsed = safeURL(url);
  if (!parsed || !(await isSafePublicHTTPURL(parsed))) return undefined;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(parsed.toString(), {
      headers: {
        "User-Agent": "SAV-E source recovery media fetcher/1.0",
        "Accept": "image/avif,image/webp,image/apng,image/*,video/*,*/*;q=0.8",
      },
      redirect: "manual",
      signal: controller.signal,
    });
    if (isRedirectResponse(response)) return undefined;
    if (!response.ok) return undefined;
    const length = Number(response.headers.get("content-length") ?? "0");
    if (length > maxBytes) return undefined;
    const data = new Uint8Array(await response.arrayBuffer());
    if (data.byteLength > maxBytes) return undefined;
    return { data, contentType: response.headers.get("content-type") ?? undefined };
  } finally {
    clearTimeout(timeout);
  }
}

async function extractFirstKeyframe(videoData: Uint8Array, sourceUrl: string): Promise<SourceMediaEvidence | undefined> {
  const dir = await mkdtemp(join(tmpdir(), "save-reel-frame-"));
  const input = join(dir, "input.bin");
  const output = join(dir, "frame.jpg");
  try {
    await writeFile(input, videoData);
    await execFileAsync("ffmpeg", [
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-ss",
      "1",
      "-i",
      input,
      "-frames:v",
      "1",
      "-vf",
      "scale='min(1024,iw)':-2",
      output,
    ], { timeout: 12_000, maxBuffer: 200_000 });
    const frameData = new Uint8Array(await readFile(output));
    if (frameData.byteLength === 0 || frameData.byteLength > 6_000_000) return undefined;
    const ocrText = await extractOCRText(output);
    return {
      kind: "video_keyframe",
      url: sourceUrl,
      contentType: "image/jpeg",
      byteLength: frameData.byteLength,
      sha256: sha256(frameData),
      frameSecond: 1,
      text: ocrText,
      textSource: ocrText ? "ocr" : undefined,
    };
  } catch {
    return undefined;
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

async function extractOCRText(imagePath: string): Promise<string | undefined> {
  if (process.env.SAVE_ENABLE_SERVER_OCR !== "true") return undefined;
  try {
    const command = process.env.SAVE_SERVER_OCR_COMMAND?.trim() || "tesseract";
    const { stdout } = await execFileAsync(command, [imagePath, "stdout"], {
      timeout: 10_000,
      maxBuffer: 500_000,
    });
    const text = cleanText(stdout);
    return text.length >= 2 ? text.slice(0, 2_000) : undefined;
  } catch {
    return undefined;
  }
}

async function extractASRTranscript(videoData: Uint8Array): Promise<string | undefined> {
  if (process.env.SAVE_ENABLE_SERVER_ASR !== "true") return undefined;
  const dir = await mkdtemp(join(tmpdir(), "save-reel-asr-"));
  const input = join(dir, "input.mp4");
  try {
    await writeFile(input, videoData);
    const command = process.env.SAVE_SERVER_ASR_COMMAND?.trim() || "whisper";
    const model = process.env.SAVE_SERVER_ASR_MODEL?.trim() || "base";
    await execFileAsync(command, [
      input,
      "--model",
      model,
      "--output_format",
      "txt",
      "--output_dir",
      dir,
    ], { timeout: 60_000, maxBuffer: 1_000_000 });
    const text = cleanText(await readFile(join(dir, "input.txt"), "utf8"));
    return text.length >= 2 ? text.slice(0, 4_000) : undefined;
  } catch {
    return undefined;
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function safePublicMediaURL(value: string | undefined, baseURL: URL | undefined): string | undefined {
  if (!value) return undefined;
  const url = safeURL(baseURL ? new URL(value, baseURL).toString() : value);
  return url && isSafePublicHTTPURLByHostname(url) ? url.toString() : undefined;
}

async function isSafePublicHTTPURL(url: URL): Promise<boolean> {
  if (!isSafePublicHTTPURLByHostname(url)) return false;
  const host = normalizedHostname(url);
  if (isIP(host)) return !isPrivateIPAddress(host);
  try {
    const addresses = await lookup(host, { all: true, verbatim: true });
    return addresses.length > 0 && addresses.every((address) => !isPrivateIPAddress(address.address));
  } catch {
    return false;
  }
}

function isSafePublicHTTPURLByHostname(url: URL): boolean {
  if (url.protocol !== "http:" && url.protocol !== "https:") return false;
  const host = normalizedHostname(url);
  if (!host || host === "localhost" || host.endsWith(".localhost")) return false;
  if (isIP(host)) return !isPrivateIPAddress(host);
  return true;
}

function normalizedHostname(url: URL): string {
  return url.hostname.toLowerCase().replace(/^\[/, "").replace(/\]$/, "");
}

function isPrivateIPAddress(host: string): boolean {
  if (host === "0.0.0.0" || host === "::" || host === "::1") return true;
  if (host.includes(":")) {
    const value = host.toLowerCase();
    return value === "::1" || value.startsWith("fc") || value.startsWith("fd") || value.startsWith("fe80:");
  }
  return [
    /^127\./,
    /^10\./,
    /^192\.168\./,
    /^169\.254\./,
    /^172\.(1[6-9]|2[0-9]|3[0-1])\./,
    /^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\./,
    /^198\.(1[8-9])\./,
  ].some((pattern) => pattern.test(host));
}

function isRedirectResponse(response: Response): boolean {
  return response.status >= 300 && response.status < 400;
}

async function boundedResponseText(response: Response, maxBytes: number): Promise<string> {
  const length = Number(response.headers.get("content-length") ?? "0");
  if (length > maxBytes) throw new Error("Response too large");
  if (!response.body) return "";

  const chunks: Uint8Array[] = [];
  let byteLength = 0;
  const reader = response.body.getReader();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    byteLength += value.byteLength;
    if (byteLength > maxBytes) {
      await reader.cancel();
      throw new Error("Response too large");
    }
    chunks.push(value);
  }

  const data = new Uint8Array(byteLength);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(data);
}

async function boundedHeadResponseText(response: Response, maxBytes: number): Promise<string> {
  if (!response.body) return "";

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let text = "";
  let byteLength = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    byteLength += value.byteLength;
    text += decoder.decode(value, { stream: true });

    const headEnd = text.match(/<\/head\s*>/i);
    if (headEnd?.index !== undefined) {
      const headLength = headEnd.index + headEnd[0].length;
      const head = text.slice(0, headLength);
      if (/<title\b|<meta\b[^>]*(?:description|og:|twitter:)/i.test(head)) {
        await reader.cancel();
        return head;
      }
      if (text.length >= headLength + 8_192) {
        await reader.cancel();
        return text.slice(0, headLength + 8_192);
      }
    }

    if (byteLength >= maxBytes) {
      await reader.cancel();
      return text.slice(0, maxBytes);
    }
  }

  return text + decoder.decode();
}

function sha256(data: Uint8Array): string {
  return createHash("sha256").update(data).digest("hex");
}

function safeURL(value: string): URL | undefined {
  try {
    return new URL(value);
  } catch {
    return undefined;
  }
}

function canonicalSearchURL(url?: URL): string | undefined {
  if (!url) return undefined;
  const copy = new URL(url.toString());
  copy.search = "";
  copy.hash = "";
  return copy.toString();
}

function normalizeDuckDuckGoURL(value: string): string | undefined {
  try {
    const url = new URL(value, "https://duckduckgo.com");
    const uddg = url.searchParams.get("uddg");
    return uddg ? decodeURIComponent(uddg) : url.toString();
  } catch {
    return undefined;
  }
}

function cleanText(value: string): string {
  return decodeHTML(value)
    .replace(/\s+/g, " ")
    .trim();
}

function stripTags(value: string): string {
  return value.replace(/<[^>]*>/g, " ");
}

export function decodeHTML(value: string): string {
  return value
    .replace(/&#x([0-9a-fA-F]+);/g, (_, code) => String.fromCodePoint(Number.parseInt(code, 16)))
    .replace(/&#([0-9]+);/g, (_, code) => String.fromCodePoint(Number.parseInt(code, 10)))
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#034;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&#039;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ");
}

function unique(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values.map((item) => item.trim()).filter(Boolean)) {
    if (seen.has(value)) continue;
    seen.add(value);
    result.push(value);
  }
  return result;
}

function canonicalName(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, " ").trim();
}
