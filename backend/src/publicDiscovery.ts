import { createHash } from "node:crypto";
import { constants } from "node:fs";
import { open } from "node:fs/promises";

const platforms = ["instagram", "threads", "xiaohongshu"] as const;
export type PublicDiscoveryPlatform = typeof platforms[number];
export type PublicDiscoveryPlace = {
  provider: "apple_maps" | "amap" | "google_places"; providerPlaceID: string; name: string; address: string;
  latitude: number; longitude: number; coordinateSystem: "WGS84"; category: string;
};
export type PublicDiscoveryPost = {
  id: string; platform: PublicDiscoveryPlatform; sourceURL: string;
  authorName: string | null; authorHandle: string | null; title: string; publishedAt: string | null;
  verifiedAt: string; visibility: "public"; locationEvidence: "explicit_geotag" | "reviewed_match";
  cover: { url: string; expiresAt: string; permission: "author" | "provider" } | null;
  place: PublicDiscoveryPlace;
  publishedOn?: string;
  multiVenue?: true;
  highlightRank?: number;
};
export type PublicDiscoveryCoverage = {
  platform: PublicDiscoveryPlatform; status: "connected" | "not_connected"; indexedPostCount: number;
};
export type PublicDiscoveryGoogleAlias = {
  googlePlaceID: string; provider: Exclude<PublicDiscoveryPlace["provider"], "google_places">; providerPlaceID: string;
};
export type PublicDiscoveryCapabilities = { multiVenue?: boolean; googleVenues?: boolean };
export type PublicDiscoveryIndex = {
  schemaVersion: 1; generatedAt: string; expiresAt: string;
  coverage: PublicDiscoveryCoverage[]; posts: PublicDiscoveryPost[];
  googlePlaceAliases?: PublicDiscoveryGoogleAlias[];
};
export type PublicDiscoveryResponse = Omit<PublicDiscoveryIndex, "googlePlaceAliases"> & {
  indexRevision: string; nextCursor: string | null; googlePlaceMatch?: PublicDiscoveryGoogleAlias;
};
export const publicDiscoveryMaxFileBytes = 6 * 1_024 * 1_024;
const day = 24 * 60 * 60 * 1_000;

export class PublicDiscoveryError extends Error {
  readonly code: "public_discovery_unavailable" | "public_discovery_invalid_query";
  constructor(readonly statusCode: 400 | 503) {
    super(statusCode === 503 ? "Public discovery is unavailable." : "Invalid public discovery query or cursor.");
    this.name = "PublicDiscoveryError";
    this.code = statusCode === 503 ? "public_discovery_unavailable" : "public_discovery_invalid_query";
  }
}

function invalid(): never { throw new PublicDiscoveryError(503); }
function queryInvalid(): never { throw new PublicDiscoveryError(400); }
function record(value: unknown, required: string[], optional: string[] = []): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)
    || ![Object.prototype, null].includes(Object.getPrototypeOf(value))) return invalid();
  const object = value as Record<string, unknown>;
  if (Object.keys(object).some(key => !required.includes(key) && !optional.includes(key))
    || required.some(key => !Object.hasOwn(object, key))) return invalid();
  return object;
}
function text(value: unknown, max: number, allowEmpty = false): string {
  if (typeof value !== "string" || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(value)) return invalid();
  const clean = value.trim();
  if ((!allowEmpty && !clean) || Array.from(clean).length > max) return invalid();
  return clean;
}
function nullableText(value: unknown, max: number): string | null {
  return value === null ? null : text(value, max, true) || null;
}
export function timestamp(value: unknown): string {
  if (typeof value !== "string") return invalid();
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,3}))?Z$/.exec(value);
  if (!match) return invalid();
  const canonical = `${match[1]}.${(match[2] ?? "").padEnd(3, "0")}Z`;
  const time = Date.parse(canonical);
  if (!Number.isFinite(time) || new Date(time).toISOString() !== canonical) return invalid();
  return canonical;
}

export function publicationDay(value: unknown): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return invalid();
  timestamp(`${value}T00:00:00Z`);
  return value;
}
function hasSecretParameters(url: URL): boolean {
  const sensitive = /token|auth|credential|password|passwd|cookie|session|secret|api[_-]?key|^key$/i;
  const fragment = new URLSearchParams(url.hash.slice(1));
  return [...url.searchParams.keys(), ...fragment.keys()].some(key => sensitive.test(key));
}
function webURL(value: unknown, max: number): URL {
  const raw = text(value, max);
  let url: URL;
  try { url = new URL(raw); } catch { return invalid(); }
  if (url.protocol !== "https:" || url.username || url.password || url.port || !url.hostname
    || hasSecretParameters(url)) return invalid();
  return url;
}
const threadsHosts = ["threads.com", "www.threads.com", "threads.net", "www.threads.net"];

export function canonicalSource(value: unknown, platform: PublicDiscoveryPlatform): { url: string; postID: string } {
  const url = webURL(value, 2_048);
  const host = url.hostname.toLowerCase();
  let match: RegExpExecArray | null;
  if (platform === "instagram" && ["instagram.com", "www.instagram.com"].includes(host)) {
    match = /^\/(p|reel|reels|tv)\/([A-Za-z0-9_-]{1,100})\/?$/.exec(url.pathname);
    if (match) return { url: `https://www.instagram.com/${match[1] === "reels" ? "reel" : match[1]}/${match[2]}/`, postID: match[2] };
  } else if (platform === "threads" && threadsHosts.includes(host)) {
    match = /^\/@([A-Za-z0-9._]{1,100})\/post\/([A-Za-z0-9_-]{1,100})\/?$/.exec(url.pathname);
    if (match) return { url: `https://www.threads.com/@${match[1]}/post/${match[2]}`, postID: match[2] };
  } else if (platform === "xiaohongshu" && ["xiaohongshu.com", "www.xiaohongshu.com"].includes(host)) {
    match = /^\/(?:explore|discovery\/item)\/([a-fA-F0-9]{24})\/?$/.exec(url.pathname);
    if (match) return { url: `https://www.xiaohongshu.com/explore/${match[1].toLowerCase()}`, postID: match[1].toLowerCase() };
  }
  return invalid();
}

/** Search indexes may append a caption slug to an otherwise exact Threads post. */
export function canonicalIndexedThreadsSource(value: unknown): { url: string; postID: string } | undefined {
  try {
    const url = webURL(value, 2_048);
    const match = /^\/@([A-Za-z0-9._]{1,100})\/post\/([A-Za-z0-9_-]{1,100})(?:\/[^/]+)?\/?$/.exec(url.pathname);
    if (!match) return;
    url.pathname = `/@${match[1]!.toLowerCase()}/post/${match[2]}`;
    return canonicalSource(url.href, "threads");
  } catch {
    return;
  }
}

function cover(value: unknown, platform: PublicDiscoveryPlatform, now: number): PublicDiscoveryPost["cover"] {
  if (value === null || value === undefined) return null;
  const input = record(value, ["url", "expiresAt", "permission"]);
  const url = webURL(input.url, 4_096);
  const host = url.hostname;
  const under = (domain: string) => host === domain || host.endsWith(`.${domain}`);
  const recognized = platform === "xiaohongshu"
    ? under("xhscdn.com") || /^(?:ci|sns-(?:img|webpic)(?:-[a-z0-9]+)*)\.xiaohongshu\.com$/.test(host)
    : under("cdninstagram.com") || under("fbcdn.net");
  const expiresAt = timestamp(input.expiresAt);
  if (!recognized || url.pathname === "/" || Date.parse(expiresAt) <= now
    || typeof input.permission !== "string" || !["author", "provider"].includes(input.permission)) return invalid();
  return { url: url.href, expiresAt, permission: input.permission as "author" | "provider" };
}
export function validatePublicDiscoveryPlace(value: unknown): PublicDiscoveryPlace {
  const input = record(value, ["provider", "providerPlaceID", "name", "address", "latitude", "longitude", "coordinateSystem", "category"]);
  const provider = input.provider;
  if ((provider !== "apple_maps" && provider !== "amap" && provider !== "google_places") || input.coordinateSystem !== "WGS84"
    || typeof input.latitude !== "number" || typeof input.longitude !== "number"
    || !Number.isFinite(input.latitude) || !Number.isFinite(input.longitude)
    || input.latitude < -90 || input.latitude > 90 || input.longitude < -180 || input.longitude > 180
    || (input.latitude === 0 && input.longitude === 0)) return invalid();
  const providerPlaceID = text(input.providerPlaceID, 200);
  if (provider === "google_places" && !isPublicDiscoveryGoogleID(input.providerPlaceID)) return invalid();
  return {
    provider, providerPlaceID,
    name: text(input.name, 80), address: text(input.address, 500),
    latitude: input.latitude === 0 ? 0 : input.latitude, longitude: input.longitude === 0 ? 0 : input.longitude,
    coordinateSystem: "WGS84", category: text(input.category, 80),
  };
}

/** Pure validation for operator tooling/fixtures; never consults accounts or performs acquisition. */
export function validatePublicDiscoveryManifest(value: unknown, now = new Date()): PublicDiscoveryIndex {
  return parsePublicDiscoveryManifest(value, now, "strict");
}

/** Validate the original snapshot, then retain only the sources still current. */
export function projectCurrentPublicDiscoveryManifest(value: unknown, now = new Date()): PublicDiscoveryIndex {
  return parsePublicDiscoveryManifest(value, now, "published");
}

/** For the local compiler only. Check archived identities, then emit current sources. */
export function projectReviewedPublicDiscoveryManifest(value: unknown, now: Date): PublicDiscoveryIndex {
  return parsePublicDiscoveryManifest(value, now, "reviewArchive");
}

function parsePublicDiscoveryManifest(value: unknown, now: Date,
                                      mode: "strict" | "published" | "reviewArchive" | "serving"): PublicDiscoveryIndex {
  const time = now.getTime();
  if (!Number.isFinite(time)) return invalid();
  const input = record(value, ["schemaVersion", "generatedAt", "expiresAt", "coverage", "posts"], ["googlePlaceAliases"]);
  const generatedAt = timestamp(input.generatedAt), expiresAt = timestamp(input.expiresAt);
  const generated = Date.parse(generatedAt), expires = Date.parse(expiresAt);
  if (input.schemaVersion !== 1 || generated > time || generated + day <= time
    || expires <= time || expires <= generated || expires > generated + day
    || !Array.isArray(input.coverage) || input.coverage.length !== 3
    || !Array.isArray(input.posts) || input.posts.length > 5_000) return invalid();
  // Validate the entire artifact as it existed at publication before omitting old rows.
  const sourceValidationTime = mode === "published" || mode === "serving" ? generated : time;
  const statuses = new Map<PublicDiscoveryPlatform, PublicDiscoveryCoverage["status"]>();
  for (const entry of input.coverage) {
    const row = record(entry, ["platform", "status"]);
    if (!platforms.includes(row.platform as PublicDiscoveryPlatform) || statuses.has(row.platform as PublicDiscoveryPlatform)
      || typeof row.status !== "string" || !["connected", "not_connected"].includes(row.status)) return invalid();
    statuses.set(row.platform as PublicDiscoveryPlatform, row.status as PublicDiscoveryCoverage["status"]);
  }
  const associationIDs = new Set<string>(), identities = new Map<string, string>();
  const highlightSlots = new Set<string>();
  const originals = new Map<string, { signature: string; multiVenue: boolean }>();
  const validatedPosts = input.posts.map((value): PublicDiscoveryPost => {
    const row = record(value, ["id", "platform", "sourceURL", "authorName", "authorHandle", "title", "publishedAt", "verifiedAt", "visibility", "locationEvidence", "place"], ["cover", "multiVenue", "highlightRank", "publishedOn"]);
    const platform = row.platform as PublicDiscoveryPlatform;
    if (!platforms.includes(platform) || statuses.get(platform) !== "connected" || row.visibility !== "public"
      || typeof row.locationEvidence !== "string" || !["explicit_geotag", "reviewed_match"].includes(row.locationEvidence)) return invalid();
    const source = canonicalSource(row.sourceURL, platform), id = text(row.id, 120);
    if (id !== `${platform}:${source.postID}`
      || (row.multiVenue !== undefined && (row.multiVenue !== true || row.locationEvidence !== "reviewed_match"))) return invalid();
    const verifiedAt = timestamp(row.verifiedAt), verified = Date.parse(verifiedAt);
    const publishedAt = row.publishedAt === null ? null : timestamp(row.publishedAt);
    const publishedOn = row.publishedOn === undefined ? undefined : publicationDay(row.publishedOn);
    if (verified > generated || (mode !== "reviewArchive" && verified + day <= sourceValidationTime)
      || (publishedAt !== null && Date.parse(publishedAt) > verified)
      || (publishedOn !== undefined && (publishedAt !== null || publishedOn > verifiedAt.slice(0, 10)))) return invalid();
    const venue = validatePublicDiscoveryPlace(row.place), key = JSON.stringify([venue.provider, venue.providerPlaceID]);
    if (row.multiVenue === true && !isPublicDiscoveryVenueID(venue.providerPlaceID)) return invalid();
    const associationID = JSON.stringify([id, key]);
    if (associationIDs.has(associationID)) return invalid();
    associationIDs.add(associationID);
    const highlightRank = row.highlightRank;
    if (highlightRank !== undefined) {
      if (typeof highlightRank !== "number" || ![1, 2, 3].includes(highlightRank)) return invalid();
      const slot = JSON.stringify([key, highlightRank]);
      if (highlightSlots.has(slot)) return invalid();
      highlightSlots.add(slot);
    }
    const authorName = nullableText(row.authorName, 80), authorHandle = nullableText(row.authorHandle, 100);
    const originalSignature = JSON.stringify([source.url, authorName, authorHandle, publishedAt, publishedOn]);
    const prior = originals.get(id);
    if (prior && (!prior.multiVenue || row.multiVenue !== true || prior.signature !== originalSignature)) return invalid();
    originals.set(id, { signature: originalSignature, multiVenue: row.multiVenue === true });
    const signature = JSON.stringify(venue);
    if (identities.has(key) && identities.get(key) !== signature) return invalid();
    identities.set(key, signature);
    return { id, platform, sourceURL: source.url, authorName, authorHandle, title: text(row.title, 160, true), publishedAt,
      verifiedAt, visibility: "public", locationEvidence: row.locationEvidence as PublicDiscoveryPost["locationEvidence"],
      cover: cover(row.cover, platform, sourceValidationTime), place: venue,
      ...(publishedOn === undefined ? {} : { publishedOn }),
      ...(row.multiVenue === true ? { multiVenue: true } : {}),
      ...(highlightRank === undefined ? {} : { highlightRank }) };
  });
  const validatedAliases = validatedGoogleAliases(input.googlePlaceAliases, identities);
  const posts = mode !== "strict"
    ? validatedPosts.filter(post => Date.parse(post.verifiedAt) + day > time).map(post =>
      post.cover && Date.parse(post.cover.expiresAt) <= time ? { ...post, cover: null } : post)
    : validatedPosts;
  if (mode === "serving" && validatedPosts.length > 0 && posts.length === 0) return invalid();
  posts.sort((a, b) => compareText(b.verifiedAt, a.verifiedAt) || compareText(a.id, b.id)
    || compareText(a.place.provider, b.place.provider) || compareText(a.place.providerPlaceID, b.place.providerPlaceID));
  const coverage = platforms.map(platform => ({ platform, status: statuses.get(platform)!,
    indexedPostCount: posts.filter(post => post.platform === platform).length }));
  const activeVenues = new Set(posts.map(({ place }) => JSON.stringify([place.provider, place.providerPlaceID])));
  const googlePlaceAliases = validatedAliases.filter(alias => activeVenues.has(JSON.stringify([alias.provider, alias.providerPlaceID])));
  return { schemaVersion: 1, generatedAt, expiresAt, coverage, posts,
    ...(googlePlaceAliases.length ? { googlePlaceAliases } : {}) };
}

function compareText(a: string, b: string): number { return a < b ? -1 : a > b ? 1 : 0; }

type Bounds = [number, number, number, number];
type VenueFilter = ["apple_maps" | "amap" | "google_places", string];

export function isPublicDiscoveryVenueID(value: unknown): value is string {
  return typeof value === "string" && value.length >= 1 && value.length <= 200 && !/[^!-~]|,/.test(value);
}

export function isPublicDiscoveryGoogleID(value: unknown): value is string {
  return typeof value === "string" && value.length >= 1 && value.length <= 180 && !/[^A-Za-z0-9_-]/.test(value);
}

function validatedGoogleAliases(value: unknown, venues: Map<string, string>): PublicDiscoveryGoogleAlias[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 5_000) return invalid();
  const ids = new Set<string>();
  const aliases = value.map((entry): PublicDiscoveryGoogleAlias => {
    const { googlePlaceID, provider, providerPlaceID } = record(entry, ["googlePlaceID", "provider", "providerPlaceID"]);
    if (!isPublicDiscoveryGoogleID(googlePlaceID) || ids.has(googlePlaceID)
      || (provider !== "apple_maps" && provider !== "amap") || !isPublicDiscoveryVenueID(providerPlaceID)
      || venues.has(JSON.stringify(["google_places", googlePlaceID]))
      || !venues.has(JSON.stringify([provider, providerPlaceID]))) return invalid();
    ids.add(googlePlaceID);
    return { googlePlaceID, provider, providerPlaceID };
  });
  return aliases.sort((a, b) => a.googlePlaceID < b.googlePlaceID ? -1 : a.googlePlaceID > b.googlePlaceID ? 1 : 0);
}

function query(url: URL): { bounds: Bounds; venue: VenueFilter | null; limit: number; cursor: string | null } {
  const keys = [...url.searchParams.keys()];
  if (keys.some(key => !["bbox", "provider", "placeID", "limit", "cursor"].includes(key))
    || new Set(keys).size !== keys.length) return queryInvalid();
  const provider = url.searchParams.get("provider"), placeID = url.searchParams.get("placeID");
  let venue: VenueFilter | null = null;
  if (provider !== null || placeID !== null) {
    if (provider === "google_places" && isPublicDiscoveryGoogleID(placeID)) venue = [provider, placeID];
    else if ((provider === "apple_maps" || provider === "amap") && isPublicDiscoveryVenueID(placeID)) {
      venue = [provider, placeID];
    } else return queryInvalid();
  }
  const raw = url.searchParams.get("bbox");
  if (!raw || raw.length > 300) return queryInvalid();
  const pieces = raw.split(",").map(value => value.trim());
  const number = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i;
  if (pieces.length !== 4 || pieces.some(value => !number.test(value))) return queryInvalid();
  const bounds = pieces.map(value => Number(value) || 0) as Bounds;
  const [west, south, east, north] = bounds;
  if (bounds.some(value => !Number.isFinite(value)) || west < -180 || west > 180 || east < -180 || east > 180
    || south < -90 || south > 90 || north < -90 || north > 90 || south >= north) return queryInvalid();
  const rawLimit = url.searchParams.get("limit") ?? "30";
  if (!/^[1-9]\d?$/.test(rawLimit) || Number(rawLimit) > 50) return queryInvalid();
  const cursor = url.searchParams.get("cursor");
  if (cursor !== null && !/^[A-Za-z0-9_-]{43}$/.test(cursor)) return queryInvalid();
  return { bounds, venue, limit: Number(rawLimit), cursor };
}
function inBounds(post: PublicDiscoveryPost, [west, south, east, north]: Bounds): boolean {
  const { latitude, longitude } = post.place;
  const includes = (lon: number) => west <= east ? lon >= west && lon <= east : lon >= west || lon <= east;
  return latitude >= south && latitude <= north
    && (includes(longitude) || (Math.abs(longitude) === 180 && includes(-longitude)));
}
function cursorFor(indexRevision: string, bounds: Bounds, venue: VenueFilter | null, limit: number, offset: number): string {
  const scope = venue === null ? [indexRevision, bounds, limit, offset] : [indexRevision, bounds, venue, limit, offset];
  return createHash("sha256").update(JSON.stringify(scope)).digest("base64url");
}
export async function readPublicDiscoveryFile(filePath: string): Promise<unknown> {
  const handle = await open(filePath, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = await handle.stat();
    if (!before.isFile() || before.size < 1 || before.size > publicDiscoveryMaxFileBytes) return invalid();
    const buffer = Buffer.alloc(Math.min(before.size + 1, publicDiscoveryMaxFileBytes));
    let length = 0;
    while (length < buffer.length) {
      const { bytesRead } = await handle.read(buffer, length, buffer.length - length, length);
      if (!bytesRead) break;
      length += bytesRead;
    }
    const after = await handle.stat();
    if (length !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs) return invalid();
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(buffer.subarray(0, length)));
  } finally { await handle.close(); }
}

export async function listPublicDiscoveryPosts(
  url: URL, options: PublicDiscoveryCapabilities & { filePath?: string; now?: Date } = {},
): Promise<PublicDiscoveryResponse> {
  const { bounds, venue, limit, cursor } = query(url);
  const filePath = options.filePath ?? process.env.SAVE_PUBLIC_DISCOVERY_INDEX_FILE;
  if (!filePath?.trim()) return invalid();
  let now: Date;
  let index: PublicDiscoveryIndex;
  try {
    const contents = await readPublicDiscoveryFile(filePath);
    now = options.now ?? new Date();
    index = parsePublicDiscoveryManifest(contents, now, "serving");
  } catch { return invalid(); }
  const revisionPayload = options.googleVenues ? [index, "googleVenues", options.multiVenue === true]
    : options.multiVenue ? [index, "multiVenue"] : index;
  const indexRevision = createHash("sha256").update(JSON.stringify(revisionPayload)).digest("hex");
  const visiblePosts = options.googleVenues ? index.posts : index.posts.filter(post => post.place.provider !== "google_places");
  const coverage = index.coverage.map(item => {
    const entries = visiblePosts.filter(post => post.platform === item.platform);
    const indexedPostCount = options.multiVenue ? entries.length : new Set(entries.map(post => post.id)).size;
    return { ...item, indexedPostCount };
  });
  const googlePlaceMatch = venue?.[0] === "google_places"
    ? index.googlePlaceAliases?.find(alias => alias.googlePlaceID === venue[1]) : undefined;
  const filter = googlePlaceMatch ? [googlePlaceMatch.provider, googlePlaceMatch.providerPlaceID] : venue;
  const scoped = visiblePosts.filter(post => inBounds(post, bounds)
    && (filter === null || (post.place.provider === filter[0] && post.place.providerPlaceID === filter[1])));
  // Older clients validate globally unique post IDs. Scoped reads still select the requested branch.
  const seen = new Set<string>();
  const filtered = options.multiVenue ? scoped : scoped.filter(post => {
    if (seen.has(post.id)) return false;
    seen.add(post.id);
    return true;
  });
  let offset = 0;
  if (cursor !== null) {
    let found = false;
    for (let candidate = limit; candidate < filtered.length; candidate += limit) {
      if (cursorFor(indexRevision, bounds, venue, limit, candidate) === cursor) { offset = candidate; found = true; break; }
    }
    if (!found) return queryInvalid();
  }
  const posts = filtered.slice(offset, offset + limit);
  const deadline = Math.min(now.getTime() + 5 * 60 * 1_000, Date.parse(index.expiresAt),
    ...visiblePosts.map(post => Date.parse(post.verifiedAt) + day),
    ...visiblePosts.flatMap(post => post.cover ? [Date.parse(post.cover.expiresAt)] : []));
  return { schemaVersion: 1, indexRevision, generatedAt: index.generatedAt, expiresAt: new Date(deadline).toISOString(),
    coverage, posts, ...(googlePlaceMatch ? { googlePlaceMatch } : {}),
    nextCursor: offset + posts.length < filtered.length ? cursorFor(indexRevision, bounds, venue, limit, offset + posts.length) : null };
}
