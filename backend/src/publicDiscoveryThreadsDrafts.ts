import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import {
  canonicalSource, readPublicDiscoveryFile, type PublicDiscoveryPlace,
} from "./publicDiscovery.js";
import { publicVenueSourceCoverage } from "./publicDiscoveryReviewedBatch.js";
import { boundedResponseText, searchPublicWebResults, type SourceSearchResult } from "./sourceSearchWorker.js";

const keywordSearchURL = "https://graph.threads.net/v1.0/keyword_search";
const searchModes = ["RECENT", "TOP"] as const;
const placeBatchSize = 20;
const pageSize = 20;
const maxResponseBytes = 256_000;

type KeywordSearchMode = typeof searchModes[number];
type SearchMode = KeywordSearchMode | "PUBLIC_WEB";
type SearchStatus = "searched" | "not_configured" | "access_required" | "rate_limited"
  | "unavailable" | "not_attempted";
type DraftCandidate = {
  platform: "threads";
  sourceURL: string;
  authorHandle: string;
  title: string;
  review: null;
};
type SearchRun = {
  mode: SearchMode;
  status: SearchStatus;
  hasMoreResults: boolean;
  candidates: DraftCandidate[];
};
type WebSearch = (query: string) => Promise<SourceSearchResult[]>;
type Options = { token?: string; offset?: number; now?: Date; fetchImpl?: typeof fetch; webSearch?: WebSearch };

function providerStatus(response: Response, code: unknown): SearchStatus {
  if (response.status === 429 || code === 4 || code === 17 || code === 32 || code === 613) {
    return "rate_limited";
  }
  if (response.status === 401 || response.status === 403 || code === 190 || code === 10 || code === 200) {
    return "access_required";
  }
  return "unavailable";
}

function emptyRun(mode: SearchMode, status: SearchStatus): SearchRun {
  return { mode, status, hasMoreResults: false, candidates: [] };
}

function draftCandidate(value: unknown): DraftCandidate | undefined {
  if (!value || typeof value !== "object" || !("permalink" in value) || !("username" in value)
    || typeof value.username !== "string" || !/^[A-Za-z0-9._]{1,30}$/.test(value.username)) return;
  try {
    const { url } = canonicalSource(value.permalink, "threads");
    const authorHandle = new URL(url).pathname.split("/")[1]!.slice(1);
    if (authorHandle.toLowerCase() !== value.username.toLowerCase()) return;
    return { platform: "threads", sourceURL: url, authorHandle, title: "", review: null };
  } catch {
    return;
  }
}

async function keywordSearch(
  query: string, mode: KeywordSearchMode, token: string, fetchImpl: typeof fetch,
): Promise<SearchRun> {
  const url = new URL(keywordSearchURL);
  url.search = new URLSearchParams({
    q: query, search_type: mode, fields: "permalink,username", limit: String(pageSize),
  }).toString();

  try {
    const response = await fetchImpl(url, {
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
      redirect: "error",
      signal: AbortSignal.timeout(8_000),
    });
    if ([401, 403, 429].includes(response.status)) {
      void response.body?.cancel().catch(() => {});
      return emptyRun(mode, providerStatus(response, undefined));
    }
    const payload = JSON.parse(await boundedResponseText(response, maxResponseBytes)) as {
      data?: unknown; error?: { code?: unknown }; paging?: { next?: unknown };
    } | null;
    if (!response.ok || payload?.error) {
      return emptyRun(mode, providerStatus(response, payload?.error?.code));
    }
    if (!Array.isArray(payload?.data)) return emptyRun(mode, "unavailable");
    const candidates = payload.data.slice(0, pageSize).flatMap(row => {
      const draft = draftCandidate(row);
      return draft ? [draft] : [];
    });
    return {
      mode, status: "searched", candidates,
      hasMoreResults: typeof payload.paging?.next === "string" || payload.data.length > pageSize,
    };
  } catch {
    return emptyRun(mode, "unavailable");
  }
}

function webDraftCandidate(value: string | undefined): DraftCandidate | undefined {
  if (!value || value.length > 2_048) return;
  try {
    const link = new URL(value);
    // Threads sometimes adds a caption slug to indexed links. Keep the
    // shortcode and author, then apply the regular host and secret checks.
    const match = /^(\/@([A-Za-z0-9._]{1,30})\/post\/[A-Za-z0-9_-]{1,100})(?:\/[^/]+)?\/?$/.exec(link.pathname);
    if (!match) return;
    link.pathname = match[1]!;
    return draftCandidate({ permalink: link.href, username: match[2] });
  } catch {
    return;
  }
}

async function publicWebSearch(place: PublicDiscoveryPlace, search: WebSearch): Promise<SearchRun> {
  const mode = "PUBLIC_WEB";
  const text = (value: string) => value.normalize("NFKC").replace(/[^\p{L}\p{N}.-]+/gu, " ").trim();
  const query = `site:threads.com ${text(place.name)} ${text(place.address).slice(0, 100)}`;
  try {
    const hits = await search(query);
    const candidates = hits.slice(0, 10).map(hit => webDraftCandidate(hit.url))
      .filter((candidate): candidate is DraftCandidate => candidate !== undefined);
    return { mode, status: "searched", hasMoreResults: false,
      candidates };
  } catch (error) {
    const message = error instanceof Error ? error.message : "";
    const status = message === "HTTP 429" ? "rate_limited"
      : ["HTTP 401", "HTTP 403", "Public search requires verification"].includes(message) ? "access_required"
        : "unavailable";
    return emptyRun(mode, status);
  }
}

/** Stages search hits only. Serving an association still requires separate original and branch review. */
export async function collectThreadsDiscoveryDrafts(
  inventory: unknown, currentManifest: unknown, options: Options = {},
) {
  const offset = options.offset ?? 0;
  if (!Number.isSafeInteger(offset) || offset < 0 || offset > 500) {
    throw new Error("Invalid Threads draft offset");
  }
  const coverage = publicVenueSourceCoverage(inventory, currentManifest, options.now);
  const missing = [
    ...coverage.nextDrafts.flatMap(group => group.publicVenues),
    ...coverage.nextPlatformDrafts
      .filter(group => group.platforms.includes("threads")).flatMap(group => group.publicVenues),
  ];
  const places = missing.slice(offset, offset + placeBatchSize);
  const token = options.token?.trim();
  const fetchImpl = options.fetchImpl ?? fetch;
  const webSearch = options.webSearch;
  const runners = webSearch
    ? [{ mode: "PUBLIC_WEB" as const, run: (place: PublicDiscoveryPlace) => publicWebSearch(place, webSearch) }]
    : searchModes.map(mode => ({ mode, run: (place: PublicDiscoveryPlace) => token
      ? keywordSearch(place.name, mode, token, fetchImpl) : emptyRun(mode, "not_configured") }));
  const venues: Array<{ place: PublicDiscoveryPlace; candidates: DraftCandidate[] }> = [];
  const webAuthors = new Map<string, string | null>();
  const searches: Array<{ placeKey: string; modes: Array<Omit<SearchRun, "candidates">> }> = [];
  let halted = false;
  let unavailable = false;

  for (const place of places) {
    const matches = new Map<string, DraftCandidate>();
    const modes: Array<Omit<SearchRun, "candidates">> = [];
    for (const { mode, run: search } of runners) {
      const run: SearchRun = halted ? emptyRun(mode, "not_attempted") : await search(place);
      modes.push({ mode, status: run.status, hasMoreResults: run.hasMoreResults });
      unavailable ||= run.status !== "searched";
      halted ||= run.status === "access_required" || run.status === "rate_limited"
        || (mode === "PUBLIC_WEB" && run.status === "unavailable");
      for (const candidate of run.candidates) {
        const { postID } = canonicalSource(candidate.sourceURL, "threads");
        if (mode === "PUBLIC_WEB") {
          const author = candidate.authorHandle.toLowerCase();
          const previous = webAuthors.get(postID);
          webAuthors.set(postID, previous === undefined || previous === author ? author : null);
        }
        matches.set(postID, candidate);
      }
    }
    if (matches.size > 0) venues.push({ place, candidates: [...matches.values()] });
    searches.push({ placeKey: `${place.provider}:${place.providerPlaceID}`, modes });
  }

  const acceptedVenues = webSearch ? venues.flatMap(({ place, candidates }) => {
    const accepted = candidates.filter(({ sourceURL }) =>
      webAuthors.get(canonicalSource(sourceURL, "threads").postID) !== null);
    return accepted.length ? [{ place, candidates: accepted }] : [];
  }) : venues;
  return {
    draft: { venues: acceptedVenues },
    coverage: {
      totalMissing: missing.length, offset,
      nextOffset: !unavailable && offset + places.length < missing.length ? offset + places.length : null,
      publicSearchAccessVerified: false,
      searches,
    },
  };
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const args = process.argv.slice(2);
  const usePublicWeb = args[0] === "--public-web";
  const [inventoryPath, manifestPath, offset, extra] = usePublicWeb ? args.slice(1) : args;
  void (async () => {
    if (!inventoryPath || !manifestPath || (offset !== undefined && !/^\d{1,3}$/.test(offset))
      || extra !== undefined) {
      throw new Error("Expected inventory, current manifest, and optional numeric offset");
    }
    const [inventory, manifest] = await Promise.all([
      readPublicDiscoveryFile(inventoryPath), readPublicDiscoveryFile(manifestPath),
    ]);
    const result = await collectThreadsDiscoveryDrafts(inventory, manifest, {
      ...(usePublicWeb
        ? { webSearch: query => searchPublicWebResults(query, undefined, 10) }
        : { token: process.env.SAVE_THREADS_KEYWORD_SEARCH_TOKEN }),
      offset: offset === undefined ? undefined : Number(offset),
    });
    process.stdout.write(`${JSON.stringify(result)}\n`);
  })().catch(() => {
    process.stderr.write("Threads drafts could not be generated. Check the public inventory, manifest and offset.\n");
    process.exitCode = 1;
  });
}
