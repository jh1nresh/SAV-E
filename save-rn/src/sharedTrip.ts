import { Buffer } from "buffer";
import { Place, PlaceCategory, SharedPlaceData, SharedTripData, SourcePlatform } from "./models";

const legacyTripBaseUrl = "https://wanderly.app/trip";
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
  "sav-e.app",
  "wanderly.app",
]);

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
    return (
      url.protocol === "https:" &&
      (acceptedShareHosts.has(url.hostname) || url.hostname === placeBase.hostname) &&
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
    return [tripBaseUrl, legacyTripBaseUrl].some((candidate) => {
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

export function decodePlaceLink(link: string): SharedPlaceData | null {
  try {
    const url = new URL(link);
    if (!isSavePlaceLink(link)) return null;
    const payload = routeToken(url, "p");
    if (!payload || !isEmbeddedPlacePayloadToken(payload)) return null;
    const json = Buffer.from(decodePayload(payload), "base64").toString("utf8");
    return JSON.parse(json) as SharedPlaceData;
  } catch {
    return null;
  }
}

export function sharedPlaceShortCode(link: string): string | null {
  try {
    const url = new URL(link);
    if (!isSavePlaceLink(link)) return null;
    const token = routeToken(url, "p");
    if (!token || isEmbeddedPlacePayloadToken(token)) return null;
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

export function sharedPlaceToBookmark(shared: SharedPlaceData): Place {
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
    importKind: "place",
  };
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
  if (value.length < 80 || !/^[A-Za-z0-9_-]+$/.test(value)) return false;
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
