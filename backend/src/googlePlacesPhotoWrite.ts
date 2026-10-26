/// G5: retire stored Google Places photo URLs on place writes.
/// `business_photo_urls` is dropped (unknown column). A Google
/// `source_image_url` is stored as null. Non-Google import images pass
/// through. Unknown extra keys stay on the body so pickFields/build*
/// can keep silently ignoring them. Never throws — old App saves must
/// not fail.
///
/// Matching is host- or resource-name scoped after repeated
/// percent-decode. The previous `place/photo` substring was too wide
/// (`marketplace/photo`, `workplace/photo`). On
/// `lh*.googleusercontent.com`, Places photo path segments
/// `/place-photos/`, `/places/`, `/p/`, `/gps-cs-s/`, `/gps-proxy/`
/// are nulled. Avatar paths `/a/` and `/a-/` stay.

export type PlaceWriteBody = Record<string, unknown>;

const retiredPhotoOnlyKeys = new Set(["business_photo_urls"]);
const patchImmutableKeys = new Set(["id", "user_id", "created_at", "updated_at"]);

const googlePhotoHosts = new Set([
  "maps.googleapis.com",
  "places.googleapis.com",
]);

const googleusercontentPlacesSegments = new Set([
  "place-photos",
  "places",
  "p",
  "gps-cs-s",
  "gps-proxy",
]);

export function decodePercentLayers(value: string, maxLayers = 8): string {
  let current = value;
  for (let i = 0; i < maxLayers; i++) {
    let next: string;
    try {
      next = decodeURIComponent(current);
    } catch {
      next = decodeURIComponentSafe(current);
    }
    if (next === current) break;
    current = next;
  }
  return current;
}

function decodeURIComponentSafe(value: string): string {
  return value.replace(/%[0-9A-Fa-f]{2}/g, (match) => {
    try {
      return decodeURIComponent(match);
    } catch {
      return match;
    }
  });
}

function omitKeys(body: PlaceWriteBody, blocked: Set<string>): PlaceWriteBody {
  return Object.fromEntries(
    Object.entries(body).filter(([key]) => !blocked.has(key)),
  );
}

export function googleusercontentPathIsPlacesPhoto(path: string): boolean {
  const parts = path.toLowerCase().split("/").filter(Boolean);
  return parts.some((part) => googleusercontentPlacesSegments.has(part));
}

export function isGooglePlacesPhotoURL(value: string): boolean {
  const decoded = decodePercentLayers(value).trim();
  if (!decoded) return false;
  const lower = decoded.toLowerCase();

  if (/^places\/[^/]+\/photos(\/|$)/i.test(lower)) return true;

  const hasPhotoReference = lower.includes("photo_reference=");

  try {
    const url = new URL(decoded);
    const host = url.hostname.toLowerCase();
    const path = url.pathname.toLowerCase();
    if (host === "maps.googleapis.com" && path.includes("/maps/api/place/photo")) {
      return true;
    }
    if (host === "places.googleapis.com" && (path.includes("/photos/") || path.includes("/media"))) {
      return true;
    }
    if ((host === "googleusercontent.com" || host.endsWith(".googleusercontent.com")) && googleusercontentPathIsPlacesPhoto(path)) {
      return true;
    }
    if (hasPhotoReference && (googlePhotoHosts.has(host) || host.endsWith(".googleapis.com"))) {
      return true;
    }
  } catch {
    if (hasPhotoReference) return true;
    return false;
  }

  // Legacy Places Photo API query. A non-Google host that reuses this
  // parameter name is still treated as a Places photo (existing contract).
  return hasPhotoReference;
}

export function persistableSourceImageURL(value: unknown): unknown {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== "string") return null;
  return isGooglePlacesPhotoURL(value) ? null : value;
}

export function sanitizePlaceWriteBody<T extends PlaceWriteBody>(body: T): T {
  const next: PlaceWriteBody = { ...body };
  delete next.business_photo_urls;
  if (Object.prototype.hasOwnProperty.call(next, "source_image_url")) {
    next.source_image_url = persistableSourceImageURL(next.source_image_url);
  }
  return next as T;
}

/// POST /places (including friend-share receipt). Mirrors withOwner then sanitize.
export function sanitizePlacePostBody(rawBody: PlaceWriteBody, userId: string): PlaceWriteBody {
  return sanitizePlaceWriteBody({ ...omitKeys(rawBody, new Set(["user_id"])), user_id: userId });
}

/// PATCH /places/:id. Strips immutable keys the handler refuses to write.
export function sanitizePlacePatchBody(rawBody: PlaceWriteBody): {
  persist: PlaceWriteBody;
  silentPhotoNoop: boolean;
} {
  const writable = omitKeys(rawBody, patchImmutableKeys);
  return {
    persist: sanitizePlaceWriteBody(writable),
    silentPhotoNoop: placeWriteIsSilentPhotoNoop(writable),
  };
}

/// insertFinalPlaceForDecision. Sanitize before pickFields(placeFields).
export function sanitizePlaceWorkflowBody(finalPlace: PlaceWriteBody): PlaceWriteBody {
  return sanitizePlaceWriteBody(finalPlace);
}

/// PATCH whose only remaining field(s) were the retired photo column.
/// Must be a 200 no-op, not 400 "No writable fields", so old Apps do
/// not fail. Does not enter the #293 cap / growth path.
export function placeWriteIsSilentPhotoNoop(body: PlaceWriteBody): boolean {
  const keys = Object.keys(body).filter((key) => body[key] !== undefined);
  return keys.length > 0 && keys.every((key) => retiredPhotoOnlyKeys.has(key));
}
