export type ChinaPlaceCoordinateSystem = "WGS84" | "GCJ-02";

export interface ChinaPlaceResolveRequest {
  query: string;
  provider: "china";
}

export interface ChinaPlaceMatch {
  provider: "amap";
  id: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  rating: null;
  reviewCount: null;
  priceLevel: null;
  types: string[];
  coordinateSystem: ChinaPlaceCoordinateSystem;
  mapURL: string;
}

export interface ChinaPlaceResolverConfig {
  usageAuthorized?: boolean;
  internationalApiKey?: string;
  domesticApiKey?: string;
  fetcher?: typeof fetch;
  timeoutMs?: number;
  maxResponseBytes?: number;
}

export class ChinaPlaceResolverInputError extends Error {}
export class ChinaPlaceResolverConfigurationError extends Error {}

const internationalEndpoint = "https://sg-restapi.opnavi.com/v3/place/text";
const domesticEndpoint = "https://restapi.amap.com/v5/place/text";
const defaultTimeoutMs = 6_000;
const maximumTimeoutMs = 10_000;
const defaultMaxResponseBytes = 128 * 1024;
const maximumResponseBytes = 256 * 1024;

type AmapPOI = {
  id?: unknown;
  name?: unknown;
  address?: unknown;
  location?: unknown;
  type?: unknown;
};

type AmapResponse = {
  status?: unknown;
  info?: unknown;
  pois?: unknown;
};

export function normalizeChinaPlaceResolveRequest(raw: unknown): ChinaPlaceResolveRequest {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new ChinaPlaceResolverInputError("Place resolver body must be an object");
  }
  const body = raw as Record<string, unknown>;
  const query = boundedString(body.query, 80);
  if (!query) throw new ChinaPlaceResolverInputError("query is required");
  if (body.provider !== undefined && body.provider !== "china") {
    throw new ChinaPlaceResolverInputError("provider must equal china");
  }
  return { query, provider: "china" };
}

export async function resolveChinaPlace(
  request: ChinaPlaceResolveRequest,
  config: ChinaPlaceResolverConfig,
): Promise<{ matches: ChinaPlaceMatch[] }> {
  if (config.usageAuthorized !== true) {
    throw new ChinaPlaceResolverConfigurationError("Amap place resolver is not authorized");
  }
  const internationalApiKey = config.internationalApiKey?.trim();
  const domesticApiKey = config.domesticApiKey?.trim();
  if (!internationalApiKey && !domesticApiKey) {
    throw new ChinaPlaceResolverConfigurationError("Amap place resolver is not configured");
  }

  if (internationalApiKey) {
    const matches = await requestAmapMatches(
      request.query,
      internationalApiKey,
      internationalEndpoint,
      "WGS84",
      config,
    );
    if (matches.length > 0) return { matches };
  }

  if (domesticApiKey) {
    const matches = await requestAmapMatches(
      request.query,
      domesticApiKey,
      domesticEndpoint,
      "GCJ-02",
      config,
    );
    return { matches };
  }

  return { matches: [] };
}

async function requestAmapMatches(
  query: string,
  apiKey: string,
  endpoint: string,
  coordinateSystem: ChinaPlaceCoordinateSystem,
  config: ChinaPlaceResolverConfig,
): Promise<ChinaPlaceMatch[]> {
  const url = new URL(endpoint);
  url.searchParams.set("key", apiKey);
  url.searchParams.set("keywords", query);
  url.searchParams.set("types", "050000");
  if (coordinateSystem === "WGS84") {
    url.searchParams.set("offset", "10");
    url.searchParams.set("page", "1");
  } else {
    url.searchParams.set("page_size", "10");
    url.searchParams.set("page_num", "1");
  }

  const timeoutMs = boundedInteger(config.timeoutMs, defaultTimeoutMs, maximumTimeoutMs);
  const maxResponseBytes = boundedInteger(
    config.maxResponseBytes,
    defaultMaxResponseBytes,
    maximumResponseBytes,
  );
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await (config.fetcher ?? fetch)(url, {
      method: "GET",
      headers: { accept: "application/json" },
      signal: controller.signal,
    });
    if (!response.ok) return [];
    const declaredLength = Number(response.headers.get("content-length") ?? 0);
    if (declaredLength > maxResponseBytes) return [];
    const text = await response.text();
    if (Buffer.byteLength(text, "utf8") > maxResponseBytes) return [];
    const body = JSON.parse(text) as AmapResponse;
    if (body.status !== "1" || !Array.isArray(body.pois)) return [];
    return body.pois
      .slice(0, 10)
      .map((poi) => parsePOI(poi, coordinateSystem))
      .filter((match): match is ChinaPlaceMatch => match !== undefined);
  } catch {
    return [];
  } finally {
    clearTimeout(timeout);
  }
}

function parsePOI(raw: unknown, coordinateSystem: ChinaPlaceCoordinateSystem): ChinaPlaceMatch | undefined {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return undefined;
  const poi = raw as AmapPOI;
  const id = boundedString(poi.id, 180);
  const name = boundedString(poi.name, 240);
  const address = addressString(poi.address);
  const coordinate = parseLocation(poi.location);
  if (!id || !name || !coordinate) return undefined;
  const mapURL = new URL("https://uri.amap.com/marker");
  mapURL.searchParams.set("position", `${coordinate.longitude},${coordinate.latitude}`);
  mapURL.searchParams.set("name", name);
  mapURL.searchParams.set("src", "save");
  mapURL.searchParams.set("callnative", "1");
  return {
    provider: "amap",
    id,
    name,
    address,
    latitude: coordinate.latitude,
    longitude: coordinate.longitude,
    rating: null,
    reviewCount: null,
    priceLevel: null,
    types: typeof poi.type === "string" ? poi.type.split(";").filter(Boolean).slice(0, 12) : [],
    coordinateSystem,
    mapURL: mapURL.toString(),
  };
}

function parseLocation(value: unknown): { latitude: number; longitude: number } | undefined {
  if (typeof value !== "string") return undefined;
  const [longitudeValue, latitudeValue, ...rest] = value.split(",");
  if (rest.length > 0) return undefined;
  const longitude = Number(longitudeValue);
  const latitude = Number(latitudeValue);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return undefined;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return undefined;
  if (latitude === 0 && longitude === 0) return undefined;
  return { latitude, longitude };
}

function addressString(value: unknown): string {
  if (typeof value === "string") return value.trim().slice(0, 500);
  if (Array.isArray(value)) {
    return value.filter((part): part is string => typeof part === "string").join(" ").trim().slice(0, 500);
  }
  return "";
}

function boundedString(value: unknown, maxLength: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.replace(/\s+/g, " ").trim();
  if (!trimmed || trimmed.length > maxLength) return undefined;
  return trimmed;
}

function boundedInteger(value: number | undefined, fallback: number, maximum: number): number {
  if (!Number.isInteger(value) || (value ?? 0) <= 0) return fallback;
  return Math.min(value as number, maximum);
}
