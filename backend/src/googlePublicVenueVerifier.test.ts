import assert from "node:assert/strict";
import test from "node:test";
import {
  createCachedGooglePublicVenueVerifier,
  verifyGooglePublicVenue,
  type GooglePublicVenueVerifierConfig,
} from "./googlePublicVenueVerifier.js";

const apiKey = "test-api-key";
const canonicalGoogleVenue = {
  id: "ChIJcanonical",
  displayName: {
    text: "賀鴨郎粵菜餐廳",
    languageCode: "zh-TW",
  },
  formattedAddress: "804台灣高雄市鼓山區美術東二路618號",
  primaryType: "chinese_restaurant",
  location: {
    latitude: 22.655,
    longitude: 120.286,
  },
};

function configWithResponse(
  body: BodyInit | null,
  responseInit: ResponseInit = { status: 200 },
): GooglePublicVenueVerifierConfig {
  return {
    apiKey,
    fetcher: async () => new Response(body, responseInit),
  };
}

test("uses authoritative Google identity instead of a forged stored name and category", async () => {
  let requestedURL = "";
  let requestedInit: RequestInit | undefined;
  const result = await verifyGooglePublicVenue(
    {
      googlePlaceId: "ChIJrequested/id",
      name: "Private Home",
      category: "residential",
    },
    {
      apiKey,
      fetcher: async (input, init) => {
        requestedURL = input.toString();
        requestedInit = init;
        return Response.json(canonicalGoogleVenue);
      },
    },
  );

  assert.deepEqual(result, {
    status: "verified",
    venue: {
      googlePlaceId: "ChIJcanonical",
      displayName: "賀鴨郎粵菜餐廳",
      formattedAddress: "804台灣高雄市鼓山區美術東二路618號",
      primaryType: "chinese_restaurant",
      latitude: 22.655,
      longitude: 120.286,
    },
  });
  assert.equal(
    requestedURL,
    "https://places.googleapis.com/v1/places/ChIJrequested%2Fid",
  );
  assert.equal(requestedInit?.method, "GET");
  assert.deepEqual(requestedInit?.headers, {
    accept: "application/json",
    "x-goog-api-key": apiKey,
    "x-goog-fieldmask": "id,displayName,formattedAddress,primaryType,location",
  });
});

test("fails closed without a Google Place ID or API key and does not call the provider", async () => {
  let fetchCount = 0;
  const fetcher: typeof fetch = async () => {
    fetchCount += 1;
    return Response.json(canonicalGoogleVenue);
  };

  assert.deepEqual(
    await verifyGooglePublicVenue({}, { apiKey, fetcher }),
    { status: "unavailable", reason: "missing_google_place_id" },
  );
  assert.deepEqual(
    await verifyGooglePublicVenue({ googlePlaceId: "ChIJrequested" }, { fetcher }),
    { status: "unavailable", reason: "missing_api_key" },
  );
  assert.equal(fetchCount, 0);
});

test("rejects residential and address-only Google primary types", async () => {
  const residential = await verifyGooglePublicVenue(
    { googlePlaceId: "ChIJresidential" },
    configWithResponse(JSON.stringify({
      ...canonicalGoogleVenue,
      primaryType: "apartment_complex",
    })),
  );
  const addressOnly = await verifyGooglePublicVenue(
    { googlePlaceId: "ChIJaddress" },
    configWithResponse(JSON.stringify({
      ...canonicalGoogleVenue,
      primaryType: "street_address",
    })),
  );

  assert.deepEqual(residential, { status: "rejected", reason: "residential_type" });
  assert.deepEqual(addressOnly, { status: "rejected", reason: "address_only_type" });
});

test("returns a generic unavailable result for provider HTTP failures without leaking details", async () => {
  const result = await verifyGooglePublicVenue(
    { googlePlaceId: "ChIJhttp" },
    configWithResponse(
      JSON.stringify({ error: { message: `invalid key ${apiKey}` } }),
      { status: 403 },
    ),
  );

  assert.deepEqual(result, { status: "unavailable", reason: "provider_http_error" });
  assert.doesNotMatch(JSON.stringify(result), /403|test-api-key|invalid key/);
});

test("fails closed on malformed or incomplete provider responses", async () => {
  const malformed = await verifyGooglePublicVenue(
    { googlePlaceId: "ChIJmalformed" },
    configWithResponse("{not-json"),
  );
  const missingIdentity = await verifyGooglePublicVenue(
    { googlePlaceId: "ChIJincomplete" },
    configWithResponse(JSON.stringify({
      ...canonicalGoogleVenue,
      primaryType: undefined,
    })),
  );

  assert.deepEqual(malformed, { status: "unavailable", reason: "malformed_response" });
  assert.deepEqual(missingIdentity, {
    status: "unavailable",
    reason: "missing_public_venue_identity",
  });
});

test("rejects oversized responses from the header or streamed body", async () => {
  const headerOversize = await verifyGooglePublicVenue(
    { googlePlaceId: "ChIJheader" },
    {
      ...configWithResponse("{}", {
        status: 200,
        headers: { "content-length": "1000" },
      }),
      maxResponseBytes: 100,
    },
  );
  const bodyOversize = await verifyGooglePublicVenue(
    { googlePlaceId: "ChIJbody" },
    {
      ...configWithResponse(JSON.stringify({
        ...canonicalGoogleVenue,
        padding: "x".repeat(500),
      })),
      maxResponseBytes: 100,
    },
  );

  assert.deepEqual(headerOversize, { status: "unavailable", reason: "response_too_large" });
  assert.deepEqual(bodyOversize, { status: "unavailable", reason: "response_too_large" });
});

test("returns a bounded timeout when provider fetch or response streaming stalls", async () => {
  const stalledFetch = await verifyGooglePublicVenue(
    { googlePlaceId: "ChIJtimeout" },
    {
      apiKey,
      timeoutMs: 5,
      fetcher: async () => await new Promise<Response>(() => {}),
    },
  );
  const stalledBody = await verifyGooglePublicVenue(
    { googlePlaceId: "ChIJstream" },
    {
      apiKey,
      timeoutMs: 5,
      fetcher: async () => new Response(new ReadableStream<Uint8Array>({
        start: () => {},
      })),
    },
  );

  assert.deepEqual(stalledFetch, { status: "unavailable", reason: "provider_timeout" });
  assert.deepEqual(stalledBody, { status: "unavailable", reason: "provider_timeout" });
});

test("coalesces and caches verified venue lookups with a bounded expiry", async () => {
  let fetchCount = 0;
  let now = 1_000;
  const verify = createCachedGooglePublicVenueVerifier({
    apiKey,
    cacheTtlMs: 100,
    now: () => now,
    fetcher: async () => {
      fetchCount += 1;
      return Response.json(canonicalGoogleVenue);
    },
  });
  const place = { googlePlaceId: "ChIJcached" };

  const [first, concurrent] = await Promise.all([verify(place), verify(place)]);
  const cached = await verify(place);
  assert.equal(first.status, "verified");
  assert.deepEqual(concurrent, first);
  assert.deepEqual(cached, first);
  assert.equal(fetchCount, 1);

  now += 101;
  const refreshed = await verify(place);
  assert.equal(refreshed.status, "verified");
  assert.equal(fetchCount, 2);
});
