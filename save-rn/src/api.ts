import { MySavesPayload, Place, SharedPlaceData, SharedPlaceReceipt, TripRecord } from "./models";
import { sanitizeSharedPlaceData } from "./sharedTrip";

const apiBaseUrl =
  normalizedEnvValue(process.env.EXPO_PUBLIC_SAVE_API_URL) ??
  normalizedEnvValue(process.env.EXPO_PUBLIC_WANDERLY_API_URL);

export type SaveAuth = {
  accessToken?: string;
  guestToken?: string;
};

export type GuestSession = {
  guestId: string;
  guestToken: string;
  expiresAt: string;
};

type BackendTripStop = {
  id: string;
  place_id?: string | null;
  place_name: string;
  day: number;
  order_index: number;
  start_time?: string | null;
  duration?: number | null;
  note?: string | null;
};

type BackendPlace = {
  id: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  category: Place["category"];
  status: Place["status"];
  source_url?: string | null;
  source_platform: Place["sourcePlatform"];
  note?: string | null;
  price_range?: string | null;
  recommender?: string | null;
};

type BackendTrip = {
  id: string;
  name: string;
  city: string;
  is_optimized: boolean;
  created_at?: string;
  trip_stops: BackendTripStop[];
};

type SharedPlaceLink = {
  code?: unknown;
  url?: unknown;
  payload?: unknown;
  sender?: unknown;
  expires_at?: unknown;
  created_at?: unknown;
};

export type FriendShareEventType =
  | "friend_share_receipt_opened"
  | "friend_share_save_tapped"
  | "friend_share_open_failed";

export type FriendShareOpenFailureReason =
  | "expired"
  | "malformed_payload"
  | "network_error"
  | "server_error"
  | "unsupported_route"
  | "unknown";

export type FriendShareEventOptions = {
  reasonCode?: FriendShareOpenFailureReason;
  recipientPlaceId?: string;
};

export type FriendSharePlaceSaveOutcome = "saved" | "already_saved";

export type FriendSharePlaceSaveResult = {
  place: Place;
  outcome: FriendSharePlaceSaveOutcome;
};

export class SharedPlaceLinkError extends Error {
  constructor(
    message: string,
    readonly reasonCode: FriendShareOpenFailureReason,
  ) {
    super(message);
    this.name = "SharedPlaceLinkError";
  }
}

function requireApiBaseUrl(): string {
  if (!apiBaseUrl) {
    throw new Error("Missing EXPO_PUBLIC_SAVE_API_URL");
  }
  return apiBaseUrl;
}

export function hasApiConfig(): boolean {
  return Boolean(apiBaseUrl);
}

function normalizedEnvValue(value?: string): string | undefined {
  const trimmed = value?.trim();
  if (!trimmed || trimmed.startsWith("__")) return undefined;
  return trimmed.replace(/\/+$/, "");
}

function requestHeaders({ accessToken, guestToken }: SaveAuth): HeadersInit {
  const baseHeaders = {
    "Content-Type": "application/json",
  };

  if (!accessToken) {
    if (!guestToken) {
      throw new Error("Missing SAV-E auth context");
    }

    return {
      ...baseHeaders,
      "x-save-guest-token": guestToken,
    };
  }

  return {
    ...baseHeaders,
    Authorization: `Bearer ${accessToken}`,
  };
}

async function apiRequest<T>(
  path: string,
  init: RequestInit,
  headersInput: SaveAuth
): Promise<T> {
  const response = await fetch(`${requireApiBaseUrl()}${path}`, {
    ...init,
    headers: {
      ...requestHeaders(headersInput),
      ...(init.headers ?? {}),
    },
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || `Backend request failed: ${response.status}`);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

export async function createGuestSession(): Promise<GuestSession> {
  const response = await fetch(`${requireApiBaseUrl()}/v0/guest-sessions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || `Guest session request failed: ${response.status}`);
  }

  const body = await response.json() as { guest_id?: unknown; guest_token?: unknown; expires_at?: unknown };
  if (typeof body.guest_id !== "string" || typeof body.guest_token !== "string" || typeof body.expires_at !== "string") {
    throw new Error("Guest session response is invalid");
  }

  return {
    guestId: body.guest_id,
    guestToken: body.guest_token,
    expiresAt: body.expires_at,
  };
}

export async function runSingleFlight<T>(
  ref: { current: Promise<T> | null },
  operation: () => Promise<T>,
): Promise<T> {
  if (ref.current) return ref.current;
  const pending = operation();
  ref.current = pending;
  try {
    return await pending;
  } finally {
    if (ref.current === pending) ref.current = null;
  }
}

export async function fetchPlaces(auth: SaveAuth): Promise<Place[]> {
  const places = await apiRequest<BackendPlace[]>("/places", { method: "GET" }, auth);
  return places.map(mapPlace);
}

export function placeCreateBody(place: Place, friendShareCode?: string): Record<string, unknown> {
  const body: Record<string, unknown> = {
    name: place.name,
    address: place.address,
    latitude: place.latitude,
    longitude: place.longitude,
    category: place.category,
    status: place.status,
    note: place.note ?? null,
    source_url: place.sourceUrl ?? null,
    source_platform: place.sourcePlatform,
    price_range: place.priceRange ?? null,
    recommender: place.recommender ?? null,
  };
  const code = normalizedString(friendShareCode);
  if (friendShareCode !== undefined && !code) {
    throw new Error("friendShareCode must not be empty");
  }
  if (code) body.friend_share_code = code;
  return body;
}

export async function createPlace(auth: SaveAuth, place: Place): Promise<Place>;
export async function createPlace(
  auth: SaveAuth,
  place: Place,
  friendShareCode: string,
): Promise<FriendSharePlaceSaveResult>;
export async function createPlace(
  auth: SaveAuth,
  place: Place,
  friendShareCode?: string,
): Promise<Place | FriendSharePlaceSaveResult> {
  const body = placeCreateBody(place, friendShareCode);

  const created = await apiRequest<BackendPlace | { place?: unknown; outcome?: unknown }>(
    "/places",
    {
      method: "POST",
      body: JSON.stringify(body),
    },
    auth
  );
  if (!friendShareCode) return mapPlace(created as BackendPlace);

  const receipt = objectValue(created);
  const canonicalPlace = objectValue(receipt?.place) as BackendPlace | undefined;
  const outcome = receipt?.outcome;
  if (!canonicalPlace || (outcome !== "saved" && outcome !== "already_saved")) {
    throw new Error("Friend share save response is malformed");
  }
  return {
    place: mapPlace(canonicalPlace),
    outcome,
  };
}

export async function fetchTrips(auth: SaveAuth): Promise<TripRecord[]> {
  const trips = await apiRequest<BackendTrip[]>("/trips", { method: "GET" }, auth);
  return trips.map(mapTrip);
}

export async function createTrip(
  auth: SaveAuth,
  input: { name: string; city: string; places: Place[] }
): Promise<TripRecord> {
  const body = {
    name: input.name,
    city: input.city,
    is_optimized: false,
    trip_stops: input.places.map((place, index) => ({
      place_id: place.id,
      place_name: place.name,
      day: 1,
      order_index: index,
      start_time: place.time ?? null,
      note: place.note ?? null,
    })),
  };

  const trip = await apiRequest<BackendTrip>(
    "/trips",
    {
      method: "POST",
      body: JSON.stringify(body),
    },
    auth
  );

  return mapTrip(trip);
}

export async function createSharedPlaceLink(
  auth: SaveAuth,
  payload: SharedPlaceData,
  sourcePlaceId?: string
): Promise<SharedPlaceLink> {
  return apiRequest<SharedPlaceLink>(
    "/v0/shared-place-links",
    {
      method: "POST",
      body: JSON.stringify({
        payload,
        source_place_id: sourcePlaceId ?? null,
      }),
    },
    auth
  );
}

export async function resolveSharedPlaceLink(code: string): Promise<SharedPlaceReceipt> {
  let response: Response;
  try {
    response = await fetch(`${requireApiBaseUrl()}/v0/shared-place-links/${encodeURIComponent(code)}`);
  } catch (error) {
    throw new SharedPlaceLinkError(
      error instanceof Error ? error.message : "Could not reach the shared place service.",
      "network_error",
    );
  }
  if (!response.ok) {
    const message = await responseErrorMessage(response, `Shared place link failed: ${response.status}`);
    const reasonCode: FriendShareOpenFailureReason = response.status === 410
      ? "expired"
      : response.status >= 500
        ? "server_error"
        : response.status === 404
          ? "unknown"
          : "unsupported_route";
    throw new SharedPlaceLinkError(message, reasonCode);
  }

  try {
    return sharedPlaceReceiptFromResponse(await response.json());
  } catch (error) {
    if (error instanceof SharedPlaceLinkError) throw error;
    throw new SharedPlaceLinkError("Shared place response is malformed.", "malformed_payload");
  }
}

export async function recordPublicFriendShareEvent(
  code: string,
  eventType: "friend_share_receipt_opened" | "friend_share_open_failed",
  reasonCode?: FriendShareOpenFailureReason,
): Promise<void> {
  const response = await fetch(
    `${requireApiBaseUrl()}/v0/shared-place-links/${encodeURIComponent(code)}/events`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(friendShareEventBody(eventType, { reasonCode })),
    },
  );
  if (!response.ok) {
    throw new Error(await responseErrorMessage(response, `Friend share event failed: ${response.status}`));
  }
}

export async function recordAuthenticatedFriendShareEvent(
  auth: SaveAuth,
  code: string,
  eventType: FriendShareEventType,
  options: FriendShareEventOptions = {},
): Promise<void> {
  await apiRequest(
    "/v0/friend-share-events",
    {
      method: "POST",
      body: JSON.stringify({
        code,
        ...friendShareEventBody(eventType, options),
      }),
    },
    auth,
  );
}

export function friendShareEventBody(
  eventType: FriendShareEventType,
  options: FriendShareEventOptions = {},
): Record<string, string> {
  if (![
    "friend_share_receipt_opened",
    "friend_share_save_tapped",
    "friend_share_open_failed",
  ].includes(eventType)) {
    throw new Error("eventType is not allowed for client-authored events");
  }
  const body: Record<string, string> = {
    event_type: eventType,
    surface: "web",
  };
  if (eventType === "friend_share_open_failed") {
    body.reason_code = options.reasonCode ?? "unknown";
  } else if (options.reasonCode) {
    throw new Error("reasonCode is only allowed for friend_share_open_failed");
  }

  if (options.recipientPlaceId !== undefined) {
    throw new Error("recipientPlaceId is not allowed for client-authored events");
  }
  return body;
}

export function sharedPlaceReceiptFromResponse(value: unknown): SharedPlaceReceipt {
  const link = objectValue(value) as SharedPlaceLink | undefined;
  const payload = sanitizeSharedPlaceData(link?.payload) ?? undefined;
  if (
    !link
    || typeof link.code !== "string"
    || typeof link.url !== "string"
    || !payload
  ) {
    throw new SharedPlaceLinkError("Shared place response is malformed.", "malformed_payload");
  }

  const rawSender = objectValue(link.sender);
  const displayName = rawSender ? normalizedString(rawSender.display_name) : undefined;
  const handle = rawSender ? normalizedString(rawSender.handle) : undefined;

  return {
    code: link.code,
    url: link.url,
    payload,
    sender: displayName
      ? { displayName, handle }
      : undefined,
    expiresAt: normalizedString(link.expires_at),
    createdAt: normalizedString(link.created_at),
  };
}

export async function resolveMySaves(token: string): Promise<MySavesPayload> {
  const response = await fetch(`${requireApiBaseUrl()}/v0/my/${encodeURIComponent(token)}`);
  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || `My SAV-E link failed: ${response.status}`);
  }
  return (await response.json()) as MySavesPayload;
}

function mapTrip(trip: BackendTrip): TripRecord {
  return {
    id: trip.id,
    name: trip.name,
    city: trip.city,
    isOptimized: trip.is_optimized,
    createdAt: trip.created_at,
    tripStops: Array.isArray(trip.trip_stops)
      ? trip.trip_stops.map((stop) => ({
          id: stop.id,
          placeId: stop.place_id ?? null,
          placeName: stop.place_name,
          day: stop.day,
          orderIndex: stop.order_index,
          startTime: stop.start_time ?? null,
          duration: stop.duration ?? null,
          note: stop.note ?? null,
        }))
      : [],
  };
}

function mapPlace(place: BackendPlace): Place {
  return {
    id: place.id,
    name: place.name,
    address: place.address,
    latitude: place.latitude,
    longitude: place.longitude,
    category: place.category,
    status: place.status,
    sourcePlatform: place.source_platform,
    sourceUrl: place.source_url ?? undefined,
    note: place.note ?? undefined,
    priceRange: place.price_range ?? undefined,
    recommender: place.recommender ?? undefined,
  };
}

async function responseErrorMessage(response: Response, fallback: string): Promise<string> {
  const text = await response.text();
  if (!text) return fallback;
  try {
    const value = JSON.parse(text) as { error?: unknown };
    return typeof value.error === "string" && value.error.trim() ? value.error : fallback;
  } catch {
    return text;
  }
}

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function normalizedString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}
