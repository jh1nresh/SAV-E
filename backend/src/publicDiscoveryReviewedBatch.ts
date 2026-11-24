import { createHash } from "node:crypto";
import { isIP } from "node:net";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import {
  canonicalSource, isPublicDiscoveryVenueID, publicDiscoveryMaxFileBytes, publicDiscoveryMaxPosts,
  projectCurrentPublicDiscoveryManifest, projectReviewedPublicDiscoveryManifest, readPublicDiscoveryFile,
  publicationDay, publicDiscoveryPagePost, publicDiscoveryPostHasEnded, timestamp,
  validatePublicDiscoveryManifest, validatePublicDiscoveryPlace,
  type PublicDiscoveryPlace, type PublicDiscoveryPost,
} from "./publicDiscovery.js";
import { addVenueHighlights, type PublicLikesObservation } from "./publicDiscoveryHighlights.js";
import { defaultFetchText } from "./sourceSearchWorker.js";
import { publicPostEvidenceFingerprint, publicReviewEmbedURL, threadsParentFingerprintPrefix } from "./publicPostReverification.js";

function publisherPageURL(value: unknown): string | undefined {
  if (typeof value !== "string" || value.length > 2_048 || /[\p{Cc}]/u.test(value)) return;
  try {
    const url = new URL(value);
    const hostname = url.hostname.replace(/\.$/, "");
    const sensitive = /token|auth|credential|passw(?:or)?d|cookie|session|secret|api[_-]?key|^key$/i;
    if (url.protocol !== "https:" || !hostname.includes(".") || isIP(hostname) !== 0
      || /(?:^|\.)(?:localhost|local|internal|home|lan)$/i.test(hostname)
      || url.username || url.password || url.port
      || [...url.searchParams.keys(), ...new URLSearchParams(url.hash.slice(1)).keys()].some(key => sensitive.test(key))) return;
    url.hash = "";
    return url.href;
  } catch { return; }
}

const maxDraftVenues = 20;
const maxReviewedVenues = publicDiscoveryMaxPosts;
const maxCandidatesPerVenue = 50;
// Keep the review workload bounded, including pending rows.
const maxReviewedCandidates = 25_000;
const defaultRecheckOriginalBudget = 100;
const maxRecheckOriginalBudget = 5_000;
const socialPlatforms = ["instagram", "threads"] as const;
type SocialPlatform = typeof socialPlatforms[number];

function venueKey(provider: PublicDiscoveryPlace["provider"], placeID: string): string {
  return `${provider}:${placeID}`;
}

function fields(value: unknown, keys: string[], optional: string[] = []): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid review row");
  const row = value as Record<string, unknown>;
  if (!keys.every(key => Object.hasOwn(row, key)) || Object.keys(row).some(key => !keys.includes(key) && !optional.includes(key))) {
    throw new Error("Invalid review fields");
  }
  return row;
}

function reviewedVenueRows(value: unknown) {
  if (!Array.isArray(value) || value.length < 1 || value.length > maxReviewedVenues) {
    throw new Error("Invalid venue count");
  }
  let candidateCount = 0;
  return value.map((row: unknown) => {
    const venue = fields(row, ["place", "candidates"]);
    if (!Array.isArray(venue.candidates) || venue.candidates.length < 1 || venue.candidates.length > maxCandidatesPerVenue) {
      throw new Error("Invalid venue review");
    }
    candidateCount += venue.candidates.length;
    if (candidateCount > maxReviewedCandidates) throw new Error("Invalid reviewed candidate count");
    return { place: venue.place, candidates: venue.candidates as unknown[] };
  });
}

function publicVenueInventory(value: unknown, limit: number): PublicDiscoveryPlace[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > limit) {
    throw new Error(`Pass 1–${limit} public venues`);
  }
  const identities = new Set<string>();
  return value.map((row: unknown) => {
    if (!row || typeof row !== "object" || !("providerPlaceID" in row) || !isPublicDiscoveryVenueID(row.providerPlaceID)) {
      throw new Error("Invalid public venue ID");
    }
    const place = validatePublicDiscoveryPlace(row);
    const identity = venueKey(place.provider, place.providerPlaceID);
    if (identities.has(identity)) throw new Error("Duplicate public venue");
    identities.add(identity);
    return place;
  });
}

/** Apply the same exact identities as Saved lookups to an explicit public venue inventory. */
export function publicVenueSourceCoverage(raw: unknown, rawIndex: unknown, now = new Date()) {
  const input = fields(raw, ["publicVenues"]);
  const places = publicVenueInventory(input.publicVenues, maxReviewedVenues);
  const index = projectCurrentPublicDiscoveryManifest(rawIndex, now);
  // An expired post stops counting towards coverage. Its reviewed venue
  // identity still routes the next draft to the existing canonical branch.
  const published = validatePublicDiscoveryManifest(rawIndex, new Date(index.generatedAt));
  const aliases = new Map([
    ...(published.googlePlaceAliases ?? []).map(alias => [
      venueKey("google_places", alias.googlePlaceID), venueKey(alias.provider, alias.providerPlaceID),
    ] as const),
    ...(published.applePlaceAliases ?? []).map(alias => [
      venueKey("apple_maps", alias.applePlaceID), venueKey("apple_maps", alias.providerPlaceID),
    ] as const),
  ]);
  const canonicalVenues = new Map(published.posts.map(({ place }) => [
    venueKey(place.provider, place.providerPlaceID), place,
  ]));
  const counts = new Map<string, Record<SocialPlatform, number>>();
  for (const post of index.posts) {
    if (post.locationEvidence !== "reviewed_match" || (post.platform !== "instagram" && post.platform !== "threads")) continue;
    const key = venueKey(post.place.provider, post.place.providerPlaceID);
    const posts = counts.get(key) ?? { instagram: 0, threads: 0 };
    posts[post.platform] += 1;
    counts.set(key, posts);
  }

  let withSources = 0;
  let withBothPlatforms = 0;
  const nextDrafts: Array<{ publicVenues: PublicDiscoveryPlace[] }> = [];
  const uncovered = new Map<string, PublicDiscoveryPlace>();
  const partialVenues = {
    instagram: new Map<string, PublicDiscoveryPlace>(),
    threads: new Map<string, PublicDiscoveryPlace>(),
  };
  const venues = places.map(place => {
    const key = venueKey(place.provider, place.providerPlaceID);
    const canonicalKey = aliases.get(key) ?? key;
    const canonicalPlace = canonicalVenues.get(canonicalKey) ?? place;
    const current = counts.get(canonicalKey);
    const posts = current ?? { instagram: 0, threads: 0 };
    if (current) {
      withSources += 1;
      if (posts.instagram > 0 && posts.threads > 0) withBothPlatforms += 1;
      for (const platform of socialPlatforms) {
        if (posts[platform] === 0) partialVenues[platform].set(canonicalKey, canonicalPlace);
      }
    } else {
      uncovered.set(canonicalKey, canonicalPlace);
    }
    return { key, canonicalKey, posts };
  });
  const missingAll = [...uncovered.values()];
  for (let start = 0; start < missingAll.length; start += maxDraftVenues) {
    nextDrafts.push({ publicVenues: missingAll.slice(start, start + maxDraftVenues) });
  }
  const nextPlatformDrafts: Array<{ platforms: SocialPlatform[]; publicVenues: PublicDiscoveryPlace[] }> = [];
  for (const platform of socialPlatforms) {
    const missing = [...partialVenues[platform].values()];
    for (let start = 0; start < missing.length; start += maxDraftVenues) {
      nextPlatformDrafts.push({ platforms: [platform], publicVenues: missing.slice(start, start + maxDraftVenues) });
    }
  }
  return { requestedPlaces: places.length, withSources, withBothPlatforms,
    withoutSources: places.length - withSources, venues, nextDrafts, nextPlatformDrafts };
}

/** Local operator input. The review file keeps its evidence; the public index
 * publishes only canonical attribution and the confirmed venue. */
export function compileReviewedPublicBatch(raw: unknown, now = new Date()) {
  const { ended, ...result } = projectReviewArchive(raw, now);
  if (result.manifest.posts.length === 0 && result.expired > ended) throw new Error("No current reviewed posts");
  return result;
}

function projectReviewArchive(raw: unknown, now: Date) {
  const batch = fields(raw, ["venues"], ["googlePlaceAliases", "applePlaceAliases"]);
  const reviewedVenues = reviewedVenueRows(batch.venues);
  const generatedAt = now.toISOString();
  const posts: PublicDiscoveryPost[] = [];
  const likes = new Map<string, PublicLikesObservation>();
  const likesByObservation = new Map<string, number>();
  const venueSignatures = new Map<string, string>();
  const associations = new Set<string>();
  let withheld = 0;
  for (const venue of reviewedVenues) {
    const place = validatePublicDiscoveryPlace(venue.place);
    if (!isPublicDiscoveryVenueID(place.providerPlaceID)) throw new Error("Invalid venue review");
    const key = venueKey(place.provider, place.providerPlaceID);
    const signature = JSON.stringify(place);
    const priorVenue = venueSignatures.get(key);
    if (priorVenue !== undefined && priorVenue !== signature) throw new Error("Conflicting reviewed venue");
    venueSignatures.set(key, signature);
    for (const value of venue.candidates) {
      const candidate = fields(value, ["platform", "sourceURL", "authorHandle", "title", "review"], ["observedIn"]);
      if (candidate.observedIn !== undefined && !publisherPageURL(candidate.observedIn)) throw new Error("Invalid publisher evidence URL");
      const platform = candidate.platform;
      if (platform !== "instagram" && platform !== "threads") throw new Error("Unsupported platform");
      const source = canonicalSource(candidate.sourceURL, platform);
      if (platform === "instagram" && new URL(source.url).pathname.startsWith("/tv/")) {
        throw new Error("Unsupported Instagram post path");
      }
      const threadsHandle = platform === "threads"
        ? new URL(source.url).pathname.split("/")[1]!.slice(1) : null;
      if ((threadsHandle !== null && !/^[A-Za-z0-9._]{1,30}$/.test(threadsHandle))
        || (candidate.authorHandle !== null && (typeof candidate.authorHandle !== "string"
        || !/^[A-Za-z0-9._]{1,30}$/.test(candidate.authorHandle)))
        || typeof candidate.title !== "string" || /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u.test(candidate.title)
        || Array.from(candidate.title.trim()).length > 160
        || (threadsHandle !== null && candidate.authorHandle !== null
          && candidate.authorHandle.toLowerCase() !== threadsHandle.toLowerCase())) {
        throw new Error("Invalid attribution");
      }
      const association = JSON.stringify([platform, source.postID, key]);
      if (associations.has(association)) throw new Error("Duplicate reviewed association");
      associations.add(association);
      if (candidate.review === null) {
        withheld += 1;
        continue;
      }
      const review = reviewedEvidence(candidate.review, candidate.observedIn, platform, now);
      if (typeof review.checkedAt !== "string") throw new Error("Invalid review date");
      const id = `${platform}:${source.postID}`;
      const publishedAt = typeof review.publishedAt === "string" ? review.publishedAt : null;
      const publishedOn = typeof review.publishedOn === "string" ? review.publishedOn : undefined;
      const visibleUntil = typeof review.visibleUntil === "string" ? review.visibleUntil : undefined;
      const observation = parsePublicLikes(review.publicLikes, publishedAt ?? publishedOn, now);
      if (observation) {
        const observationKey = JSON.stringify([id, observation.observedAt]);
        const previousCount = likesByObservation.get(observationKey);
        if (previousCount !== undefined && previousCount !== observation.count) {
          throw new Error("Conflicting public likes observations");
        }
        likesByObservation.set(observationKey, observation.count);
        const latest = likes.get(id);
        if (!latest || observation.observedAt > latest.observedAt) likes.set(id, observation);
      }
      posts.push({ id, platform, sourceURL: source.url,
        authorName: null, authorHandle: candidate.authorHandle ?? threadsHandle, title: candidate.title,
        publishedAt,
        verifiedAt: review.checkedAt, visibility: "public", locationEvidence: "reviewed_match",
        cover: null, place,
        ...(publishedOn === undefined ? {} : { publishedOn }),
        ...(visibleUntil === undefined ? {} : { visibleUntil }),
        ...(review.multiVenue === true ? { multiVenue: true } : {}) });
      if (posts.length > publicDiscoveryMaxPosts) throw new Error("Invalid post count");
    }
  }
  const day = 86_400_000;
  const googlePlaceAliases = reviewedAliases(batch.googlePlaceAliases, ["googlePlaceID", "provider", "providerPlaceID"]);
  const applePlaceAliases = reviewedAliases(batch.applePlaceAliases, ["applePlaceID", "providerPlaceID"]);
  const manifest = {
    schemaVersion: 1, generatedAt, expiresAt: new Date(now.getTime() + day).toISOString(),
    coverage: (["instagram", "threads", "xiaohongshu"] as const).map(platform => ({
      platform, status: posts.some(post => post.platform === platform) ? "connected" : "not_connected",
    })),
    posts, ...(googlePlaceAliases.length ? { googlePlaceAliases } : {}),
    ...(applePlaceAliases.length ? { applePlaceAliases } : {}),
  };
  const projected = projectReviewedPublicDiscoveryManifest(manifest, now);
  const expired = posts.length - projected.posts.length;
  const currentManifest = {
    schemaVersion: manifest.schemaVersion, generatedAt, expiresAt: manifest.expiresAt,
    coverage: projected.coverage.map(({ platform, indexedPostCount }) => ({
      platform, status: indexedPostCount > 0 ? "connected" : "not_connected",
    })),
    posts: addVenueHighlights(projected.posts, likes, now),
    ...(projected.googlePlaceAliases ? { googlePlaceAliases: projected.googlePlaceAliases } : {}),
    ...(projected.applePlaceAliases ? { applePlaceAliases: projected.applePlaceAliases } : {}),
  };
  const ended = posts.filter(post => publicDiscoveryPostHasEnded(post, now.getTime())).length;
  return { manifest: currentManifest, withheld, expired, ended };
}

function reviewedAliases(value: unknown, keys: string[]) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 5_000) throw new Error("Invalid reviewed place aliases");
  return value.map(entry => {
    const { branchEvidence, ...alias } = fields(entry, [...keys, "branchEvidence"]);
    if (typeof branchEvidence !== "string" || !branchEvidence.trim() || branchEvidence.length > 1_000) {
      throw new Error("Place alias requires reviewed evidence");
    }
    return alias;
  });
}

function reviewedEvidence(value: unknown, observedIn: unknown, platform: "threads" | "instagram", now: Date) {
  const review = fields(value, ["checkedAt", "origin", "branchEvidence"], ["contentFingerprint", "multiVenue", "publishedAt", "publishedOn", "publicLikes", "visibleUntil"]);
  if (review.multiVenue !== undefined && review.multiVenue !== true) throw new Error("Invalid multi-venue review");
  if ((review.origin !== "public_web_index" && review.origin !== "creator_submission"
    && (review.origin !== "publisher_reference" || !publisherPageURL(observedIn)))
    || typeof review.branchEvidence !== "string" || !review.branchEvidence.trim() || review.branchEvidence.length > 1_000) {
    throw new Error("Branch review evidence is required");
  }
  if (review.contentFingerprint !== undefined) {
    const fingerprint = review.contentFingerprint;
    if (typeof fingerprint !== "string" || (!/^[a-f0-9]{64}$/.test(fingerprint)
      && !(platform === "threads" && fingerprint.startsWith(threadsParentFingerprintPrefix)
        && /^[a-f0-9]{64}$/.test(fingerprint.slice(threadsParentFingerprintPrefix.length))))) {
      throw new Error("Invalid reviewed content fingerprint");
    }
  }
  const normalized = review.visibleUntil === undefined ? review
    : { ...review, visibleUntil: timestamp(review.visibleUntil) };
  if (review.publishedOn !== undefined) {
    const publishedOn = publicationDay(review.publishedOn);
    if (review.publishedAt !== undefined || publishedOn > timestamp(review.checkedAt).slice(0, 10)
      || publishedOn > now.toISOString().slice(0, 10)) {
      throw new Error("Invalid calendar publication day");
    }
  } else if (review.publishedAt !== undefined) {
    const publishedAt = timestamp(review.publishedAt);
    if (publishedAt > timestamp(review.checkedAt)) throw new Error("Publication date follows review");
    return { ...normalized, publishedAt };
  }
  return normalized;
}

function parsePublicLikes(value: unknown, publication: string | undefined, now: Date): PublicLikesObservation | undefined {
  if (value === undefined) return;
  const row = fields(value, ["count", "observedAt"]);
  const observedAt = timestamp(row.observedAt);
  if (typeof row.count !== "number" || !Number.isSafeInteger(row.count) || row.count < 0
    || publication === undefined || observedAt < publication || Date.parse(observedAt) > now.getTime()) {
    throw new Error("Invalid public likes observation");
  }
  return { count: row.count, observedAt };
}

type RecheckOptions = {
  now?: Date; fetchEmbed?: (url: string) => Promise<string>;
  maxOriginals?: number;
};

/** Refresh only a prior branch review whose public original has identical evidence. */
export async function recheckReviewedPublicBatch(raw: unknown, options: RecheckOptions = {}) {
  const maxOriginals = options.maxOriginals === undefined ? defaultRecheckOriginalBudget : options.maxOriginals;
  if (!Number.isInteger(maxOriginals) || maxOriginals < 1 || maxOriginals > maxRecheckOriginalBudget) {
    throw new Error("Invalid original recheck budget. Choose an integer from 1 to 5000");
  }
  const batch = fields(raw, ["venues"], ["googlePlaceAliases", "applePlaceAliases"]);
  const reviewedVenues = reviewedVenueRows(batch.venues);
  const now = options.now ?? new Date();
  const checkedAt = now.toISOString();
  const fetchEmbed = options.fetchEmbed ?? defaultFetchText;
  const summary = { refreshed: 0, unconfirmed: 0, unconfigured: 0, pending: 0 };
  const checksByEmbed = new Map<string, Array<(html: string | undefined) => void>>();
  const venues = reviewedVenues.map(venue => {
    const place = validatePublicDiscoveryPlace(venue.place);
    if (!isPublicDiscoveryVenueID(place.providerPlaceID)) throw new Error("Invalid venue review");
    const candidates = venue.candidates.map(value => {
      const candidate = fields(value, ["platform", "sourceURL", "authorHandle", "title", "review"], ["observedIn"]);
      if (candidate.observedIn !== undefined && !publisherPageURL(candidate.observedIn)) throw new Error("Invalid publisher evidence URL");
      const platform = candidate.platform;
      if (platform !== "instagram" && platform !== "threads") throw new Error("Unsupported platform");
      const sourceURL = canonicalSource(candidate.sourceURL, platform).url;
      if (candidate.review === null) { summary.pending++; return candidate; }
      const review = reviewedEvidence(candidate.review, candidate.observedIn, platform, now);
      const publication = review.publishedAt ?? review.publishedOn;
      parsePublicLikes(review.publicLikes, typeof publication === "string" ? publication : undefined, now);
      const next = { ...candidate, review: { ...review } };
      if (!review.contentFingerprint) { summary.unconfigured++; return next; }
      const includeThreadParent = String(review.contentFingerprint).startsWith(threadsParentFingerprintPrefix);
      const author = candidate.authorHandle;
      const prior = typeof review.checkedAt === "string"
        ? /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,3}))?Z$/.exec(review.checkedAt) : null;
      const timestamp = prior ? `${prior[1]}.${(prior[2] ?? "").padEnd(3, "0")}Z` : "";
      const priorCheck = Date.parse(timestamp);
      if (typeof author !== "string" || !/^[A-Za-z0-9._]{1,30}$/.test(author) || !Number.isFinite(priorCheck)
        || new Date(priorCheck).toISOString() !== timestamp || priorCheck >= now.getTime()
        || (platform === "threads" && new URL(sourceURL).pathname.split("/")[1]!.slice(1).toLowerCase() !== author.toLowerCase())
        || (platform === "instagram" && new URL(sourceURL).pathname.startsWith("/tv/"))) {
        summary.unconfirmed++;
        return next;
      }
      const embedURL = publicReviewEmbedURL(platform, sourceURL);
      const checks = checksByEmbed.get(embedURL) ?? [];
      checks.push(html => {
        try {
          if (html !== undefined
            && publicPostEvidenceFingerprint(html, platform, sourceURL, author, place, includeThreadParent) === review.contentFingerprint) {
            next.review.checkedAt = checkedAt;
            summary.refreshed++;
            return;
          }
        } catch { /* Malformed evidence leaves the prior check date untouched. */ }
        summary.unconfirmed++;
      });
      checksByEmbed.set(embedURL, checks);
      return next;
    });
    return { place: venue.place, candidates };
  });
  if (checksByEmbed.size > maxOriginals) {
    throw new Error(`Recheck budget is ${maxOriginals} distinct originals for ${checksByEmbed.size} queued originals`);
  }
  const queue = [...checksByEmbed];
  for (let start = 0; start < queue.length; start += 3) {
    await Promise.all(queue.slice(start, start + 3).map(async ([url, checks]) => {
      let html: string | undefined;
      try { html = await fetchEmbed(url); }
      catch { /* A failed public read refreshes none of the associated venues. */ }
      for (const check of checks) check(html);
    }));
  }
  return { batch: { ...batch, venues }, summary };
}

/** Assemble reviewed files into one snapshot without publishing a partial subset. */
export async function compileReviewedPublicFiles(files: string[], now = new Date()) {
  return compileReviewedPublicBatch(await readReviewedPublicFiles(files), now);
}

/** Validate the whole archive before any provider read, then compile one fresh snapshot. */
export async function refreshReviewedPublicFiles(files: string[], options: RecheckOptions = {}) {
  const now = options.now ?? new Date();
  const batch = await readReviewedPublicFiles(files);
  projectReviewArchive(batch, now);
  const { batch: refreshed, summary } = await recheckReviewedPublicBatch(batch, { ...options, now });
  const result = compileReviewedPublicBatch(refreshed, now);
  if (result.manifest.posts.length === 0 && result.expired === 0) throw new Error("No current reviewed posts");
  return { ...result, summary };
}

async function readReviewedPublicFiles(files: string[]) {
  if (files.length < 1 || files.length > 25) throw new Error("Pass 1–25 review JSON paths");
  const venues: unknown[] = [];
  const aliases = { googlePlaceAliases: [] as unknown[], applePlaceAliases: [] as unknown[] };
  const aliasFields = ["googlePlaceAliases", "applePlaceAliases"] as const;
  for (const file of files) {
    const batch = fields(await readPublicDiscoveryFile(file), ["venues"], [...aliasFields]);
    if (!Array.isArray(batch.venues) || batch.venues.length === 0 || venues.length + batch.venues.length > maxReviewedVenues) {
      throw new Error("Invalid venue count");
    }
    venues.push(...batch.venues);
    for (const key of aliasFields) {
      const entries = batch[key];
      if (entries === undefined) continue;
      if (!Array.isArray(entries) || aliases[key].length + entries.length > 5_000) {
        throw new Error("Invalid reviewed place aliases");
      }
      aliases[key].push(...entries);
    }
  }
  return { venues, ...aliases };
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  void (async () => {
    const args = process.argv.slice(2);
    const recheckOptions: RecheckOptions = {};
    const budgetArgument = args[1];
    if (budgetArgument?.startsWith("--max-originals=")) {
      if (!["--recheck", "--refresh-index", "--refresh-preview"].includes(args[0] ?? "")
        || !/^--max-originals=[1-9]\d{0,3}$/.test(budgetArgument)) {
        throw new Error("Invalid original recheck budget option");
      }
      recheckOptions.maxOriginals = Number(budgetArgument.slice("--max-originals=".length));
      args.splice(1, 1);
    }
    if (args.length === 2 && args[0] === "--recheck" && args[1]) {
      const { batch, summary } = await recheckReviewedPublicBatch(await readPublicDiscoveryFile(args[1]), recheckOptions);
      const output = `${JSON.stringify(batch)}\n`;
      if (Buffer.byteLength(output) > publicDiscoveryMaxFileBytes) throw new Error("Review batch is too large");
      process.stdout.write(output);
      process.stderr.write(`${JSON.stringify(summary)}\n`);
      return;
    }
    if (args.length === 3 && args[0] === "--coverage" && args[1] && args[2]) {
      const publicVenues = await readPublicDiscoveryFile(args[1]);
      const manifest = await readPublicDiscoveryFile(args[2]);
      const coverage = publicVenueSourceCoverage(publicVenues, manifest);
      process.stdout.write(`${JSON.stringify(coverage)}\n`);
      return;
    }
    const preview = args[0] === "--preview" || args[0] === "--refresh-preview";
    const refresh = args[0] === "--refresh-index" || args[0] === "--refresh-preview";
    const files = preview || refresh ? args.slice(1) : args;
    const now = new Date();
    const result = refresh ? await refreshReviewedPublicFiles(files, { ...recheckOptions, now }) : await compileReviewedPublicFiles(files, now);
    const { manifest, withheld, expired } = result;
    const artifact = preview ? makeReviewedPublicPreview(manifest, now) : manifest;
    const output = `${JSON.stringify(artifact)}\n`;
    if (Buffer.byteLength(output) > publicDiscoveryMaxFileBytes) throw new Error("Manifest is too large");
    process.stdout.write(output);
    process.stderr.write(`${manifest.posts.length} indexed · ${withheld} awaiting review · ${expired} outside the visibility window\n`);
    if ("summary" in result) process.stderr.write(`${JSON.stringify(result.summary)}\n`);
  })().catch(() => {
    process.stderr.write("Review batch rejected. Check the input shape, source URLs, attribution, or verification dates.\n");
    process.exitCode = 1;
  });
}

export function makeReviewedPublicPreview(raw: unknown, now = new Date()) {
  const index = projectCurrentPublicDiscoveryManifest(raw, now);
  const { googlePlaceAliases = [], applePlaceAliases, ...page } = index;
  if (page.posts.length === 0) throw new Error("Preview requires at least one reviewed association");
  const deadline = Math.min(Date.parse(page.expiresAt),
    ...page.posts.flatMap(post => post.visibleUntil ? [Date.parse(post.visibleUntil)] : []));
  return {
    snapshot: {
      ...page, expiresAt: new Date(deadline).toISOString(), posts: page.posts.map(publicDiscoveryPagePost), nextCursor: null,
      indexRevision: createHash("sha256").update(JSON.stringify(index)).digest("hex"),
    },
    googlePlaceAliases, ...(applePlaceAliases ? { applePlaceAliases } : {}),
  };
}
