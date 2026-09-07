import assert from "node:assert/strict";
import test from "node:test";
import type { RelatedSourcePlaceIdentity } from "./relatedPlaceSources.js";
import {
  executeRelatedPlaceSourcesEndpoint,
  hasAccountBearerAuthorization,
  RelatedPlaceSourcesOwnerRateLimiter,
  type OwnedRelatedSourcePlace,
} from "./relatedPlaceSourcesEndpoint.js";
import type { RelatedPlaceSourcePack } from "./relatedPlaceSources.js";
import type { StoredRelatedPlaceSourcePack } from "./relatedPlaceSourcesStore.js";

const ownedPlace: OwnedRelatedSourcePlace = {
  id: "11111111-1111-4111-8111-111111111111",
  googlePlaceId: "ChIJcanonical",
  name: "Alice's House",
  category: "food",
  sourceUrl: "https://instagram.com/reel/seed",
};

const verifiedVenue = {
  status: "verified" as const,
  venue: {
    googlePlaceId: "ChIJcanonical",
    displayName: "賀鴨郎粵菜餐廳",
    formattedAddress: "804台灣高雄市鼓山區美術東二路618號",
    primaryType: "chinese_restaurant",
    latitude: 22.655,
    longitude: 120.286,
  },
};

const noStoredPack = async (): Promise<StoredRelatedPlaceSourcePack | undefined> => undefined;
const ignoreStoredPack = async (): Promise<void> => {};

const emptyPack = (place: Record<string, unknown>, checkedAt = "2026-07-24T12:00:00.000Z"): RelatedPlaceSourcePack => ({
  place: place as RelatedPlaceSourcePack["place"],
  sources: [],
  coverage: [],
  receipt: {
    sourceBoundary: "public_web_index",
    privacy: "owner_private",
    checkedAt,
    requestedPlatforms: [],
    searchedPlatforms: [],
    failedPlatforms: [],
    rawResultCount: 0,
    independentResultCount: 0,
    missing: [],
  },
});

test("related-source discovery requires the already-verified account bearer path", () => {
  assert.equal(hasAccountBearerAuthorization(undefined), false);
  assert.equal(hasAccountBearerAuthorization("Basic guest-token"), false);
  assert.equal(hasAccountBearerAuthorization("Bearer"), false);
  assert.equal(hasAccountBearerAuthorization("Bearer verified-privy-token"), true);
});

test("an owner lookup failure prevents venue verification and public search", async () => {
  let verificationCount = 0;
  let discoveryCount = 0;
  const notFound = new Error("Place not found");

  await assert.rejects(
    executeRelatedPlaceSourcesEndpoint(
      ownedPlace.id,
      "other-user",
      { platforms: ["instagram"] },
      {
        loadOwnedPlace: async () => {
          throw notFound;
        },
        verifyPublicVenue: async () => {
          verificationCount += 1;
          return verifiedVenue;
        },
        discover: async () => {
          discoveryCount += 1;
          throw new Error("must not run");
        },
        loadStoredPack: noStoredPack,
        storePack: ignoreStoredPack,
      },
    ),
    (error) => error === notFound,
  );

  assert.equal(verificationCount, 0);
  assert.equal(discoveryCount, 0);
});

test("discovery receives only the authoritative public venue identity", async () => {
  let discoveredPlace: Record<string, unknown> | undefined;
  const result = await executeRelatedPlaceSourcesEndpoint(
    ownedPlace.id,
    "owner-user",
    { platforms: ["instagram"] },
    {
      loadOwnedPlace: async (placeId, userId) => {
        assert.equal(placeId, ownedPlace.id);
        assert.equal(userId, "owner-user");
        return ownedPlace;
      },
      verifyPublicVenue: async () => verifiedVenue,
      discover: async (place) => {
        discoveredPlace = place;
        return emptyPack(place);
      },
      loadStoredPack: noStoredPack,
      storePack: ignoreStoredPack,
      now: () => new Date("2026-07-24T12:00:00.000Z"),
    },
  );

  assert.equal(result.statusCode, 200);
  assert.deepEqual(discoveredPlace, {
    id: ownedPlace.id,
    name: "賀鴨郎粵菜餐廳",
    address: "804台灣高雄市鼓山區美術東二路618號",
    latitude: 22.655,
    longitude: 120.286,
    category: "chinese_restaurant",
    googlePlaceId: "ChIJcanonical",
    sourceUrl: "https://instagram.com/reel/seed",
  });
  assert.ok(!JSON.stringify(discoveredPlace).includes("Alice"));
});

test("failed public-venue verification returns a bounded error without discovery", async () => {
  let discoveryCount = 0;
  const result = await executeRelatedPlaceSourcesEndpoint(
    ownedPlace.id,
    "owner-user",
    { platforms: ["instagram"] },
    {
      loadOwnedPlace: async () => ownedPlace,
      verifyPublicVenue: async () => ({
        status: "rejected",
        reason: "residential_type",
      }),
      discover: async () => {
        discoveryCount += 1;
        throw new Error("must not run");
      },
      loadStoredPack: noStoredPack,
      storePack: ignoreStoredPack,
    },
  );

  assert.deepEqual(result, {
    statusCode: 400,
    body: { error: "Related-source discovery only supports public venues" },
  });
  assert.equal(discoveryCount, 0);
});

test("a matching owner-scoped pack is re-read without verification, quota, or discovery", async () => {
  let verificationCount = 0;
  let discoveryCount = 0;
  let quotaCount = 0;
  const storedPack: StoredRelatedPlaceSourcePack = {
    pack: {
      place: { id: ownedPlace.id, google_place_id: ownedPlace.googlePlaceId },
      sources: [],
      coverage: [{ platform: "instagram", status: "failed", queries: ["stored query"] }],
      receipt: { checked_at: "2026-08-15T12:00:00.000Z", privacy: "owner_private" },
    },
    fetchedAt: "2026-08-15T12:00:00.000Z",
    requestedPlatforms: ["instagram"],
    maxResultsPerPlatform: 3,
    querySet: ["stored query"],
  };

  const result = await executeRelatedPlaceSourcesEndpoint(
    ownedPlace.id,
    "owner-user",
    { platforms: ["instagram"] },
    {
      loadOwnedPlace: async () => ownedPlace,
      verifyPublicVenue: async () => {
        verificationCount += 1;
        return verifiedVenue;
      },
      discover: async () => {
        discoveryCount += 1;
        throw new Error("must not run");
      },
      loadStoredPack: async (placeId, userId) => {
        assert.equal(placeId, ownedPlace.id);
        assert.equal(userId, "owner-user");
        return storedPack;
      },
      storePack: ignoreStoredPack,
      consumeDiscoveryQuota: () => {
        quotaCount += 1;
        return { allowed: true };
      },
      now: () => new Date("2026-08-23T12:00:00.000Z"),
    },
  );

  assert.equal(result.statusCode, 200);
  assert.equal(verificationCount, 0);
  assert.equal(discoveryCount, 0);
  assert.equal(quotaCount, 0);
  assert.deepEqual(result.body.coverage, storedPack.pack.coverage);
  assert.deepEqual(result.body.storage, {
    persistence: "owner_private_backend",
    fetched_at: "2026-08-15T12:00:00.000Z",
    stale_after: "2026-08-22T12:00:00.000Z",
    is_stale: true,
    query_set: ["stored query"],
  });
});

test("force refresh replaces the one current pack and preserves failed coverage", async () => {
  let saved: StoredRelatedPlaceSourcePack | undefined;
  const failedPack: RelatedPlaceSourcePack = {
    ...emptyPack({
      id: ownedPlace.id,
      name: verifiedVenue.venue.displayName,
      address: verifiedVenue.venue.formattedAddress,
      googlePlaceId: verifiedVenue.venue.googlePlaceId,
    }, "2026-08-23T12:00:00.000Z"),
    coverage: [{
      platform: "instagram",
      method: "public_index",
      status: "failed",
      queries: ["site:instagram.com venue"],
      inspectedCount: 0,
      resultCount: 0,
      blockedReason: "public_search_failed",
    }],
  };

  const result = await executeRelatedPlaceSourcesEndpoint(
    ownedPlace.id,
    "owner-user",
    { platforms: ["instagram"], maxResultsPerPlatform: 2, forceRefresh: true },
    {
      loadOwnedPlace: async () => ownedPlace,
      verifyPublicVenue: async () => verifiedVenue,
      discover: async () => failedPack,
      loadStoredPack: async () => {
        throw new Error("force refresh must bypass the stored read");
      },
      storePack: async (_placeId, _userId, value) => {
        saved = value;
      },
      consumeDiscoveryQuota: () => ({ allowed: true }),
      now: () => new Date("2026-08-23T12:00:00.000Z"),
    },
  );

  assert.equal(result.statusCode, 200);
  assert.deepEqual(saved?.querySet, ["site:instagram.com venue"]);
  assert.deepEqual(saved?.requestedPlatforms, ["instagram"]);
  assert.equal(saved?.maxResultsPerPlatform, 2);
  assert.deepEqual((saved?.pack.coverage as Array<Record<string, unknown>>)[0]?.status, "failed");
  assert.deepEqual(result.body.storage, {
    persistence: "owner_private_backend",
    fetched_at: "2026-08-23T12:00:00.000Z",
    stale_after: "2026-08-30T12:00:00.000Z",
    is_stale: false,
    query_set: ["site:instagram.com venue"],
  });
});

test("a cache miss consumes quota before public venue verification", async () => {
  let verificationCount = 0;
  const result = await executeRelatedPlaceSourcesEndpoint(
    ownedPlace.id,
    "owner-user",
    { platforms: ["instagram"] },
    {
      loadOwnedPlace: async () => ownedPlace,
      verifyPublicVenue: async () => {
        verificationCount += 1;
        return verifiedVenue;
      },
      loadStoredPack: noStoredPack,
      storePack: ignoreStoredPack,
      consumeDiscoveryQuota: () => ({ allowed: false, retryAfterSeconds: 12 }),
    },
  );

  assert.deepEqual(result, {
    statusCode: 429,
    body: { error: "Related-source request limit reached" },
    retryAfterSeconds: 12,
  });
  assert.equal(verificationCount, 0);
});

test("owner quota blocks repeated discovery and resets after its window", () => {
  let now = 1_000;
  const limiter = new RelatedPlaceSourcesOwnerRateLimiter(
    2,
    10_000,
    100,
    () => now,
  );

  assert.deepEqual(limiter.consume("owner-user"), { allowed: true });
  assert.deepEqual(limiter.consume("owner-user"), { allowed: true });
  assert.deepEqual(limiter.consume("owner-user"), {
    allowed: false,
    retryAfterSeconds: 10,
  });
  assert.deepEqual(limiter.consume("another-owner"), { allowed: true });

  now += 10_000;
  assert.deepEqual(limiter.consume("owner-user"), { allowed: true });
});


test("canonical venue IDs retain request identity and cache only for that request", async () => {
  const aliasPlace = { ...ownedPlace, googlePlaceId: "  ChIJ-alias-B  " };
  let stored: StoredRelatedPlaceSourcePack | undefined;
  let verificationCount = 0;
  let discoveries = 0;
  const dependencies = {
    loadOwnedPlace: async () => aliasPlace,
    loadStoredPack: async () => stored,
    storePack: async (_place: string, _user: string, value: StoredRelatedPlaceSourcePack) => { stored = value; },
    verifyPublicVenue: async () => { verificationCount += 1; return verifiedVenue; },
    discover: async (place: RelatedSourcePlaceIdentity) => { discoveries += 1; return emptyPack(place); },
  };
  const first = await executeRelatedPlaceSourcesEndpoint(ownedPlace.id, "owner", {}, dependencies);
  assert.equal((first.body.place as Record<string, unknown>).google_place_id, "ChIJcanonical");
  assert.equal((first.body.place as Record<string, unknown>).requested_google_place_id, "ChIJ-alias-B");
  const cached = await executeRelatedPlaceSourcesEndpoint(ownedPlace.id, "owner", {}, dependencies);
  assert.equal((cached.body.place as Record<string, unknown>).requested_google_place_id, "ChIJ-alias-B");
  assert.equal(verificationCount, 1);
  assert.equal(discoveries, 1);
});

test("cache cannot cross corrected, case-different, or missing Google identities", async () => {
  for (const googleID of ["ChIJ-previous-A", "chij-current-b", undefined]) {
    let discoveries = 0;
    const stale: StoredRelatedPlaceSourcePack = {
      pack: { place: { id: ownedPlace.id, google_place_id: "ChIJcanonical", requested_google_place_id: googleID } },
      fetchedAt: "2026-08-23T12:00:00.000Z", requestedPlatforms: ["instagram"],
      maxResultsPerPlatform: 3, querySet: [],
    };
    const result = await executeRelatedPlaceSourcesEndpoint(ownedPlace.id, "owner", { platforms: ["instagram"] }, {
      loadOwnedPlace: async () => ({ ...ownedPlace, googlePlaceId: "ChIJ-current-B" }),
      loadStoredPack: async () => stale,
      storePack: ignoreStoredPack,
      verifyPublicVenue: async () => verifiedVenue,
      discover: async (place) => { discoveries += 1; return emptyPack(place); },
    });
    assert.equal(discoveries, 1, `must bypass unrelated cache ${googleID}`);
    assert.equal((result.body.place as Record<string, unknown>).requested_google_place_id, "ChIJ-current-B");
  }
});
