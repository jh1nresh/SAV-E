import {
  searchPublicWebResults,
  type SourceSearchResult,
} from "./sourceSearchWorker.js";

export const relatedSourcePlatforms = [
  "instagram",
  "tiktok",
  "youtube",
  "xiaohongshu",
  "douyin",
  "threads",
  "x",
] as const;

export type RelatedSourcePlatform = typeof relatedSourcePlatforms[number];
export type RelatedSourceRelation = "same_place" | "mentions_place";
export type RelatedSourceCoverageStatus = "searched" | "partial" | "failed";

export type RelatedSourcePlaceIdentity = {
  id: string;
  name: string;
  address: string;
  latitude?: number;
  longitude?: number;
  category?: string;
  googlePlaceId?: string;
  sourceUrl?: string;
};

export type RelatedPlaceSourcesRequest = {
  platforms?: RelatedSourcePlatform[];
  maxResultsPerPlatform?: number;
  forceRefresh?: boolean;
};

export type RelatedPlaceSource = {
  platform: RelatedSourcePlatform;
  url: string;
  title: string;
  snippet?: string;
  query: string;
  relation: RelatedSourceRelation;
  identityStatus: "candidate";
  matchConfidence: number;
};

export type RelatedSourceCoverage = {
  platform: RelatedSourcePlatform;
  method: "public_index";
  status: RelatedSourceCoverageStatus;
  queries: string[];
  inspectedCount: number;
  resultCount: number;
  blockedReason?: "public_search_failed";
};

export type RelatedSourcesReceipt = {
  sourceBoundary: "public_web_index";
  privacy: "owner_private";
  checkedAt: string;
  requestedPlatforms: RelatedSourcePlatform[];
  searchedPlatforms: RelatedSourcePlatform[];
  failedPlatforms: RelatedSourcePlatform[];
  rawResultCount: number;
  independentResultCount: number;
  missing: string[];
};

export type RelatedPlaceSourcePack = {
  place: RelatedSourcePlaceIdentity;
  sources: RelatedPlaceSource[];
  coverage: RelatedSourceCoverage[];
  receipt: RelatedSourcesReceipt;
};

export type PublicIndexSearch = (
  query: string,
  platform: RelatedSourcePlatform,
  signal?: AbortSignal,
) => Promise<SourceSearchResult[]>;

export type RelatedPlaceSourcesOptions = {
  search?: PublicIndexSearch;
  now?: () => Date;
  deadlineMs?: number;
};

type PlatformDefinition = {
  queryDomain: string;
  hosts: readonly string[];
};

type RelatedSourceSearchOutcome = {
  platform: RelatedSourcePlatform;
  query: string;
  results: SourceSearchResult[];
  failed: boolean;
};

const platformDefinitions: Record<RelatedSourcePlatform, PlatformDefinition> = {
  instagram: {
    queryDomain: "instagram.com",
    hosts: ["instagram.com"],
  },
  tiktok: {
    queryDomain: "tiktok.com",
    hosts: ["tiktok.com"],
  },
  youtube: {
    queryDomain: "youtube.com",
    hosts: ["youtube.com", "youtu.be"],
  },
  xiaohongshu: {
    queryDomain: "xiaohongshu.com",
    hosts: ["xiaohongshu.com", "xhslink.com"],
  },
  douyin: {
    queryDomain: "douyin.com",
    hosts: ["douyin.com", "iesdouyin.com"],
  },
  threads: {
    queryDomain: "threads.net",
    hosts: ["threads.net"],
  },
  x: {
    queryDomain: "x.com",
    hosts: ["x.com", "twitter.com"],
  },
};

export const defaultRelatedSourcePlatforms: RelatedSourcePlatform[] = [
  "instagram",
  "tiktok",
  "youtube",
  "xiaohongshu",
];
const maxQueriesPerPlatform = 2;
const maxResultsPerPlatformLimit = 5;
const maxSearchConcurrency = 3;
const defaultSearchDeadlineMs = 20_000;
const maxQueryLength = 240;
const maxTitleLength = 200;
const maxSnippetLength = 500;
const trackingParameters = new Set([
  "fbclid",
  "feature",
  "gclid",
  "igsh",
  "si",
  "share_app_id",
  "share_item_id",
  "share_token",
  "utm_campaign",
  "utm_content",
  "utm_medium",
  "utm_source",
  "utm_term",
]);
const genericPathPrefixes = [
  "/accounts",
  "/hashtag",
  "/login",
  "/results",
  "/search",
  "/search_result",
  "/signin",
];
const privatePlacePattern =
  /^(?:home|my home|private residence|residence|住家|自宅|我家|私人住宅|住所)$/i;
const privateCategoryPattern =
  /^(?:home|residence|private|private_place|住家|住宅|住所)$/i;
const regionPattern =
  /(?:台北市|臺北市|新北市|桃園市|台中市|臺中市|台南市|臺南市|高雄市|東京都|大阪府|京都府|北海道|上海市|北京市|深圳市|廣州市|广州市|香港|澳門|澳门)/g;

export class RelatedPlaceSourcesInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RelatedPlaceSourcesInputError";
  }
}

export function normalizeRelatedPlaceSourcesRequest(
  body: Record<string, unknown>,
): RelatedPlaceSourcesRequest {
  let platforms: RelatedSourcePlatform[] | undefined;
  if (body.platforms !== undefined) {
    if (!Array.isArray(body.platforms)) {
      throw new RelatedPlaceSourcesInputError("platforms must be an array");
    }
    const values = uniqueStrings(body.platforms.map((value) => {
      if (typeof value !== "string") {
        throw new RelatedPlaceSourcesInputError("platforms must contain strings");
      }
      return value.trim().toLowerCase();
    }));
    if (values.length === 0 || values.length > relatedSourcePlatforms.length) {
      throw new RelatedPlaceSourcesInputError("platforms must contain 1-7 supported values");
    }
    const supported = new Set<string>(relatedSourcePlatforms);
    if (values.some((value) => !supported.has(value))) {
      throw new RelatedPlaceSourcesInputError("platforms contains an unsupported value");
    }
    platforms = values as RelatedSourcePlatform[];
  }

  if (body.aliases !== undefined) {
    throw new RelatedPlaceSourcesInputError(
      "aliases are not accepted until they can be verified as venue identity",
    );
  }

  let maxResultsPerPlatform: number | undefined;
  if (body.max_results_per_platform !== undefined) {
    const value = body.max_results_per_platform;
    if (!Number.isInteger(value) || Number(value) < 1 || Number(value) > maxResultsPerPlatformLimit) {
      throw new RelatedPlaceSourcesInputError(
        `max_results_per_platform must be an integer from 1-${maxResultsPerPlatformLimit}`,
      );
    }
    maxResultsPerPlatform = Number(value);
  }

  let forceRefresh: boolean | undefined;
  if (body.force_refresh !== undefined) {
    if (typeof body.force_refresh !== "boolean") {
      throw new RelatedPlaceSourcesInputError("force_refresh must be a boolean");
    }
    forceRefresh = body.force_refresh;
  }

  return {
    platforms,
    maxResultsPerPlatform,
    ...(forceRefresh === undefined ? {} : { forceRefresh }),
  };
}

export function resolvedRelatedPlaceSourcesRequest(
  request: RelatedPlaceSourcesRequest,
): { platforms: RelatedSourcePlatform[]; maxResultsPerPlatform: number } {
  return {
    platforms: request.platforms?.length
      ? uniquePlatforms(request.platforms)
      : [...defaultRelatedSourcePlatforms],
    maxResultsPerPlatform: request.maxResultsPerPlatform ?? 3,
  };
}

export async function discoverRelatedPlaceSources(
  rawPlace: RelatedSourcePlaceIdentity,
  request: RelatedPlaceSourcesRequest = {},
  options: RelatedPlaceSourcesOptions = {},
): Promise<RelatedPlaceSourcePack> {
  const place = normalizePlaceIdentity(rawPlace);
  const resolvedRequest = resolvedRelatedPlaceSourcesRequest(request);
  const platforms = resolvedRequest.platforms;
  const maxResultsPerPlatform = resolvedRequest.maxResultsPerPlatform;
  if (
    !Number.isInteger(maxResultsPerPlatform) ||
    maxResultsPerPlatform < 1 ||
    maxResultsPerPlatform > maxResultsPerPlatformLimit
  ) {
    throw new RelatedPlaceSourcesInputError(
      `maxResultsPerPlatform must be an integer from 1-${maxResultsPerPlatformLimit}`,
    );
  }

  const search = options.search ?? defaultPublicIndexSearch;
  const now = options.now ?? (() => new Date());
  const deadlineMs = boundedDeadlineMs(options.deadlineMs);
  const coverage: RelatedSourceCoverage[] = [];
  const sources: RelatedPlaceSource[] = [];
  let rawResultCount = 0;

  const queryPlans = platforms.map((platform) => ({
    platform,
    queries: buildRelatedSourceQueries(place, platform),
  }));
  const controller = new AbortController();
  const deadline = setTimeout(() => controller.abort(), deadlineMs);
  let outcomes: RelatedSourceSearchOutcome[] = [];
  try {
    outcomes = await mapWithConcurrency(
      queryPlans.flatMap(({ platform, queries }) =>
        queries.map((query) => ({ platform, query }))
      ),
      maxSearchConcurrency,
      async ({ platform, query }) => {
        if (controller.signal.aborted) {
          return { platform, query, results: [], failed: true };
        }
        try {
          const results = await waitForSearch(
            search(query, platform, controller.signal),
            controller.signal,
          );
          return {
            platform,
            query,
            results: results.slice(0, maxResultsPerPlatformLimit),
            failed: false,
          };
        } catch {
          return { platform, query, results: [], failed: true };
        }
      },
    );
  } finally {
    clearTimeout(deadline);
  }

  for (const { platform, queries } of queryPlans) {
    const platformOutcomes = outcomes.filter((outcome) => outcome.platform === platform);
    const rawResults = platformOutcomes.flatMap((outcome) => outcome.results);
    const failureCount = platformOutcomes.filter((outcome) => outcome.failed).length;
    rawResultCount += rawResults.length;
    const platformSources = dedupeSources(
      rawResults
        .map((result) => relatedSourceFromSearchResult(place, platform, result))
        .filter((source): source is RelatedPlaceSource => source !== undefined)
        .filter((source) => !isSeedSource(place.sourceUrl, source.url)),
    )
      .sort(compareRelatedSources)
      .slice(0, maxResultsPerPlatform);

    sources.push(...platformSources);
    const status: RelatedSourceCoverageStatus = failureCount === queries.length
      ? "failed"
      : failureCount > 0
        ? "partial"
        : "searched";
    coverage.push({
      platform,
      method: "public_index",
      status,
      queries,
      inspectedCount: rawResults.length,
      resultCount: platformSources.length,
      ...(failureCount > 0 ? { blockedReason: "public_search_failed" as const } : {}),
    });
  }

  const independentSources = dedupeSources(sources)
    .sort(compareRelatedSources);
  const searchedPlatforms = coverage
    .filter((entry) => entry.status !== "failed")
    .map((entry) => entry.platform);
  const failedPlatforms = coverage
    .filter((entry) => entry.status === "failed")
    .map((entry) => entry.platform);
  const missing = coverage.flatMap((entry) => {
    if (entry.status === "failed") return [`${entry.platform}: public search failed`];
    if (entry.resultCount === 0) return [`${entry.platform}: no same-place public source found`];
    return [];
  });

  return {
    place,
    sources: independentSources,
    coverage,
    receipt: {
      sourceBoundary: "public_web_index",
      privacy: "owner_private",
      checkedAt: now().toISOString(),
      requestedPlatforms: platforms,
      searchedPlatforms,
      failedPlatforms,
      rawResultCount,
      independentResultCount: independentSources.length,
      missing,
    },
  };
}

export function buildRelatedSourceQueries(
  place: RelatedSourcePlaceIdentity,
  platform: RelatedSourcePlatform,
): string[] {
  const definition = platformDefinitions[platform];
  if (!definition) throw new RelatedPlaceSourcesInputError("Unsupported platform");

  const name = normalizeQueryValue(place.name, 100);
  const location = publicSearchLocationClue(place.address);
  const base = [`site:${definition.queryDomain}`, quoteQueryValue(name)];
  return uniqueStrings([
    [...base, location ? quoteQueryValue(location) : ""].filter(Boolean).join(" "),
    base.join(" "),
  ])
    .slice(0, maxQueriesPerPlatform)
    .map((query) => query.slice(0, maxQueryLength).trim());
}

export function relatedPlaceSourcePackResponseBody(
  pack: RelatedPlaceSourcePack,
): Record<string, unknown> {
  return {
    place: {
      id: pack.place.id,
      name: pack.place.name,
      address: pack.place.address,
      latitude: pack.place.latitude ?? null,
      longitude: pack.place.longitude ?? null,
      google_place_id: pack.place.googlePlaceId ?? null,
    },
    sources: pack.sources.map((source) => ({
      platform: source.platform,
      url: source.url,
      title: source.title,
      snippet: source.snippet ?? null,
      query: source.query,
      relation: source.relation,
      identity_status: source.identityStatus,
      match_confidence: source.matchConfidence,
    })),
    coverage: pack.coverage.map((entry) => ({
      platform: entry.platform,
      method: entry.method,
      status: entry.status,
      queries: entry.queries,
      inspected_count: entry.inspectedCount,
      result_count: entry.resultCount,
      blocked_reason: entry.blockedReason ?? null,
    })),
    receipt: {
      source_boundary: pack.receipt.sourceBoundary,
      privacy: pack.receipt.privacy,
      checked_at: pack.receipt.checkedAt,
      requested_platforms: pack.receipt.requestedPlatforms,
      searched_platforms: pack.receipt.searchedPlatforms,
      failed_platforms: pack.receipt.failedPlatforms,
      raw_result_count: pack.receipt.rawResultCount,
      independent_result_count: pack.receipt.independentResultCount,
      missing: pack.receipt.missing,
    },
  };
}

function normalizePlaceIdentity(
  place: RelatedSourcePlaceIdentity,
): RelatedSourcePlaceIdentity {
  const id = normalizeQueryValue(place.id, 100);
  const name = normalizeQueryValue(place.name, 120);
  const address = normalizeQueryValue(place.address, 180);
  const category = normalizeQueryValue(place.category ?? "", 80);

  if (!id || !name) {
    throw new RelatedPlaceSourcesInputError("Confirmed place id and name are required");
  }
  if (privatePlacePattern.test(name) || privateCategoryPattern.test(category)) {
    throw new RelatedPlaceSourcesInputError("Related-source discovery only supports public venues");
  }

  return {
    id,
    name,
    address,
    latitude: finiteNumber(place.latitude),
    longitude: finiteNumber(place.longitude),
    category: category || undefined,
    googlePlaceId: normalizeQueryValue(place.googlePlaceId ?? "", 180) || undefined,
    sourceUrl: canonicalizeSourceURL(place.sourceUrl),
  };
}

function relatedSourceFromSearchResult(
  place: RelatedSourcePlaceIdentity,
  platform: RelatedSourcePlatform,
  result: SourceSearchResult,
): RelatedPlaceSource | undefined {
  const url = canonicalizeSourceURL(result.url);
  if (!url || !isAllowedPlatformURL(platform, url)) return undefined;

  const title = boundedText(result.title, maxTitleLength);
  const snippet = boundedText(result.snippet ?? "", maxSnippetLength);
  if (!title) return undefined;

  const evidence = canonicalText(`${title} ${snippet}`);
  const canonicalName = canonicalText(place.name);
  if (canonicalName.length < 2 || !evidence.includes(canonicalName)) return undefined;

  if (
    hasConflictingRegionEvidence(place.address, `${title} ${snippet}`)
    || hasConflictingBranchEvidence(place.address, `${title} ${snippet}`)
  ) {
    return undefined;
  }
  const locationMatched = branchLocationEvidenceTokens(place.address)
    .some((token) => evidence.includes(token));
  const relation: RelatedSourceRelation = locationMatched ? "same_place" : "mentions_place";
  const matchConfidence = relation === "same_place" ? 0.86 : 0.62;

  return {
    platform,
    url,
    title,
    snippet: snippet || undefined,
    query: boundedText(result.query, maxQueryLength),
    relation,
    identityStatus: "candidate",
    matchConfidence,
  };
}

function isAllowedPlatformURL(
  platform: RelatedSourcePlatform,
  value: string,
): boolean {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return false;

  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  const definition = platformDefinitions[platform];
  if (!definition.hosts.some((domain) => host === domain || host.endsWith(`.${domain}`))) {
    return false;
  }

  const path = url.pathname.toLowerCase().replace(/\/+$/, "") || "/";
  if (path === "/") return false;
  if (path === "/explore") return false;
  if (platform === "instagram" && path.startsWith("/explore/")) return false;
  return !genericPathPrefixes.some((prefix) => path === prefix || path.startsWith(`${prefix}/`));
}

function branchLocationEvidenceTokens(address: string): string[] {
  const normalized = canonicalText(address);
  if (!normalized) return [];

  const tokens = new Set<string>();
  if (normalized.length >= 8) tokens.add(normalized);

  const addressWithoutLocality = address
    .replace(regionPattern, " ")
    .replace(/[\p{L}\p{N}]{1,16}?(?:區|区|鄉|乡|鎮|镇|村|里)/gu, " ");
  for (const match of addressWithoutLocality
    .match(/[\p{L}\p{N}]{2,24}?(?:路|街|道|巷)/gu) ?? []) {
    tokens.add(canonicalText(match));
  }

  const firstAddressPart = canonicalText(address.split(/[,，、|]/)[0] ?? "");
  if (
    firstAddressPart.length >= 5
    && firstAddressPart.length <= 60
    && (
      /\d/.test(firstAddressPart)
      || /(?:street|st|road|rd|avenue|ave|boulevard|blvd|lane|ln|drive|dr)\b/i
        .test(firstAddressPart)
    )
  ) {
    tokens.add(firstAddressPart);
  }

  return [...tokens].filter((token) => token.length >= 2);
}

function publicSearchLocationClue(address: string): string {
  const region = address.match(regionPattern)?.[0];
  if (region) return normalizeQueryValue(region, 40);

  const parts = address
    .split(/[,，、|]/)
    .map((part) => normalizeQueryValue(part, 60))
    .filter(Boolean);
  if (parts.length >= 2) {
    const locality = parts.find((part, index) =>
      index > 0 &&
      /[\p{L}]/u.test(part) &&
      !/^(?:[A-Z]{2}\s+\d{4,10}|\d{4,10})$/i.test(part)
    );
    return locality ?? "";
  }
  return "";
}

function hasConflictingRegionEvidence(address: string, evidence: string): boolean {
  const expected = new Set((address.match(regionPattern) ?? []).map(canonicalText));
  const observed = new Set((evidence.match(regionPattern) ?? []).map(canonicalText));
  if (expected.size === 0 || observed.size === 0) return false;
  return ![...observed].some((region) => expected.has(region));
}

function hasConflictingBranchEvidence(address: string, evidence: string): boolean {
  const expected = new Set(branchAdministrativeTokens(address));
  const observed = new Set(branchAdministrativeTokens(evidence));
  if (expected.size === 0 || observed.size === 0) return false;
  return ![...observed].some((branch) => expected.has(branch));
}

function branchAdministrativeTokens(value: string): string[] {
  const withoutRegion = value.replace(regionPattern, " ");
  return uniqueStrings(
    (withoutRegion.match(/[\p{L}\p{N}]{1,16}?(?:區|区|鄉|乡|鎮|镇|村|里)/gu) ?? [])
      .map(canonicalText)
      .filter((token) => token.length >= 2),
  );
}

function canonicalizeSourceURL(value: string | undefined): string | undefined {
  if (!value) return undefined;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" && url.protocol !== "http:") return undefined;
    url.protocol = "https:";
    url.hostname = url.hostname.toLowerCase().replace(/^www\./, "");
    url.hash = "";
    for (const key of [...url.searchParams.keys()]) {
      if (trackingParameters.has(key.toLowerCase()) || key.toLowerCase().startsWith("utm_")) {
        url.searchParams.delete(key);
      }
    }
    url.searchParams.sort();
    if (url.pathname.length > 1) url.pathname = url.pathname.replace(/\/+$/, "");
    return url.toString();
  } catch {
    return undefined;
  }
}

function isSeedSource(seedURL: string | undefined, resultURL: string): boolean {
  const seed = canonicalizeSourceURL(seedURL);
  return seed !== undefined && seed === canonicalizeSourceURL(resultURL);
}

function dedupeSources(sources: RelatedPlaceSource[]): RelatedPlaceSource[] {
  const byURL = new Map<string, RelatedPlaceSource>();
  for (const source of sources) {
    const existing = byURL.get(source.url);
    if (!existing || compareRelatedSources(source, existing) < 0) {
      byURL.set(source.url, source);
    }
  }
  return [...byURL.values()];
}

function compareRelatedSources(
  left: RelatedPlaceSource,
  right: RelatedPlaceSource,
): number {
  return right.matchConfidence - left.matchConfidence ||
    left.platform.localeCompare(right.platform) ||
    left.url.localeCompare(right.url);
}

function uniquePlatforms(values: RelatedSourcePlatform[]): RelatedSourcePlatform[] {
  const supported = new Set<RelatedSourcePlatform>(relatedSourcePlatforms);
  const result: RelatedSourcePlatform[] = [];
  for (const value of values) {
    if (!supported.has(value)) {
      throw new RelatedPlaceSourcesInputError("Unsupported platform");
    }
    if (!result.includes(value)) result.push(value);
  }
  if (result.length === 0) {
    throw new RelatedPlaceSourcesInputError("At least one platform is required");
  }
  return result;
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function normalizeQueryValue(value: string, maxLength: number): string {
  return value
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\bsite\s*:/gi, "")
    .replace(/["“”]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
}

function quoteQueryValue(value: string): string {
  return `"${value.replace(/"/g, "")}"`;
}

function canonicalText(value: string): string {
  return value
    .toLowerCase()
    .normalize("NFKC")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function boundedText(value: string, maxLength: number): string {
  return value.replace(/\s+/g, " ").trim().slice(0, maxLength);
}

function finiteNumber(value: number | undefined): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function boundedDeadlineMs(value: number | undefined): number {
  if (value === undefined) return defaultSearchDeadlineMs;
  if (!Number.isFinite(value)) return defaultSearchDeadlineMs;
  return Math.max(10, Math.min(defaultSearchDeadlineMs, Math.trunc(value)));
}

async function mapWithConcurrency<Input, Output>(
  inputs: Input[],
  concurrency: number,
  transform: (input: Input) => Promise<Output>,
): Promise<Output[]> {
  const outputs = new Array<Output>(inputs.length);
  let nextIndex = 0;

  async function worker(): Promise<void> {
    while (nextIndex < inputs.length) {
      const index = nextIndex;
      nextIndex += 1;
      outputs[index] = await transform(inputs[index]);
    }
  }

  const workerCount = Math.min(Math.max(1, concurrency), inputs.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
  return outputs;
}

async function waitForSearch<T>(
  search: Promise<T>,
  signal: AbortSignal,
): Promise<T> {
  if (signal.aborted) throw new Error("Related-source search deadline exceeded");

  return await new Promise<T>((resolve, reject) => {
    let settled = false;
    const finish = (callback: () => void) => {
      if (settled) return;
      settled = true;
      signal.removeEventListener("abort", onAbort);
      callback();
    };
    const onAbort = () => finish(() =>
      reject(new Error("Related-source search deadline exceeded"))
    );
    signal.addEventListener("abort", onAbort, { once: true });
    search.then(
      (value) => finish(() => resolve(value)),
      (error: unknown) => finish(() => reject(error)),
    );
  });
}

async function defaultPublicIndexSearch(
  query: string,
  _platform: RelatedSourcePlatform,
  signal?: AbortSignal,
): Promise<SourceSearchResult[]> {
  return await searchPublicWebResults(
    query,
    undefined,
    maxResultsPerPlatformLimit,
    signal,
  );
}
