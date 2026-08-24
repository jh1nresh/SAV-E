import {
  discoverRelatedPlaceSources,
  relatedPlaceSourcePackResponseBody,
  resolvedRelatedPlaceSourcesRequest,
  type RelatedPlaceSourcePack,
  type RelatedPlaceSourcesRequest,
  type RelatedSourcePlaceIdentity,
} from "./relatedPlaceSources.js";
import type { StoredRelatedPlaceSourcePack } from "./relatedPlaceSourcesStore.js";
import type {
  GooglePublicVenuePlaceReference,
  GooglePublicVenueVerificationResult,
} from "./googlePublicVenueVerifier.js";

export type OwnedRelatedSourcePlace = GooglePublicVenuePlaceReference & {
  id: string;
  sourceUrl?: string;
};

export type RelatedPlaceSourcesEndpointResult = {
  statusCode: 200 | 400 | 409 | 429 | 503;
  body: Record<string, unknown>;
  retryAfterSeconds?: number;
};

export type RelatedPlaceSourcesEndpointDependencies = {
  loadOwnedPlace: (
    placeId: string,
    userId: string,
  ) => Promise<OwnedRelatedSourcePlace>;
  verifyPublicVenue: (
    place: GooglePublicVenuePlaceReference,
  ) => Promise<GooglePublicVenueVerificationResult>;
  discover?: (
    place: RelatedSourcePlaceIdentity,
    request: RelatedPlaceSourcesRequest,
  ) => Promise<RelatedPlaceSourcePack>;
  loadStoredPack: (
    placeId: string,
    userId: string,
  ) => Promise<StoredRelatedPlaceSourcePack | undefined>;
  storePack: (
    placeId: string,
    userId: string,
    stored: StoredRelatedPlaceSourcePack,
  ) => Promise<void>;
  consumeDiscoveryQuota?: () => RelatedPlaceSourcesQuotaResult;
  now?: () => Date;
};

export const relatedPlaceSourcesStalenessWindowMs = 7 * 24 * 60 * 60 * 1_000;

export type RelatedPlaceSourcesQuotaResult =
  | { allowed: true }
  | { allowed: false; retryAfterSeconds: number };

export class RelatedPlaceSourcesOwnerRateLimiter {
  private readonly windows = new Map<string, { startedAt: number; count: number }>();

  constructor(
    private readonly limit = 6,
    private readonly windowMs = 10 * 60 * 1_000,
    private readonly maxOwners = 10_000,
    private readonly now: () => number = Date.now,
  ) {}

  consume(ownerId: string): RelatedPlaceSourcesQuotaResult {
    const currentTime = this.now();
    const existing = this.windows.get(ownerId);
    if (!existing || currentTime - existing.startedAt >= this.windowMs) {
      this.prune(currentTime);
      this.windows.set(ownerId, { startedAt: currentTime, count: 1 });
      return { allowed: true };
    }
    if (existing.count >= this.limit) {
      return {
        allowed: false,
        retryAfterSeconds: Math.max(
          1,
          Math.ceil((existing.startedAt + this.windowMs - currentTime) / 1_000),
        ),
      };
    }
    existing.count += 1;
    return { allowed: true };
  }

  private prune(currentTime: number): void {
    for (const [ownerId, entry] of this.windows) {
      if (currentTime - entry.startedAt >= this.windowMs) {
        this.windows.delete(ownerId);
      }
    }
    while (this.windows.size >= this.maxOwners) {
      const oldestOwnerId = this.windows.keys().next().value;
      if (typeof oldestOwnerId !== "string") break;
      this.windows.delete(oldestOwnerId);
    }
  }
}

export function hasAccountBearerAuthorization(
  authorizationHeader: string | undefined,
): boolean {
  return /^Bearer\s+\S+$/i.test(authorizationHeader ?? "");
}

export async function executeRelatedPlaceSourcesEndpoint(
  placeId: string,
  userId: string,
  request: RelatedPlaceSourcesRequest,
  dependencies: RelatedPlaceSourcesEndpointDependencies,
): Promise<RelatedPlaceSourcesEndpointResult> {
  const ownedPlace = await dependencies.loadOwnedPlace(placeId, userId);
  const resolvedRequest = resolvedRelatedPlaceSourcesRequest(request);

  if (!request.forceRefresh) {
    const stored = await dependencies.loadStoredPack(placeId, userId);
    if (stored && storedRequestMatches(stored, resolvedRequest)) {
      return {
        statusCode: 200,
        body: storedPackResponseBody(stored, dependencies.now?.() ?? new Date()),
      };
    }
  }

  const quota = dependencies.consumeDiscoveryQuota?.();
  if (quota && !quota.allowed) {
    return {
      statusCode: 429,
      body: { error: "Related-source request limit reached" },
      retryAfterSeconds: quota.retryAfterSeconds,
    };
  }

  const verification = await dependencies.verifyPublicVenue(ownedPlace);

  if (verification.status === "rejected") {
    return {
      statusCode: 400,
      body: { error: "Related-source discovery only supports public venues" },
    };
  }
  if (verification.status === "unavailable") {
    const statusCode = verification.reason === "missing_google_place_id" ? 409 : 503;
    return {
      statusCode,
      body: {
        error: statusCode === 409
          ? "Confirm this place with Google Places before related-source discovery"
          : "Public venue verification is temporarily unavailable",
      },
    };
  }

  const venue = verification.venue;
  const discover = dependencies.discover ?? discoverRelatedPlaceSources;
  const pack = await discover({
    id: ownedPlace.id,
    name: venue.displayName,
    address: venue.formattedAddress,
    latitude: venue.latitude,
    longitude: venue.longitude,
    category: venue.primaryType,
    googlePlaceId: venue.googlePlaceId,
    sourceUrl: ownedPlace.sourceUrl,
  }, request);
  const body = relatedPlaceSourcePackResponseBody(pack);
  const stored: StoredRelatedPlaceSourcePack = {
    pack: body,
    fetchedAt: pack.receipt.checkedAt,
    requestedPlatforms: resolvedRequest.platforms,
    maxResultsPerPlatform: resolvedRequest.maxResultsPerPlatform,
    querySet: uniqueStrings(pack.coverage.flatMap((entry) => entry.queries)),
  };
  await dependencies.storePack(placeId, userId, stored);

  return {
    statusCode: 200,
    body: storedPackResponseBody(stored, dependencies.now?.() ?? new Date()),
  };
}

function storedRequestMatches(
  stored: StoredRelatedPlaceSourcePack,
  request: { platforms: string[]; maxResultsPerPlatform: number },
): boolean {
  return stored.maxResultsPerPlatform === request.maxResultsPerPlatform
    && sortedStrings(stored.requestedPlatforms).join("\n") === sortedStrings(request.platforms).join("\n");
}

function storedPackResponseBody(
  stored: StoredRelatedPlaceSourcePack,
  now: Date,
): Record<string, unknown> {
  const fetchedAt = new Date(stored.fetchedAt);
  if (Number.isNaN(fetchedAt.getTime())) {
    throw new Error("Stored related-source fetched_at is invalid");
  }
  const staleAfter = new Date(fetchedAt.getTime() + relatedPlaceSourcesStalenessWindowMs);
  return {
    ...stored.pack,
    storage: {
      persistence: "owner_private_backend",
      fetched_at: fetchedAt.toISOString(),
      stale_after: staleAfter.toISOString(),
      is_stale: now.getTime() > staleAfter.getTime(),
      query_set: stored.querySet,
    },
  };
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}

function sortedStrings(values: readonly string[]): string[] {
  return [...values].sort((left, right) => left.localeCompare(right));
}
