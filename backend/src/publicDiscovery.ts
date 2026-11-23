import { createHash } from "node:crypto";
import { constants } from "node:fs";
import { open } from "node:fs/promises";
import { dirname, join } from "node:path";
import { isCatalogDestinationID, matchesCatalogDestination } from "./publicDiscoveryCatalog.js";

const platforms = ["instagram", "threads", "xiaohongshu"] as const;
export type PublicDiscoveryPlatform = typeof platforms[number];
export type PublicDiscoveryPlace = {
  provider: "apple_maps" | "amap" | "google_places" | "taipei_catalog"; providerPlaceID: string; name: string; address: string;
  latitude: number; longitude: number; coordinateSystem: "WGS84"; category: string;
};
export type PublicDiscoveryPost = {
  id: string; platform: PublicDiscoveryPlatform; sourceURL: string;
  authorName: string | null; authorHandle: string | null; title: string; publishedAt: string | null;
  verifiedAt: string; visibility: "public"; locationEvidence: "explicit_geotag" | "reviewed_match";
  cover: { url: string; expiresAt: string; permission: "author" | "provider" } | null;
  place: PublicDiscoveryPlace;
  publishedOn?: string;
  visibleUntil?: string;
  multiVenue?: true;
  highlightRank?: number;
};
export type PublicDiscoveryCoverage = {
  platform: PublicDiscoveryPlatform; status: "connected" | "not_connected"; indexedPostCount: number;
};
export type PublicDiscoveryGoogleAlias = {
  googlePlaceID: string; provider: Exclude<PublicDiscoveryPlace["provider"], "taipei_catalog">; providerPlaceID: string;
};
type PublicDiscoveryAppleAlias = { applePlaceID: string; providerPlaceID: string };
export type PublicDiscoveryCapabilities = { multiVenue?: boolean; googleVenues?: boolean; catalogVenues?: boolean; largeIndex?: boolean };
export type PublicDiscoveryIndex = {
  schemaVersion: 1; generatedAt: string; expiresAt: string;
  coverage: PublicDiscoveryCoverage[]; posts: PublicDiscoveryPost[];
  googlePlaceAliases?: PublicDiscoveryGoogleAlias[];
  applePlaceAliases?: PublicDiscoveryAppleAlias[];
};
export type PublicDiscoveryResponse = Omit<PublicDiscoveryIndex, "googlePlaceAliases" | "applePlaceAliases"> & {
  indexRevision: string; nextCursor: string | null; googlePlaceMatch?: PublicDiscoveryGoogleAlias;
};
export const publicDiscoveryMaxFileBytes = 6 * 1_024 * 1_024;
export const publicDiscoveryMaxPosts = 5_000;
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
  if ((provider !== "apple_maps" && provider !== "amap" && provider !== "google_places" && provider !== "taipei_catalog")
    || input.coordinateSystem !== "WGS84"
    || typeof input.latitude !== "number" || typeof input.longitude !== "number"
    || !Number.isFinite(input.latitude) || !Number.isFinite(input.longitude)
    || input.latitude < -90 || input.latitude > 90 || input.longitude < -180 || input.longitude > 180
    || (input.latitude === 0 && input.longitude === 0)) return invalid();
  if (provider === "taipei_catalog" && !matchesCatalogDestination(input)) return invalid();
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
                                      mode: "strict" | "published" | "reviewArchive" | "serving",
                                      sharded = false): PublicDiscoveryIndex {
  const time = now.getTime();
  if (!Number.isFinite(time)) return invalid();
  const input = record(value, ["schemaVersion", "generatedAt", "expiresAt", "coverage", "posts"], ["googlePlaceAliases", "applePlaceAliases"]);
  const generatedAt = timestamp(input.generatedAt), expiresAt = timestamp(input.expiresAt);
  const generated = Date.parse(generatedAt), expires = Date.parse(expiresAt);
  if (input.schemaVersion !== 1 || generated > time || generated + day <= time
    || expires <= time || expires <= generated || expires > generated + day
    || !Array.isArray(input.coverage) || input.coverage.length !== 3
    || !Array.isArray(input.posts) || (!sharded && input.posts.length > publicDiscoveryMaxPosts)) return invalid();
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
    const row = record(value, ["id", "platform", "sourceURL", "authorName", "authorHandle", "title", "publishedAt", "verifiedAt", "visibility", "locationEvidence", "place"], ["cover", "multiVenue", "highlightRank", "publishedOn", "visibleUntil"]);
    const platform = row.platform as PublicDiscoveryPlatform;
    if (!platforms.includes(platform) || statuses.get(platform) !== "connected" || row.visibility !== "public"
      || typeof row.locationEvidence !== "string" || !["explicit_geotag", "reviewed_match"].includes(row.locationEvidence)) return invalid();
    const source = canonicalSource(row.sourceURL, platform), id = text(row.id, 120);
    if (id !== `${platform}:${source.postID}`
      || (row.multiVenue !== undefined && (row.multiVenue !== true || row.locationEvidence !== "reviewed_match"))) return invalid();
    const verifiedAt = timestamp(row.verifiedAt), verified = Date.parse(verifiedAt);
    const visibleUntil = row.visibleUntil === undefined ? undefined : timestamp(row.visibleUntil);
    if (visibleUntil !== undefined && (row.locationEvidence !== "reviewed_match"
      || (mode !== "reviewArchive" && Date.parse(visibleUntil) <= sourceValidationTime))) return invalid();
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
      ...(visibleUntil === undefined ? {} : { visibleUntil }),
      ...(row.multiVenue === true ? { multiVenue: true } : {}),
      ...(highlightRank === undefined ? {} : { highlightRank }) };
  });
  const validatedAliases = validatedGoogleAliases(input.googlePlaceAliases, identities, sharded);
  const validatedAppleAliases = validateAppleAliases(input.applePlaceAliases, identities, sharded);
  const scheduledPosts = mode === "strict" ? validatedPosts
    : validatedPosts.filter(post => !publicDiscoveryPostHasEnded(post, time));
  const posts = mode === "strict" ? scheduledPosts : scheduledPosts
    .filter(post => Date.parse(post.verifiedAt) + day > time)
    .map(post => post.cover && Date.parse(post.cover.expiresAt) <= time ? { ...post, cover: null } : post);
  if (mode === "serving" && scheduledPosts.length > 0 && posts.length === 0) return invalid();
  posts.sort((a, b) => compareText(b.verifiedAt, a.verifiedAt) || compareText(a.id, b.id)
    || compareText(a.place.provider, b.place.provider) || compareText(a.place.providerPlaceID, b.place.providerPlaceID));
  const coverage = platforms.map(platform => ({ platform, status: statuses.get(platform)!,
    indexedPostCount: posts.filter(post => post.platform === platform).length }));
  const activeVenues = new Set(posts.map(({ place }) => JSON.stringify([place.provider, place.providerPlaceID])));
  const googlePlaceAliases = validatedAliases.filter(alias => activeVenues.has(JSON.stringify([alias.provider, alias.providerPlaceID])));
  const applePlaceAliases = validatedAppleAliases.filter(alias => activeVenues.has(JSON.stringify(["apple_maps", alias.providerPlaceID])));
  return { schemaVersion: 1, generatedAt, expiresAt, coverage, posts,
    ...(googlePlaceAliases.length ? { googlePlaceAliases } : {}),
    ...(applePlaceAliases.length ? { applePlaceAliases } : {}) };
}

function compareText(a: string, b: string): number { return a < b ? -1 : a > b ? 1 : 0; }

type Bounds = [number, number, number, number];
type VenueFilter = [PublicDiscoveryPlace["provider"], string];

export function isPublicDiscoveryVenueID(value: unknown): value is string {
  return typeof value === "string" && value.length >= 1 && value.length <= 200 && !/[^!-~]|,/.test(value);
}

export function isPublicDiscoveryGoogleID(value: unknown): value is string {
  return typeof value === "string" && value.length >= 1 && value.length <= 180 && !/[^A-Za-z0-9_-]/.test(value);
}

function validatedGoogleAliases(value: unknown, venues: Map<string, string>, sharded: boolean): PublicDiscoveryGoogleAlias[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || (!sharded && value.length > 5_000)) return invalid();
  const ids = new Set<string>();
  const aliases = value.map((entry): PublicDiscoveryGoogleAlias => {
    const { googlePlaceID, provider, providerPlaceID } = record(entry, ["googlePlaceID", "provider", "providerPlaceID"]);
    if (!isPublicDiscoveryGoogleID(googlePlaceID) || ids.has(googlePlaceID)
      || (provider !== "apple_maps" && provider !== "amap" && provider !== "google_places") || !isPublicDiscoveryVenueID(providerPlaceID)
      || venues.has(JSON.stringify(["google_places", googlePlaceID]))
      || !venues.has(JSON.stringify([provider, providerPlaceID]))) return invalid();
    ids.add(googlePlaceID);
    return { googlePlaceID, provider, providerPlaceID };
  });
  return aliases.sort((a, b) => a.googlePlaceID < b.googlePlaceID ? -1 : a.googlePlaceID > b.googlePlaceID ? 1 : 0);
}

function validateAppleAliases(value: unknown, venues: Map<string, string>, sharded: boolean): PublicDiscoveryAppleAlias[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || (!sharded && value.length > publicDiscoveryMaxPosts)) return invalid();
  const ids = new Set<string>();
  const aliases = value.map((entry): PublicDiscoveryAppleAlias => {
    const { applePlaceID, providerPlaceID } = record(entry, ["applePlaceID", "providerPlaceID"]);
    if (!isPublicDiscoveryVenueID(applePlaceID) || !isPublicDiscoveryVenueID(providerPlaceID) || ids.has(applePlaceID)
      || venues.has(JSON.stringify(["apple_maps", applePlaceID]))
      || !venues.has(JSON.stringify(["apple_maps", providerPlaceID]))) return invalid();
    ids.add(applePlaceID);
    return { applePlaceID, providerPlaceID };
  });
  return aliases.sort((a, b) => compareText(a.applePlaceID, b.applePlaceID));
}

function query(url: URL, catalogVenues: boolean): { bounds: Bounds; venue: VenueFilter | null; limit: number; cursor: string | null } {
  const keys = [...url.searchParams.keys()];
  if (keys.some(key => !["bbox", "provider", "placeID", "limit", "cursor"].includes(key))
    || new Set(keys).size !== keys.length) return queryInvalid();
  const provider = url.searchParams.get("provider"), placeID = url.searchParams.get("placeID");
  let venue: VenueFilter | null = null;
  if (provider !== null || placeID !== null) {
    if (provider === "google_places" && isPublicDiscoveryGoogleID(placeID)) venue = [provider, placeID];
    else if (catalogVenues && provider === "taipei_catalog" && isCatalogDestinationID(placeID)) {
      venue = [provider, placeID];
    } else if ((provider === "apple_maps" || provider === "amap") && isPublicDiscoveryVenueID(placeID)) {
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
async function readPublicDiscoveryBytes(filePath: string, digest?: string): Promise<Buffer> {
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
    const bytes = buffer.subarray(0, length);
    if (digest !== undefined && createHash("sha256").update(bytes).digest("hex") !== digest) return invalid();
    return bytes;
  } finally { await handle.close(); }
}

export async function readPublicDiscoveryFile(filePath: string, digest?: string): Promise<unknown> {
  const bytes = await readPublicDiscoveryBytes(filePath, digest);
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

export function publicDiscoveryPostHasEnded(post: PublicDiscoveryPost, time: number): boolean {
  return post.visibleUntil !== undefined && Date.parse(post.visibleUntil) <= time;
}

export function publicDiscoveryPagePost({ visibleUntil: _visibleUntil, ...post }: PublicDiscoveryPost) {
  return post;
}

type DiscoveryShard = Omit<PublicDiscoveryIndex, "coverage"> & {
  coverage: Pick<PublicDiscoveryCoverage, "platform" | "status">[];
};

export function combinePublicDiscoveryShards(parts: DiscoveryShard[], now: Date): PublicDiscoveryIndex {
  const first = parts[0];
  if (!first) return invalid();
  const { generatedAt, expiresAt } = first;
  if (parts.some(part => part.generatedAt !== generatedAt || part.expiresAt !== expiresAt)) return invalid();
  const coverage = platforms.map(platform => ({
    platform, status: parts.some(part => part.coverage.some(row => row.platform === platform && row.status === "connected"))
      ? "connected" : "not_connected",
  }));
  return parsePublicDiscoveryManifest({ schemaVersion: 1, generatedAt, expiresAt, coverage,
    posts: parts.flatMap(part => part.posts),
    googlePlaceAliases: parts.flatMap(part => part.googlePlaceAliases ?? []),
    applePlaceAliases: parts.flatMap(part => part.applePlaceAliases ?? []),
  }, now, "serving", true);
}

function projectionDeadline(index: PublicDiscoveryIndex, posts = index.posts): number {
  let deadline = Date.parse(index.expiresAt);
  for (const post of posts) {
    deadline = Math.min(deadline, Date.parse(post.verifiedAt) + day);
    if (post.visibleUntil) deadline = Math.min(deadline, Date.parse(post.visibleUntil));
    if (post.cover) deadline = Math.min(deadline, Date.parse(post.cover.expiresAt));
  }
  return deadline;
}

type CatalogProjection = {
  filePath: string;
  shardKey: string;
  projectedAt: number;
  deadline: number;
  index: PublicDiscoveryIndex;
  revisions: Map<string, string>;
};

let cachedProjection: CatalogProjection | undefined;

async function readPublicDiscoveryIndex(filePath: string, requestedTime?: Date) {
  const contents = await readPublicDiscoveryFile(filePath);
  if (!contents || typeof contents !== "object" || !("schemaVersion" in contents) || contents.schemaVersion !== 2) {
    const now = requestedTime ?? new Date();
    return { now, index: parsePublicDiscoveryManifest(contents, now, "serving"), sharded: false };
  }
  const { shards } = record(contents, ["schemaVersion", "shards"]);
  if (!Array.isArray(shards) || shards.length === 0 || new Set(shards).size !== shards.length
    || !shards.every(digest => typeof digest === "string" && /^[a-f0-9]{64}$/.test(digest))) return invalid();
  const shardKey = JSON.stringify(shards);
  const directory = dirname(filePath);
  const cached = cachedProjection;
  if (cached?.filePath === filePath && cached.shardKey === shardKey) {
    // Immutable filenames still need a byte-for-byte check. Missing, replaced,
    // or unreadable files must not silently fall back to an older projection.
    for (const digest of shards) await readPublicDiscoveryBytes(join(directory, digest + ".json"), digest);
    const now = requestedTime ?? new Date();
    if (cached.projectedAt <= now.getTime() && now.getTime() < cached.deadline) {
      return { now, index: cached.index, sharded: true, revisions: cached.revisions };
    }
  }
  const parts: PublicDiscoveryIndex[] = [];
  for (const digest of shards) {
    const raw = await readPublicDiscoveryFile(join(directory, digest + ".json"), digest);
    const { generatedAt } = record(raw, ["schemaVersion", "generatedAt", "expiresAt", "coverage", "posts"], ["googlePlaceAliases", "applePlaceAliases"]);
    // Check every shard at publication before dropping any old posts from the combined index.
    parts.push(validatePublicDiscoveryManifest(raw, new Date(timestamp(generatedAt))));
  }
  const now = requestedTime ?? new Date();
  const index = combinePublicDiscoveryShards(parts, now);
  const revisions = new Map<string, string>();
  cachedProjection = { filePath, shardKey, projectedAt: now.getTime(), deadline: projectionDeadline(index), index, revisions };
  return { now, index, sharded: true, revisions };
}

export async function indexedPublicPlatforms(
  filePath: string, place: PublicDiscoveryPlace, now?: Date,
): Promise<ReadonlySet<PublicDiscoveryPlatform>> {
  const { index } = await readPublicDiscoveryIndex(filePath, now);
  return new Set(index.posts.filter(post => post.place.provider === place.provider
    && post.place.providerPlaceID === place.providerPlaceID).map(post => post.platform));
}

export async function listPublicDiscoveryPosts(
  url: URL, options: PublicDiscoveryCapabilities & { filePath?: string; now?: Date } = {},
): Promise<PublicDiscoveryResponse> {
  const { bounds, venue, limit, cursor } = query(url, options.catalogVenues === true);
  const filePath = options.filePath ?? process.env.SAVE_PUBLIC_DISCOVERY_INDEX_FILE;
  if (!filePath?.trim()) return invalid();
  let now: Date;
  let index: PublicDiscoveryIndex;
  let sharded: boolean;
  let revisions: Map<string, string> | undefined;
  try {
    ({ now, index, sharded, revisions } = await readPublicDiscoveryIndex(filePath, options.now));
  } catch { return invalid(); }
  const permittedPosts = options.catalogVenues ? index.posts : index.posts.filter(post => post.place.provider !== "taipei_catalog");
  const compatibleIndex = permittedPosts.length === index.posts.length ? index : {
    ...index, posts: permittedPosts, coverage: index.coverage.map(item => {
      const indexedPostCount = permittedPosts.filter(post => post.platform === item.platform).length;
      const status = indexedPostCount === 0 && item.indexedPostCount > 0 ? "not_connected" as const : item.status;
      return { ...item, status, indexedPostCount };
    }),
  };
  const revisionPayload = options.catalogVenues ? [index, "catalogVenues", !!options.googleVenues, !!options.multiVenue]
    : options.googleVenues ? [compatibleIndex, "googleVenues", options.multiVenue === true]
    : options.multiVenue ? [compatibleIndex, "multiVenue"] : compatibleIndex;
  const revisionKey = JSON.stringify([!!options.catalogVenues, !!options.googleVenues, !!options.multiVenue, !!options.largeIndex]);
  let indexRevision = revisions?.get(revisionKey);
  if (indexRevision === undefined) {
    indexRevision = createHash("sha256")
      .update(JSON.stringify(sharded && options.largeIndex ? [revisionPayload, "largeIndex"] : revisionPayload)).digest("hex");
    revisions?.set(revisionKey, indexRevision);
  }
  const visiblePosts = options.googleVenues ? permittedPosts : permittedPosts.filter(post => post.place.provider !== "google_places");
  const savedAlias = venue?.[0] === "google_places"
    ? index.googlePlaceAliases?.find(alias => alias.googlePlaceID === venue[1]) : undefined;
  const appleAlias = venue?.[0] === "apple_maps"
    ? index.applePlaceAliases?.find(alias => alias.applePlaceID === venue[1]) : undefined;
  const filter = appleAlias ? ["apple_maps", appleAlias.providerPlaceID]
    : savedAlias ? [savedAlias.provider, savedAlias.providerPlaceID] : venue;
  const retiredGoogleID = savedAlias?.provider === "google_places" ? savedAlias.googlePlaceID : undefined;
  const retiredPlaceID = appleAlias?.applePlaceID ?? retiredGoogleID;
  const scoped = visiblePosts.filter(post => inBounds(post, bounds)
    && (filter === null || (post.place.provider === filter[0] && post.place.providerPlaceID === filter[1])));
  // Older clients validate globally unique post IDs. Scoped reads still select the requested branch.
  const seen = new Set<string>();
  const selected = options.multiVenue ? scoped : scoped.filter(post => {
    if (seen.has(post.id)) return false;
    seen.add(post.id);
    return true;
  });
  // Old native readers reject totals above 5,000. In a larger catalog, retain
  // exact/viewport matches by applying their limit only after scoping the query.
  const limited = sharded && !options.largeIndex && visiblePosts.length > publicDiscoveryMaxPosts;
  const filtered = limited ? selected.slice(0, publicDiscoveryMaxPosts) : selected;
  const coverage = compatibleIndex.coverage.map(item => {
    const entries = (limited ? filtered : visiblePosts).filter(post => post.platform === item.platform);
    const indexedPostCount = options.multiVenue ? entries.length : new Set(entries.map(post => post.id)).size;
    return { ...item, indexedPostCount };
  });
  let offset = 0;
  if (cursor !== null) {
    let found = false;
    for (let candidate = limit; candidate < filtered.length; candidate += limit) {
      if (cursorFor(indexRevision, bounds, venue, limit, candidate) === cursor) { offset = candidate; found = true; break; }
    }
    if (!found) return queryInvalid();
  }
  const posts = filtered.slice(offset, offset + limit).map(publicDiscoveryPagePost);
  const deadline = Math.min(now.getTime() + 5 * 60 * 1_000, projectionDeadline(index, visiblePosts));
  // Keep the requested identity in same-provider Saved responses for existing clients.
  const responsePosts = retiredPlaceID ? posts.map(post => ({
    ...post, place: { ...post.place, providerPlaceID: retiredPlaceID },
  })) : posts;
  const googlePlaceMatch = retiredGoogleID === undefined ? savedAlias : undefined;
  const response: PublicDiscoveryResponse = {
    schemaVersion: 1, indexRevision, generatedAt: index.generatedAt, expiresAt: new Date(deadline).toISOString(),
    coverage, posts: responsePosts, ...(googlePlaceMatch ? { googlePlaceMatch } : {}),
    nextCursor: offset + posts.length < filtered.length ? cursorFor(indexRevision, bounds, venue, limit, offset + posts.length) : null,
  };
  return sharded ? structuredClone(response) : response;
}
