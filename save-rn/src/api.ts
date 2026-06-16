import { MySavesPayload, Place, SharedPlaceData, TripRecord } from "./models";

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
  code: string;
  url: string;
  payload: SharedPlaceData;
  source_place_id?: string | null;
  expires_at?: string | null;
  created_at?: string;
};

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

export async function fetchPlaces(auth: SaveAuth): Promise<Place[]> {
  const places = await apiRequest<BackendPlace[]>("/places", { method: "GET" }, auth);
  return places.map(mapPlace);
}

export async function createPlace(auth: SaveAuth, place: Place): Promise<Place> {
  const body = {
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
  };

  const created = await apiRequest<BackendPlace>(
    "/places",
    {
      method: "POST",
      body: JSON.stringify(body),
    },
    auth
  );
  return mapPlace(created);
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

export async function resolveSharedPlaceLink(code: string): Promise<SharedPlaceData> {
  const response = await fetch(`${requireApiBaseUrl()}/v0/shared-place-links/${encodeURIComponent(code)}`);
  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || `Shared place link failed: ${response.status}`);
  }
  const link = (await response.json()) as SharedPlaceLink;
  return link.payload;
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
  };
}
