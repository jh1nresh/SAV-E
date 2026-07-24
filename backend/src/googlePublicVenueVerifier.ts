export interface GooglePublicVenuePlaceReference {
  googlePlaceId?: string | null;
  name?: string | null;
  category?: string | null;
}

export interface CanonicalGooglePublicVenue {
  googlePlaceId: string;
  displayName: string;
  formattedAddress: string;
  primaryType: string;
  latitude: number;
  longitude: number;
}

export type GooglePublicVenueVerificationResult =
  | {
    status: "verified";
    venue: CanonicalGooglePublicVenue;
  }
  | {
    status: "rejected";
    reason: "residential_type" | "address_only_type";
  }
  | {
    status: "unavailable";
    reason:
      | "missing_google_place_id"
      | "missing_api_key"
      | "provider_http_error"
      | "provider_timeout"
      | "response_too_large"
      | "malformed_response"
      | "missing_public_venue_identity";
  };

export interface GooglePublicVenueVerifierConfig {
  apiKey?: string;
  fetcher?: typeof fetch;
  timeoutMs?: number;
  maxResponseBytes?: number;
}

export interface CachedGooglePublicVenueVerifierConfig
  extends GooglePublicVenueVerifierConfig {
  cacheTtlMs?: number;
  maxCacheEntries?: number;
  now?: () => number;
}

const googlePlacesEndpoint = "https://places.googleapis.com/v1/places";
const googlePlacesFieldMask = "id,displayName,formattedAddress,primaryType,location";
const defaultTimeoutMs = 5_000;
const maximumTimeoutMs = 10_000;
const defaultMaxResponseBytes = 64 * 1024;
const maximumResponseBytes = 128 * 1024;
const defaultCacheTtlMs = 24 * 60 * 60 * 1_000;
const maximumCacheTtlMs = 7 * defaultCacheTtlMs;
const defaultMaxCacheEntries = 500;
const maximumCacheEntries = 5_000;

const residentialPrimaryTypes = new Set([
  "apartment_building",
  "apartment_complex",
  "condominium_complex",
  "housing_complex",
  "residential_building",
]);

const addressOnlyPrimaryTypes = new Set([
  "administrative_area_level_1",
  "administrative_area_level_2",
  "administrative_area_level_3",
  "administrative_area_level_4",
  "administrative_area_level_5",
  "administrative_area_level_6",
  "administrative_area_level_7",
  "country",
  "geocode",
  "intersection",
  "locality",
  "neighborhood",
  "plus_code",
  "postal_code",
  "postal_code_prefix",
  "premise",
  "route",
  "street_address",
  "sublocality",
  "subpremise",
]);

class VerificationFailure extends Error {
  constructor(readonly reason: Extract<GooglePublicVenueVerificationResult, { status: "unavailable" }>["reason"]) {
    super(reason);
  }
}

/**
 * Verifies a place reference that the caller has already owner-scoped.
 *
 * The stored name and category are deliberately ignored: Google Places Details
 * is the authoritative identity source for this gate.
 */
export async function verifyGooglePublicVenue(
  place: GooglePublicVenuePlaceReference,
  config: GooglePublicVenueVerifierConfig,
): Promise<GooglePublicVenueVerificationResult> {
  const googlePlaceId = exactBoundedString(place.googlePlaceId, 180);
  if (!googlePlaceId) {
    return { status: "unavailable", reason: "missing_google_place_id" };
  }

  const apiKey = config.apiKey?.trim();
  if (!apiKey) {
    return { status: "unavailable", reason: "missing_api_key" };
  }

  const timeoutMs = boundedPositiveInteger(config.timeoutMs, defaultTimeoutMs, maximumTimeoutMs);
  const maxResponseBytes = boundedPositiveInteger(
    config.maxResponseBytes,
    defaultMaxResponseBytes,
    maximumResponseBytes,
  );
  const controller = new AbortController();
  let timeout: NodeJS.Timeout | undefined;
  const timeoutFailure = new Promise<never>((_resolve, reject) => {
    timeout = setTimeout(() => {
      controller.abort();
      reject(new VerificationFailure("provider_timeout"));
    }, timeoutMs);
  });

  try {
    return await Promise.race([
      requestGooglePublicVenue(
        googlePlaceId,
        apiKey,
        maxResponseBytes,
        config.fetcher ?? fetch,
        controller.signal,
      ),
      timeoutFailure,
    ]);
  } catch (error) {
    if (error instanceof VerificationFailure) {
      return { status: "unavailable", reason: error.reason };
    }
    if (controller.signal.aborted) {
      return { status: "unavailable", reason: "provider_timeout" };
    }
    return { status: "unavailable", reason: "malformed_response" };
  } finally {
    controller.abort();
    if (timeout) clearTimeout(timeout);
  }
}

export function createCachedGooglePublicVenueVerifier(
  config: CachedGooglePublicVenueVerifierConfig,
): (place: GooglePublicVenuePlaceReference) => Promise<GooglePublicVenueVerificationResult> {
  const cache = new Map<string, {
    expiresAt: number;
    result: GooglePublicVenueVerificationResult;
  }>();
  const inFlight = new Map<string, Promise<GooglePublicVenueVerificationResult>>();
  const now = config.now ?? Date.now;
  const cacheTtlMs = boundedPositiveInteger(
    config.cacheTtlMs,
    defaultCacheTtlMs,
    maximumCacheTtlMs,
  );
  const maxCacheEntries = boundedPositiveInteger(
    config.maxCacheEntries,
    defaultMaxCacheEntries,
    maximumCacheEntries,
  );

  return async (place) => {
    const cacheKey = exactBoundedString(place.googlePlaceId, 180);
    if (!cacheKey) return await verifyGooglePublicVenue(place, config);

    const cached = cache.get(cacheKey);
    if (cached && cached.expiresAt > now()) return cached.result;
    if (cached) cache.delete(cacheKey);

    const pending = inFlight.get(cacheKey);
    if (pending) return await pending;

    const verification = verifyGooglePublicVenue(place, config);
    inFlight.set(cacheKey, verification);
    try {
      const result = await verification;
      if (result.status !== "unavailable") {
        pruneVenueCache(cache, now(), maxCacheEntries);
        cache.set(cacheKey, {
          expiresAt: now() + cacheTtlMs,
          result,
        });
      }
      return result;
    } finally {
      inFlight.delete(cacheKey);
    }
  };
}

async function requestGooglePublicVenue(
  googlePlaceId: string,
  apiKey: string,
  maxResponseBytes: number,
  fetcher: typeof fetch,
  signal: AbortSignal,
): Promise<GooglePublicVenueVerificationResult> {
  const response = await fetcher(
    `${googlePlacesEndpoint}/${encodeURIComponent(googlePlaceId)}`,
    {
      method: "GET",
      headers: {
        accept: "application/json",
        "x-goog-api-key": apiKey,
        "x-goog-fieldmask": googlePlacesFieldMask,
      },
      redirect: "error",
      signal,
    },
  );

  if (!response.ok) {
    return { status: "unavailable", reason: "provider_http_error" };
  }

  const payload = await readBoundedJsonObject(response, maxResponseBytes);
  const identity = canonicalPublicVenue(payload);
  if (!identity) {
    return { status: "unavailable", reason: "missing_public_venue_identity" };
  }
  if (residentialPrimaryTypes.has(identity.primaryType)) {
    return { status: "rejected", reason: "residential_type" };
  }
  if (addressOnlyPrimaryTypes.has(identity.primaryType)) {
    return { status: "rejected", reason: "address_only_type" };
  }

  return { status: "verified", venue: identity };
}

function canonicalPublicVenue(payload: Record<string, unknown>): CanonicalGooglePublicVenue | undefined {
  const googlePlaceId = boundedString(payload.id, 180);
  const displayNameObject = objectValue(payload.displayName);
  const displayName = boundedString(displayNameObject?.text, 160);
  const formattedAddress = boundedString(payload.formattedAddress, 300);
  const primaryType = boundedString(payload.primaryType, 80)?.toLowerCase();
  const location = objectValue(payload.location);
  const latitude = finiteCoordinate(location?.latitude, -90, 90);
  const longitude = finiteCoordinate(location?.longitude, -180, 180);

  if (!googlePlaceId || !displayName || !formattedAddress || !primaryType) return undefined;
  if (latitude === undefined || longitude === undefined) return undefined;

  return {
    googlePlaceId,
    displayName,
    formattedAddress,
    primaryType,
    latitude,
    longitude,
  };
}

async function readBoundedJsonObject(
  response: Response,
  maxResponseBytes: number,
): Promise<Record<string, unknown>> {
  const declaredLength = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > maxResponseBytes) {
    throw new VerificationFailure("response_too_large");
  }
  if (!response.body) {
    throw new VerificationFailure("malformed_response");
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > maxResponseBytes) {
        await reader.cancel();
        throw new VerificationFailure("response_too_large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new VerificationFailure("malformed_response");
  }
  const object = objectValue(parsed);
  if (!object) {
    throw new VerificationFailure("malformed_response");
  }
  return object;
}

function objectValue(value: unknown): Record<string, unknown> | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  return value as Record<string, unknown>;
}

function boundedString(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.replace(/\s+/g, " ").trim();
  if (!normalized) return undefined;
  return normalized.slice(0, maxLength);
}

function exactBoundedString(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.replace(/\s+/g, " ").trim();
  if (!normalized || normalized.length > maxLength) return undefined;
  return normalized;
}

function finiteCoordinate(value: unknown, minimum: number, maximum: number): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return value >= minimum && value <= maximum ? value : undefined;
}

function boundedPositiveInteger(value: number | undefined, fallback: number, maximum: number): number {
  if (!Number.isInteger(value) || (value ?? 0) <= 0) return fallback;
  return Math.min(value as number, maximum);
}

function pruneVenueCache(
  cache: Map<string, { expiresAt: number; result: GooglePublicVenueVerificationResult }>,
  now: number,
  maximumEntries: number,
): void {
  for (const [key, entry] of cache) {
    if (entry.expiresAt <= now) cache.delete(key);
  }
  while (cache.size >= maximumEntries) {
    const oldestKey = cache.keys().next().value;
    if (typeof oldestKey !== "string") break;
    cache.delete(oldestKey);
  }
}
