import { Buffer } from "buffer";
import { Place, PlaceCategory, SharedPlaceData, SharedTripData, SourcePlatform } from "./models";

const placeBaseUrl =
  normalizedEnvValue(process.env.EXPO_PUBLIC_SAVE_PLACE_SHARE_BASE_URL) ??
  "https://sav-e-app.vercel.app/p";
const tripBaseUrl =
  normalizedEnvValue(process.env.EXPO_PUBLIC_SAVE_TRIP_SHARE_BASE_URL) ??
  normalizedEnvValue(process.env.EXPO_PUBLIC_SAVE_SHARE_BASE_URL) ??
  normalizedEnvValue(process.env.EXPO_PUBLIC_WANDERLY_SHARE_BASE_URL) ??
  "https://sav-e-app.vercel.app/trip";

const acceptedShareHosts = new Set([
  "sav-e-app.vercel.app",
]);
const sharedPlacePayloadMaxBytes = 12 * 1024;
const sharedPlaceEmbeddedTokenMaxCharacters = 16 * 1024;
const sharedPlacePublicURLMaxCharacters = 2 * 1024;

export function buildSharedTripData(
  name: string,
  city: string,
  places: Place[]
): SharedTripData {
  return {
    name,
    city,
    stops: places.map((place) => ({
      id: place.id,
      name: place.name,
      address: place.address,
      lat: place.latitude,
      lng: place.longitude,
      time: place.time,
      note: place.note,
    })),
  };
}

export function buildTripLink(
  trip: SharedTripData,
  baseUrl = tripBaseUrl
): string {
  return `${baseUrl}/${encodePayload(trip)}`;
}

export function isSavePlaceLink(value: string): boolean {
  try {
    const url = new URL(value);
    const placeBase = new URL(placeBaseUrl);
    const isConfiguredShareBase = url.hostname === placeBase.hostname;
    const protocolAccepted = acceptedShareHosts.has(url.hostname)
      ? url.protocol === "https:"
      : isConfiguredShareBase && url.protocol === placeBase.protocol;
    return (
      protocolAccepted &&
      (acceptedShareHosts.has(url.hostname) || isConfiguredShareBase) &&
      (url.pathname === placeBase.pathname ||
        url.pathname.startsWith(`${placeBase.pathname}/`))
    );
  } catch {
    return false;
  }
}

export function isSaveTripLink(value: string): boolean {
  try {
    const url = new URL(value);
    return [tripBaseUrl].some((candidate) => {
      const candidateUrl = new URL(candidate);
      return (
        url.protocol === candidateUrl.protocol &&
        (acceptedShareHosts.has(url.hostname) || url.hostname === candidateUrl.hostname) &&
        (url.pathname === candidateUrl.pathname ||
          url.pathname.startsWith(`${candidateUrl.pathname}/`))
      );
    });
  } catch {
    return false;
  }
}

export function isSaveMySavesLink(value: string): boolean {
  return Boolean(mySavesToken(value));
}

export function mySavesToken(value: string): string | null {
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:" ||
      (!acceptedShareHosts.has(url.hostname) && !url.hostname.endsWith("up.railway.app"))
    ) {
      return null;
    }
    return routeToken(url, "my");
  } catch {
    return null;
  }
}

export function decodePlaceLink(link: string): SharedPlaceData | null {
  try {
    const url = new URL(link);
    if (!isSavePlaceLink(link)) return null;
    const payload = routeToken(url, "p");
    if (
      !payload
      || payload.length > sharedPlaceEmbeddedTokenMaxCharacters
      || !isEmbeddedPlacePayloadToken(payload)
    ) return null;
    const json = Buffer.from(decodePayload(payload), "base64").toString("utf8");
    const parsed = JSON.parse(json) as unknown;
    return sanitizeSharedPlaceData(parsed);
  } catch {
    return null;
  }
}

export function sanitizeSharedPlaceData(value: unknown): SharedPlaceData | null {
  const payload = objectValue(value);
  if (!payload || jsonByteLength(payload) > sharedPlacePayloadMaxBytes) return null;
  const name = normalizedTextValue(payload?.name);
  const lat = finiteNumber(payload?.lat);
  const lng = finiteNumber(payload?.lng);
  if (!payload || !name || lat === undefined || lng === undefined || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return null;
  }

  return {
    id: normalizedTextValue(payload.id) ?? "",
    name,
    address: normalizedTextValue(payload.address) ?? "",
    lat,
    lng,
    category: normalizedTextValue(payload.category) ?? "Place",
    rating: nullableFiniteNumber(payload.rating),
    reviewCount: nullableNonnegativeInteger(payload.reviewCount),
    priceRange: nullableText(payload.priceRange),
    hours: nullableText(payload.hours),
    sourceLabel: normalizedTextValue(payload.sourceLabel) ?? "SAV-E",
    sourceURL: safeHTTPURL(payload.sourceURL),
    photoURLs: Array.isArray(payload.photoURLs)
      ? payload.photoURLs.map(safeHTTPURL).filter(isString).slice(0, 1)
      : [],
    note: safeSharedPlaceNote(payload.note),
  };
}

export function sharedPlaceShortCode(link: string): string | null {
  try {
    const url = new URL(link);
    if (!isSavePlaceLink(link)) return null;
    const token = routeToken(url, "p");
    if (
      !token
      || !/^[A-Za-z0-9_-]{6,32}$/.test(token)
      || isEmbeddedPlacePayloadToken(token)
    ) return null;
    return token;
  } catch {
    return null;
  }
}

export function decodeTripLink(link: string): SharedTripData | null {
  try {
    const url = new URL(link);
    if (!isSaveTripLink(link)) return null;
    const payload = routeToken(url, "trip") ?? url.searchParams.get("d");
    if (!payload) return null;
    const json = Buffer.from(decodePayload(payload), "base64").toString("utf8");
    return JSON.parse(json) as SharedTripData;
  } catch {
    return null;
  }
}

export function sharedPlaceToBookmark(shared: SharedPlaceData, recommender?: string): Place {
  return {
    id: shared.id || `shared_${Date.now()}`,
    name: shared.name || "Shared SAV-E place",
    address: shared.address || "",
    latitude: Number.isFinite(shared.lat) ? shared.lat : 0,
    longitude: Number.isFinite(shared.lng) ? shared.lng : 0,
    category: categoryFromLabel(shared.category),
    status: "wantToGo",
    sourcePlatform: sourcePlatformFromLabel(shared.sourceLabel),
    priceRange: shared.priceRange ?? undefined,
    note: shared.note ?? undefined,
    sourceUrl: shared.sourceURL ?? undefined,
    recommender: normalizedText(recommender),
    importKind: "place",
  };
}

export function findMatchingBookmark(bookmarks: Place[], candidate: Place): Place | undefined {
  return bookmarks.find(
    (place) =>
      (candidate.sourceUrl && place.sourceUrl === candidate.sourceUrl) ||
      (place.name.toLowerCase() === candidate.name.toLowerCase() &&
        place.address.toLowerCase() === candidate.address.toLowerCase()),
  );
}

export function buildAppleMapsUrl(place: Place): string {
  const daddr = encodeURIComponent(place.address || `${place.latitude},${place.longitude}`);
  const q = encodeURIComponent(place.name);
  return `https://maps.apple.com/?daddr=${daddr}&q=${q}`;
}

function normalizedEnvValue(value?: string): string | undefined {
  const trimmed = value?.trim();
  if (!trimmed || trimmed.startsWith("__")) return undefined;
  return trimmed.replace(/\/+$/, "");
}

function normalizedText(value?: string): string | undefined {
  const trimmed = value?.trim();
  return trimmed || undefined;
}

function encodePayload(value: unknown): string {
  return Buffer.from(JSON.stringify(value), "utf8")
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function decodePayload(value: string): string {
  const decoded = decodeURIComponent(value);
  const base64 = decoded.replaceAll("-", "+").replaceAll("_", "/");
  const padding = base64.length % 4;
  return padding === 0 ? base64 : `${base64}${"=".repeat(4 - padding)}`;
}

function isEmbeddedPlacePayloadToken(value: string): boolean {
  if (
    value.length < 80
    || value.length > sharedPlaceEmbeddedTokenMaxCharacters
    || !/^[A-Za-z0-9_-]+$/.test(value)
  ) return false;
  try {
    const json = Buffer.from(decodePayload(value), "base64").toString("utf8");
    const parsed = JSON.parse(json) as Partial<SharedPlaceData>;
    return Boolean(parsed.name && typeof parsed.lat === "number" && typeof parsed.lng === "number");
  } catch {
    return false;
  }
}

function routeToken(url: URL, route: string): string | null {
  const parts = url.pathname.split("/").filter(Boolean);
  const routeIndex = parts.indexOf(route);
  if (routeIndex < 0 || routeIndex + 1 >= parts.length) return null;
  return parts[routeIndex + 1];
}

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function normalizedTextValue(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}

function nullableText(value: unknown): string | null {
  return normalizedTextValue(value) ?? null;
}

function finiteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function nullableFiniteNumber(value: unknown): number | null {
  return finiteNumber(value) ?? null;
}

function nullableNonnegativeInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}

function safeHTTPURL(value: unknown): string | null {
  const text = normalizedTextValue(value);
  if (!text || text.length > sharedPlacePublicURLMaxCharacters) return null;
  try {
    const url = new URL(text);
    const safeProtocol = url.protocol === "http:" || url.protocol === "https:";
    if (!safeProtocol || !url.hostname || url.username || url.password) return null;
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function jsonByteLength(value: unknown): number {
  try {
    return Buffer.byteLength(JSON.stringify(value), "utf8");
  } catch {
    return Number.POSITIVE_INFINITY;
  }
}

function safeSharedPlaceNote(value: unknown): string | null {
  const rawNote = normalizedTextValue(value);
  const note = rawNote?.replace(/\r\n?/g, "\n");
  if (!note || note.length > 180) return null;
  const lines = note.split("\n");
  if (lines.length > 2) return null;
  if (lines.some((line) => {
    const normalized = line.trim().toLocaleLowerCase("en-US");
    return diagnosticNotePrefixes.some((prefix) => normalized.startsWith(prefix));
  })) {
    return null;
  }
  return note;
}

function isString(value: string | null): value is string {
  return typeof value === "string";
}

const diagnosticNotePrefixes = [
  "address clue:",
  "analysis failed:",
  "analysis pipeline:",
  "category clue:",
  "confidence:",
  "debug:",
  "diagnostic:",
  "error:",
  "evidence tier:",
  "google places address:",
  "google places coordinates:",
  "google places refined match:",
  "location clue:",
  "source recovery failed:",
  "source url:",
  "stack trace:",
  "venue name:",
] as const;

function categoryFromLabel(value?: string | null): PlaceCategory {
  const normalized = value?.toLowerCase() ?? "";
  if (normalized.includes("cafe") || normalized.includes("coffee")) return "cafe";
  if (normalized.includes("bar")) return "bar";
  if (normalized.includes("attraction") || normalized.includes("museum") || normalized.includes("park")) return "attraction";
  if (normalized.includes("stay") || normalized.includes("hotel")) return "stay";
  if (normalized.includes("shopping") || normalized.includes("shop")) return "shopping";
  return "food";
}

function sourcePlatformFromLabel(value?: string | null): SourcePlatform {
  const normalized = value?.toLowerCase() ?? "";
  if (normalized.includes("instagram")) return "instagram";
  if (normalized.includes("threads")) return "threads";
  if (normalized.includes("xiaohongshu")) return "xiaohongshu";
  if (normalized.includes("google")) return "googleMaps";
  if (normalized.includes("apple")) return "appleMaps";
  return "other";
}
