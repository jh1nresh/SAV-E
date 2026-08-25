type QueryRow = Record<string, unknown>;

export type BackfillQuery = (
  sql: string,
  values: readonly unknown[],
) => Promise<{ rows: QueryRow[] }>;

export type BackfillFetch = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

export type MissingPhotoPlace = {
  id: string;
  userId: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  googlePlaceId?: string;
};

type GooglePhotoCandidate = {
  id: string;
  name: string;
  latitude?: number;
  longitude?: number;
  photoReferences: string[];
};

export type PlacePhotoBackfillReceipt = {
  mode: "dry_run" | "apply";
  selected: number;
  matched: number;
  wouldUpdate: number;
  updated: number;
  raced: number;
  skipped: number;
  failed: number;
};

export const selectMissingPlacePhotosSQL = `
select id, user_id, name, address, latitude, longitude, google_place_id
from places
where user_id = $1
  and (source_image_url is null or btrim(source_image_url) = '')
  and coalesce(cardinality(business_photo_urls), 0) = 0
order by created_at asc, id asc
limit $2
`;

export const updateMissingPlacePhotosSQL = `
update places
set source_image_url = $3,
    business_photo_urls = $4
where id = $1
  and user_id = $2
  and (source_image_url is null or btrim(source_image_url) = '')
  and coalesce(cardinality(business_photo_urls), 0) = 0
returning id
`;

export async function runPlacePhotoBackfill(options: {
  userId: string;
  limit: number;
  apply: boolean;
  apiKey: string;
  query: BackfillQuery;
  fetcher?: BackfillFetch;
}): Promise<PlacePhotoBackfillReceipt> {
  const userId = options.userId.trim();
  if (!userId) throw new Error("A non-empty owner user id is required");
  if (!Number.isInteger(options.limit) || options.limit < 1 || options.limit > 100) {
    throw new Error("Backfill limit must be an integer from 1 through 100");
  }
  if (!options.apiKey.trim()) throw new Error("GOOGLE_PLACES_API_KEY is required");

  const selected = await options.query(selectMissingPlacePhotosSQL, [userId, options.limit]);
  const places = selected.rows.map(missingPhotoPlaceFromRow);
  const receipt: PlacePhotoBackfillReceipt = {
    mode: options.apply ? "apply" : "dry_run",
    selected: places.length,
    matched: 0,
    wouldUpdate: 0,
    updated: 0,
    raced: 0,
    skipped: 0,
    failed: 0,
  };

  for (const place of places) {
    try {
      const photoURLs = await resolveGooglePhotoURLs(
        place,
        options.apiKey,
        options.fetcher ?? fetch,
      );
      if (photoURLs.length === 0) {
        receipt.skipped += 1;
        continue;
      }

      receipt.matched += 1;
      receipt.wouldUpdate += 1;
      if (!options.apply) continue;

      const result = await options.query(updateMissingPlacePhotosSQL, [
        place.id,
        userId,
        photoURLs[0],
        photoURLs,
      ]);
      if (result.rows.length === 1) receipt.updated += 1;
      else receipt.raced += 1;
    } catch {
      receipt.failed += 1;
    }
  }

  return receipt;
}

export async function resolveGooglePhotoURLs(
  place: MissingPhotoPlace,
  apiKey: string,
  fetcher: BackfillFetch = fetch,
): Promise<string[]> {
  let candidate: GooglePhotoCandidate | undefined;
  if (place.googlePlaceId) {
    candidate = await fetchGooglePlaceDetails(place.googlePlaceId, apiKey, fetcher);
  }

  if (!candidate || candidate.photoReferences.length === 0) {
    const candidates = await searchGooglePlaces(place, apiKey, fetcher);
    candidate = selectBestPhotoCandidate(place, candidates);
  }

  return (candidate?.photoReferences ?? [])
    .slice(0, 6)
    .map(persistableGooglePhotoURL)
    .filter((value, index, values) => values.indexOf(value) === index);
}

export function selectBestPhotoCandidate(
  place: MissingPhotoPlace,
  candidates: GooglePhotoCandidate[],
): GooglePhotoCandidate | undefined {
  const targetName = normalizedPlaceText(place.name);
  return candidates.find((candidate) => {
    const candidateName = normalizedPlaceText(candidate.name);
    const sameName = targetName.length > 0 && candidateName.length > 0 &&
      (targetName.includes(candidateName) || candidateName.includes(targetName));
    const distance = coordinateDistanceMeters(
      place.latitude,
      place.longitude,
      candidate.latitude,
      candidate.longitude,
    );
    return candidate.photoReferences.length > 0 && (sameName || (distance !== undefined && distance < 250));
  });
}

export function persistableGooglePhotoURL(photoReference: string): string {
  const url = new URL("https://maps.googleapis.com/maps/api/place/photo");
  url.searchParams.set("maxwidth", "900");
  url.searchParams.set("photo_reference", photoReference);
  return url.toString();
}

function missingPhotoPlaceFromRow(row: QueryRow): MissingPhotoPlace {
  const id = requiredString(row.id, "id");
  const userId = requiredString(row.user_id, "user_id");
  const name = requiredString(row.name, "name");
  return {
    id,
    userId,
    name,
    address: optionalString(row.address) ?? "",
    latitude: requiredNumber(row.latitude, "latitude"),
    longitude: requiredNumber(row.longitude, "longitude"),
    googlePlaceId: optionalString(row.google_place_id),
  };
}

async function fetchGooglePlaceDetails(
  placeId: string,
  apiKey: string,
  fetcher: BackfillFetch,
): Promise<GooglePhotoCandidate | undefined> {
  const url = new URL("https://maps.googleapis.com/maps/api/place/details/json");
  url.searchParams.set("place_id", placeId);
  url.searchParams.set("fields", "place_id,name,geometry,photos");
  url.searchParams.set("key", apiKey);
  const body = await googleJSON(url, fetcher);
  const result = objectValue(body.result);
  if (!result) return undefined;
  return googleCandidateFromObject(result);
}

async function searchGooglePlaces(
  place: MissingPhotoPlace,
  apiKey: string,
  fetcher: BackfillFetch,
): Promise<GooglePhotoCandidate[]> {
  const url = new URL("https://maps.googleapis.com/maps/api/place/textsearch/json");
  url.searchParams.set("query", [place.name, place.address].filter(Boolean).join(" "));
  if (validCoordinate(place.latitude, place.longitude)) {
    url.searchParams.set("location", `${place.latitude},${place.longitude}`);
    url.searchParams.set("radius", "5000");
  }
  url.searchParams.set("key", apiKey);
  const body = await googleJSON(url, fetcher);
  return arrayValue(body.results)
    .map(objectValue)
    .filter((value): value is QueryRow => value !== undefined)
    .map(googleCandidateFromObject)
    .filter((value): value is GooglePhotoCandidate => value !== undefined);
}

async function googleJSON(url: URL, fetcher: BackfillFetch): Promise<QueryRow> {
  const response = await fetcher(url);
  if (!response.ok) throw new Error(`Google Places request failed with ${response.status}`);
  const body = objectValue(await response.json());
  if (!body) throw new Error("Google Places returned an invalid response");
  const status = optionalString(body.status);
  if (status && status !== "OK" && status !== "ZERO_RESULTS") {
    throw new Error(`Google Places returned ${status}`);
  }
  return body;
}

function googleCandidateFromObject(value: QueryRow): GooglePhotoCandidate | undefined {
  const id = optionalString(value.place_id);
  const name = optionalString(value.name);
  if (!id || !name) return undefined;
  const geometry = objectValue(value.geometry);
  const location = objectValue(geometry?.location);
  const photoReferences = arrayValue(value.photos)
    .map(objectValue)
    .filter((photo): photo is QueryRow => photo !== undefined)
    .map((photo) => optionalString(photo.photo_reference))
    .filter((reference): reference is string => reference !== undefined);
  return {
    id,
    name,
    latitude: optionalNumber(location?.lat),
    longitude: optionalNumber(location?.lng),
    photoReferences,
  };
}

function coordinateDistanceMeters(
  latitude: number,
  longitude: number,
  candidateLatitude: number | undefined,
  candidateLongitude: number | undefined,
): number | undefined {
  if (!validCoordinate(latitude, longitude) ||
      candidateLatitude === undefined || candidateLongitude === undefined ||
      !validCoordinate(candidateLatitude, candidateLongitude)) return undefined;
  const radians = (degrees: number) => degrees * Math.PI / 180;
  const deltaLatitude = radians(candidateLatitude - latitude);
  const deltaLongitude = radians(candidateLongitude - longitude);
  const a = Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(radians(latitude)) * Math.cos(radians(candidateLatitude)) *
      Math.sin(deltaLongitude / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function validCoordinate(latitude: number, longitude: number): boolean {
  return Number.isFinite(latitude) && Number.isFinite(longitude) &&
    latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180 &&
    (latitude !== 0 || longitude !== 0);
}

function normalizedPlaceText(value: string): string {
  return value.normalize("NFKD").toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
}

function requiredString(value: unknown, field: string): string {
  const result = optionalString(value);
  if (!result) throw new Error(`Missing ${field}`);
  return result;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function requiredNumber(value: unknown, field: string): number {
  const result = optionalNumber(value);
  if (result === undefined) throw new Error(`Missing ${field}`);
  return result;
}

function optionalNumber(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function objectValue(value: unknown): QueryRow | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as QueryRow
    : undefined;
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}
