import assert from "node:assert/strict";
import test from "node:test";

import {
  canonicalizeOwnedTripStops,
  deleteTripStopsSql,
  maxTripStops,
  normalizeTripStopSnapshot,
  ownedTripForUpdateSql,
  ownedTripPlacesSql,
  validateTripMetadataSnapshot,
} from "./tripPersistence.js";

const placeId = "11111111-1111-4111-8111-111111111111";
const secondPlaceId = "22222222-2222-4222-8222-222222222222";
const stopId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

test("normalizes a bounded full trip stop snapshot without trusting client place names", () => {
  assert.deepEqual(normalizeTripStopSnapshot({
    trip_stops: [{
      id: stopId.toUpperCase(),
      trip_id: "33333333-3333-4333-8333-333333333333",
      place_id: placeId.toUpperCase(),
      place_name: "Spoofed client name",
      day: 1,
      order_index: 0,
      start_time: "09:30",
      duration: 90,
      note: "Window seat",
    }],
  }), [{
    id: stopId,
    place_id: placeId,
    day: 1,
    order_index: 0,
    start_time: "09:30",
    duration: 90,
    note: "Window seat",
  }]);

  assert.deepEqual(normalizeTripStopSnapshot({ trip_stops: [] }), []);
});

test("rejects missing, oversized, malformed, and ambiguously ordered snapshots", () => {
  assert.throws(() => normalizeTripStopSnapshot({}), /trip_stops must be an array/);
  assert.throws(
    () => normalizeTripStopSnapshot({
      trip_stops: Array.from({ length: maxTripStops + 1 }, () => ({
        place_id: placeId,
        day: 1,
        order_index: 0,
      })),
    }),
    /at most 100/,
  );
  assert.throws(
    () => normalizeTripStopSnapshot({
      trip_stops: [{ place_id: "not-a-uuid", day: 1, order_index: 0 }],
    }),
    /place_id must be a UUID/,
  );
  assert.throws(
    () => normalizeTripStopSnapshot({
      trip_stops: [
        { place_id: placeId, day: 1, order_index: 0 },
        { place_id: secondPlaceId, day: 1, order_index: 0 },
      ],
    }),
    /duplicate day\/order positions/,
  );
});

test("enforces day, order, duration, text, and field boundaries", () => {
  const stop = { place_id: placeId, day: 1, order_index: 0 };

  assert.throws(() => normalizeTripStopSnapshot({ trip_stops: [{ ...stop, day: 0 }] }), /day must be an integer/);
  assert.throws(
    () => normalizeTripStopSnapshot({ trip_stops: [{ ...stop, order_index: maxTripStops }] }),
    /order_index must be an integer/,
  );
  assert.throws(() => normalizeTripStopSnapshot({ trip_stops: [{ ...stop, duration: 0 }] }), /duration must be an integer/);
  assert.throws(
    () => normalizeTripStopSnapshot({ trip_stops: [{ ...stop, note: "x".repeat(4_097) }] }),
    /note exceeds 4096 bytes/,
  );
  assert.throws(
    () => normalizeTripStopSnapshot({ trip_stops: [{ ...stop, latitude: 25.03 }] }),
    /unexpected fields/,
  );
});

test("validates bounded trip metadata and chronological dates", () => {
  assert.doesNotThrow(() => validateTripMetadataSnapshot({
    name: "Taipei weekend",
    city: "Taipei",
    start_date: "2026-07-19",
    end_date: "2026-07-21",
    is_optimized: false,
  }, true));
  assert.throws(() => validateTripMetadataSnapshot({ city: "Taipei" }, true), /name must be a string/);
  assert.throws(() => validateTripMetadataSnapshot({ name: "   " }, true), /name must not be empty/);
  assert.throws(
    () => validateTripMetadataSnapshot({ name: "Trip", start_date: "2026-02-30" }, true),
    /valid calendar date/,
  );
  assert.throws(
    () => validateTripMetadataSnapshot({ start_date: "2026-07-21", end_date: "2026-07-19" }, false),
    /end_date must be on or after start_date/,
  );
});

test("canonicalizes names from owned place rows and fails closed on missing ownership", () => {
  const stops = normalizeTripStopSnapshot({
    trip_stops: [
      { place_id: placeId, place_name: "Spoofed", day: 1, order_index: 0 },
      { place_id: secondPlaceId, place_name: "Also spoofed", day: 2, order_index: 0 },
    ],
  });

  assert.deepEqual(canonicalizeOwnedTripStops(stops, [
    { id: placeId, name: "Canonical One" },
    { id: secondPlaceId, name: "Canonical Two" },
  ]).map((stop) => stop.place_name), ["Canonical One", "Canonical Two"]);
  assert.throws(
    () => canonicalizeOwnedTripStops(stops, [{ id: placeId, name: "Canonical One" }]),
    /not owned by the user/,
  );
});

test("transaction SQL locks the owned trip and only projects owned place names", () => {
  const tripLock = ownedTripForUpdateSql.replace(/\s+/g, " ").trim().toLowerCase();
  const placesLock = ownedTripPlacesSql.replace(/\s+/g, " ").trim().toLowerCase();

  assert.match(tripLock, /where id = \$1 and user_id = \$2 for update/);
  assert.match(placesLock, /^select id, name from places/);
  assert.match(placesLock, /where user_id = \$1/);
  assert.match(placesLock, /id = any\(\$2::uuid\[\]\)/);
  assert.match(placesLock, /for key share$/);
  assert.doesNotMatch(placesLock, /note|source_url|latitude|longitude/);
  assert.equal(deleteTripStopsSql, "delete from trip_stops where trip_id = $1");
});
