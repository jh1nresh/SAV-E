export type JsonObject = Record<string, unknown>;

export type SharedPlacePayload = {
  id: string;
  name: string;
  address: string;
  lat: number;
  lng: number;
  category: string;
  rating?: number | null;
  reviewCount?: number | null;
  priceRange?: string | null;
  hours?: string | null;
  sourceLabel: string;
  sourceURL?: string | null;
  photoURLs: string[];
  note?: string | null;
};

export interface SharedPlaceLinkCreate {
  payload: SharedPlacePayload;
  sourcePlaceId?: string;
  expiresAt?: string;
}

export function normalizeSharedPlaceLinkCreate(body: JsonObject): SharedPlaceLinkCreate {
  const payload = objectValue(body.payload);
  if (!payload) throw new Error("payload is required");

  const name = trimmedString(payload.name);
  const address = trimmedString(payload.address) ?? "";
  const lat = finiteNumber(payload.lat);
  const lng = finiteNumber(payload.lng);
  if (!name) throw new Error("payload.name is required");
  if (lat === undefined || lng === undefined) throw new Error("payload.lat and payload.lng are required");

  return {
    payload: {
      id: trimmedString(payload.id) ?? "",
      name,
      address,
      lat,
      lng,
      category: trimmedString(payload.category) ?? "Place",
      rating: nullableFiniteNumber(payload.rating),
      reviewCount: nullableInteger(payload.reviewCount),
      priceRange: nullableString(payload.priceRange),
      hours: nullableString(payload.hours),
      sourceLabel: trimmedString(payload.sourceLabel) ?? "SAV-E",
      sourceURL: nullableString(payload.sourceURL),
      photoURLs: stringArray(payload.photoURLs).slice(0, 3),
      note: nullableString(payload.note),
    },
    sourcePlaceId: trimmedString(body.source_place_id ?? body.sourcePlaceId),
    expiresAt: dateString(body.expires_at ?? body.expiresAt),
  };
}

export function formatSharedPlaceLink(row: JsonObject, shareBaseURL = "https://sav-e-app.vercel.app/p"): JsonObject {
  return {
    code: row.code,
    url: `${shareBaseURL.replace(/\/+$/, "")}/${row.code}`,
    payload: row.payload,
    source_place_id: row.source_place_id ?? null,
    expires_at: row.expires_at ?? null,
    created_at: row.created_at,
  };
}

export function isEmbeddedSharePayloadToken(value: string): boolean {
  if (value.length < 80) return false;
  if (!/^[A-Za-z0-9_-]+$/.test(value)) return false;
  const decoded = decodeBase64URL(value);
  if (!decoded) return false;
  try {
    const parsed = JSON.parse(decoded);
    return Boolean(parsed && typeof parsed === "object" && "name" in parsed && "lat" in parsed && "lng" in parsed);
  } catch {
    return false;
  }
}

function decodeBase64URL(value: string): string | undefined {
  let base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  const padding = base64.length % 4;
  if (padding > 0) base64 += "=".repeat(4 - padding);
  try {
    return Buffer.from(base64, "base64").toString("utf8");
  } catch {
    return undefined;
  }
}

function objectValue(value: unknown): JsonObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : undefined;
}

function trimmedString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}

function nullableString(value: unknown): string | null {
  return trimmedString(value) ?? null;
}

function finiteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function nullableFiniteNumber(value: unknown): number | null {
  return finiteNumber(value) ?? null;
}

function nullableInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function dateString(value: unknown): string | undefined {
  const text = trimmedString(value);
  if (!text) return undefined;
  return Number.isNaN(Date.parse(text)) ? undefined : text;
}
