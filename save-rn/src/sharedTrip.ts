import { Buffer } from "buffer";
import { Place, SharedTripData } from "./models";

const legacyTripBaseUrl = "https://wanderly.app/trip";
const tripBaseUrl =
  normalizedEnvValue(process.env.EXPO_PUBLIC_SAVE_SHARE_BASE_URL) ??
  normalizedEnvValue(process.env.EXPO_PUBLIC_WANDERLY_SHARE_BASE_URL) ??
  "https://sav-e-app.vercel.app/trip";

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

export function isSaveTripLink(value: string): boolean {
  try {
    const url = new URL(value);
    return [tripBaseUrl, legacyTripBaseUrl].some((candidate) => {
      const candidateUrl = new URL(candidate);
      return (
        url.protocol === candidateUrl.protocol &&
        url.hostname === candidateUrl.hostname &&
        (url.pathname === candidateUrl.pathname ||
          url.pathname.startsWith(`${candidateUrl.pathname}/`))
      );
    });
  } catch {
    return false;
  }
}

export function decodeTripLink(link: string): SharedTripData | null {
  try {
    const url = new URL(link);
    const payload = routeToken(url) ?? url.searchParams.get("d");
    if (!payload) return null;
    const json = Buffer.from(decodePayload(payload), "base64").toString("utf8");
    return JSON.parse(json) as SharedTripData;
  } catch {
    return null;
  }
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

function routeToken(url: URL): string | null {
  const parts = url.pathname.split("/").filter(Boolean);
  const tripIndex = parts.indexOf("trip");
  if (tripIndex < 0 || tripIndex + 1 >= parts.length) return null;
  return parts[tripIndex + 1];
}
