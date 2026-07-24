import {
  discoverRelatedPlaceSources,
  relatedPlaceSourcePackResponseBody,
  type RelatedPlaceSourcePack,
  type RelatedPlaceSourcesRequest,
  type RelatedSourcePlaceIdentity,
} from "./relatedPlaceSources.js";
import type {
  GooglePublicVenuePlaceReference,
  GooglePublicVenueVerificationResult,
} from "./googlePublicVenueVerifier.js";

export type OwnedRelatedSourcePlace = GooglePublicVenuePlaceReference & {
  id: string;
  sourceUrl?: string;
};

export type RelatedPlaceSourcesEndpointResult = {
  statusCode: 200 | 400 | 409 | 503;
  body: Record<string, unknown>;
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
};

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

  return {
    statusCode: 200,
    body: relatedPlaceSourcePackResponseBody(pack),
  };
}
