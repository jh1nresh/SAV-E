/// G5: retire stored Google Places photo URLs on place writes.
/// `business_photo_urls` is dropped (unknown column). A Google
/// `source_image_url` is stored as null. Non-Google import images pass
/// through. Unknown extra keys stay on the body so pickFields/build*
/// can keep silently ignoring them. Never throws — old App saves must
/// not fail.

export type PlaceWriteBody = Record<string, unknown>;

const retiredPhotoOnlyKeys = new Set(["business_photo_urls"]);

export function isGooglePlacesPhotoURL(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed) return false;
  const lower = trimmed.toLowerCase();
  if (lower.includes("photo_reference=")) return true;
  if (lower.includes("/maps/api/place/photo")) return true;
  if (lower.includes("place/photo")) return true;
  if (
    lower.includes("places.googleapis.com")
    && (lower.includes("/photos/") || lower.includes("/media"))
  ) {
    return true;
  }
  if (/^places\/.+\/photos(\/|$)/i.test(trimmed)) return true;
  return false;
}

export function persistableSourceImageURL(value: unknown): unknown {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== "string") return value;
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

/// PATCH whose only remaining field(s) were the retired photo column.
/// Must be a 200 no-op, not 400 "No writable fields", so old Apps do
/// not fail. Does not enter the #293 cap / growth path.
export function placeWriteIsSilentPhotoNoop(body: PlaceWriteBody): boolean {
  const keys = Object.keys(body).filter((key) => body[key] !== undefined);
  return keys.length > 0 && keys.every((key) => retiredPhotoOnlyKeys.has(key));
}
