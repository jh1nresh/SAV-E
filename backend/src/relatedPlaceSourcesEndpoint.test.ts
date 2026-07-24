import assert from "node:assert/strict";
import test from "node:test";
import {
  executeRelatedPlaceSourcesEndpoint,
  hasAccountBearerAuthorization,
  RelatedPlaceSourcesOwnerRateLimiter,
  type OwnedRelatedSourcePlace,
} from "./relatedPlaceSourcesEndpoint.js";
import type { RelatedPlaceSourcePack } from "./relatedPlaceSources.js";

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
      },
    ),
    (error) => error === notFound,
  );

  assert.equal(verificationCount, 0);
  assert.equal(discoveryCount, 0);
});

test("discovery receives only the authoritative public venue identity", async () => {
  let discoveredPlace: Record<string, unknown> | undefined;
  const emptyPack = (place: Record<string, unknown>): RelatedPlaceSourcePack => ({
    place: place as RelatedPlaceSourcePack["place"],
    sources: [],
    coverage: [],
    receipt: {
      sourceBoundary: "public_web_index",
      privacy: "owner_private",
      checkedAt: "2026-07-24T12:00:00.000Z",
      requestedPlatforms: [],
      searchedPlatforms: [],
      failedPlatforms: [],
      rawResultCount: 0,
      independentResultCount: 0,
      missing: [],
    },
  });

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
    },
  );

  assert.deepEqual(result, {
    statusCode: 400,
    body: { error: "Related-source discovery only supports public venues" },
  });
  assert.equal(discoveryCount, 0);
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
