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
  noteConsentVersion: 1 | null;
  expiresAt: string;
}

export const sharedPlaceLinkLifetimeDays = 30;
export const sharedSenderDisplayNameMaxLength = 80;
export const sharedSenderHandleMaxLength = 40;
export const sharedPlacePayloadMaxBytes = 12 * 1024;
export const sharedPlaceLinkBodyMaxBytes = 16 * 1024;
export const sharedPlaceEmbeddedTokenMaxCharacters = 16 * 1024;
export const sharedPlacePublicURLMaxCharacters = 2 * 1024;

export const publicSharedPlaceLinkSelectSQL = `select
  code,
  payload,
  expires_at,
  created_at,
  sender_display_name,
  sender_handle,
  source_verified_at,
  note_consent_version
from shared_place_links
where code = $1
limit 1`;

export function normalizeSharedPlaceLinkCreate(
  body: JsonObject,
  now = new Date(),
): SharedPlaceLinkCreate {
  const payload = objectValue(body.payload);
  if (!payload) throw new Error("payload is required");

  const name = trimmedString(payload.name);
  const address = trimmedString(payload.address) ?? "";
  const lat = finiteNumber(payload.lat);
  const lng = finiteNumber(payload.lng);
  if (!name) throw new Error("payload.name is required");
  if (lat === undefined || lng === undefined) throw new Error("payload.lat and payload.lng are required");
  if (lat < -90 || lat > 90) throw new Error("payload.lat must be between -90 and 90");
  if (lng < -180 || lng > 180) throw new Error("payload.lng must be between -180 and 180");
  const requestedNoteConsentVersion = body.note_consent_version === 1 ? 1 : null;
  const note = requestedNoteConsentVersion === 1 ? sharedPlaceNote(payload.note) : null;

  const normalizedPayload: SharedPlacePayload = {
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
    sourceURL: safeHTTPURL(payload.sourceURL),
    photoURLs: stringArray(payload.photoURLs).map(safeHTTPURL).filter(isString).slice(0, 1),
    note,
  };
  if (Buffer.byteLength(JSON.stringify(normalizedPayload), "utf8") > sharedPlacePayloadMaxBytes) {
    throw new Error("payload is too large");
  }

  return {
    payload: normalizedPayload,
    sourcePlaceId: trimmedString(body.source_place_id ?? body.sourcePlaceId),
    noteConsentVersion: note ? 1 : null,
    expiresAt: sharedPlaceLinkExpiry(body.expires_at ?? body.expiresAt, now),
  };
}

export function formatSharedPlaceLink(row: JsonObject, shareBaseURL = "https://sav-e-app.vercel.app/p"): JsonObject {
  const sender = verifiedSender(row);
  return {
    code: row.code,
    url: `${shareBaseURL.replace(/\/+$/, "")}/${row.code}`,
    payload: row.payload,
    source_place_id: row.source_place_id ?? null,
    sender,
    expires_at: row.expires_at ?? null,
    created_at: row.created_at,
  };
}

export function formatPublicSharedPlaceLink(
  row: JsonObject,
  shareBaseURL = "https://sav-e-app.vercel.app/p",
): JsonObject {
  const formatted = formatSharedPlaceLink(row, shareBaseURL);
  const payload = objectValue(formatted.payload);
  const publicPayload = payload
    ? {
        ...payload,
        id: "",
        note: row.note_consent_version === 1 ? payload.note ?? null : null,
      }
    : formatted.payload;
  return {
    code: formatted.code,
    url: formatted.url,
    payload: publicPayload,
    sender: formatted.sender,
    expires_at: formatted.expires_at,
    created_at: formatted.created_at,
  };
}

export function isSharedPlaceLinkExpired(expiresAt: unknown, now = new Date()): boolean {
  const expiresTime = expiresAt instanceof Date
    ? expiresAt.getTime()
    : typeof expiresAt === "string"
      ? Date.parse(expiresAt)
      : Number.NaN;
  return Number.isFinite(expiresTime) && expiresTime <= now.getTime();
}

export function normalizeSharedSenderSnapshot(
  displayNameValue: unknown,
  handleValue: unknown,
): { displayName: string | null; handle: string | null } {
  return {
    displayName: boundedSingleLineText(displayNameValue, sharedSenderDisplayNameMaxLength),
    handle: boundedSingleLineText(handleValue, sharedSenderHandleMaxLength),
  };
}

function verifiedSender(row: JsonObject): JsonObject | null {
  if (!row.source_verified_at) return null;
  const snapshot = normalizeSharedSenderSnapshot(row.sender_display_name, row.sender_handle);
  const displayName = snapshot.displayName ?? undefined;
  const handle = snapshot.handle ?? undefined;
  if (!displayName && !handle) return null;

  return {
    display_name: displayName ?? handle,
    handle: handle ?? null,
  };
}

export function isEmbeddedSharePayloadToken(value: string): boolean {
  if (value.length < 80 || value.length > sharedPlaceEmbeddedTokenMaxCharacters) return false;
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

function safeHTTPURL(value: unknown): string | null {
  const text = trimmedString(value);
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

function isString(value: string | null): value is string {
  return typeof value === "string";
}

function sharedPlaceNote(value: unknown): string | null {
  const rawNote = trimmedString(value);
  const note = rawNote?.replace(/\r\n?/g, "\n");
  if (!note) return null;
  if (note.length > 180) throw new Error("payload.note cannot exceed 180 characters");
  const lines = note.split(/\r?\n/);
  if (lines.length > 2) throw new Error("payload.note cannot exceed 2 lines");
  if (lines.some((line) => {
    const normalized = line.trim().toLocaleLowerCase("en-US");
    return diagnosticNotePrefixes.some((prefix) => normalized.startsWith(prefix));
  })) {
    throw new Error("payload.note cannot contain diagnostic output");
  }
  return note;
}

function boundedSingleLineText(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  const singleLine = value
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!singleLine) return null;
  let bounded = singleLine.slice(0, maxLength);
  if (/[\uD800-\uDBFF]$/.test(bounded)) bounded = bounded.slice(0, -1);
  return bounded || null;
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

function sharedPlaceLinkExpiry(value: unknown, now: Date): string {
  const nowTime = now.getTime();
  if (!Number.isFinite(nowTime)) throw new Error("Invalid server time");

  const maxTime = nowTime + sharedPlaceLinkLifetimeDays * 24 * 60 * 60 * 1000;
  if (value === undefined || value === null) return new Date(maxTime).toISOString();

  const text = trimmedString(value);
  const expiresTime = text ? Date.parse(text) : Number.NaN;
  if (!Number.isFinite(expiresTime)) throw new Error("expires_at must be a valid date");
  if (expiresTime <= nowTime) throw new Error("expires_at must be in the future");
  if (expiresTime > maxTime) {
    throw new Error(`expires_at cannot be more than ${sharedPlaceLinkLifetimeDays} days in the future`);
  }
  return new Date(expiresTime).toISOString();
}
