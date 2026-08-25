import assert from "node:assert/strict";
import test from "node:test";
import {
  persistableGooglePhotoURL,
  runPlacePhotoBackfill,
  selectBestPhotoCandidate,
  selectMissingPlacePhotosSQL,
  updateMissingPlacePhotosSQL,
  type BackfillFetch,
  type BackfillQuery,
  type MissingPhotoPlace,
} from "./placePhotoBackfill.js";

const place: MissingPhotoPlace = {
  id: "place-1",
  userId: "did:privy:owner",
  name: "Koffee Mameya",
  address: "Shibuya, Tokyo",
  latitude: 35.6629,
  longitude: 139.7078,
};

test("photo candidate requires the same name or a nearby coordinate", () => {
  const unrelated = {
    id: "wrong",
    name: "Different Cafe",
    latitude: 35.7,
    longitude: 139.8,
    photoReferences: ["wrong-photo"],
  };
  const matching = {
    id: "right",
    name: "Koffee Mameya Omotesando",
    latitude: 35.663,
    longitude: 139.7079,
    photoReferences: ["right-photo"],
  };

  assert.equal(selectBestPhotoCandidate(place, [unrelated, matching])?.id, "right");
  assert.equal(selectBestPhotoCandidate(place, [unrelated]), undefined);
});

test("persisted Google photo URL never contains the API key", () => {
  const url = persistableGooglePhotoURL("photo/reference+value");
  assert.match(url, /^https:\/\/maps\.googleapis\.com\/maps\/api\/place\/photo\?/);
  assert.match(url, /maxwidth=900/);
  assert.match(url, /photo_reference=photo%2Freference%2Bvalue/);
  assert.doesNotMatch(url, /(?:^|[?&])key=/);
});

test("dry run is owner scoped and performs no writes", async () => {
  const calls: { sql: string; values: readonly unknown[] }[] = [];
  const query: BackfillQuery = async (sql, values) => {
    calls.push({ sql, values });
    return { rows: [databaseRow()] };
  };

  const receipt = await runPlacePhotoBackfill({
    userId: place.userId,
    limit: 20,
    apply: false,
    apiKey: "test-key",
    query,
    fetcher: googleSearchFetcher,
  });

  assert.deepEqual(receipt, {
    mode: "dry_run",
    selected: 1,
    matched: 1,
    wouldUpdate: 1,
    updated: 0,
    raced: 0,
    skipped: 0,
    failed: 0,
  });
  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /where user_id = \$1/);
  assert.match(calls[0].sql, /cardinality\(business_photo_urls\)/);
  assert.deepEqual(calls[0].values, [place.userId, 20]);
});

test("apply updates only the selected owner row if photos are still missing", async () => {
  const calls: { sql: string; values: readonly unknown[] }[] = [];
  const query: BackfillQuery = async (sql, values) => {
    calls.push({ sql, values });
    if (sql === selectMissingPlacePhotosSQL) return { rows: [databaseRow()] };
    assert.equal(sql, updateMissingPlacePhotosSQL);
    return { rows: [{ id: place.id }] };
  };

  const receipt = await runPlacePhotoBackfill({
    userId: place.userId,
    limit: 1,
    apply: true,
    apiKey: "test-key",
    query,
    fetcher: googleSearchFetcher,
  });

  assert.equal(receipt.updated, 1);
  assert.equal(calls.length, 2);
  assert.match(calls[1].sql, /where id = \$1/);
  assert.match(calls[1].sql, /and user_id = \$2/);
  assert.match(calls[1].sql, /source_image_url is null/);
  assert.equal(calls[1].values[0], place.id);
  assert.equal(calls[1].values[1], place.userId);
  assert.doesNotMatch(String(calls[1].values[2]), /key=/);
});

function databaseRow(): Record<string, unknown> {
  return {
    id: place.id,
    user_id: place.userId,
    name: place.name,
    address: place.address,
    latitude: place.latitude,
    longitude: place.longitude,
    google_place_id: null,
  };
}

const googleSearchFetcher: BackfillFetch = async (input) => {
  const url = new URL(String(input));
  assert.equal(url.searchParams.get("key"), "test-key");
  return new Response(JSON.stringify({
    status: "OK",
    results: [{
      place_id: "google-place-1",
      name: "Koffee Mameya",
      geometry: { location: { lat: place.latitude, lng: place.longitude } },
      photos: [{ photo_reference: "photo/reference+value" }],
    }],
  }), { status: 200, headers: { "content-type": "application/json" } });
};
