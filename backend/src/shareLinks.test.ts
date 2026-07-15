import assert from "node:assert/strict";
import test from "node:test";
import {
  formatPublicSharedPlaceLink,
  formatSharedPlaceLink,
  isEmbeddedSharePayloadToken,
  isSharedPlaceLinkExpired,
  normalizeSharedSenderSnapshot,
  normalizeSharedPlaceLinkCreate,
  publicSharedPlaceLinkSelectSQL,
  sharedPlaceEmbeddedTokenMaxCharacters,
  sharedPlacePayloadMaxBytes,
} from "./shareLinks.js";

test("normalizeSharedPlaceLinkCreate stores public place payload for short code resolving", () => {
  const now = new Date("2026-07-15T00:00:00.000Z");
  const link = normalizeSharedPlaceLinkCreate({
    source_place_id: "550e8400-e29b-41d4-a716-446655440000",
    note_consent_version: 1,
    payload: {
      id: "place_1",
      name: "A Cheng Goose",
      address: "No. 105, Jilin Rd, Taipei",
      lat: 25.055,
      lng: 121.533,
      category: "Food",
      rating: 4.6,
      reviewCount: 320,
      sourceLabel: "Instagram",
      sourceURL: "https://www.instagram.com/reel/example/",
      photoURLs: ["https://example.com/a.jpg", "https://example.com/a.jpg?2", "https://example.com/a.jpg?3", "https://example.com/a.jpg?4"],
      note: "Known for goose plates.",
    },
  }, now);

  assert.equal(link.sourcePlaceId, "550e8400-e29b-41d4-a716-446655440000");
  assert.equal(link.payload.name, "A Cheng Goose");
  assert.equal(link.payload.lat, 25.055);
  assert.deepEqual(link.payload.photoURLs, ["https://example.com/a.jpg"]);
  assert.equal(link.payload.note, "Known for goose plates.");
  assert.equal(link.noteConsentVersion, 1);
  assert.equal(link.expiresAt, "2026-08-14T00:00:00.000Z");
});

test("normalizeSharedPlaceLinkCreate rejects expired, invalid, and overlong expiry", () => {
  const now = new Date("2026-07-15T00:00:00.000Z");
  const body = {
    payload: {
      name: "Kato",
      lat: 34.04,
      lng: -118.23,
    },
  };

  assert.throws(
    () => normalizeSharedPlaceLinkCreate({ ...body, expires_at: "not-a-date" }, now),
    /valid date/,
  );
  assert.throws(
    () => normalizeSharedPlaceLinkCreate({ ...body, expires_at: "2026-07-15T00:00:00.000Z" }, now),
    /future/,
  );
  assert.throws(
    () => normalizeSharedPlaceLinkCreate({ ...body, expires_at: "2026-08-14T00:00:00.001Z" }, now),
    /30 days/,
  );
});

test("normalizeSharedPlaceLinkCreate rejects coordinates outside valid geographic ranges", () => {
  const payload = { name: "Kato", lat: 34.04, lng: -118.23 };

  assert.throws(
    () => normalizeSharedPlaceLinkCreate({ payload: { ...payload, lat: 90.0001 } }),
    /lat must be between -90 and 90/,
  );
  assert.throws(
    () => normalizeSharedPlaceLinkCreate({ payload: { ...payload, lng: -180.0001 } }),
    /lng must be between -180 and 180/,
  );
  assert.doesNotThrow(
    () => normalizeSharedPlaceLinkCreate({ payload: { ...payload, lat: -90, lng: 180 } }),
  );
});

test("normalizeSharedPlaceLinkCreate rejects oversized public payloads", () => {
  assert.throws(
    () => normalizeSharedPlaceLinkCreate({
      payload: {
        name: "x".repeat(sharedPlacePayloadMaxBytes),
        lat: 34.04,
        lng: -118.23,
      },
    }),
    /payload is too large/,
  );
});

test("normalizeSharedPlaceLinkCreate bounds notes and accepts only web source URLs", () => {
  const payload = {
    name: "Kato",
    lat: 34.04,
    lng: -118.23,
    sourceURL: "javascript:alert(1)",
    photoURLs: ["data:image/png;base64,private", "https://example.com/place.jpg", "https://example.com/second.jpg"],
  };
  const normalized = normalizeSharedPlaceLinkCreate({ payload });

  assert.equal(normalized.payload.sourceURL, null);
  assert.deepEqual(normalized.payload.photoURLs, ["https://example.com/place.jpg"]);
  const credentialed = normalizeSharedPlaceLinkCreate({
    payload: {
      ...payload,
      sourceURL: "https://user:secret@example.com/private",
      photoURLs: ["https://user:secret@example.com/private.jpg"],
    },
  });
  assert.equal(credentialed.payload.sourceURL, null);
  assert.deepEqual(credentialed.payload.photoURLs, []);
  const queryCredentialed = normalizeSharedPlaceLinkCreate({
    payload: {
      ...payload,
      sourceURL: "https://example.com/private?X-Amz-Signature=secret#access_token=secret",
      photoURLs: ["https://example.com/photo.jpg?token=secret#fragment"],
    },
  });
  assert.equal(queryCredentialed.payload.sourceURL, "https://example.com/private");
  assert.deepEqual(queryCredentialed.payload.photoURLs, ["https://example.com/photo.jpg"]);
  assert.throws(
    () => normalizeSharedPlaceLinkCreate({ note_consent_version: 1, payload: { ...payload, note: "x".repeat(181) } }),
    /180 characters/,
  );
  assert.throws(
    () => normalizeSharedPlaceLinkCreate({ note_consent_version: 1, payload: { ...payload, note: "one\ntwo\nthree" } }),
    /2 lines/,
  );
  assert.throws(
    () => normalizeSharedPlaceLinkCreate({ note_consent_version: 1, payload: { ...payload, note: "Try noodles\nVenue name: raw pipeline clue" } }),
    /diagnostic output/,
  );
  const unconsented = normalizeSharedPlaceLinkCreate({
    payload: { ...payload, note: "Private note from an older client" },
  });
  assert.equal(unconsented.payload.note, null);
  assert.equal(unconsented.noteConsentVersion, null);
});

test("formatSharedPlaceLink keeps the /p route and replaces embedded payload with code", () => {
  const formatted = formatSharedPlaceLink({
    code: "AbC123_x",
    payload: { name: "Kato", lat: 34.04, lng: -118.23 },
    source_place_id: null,
    expires_at: null,
    created_at: "2026-06-04T00:00:00Z",
  });

  assert.equal(formatted.url, "https://sav-e-app.vercel.app/p/AbC123_x");
  assert.equal((formatted.payload as Record<string, unknown>).name, "Kato");
  assert.equal(formatted.sender, null);
});

test("formatSharedPlaceLink exposes only safe sender fields for owned place receipts", () => {
  const formatted = formatSharedPlaceLink({
    code: "AbC123_x",
    payload: { name: "Kato", lat: 34.04, lng: -118.23 },
    source_place_id: "550e8400-e29b-41d4-a716-446655440000",
    sender_display_name: "Alice",
    sender_handle: "alice_eats",
    source_verified_at: "2026-07-15T00:00:00Z",
    note_consent_version: 1,
    user_id: "private-user-id",
    sender_email: "alice@example.com",
    sender_phone: "+15550000000",
    expires_at: "2026-08-14T00:00:00Z",
    created_at: "2026-07-15T00:00:00Z",
  });

  assert.deepEqual(formatted.sender, {
    display_name: "Alice",
    handle: "alice_eats",
  });
  assert.equal("user_id" in formatted, false);
  assert.equal("sender_email" in formatted, false);
  assert.equal("sender_phone" in formatted, false);
});

test("sender snapshots are bounded single-line account attribution", () => {
  const snapshot = normalizeSharedSenderSnapshot(
    ` Alice\n${"x".repeat(100)}\u0000`,
    `alice\r\n${"h".repeat(80)}`,
  );

  assert.equal(snapshot.displayName?.includes("\n"), false);
  assert.equal(snapshot.displayName?.includes("\u0000"), false);
  assert.equal(snapshot.displayName?.length, 80);
  assert.equal(snapshot.handle?.includes("\n"), false);
  assert.equal(snapshot.handle?.length, 40);

  const formatted = formatPublicSharedPlaceLink({
    code: "AbC123_x",
    payload: { id: "", name: "Kato", lat: 34.04, lng: -118.23 },
    sender_display_name: `Alice\n${"x".repeat(100)}`,
    sender_handle: `alice\u0000${"h".repeat(80)}`,
    source_verified_at: "2026-07-15T00:00:00Z",
  });
  const sender = formatted.sender as Record<string, unknown>;
  assert.equal(String(sender.display_name).length, 80);
  assert.equal(String(sender.handle).length, 40);
  assert.doesNotMatch(JSON.stringify(sender), /[\u0000\r\n]/);
});

test("formatPublicSharedPlaceLink omits database source ids and blanks caller payload ids", () => {
  const formatted = formatPublicSharedPlaceLink({
    code: "AbC123_x",
    payload: { id: "caller-controlled-id", name: "Kato", lat: 34.04, lng: -118.23 },
    source_place_id: null,
    sender_display_name: "Alice",
    sender_handle: "alice_eats",
    source_verified_at: "2026-07-15T00:00:00Z",
    note_consent_version: 1,
    expires_at: "2026-08-14T00:00:00Z",
    created_at: "2026-07-15T00:00:00Z",
  });

  assert.equal("source_place_id" in formatted, false);
  assert.equal((formatted.payload as Record<string, unknown>).id, "");
  assert.deepEqual(formatted.sender, { display_name: "Alice", handle: "alice_eats" });
});

test("public formatter exposes only newly consented notes", () => {
  const baseRow = {
    code: "AbC123_x",
    payload: { id: "private-id", name: "Kato", lat: 34.04, lng: -118.23, note: "Try the tasting menu" },
    sender_display_name: "Alice",
    source_verified_at: "2026-07-15T00:00:00Z",
  };

  const legacy = formatPublicSharedPlaceLink({ ...baseRow, note_consent_version: null });
  const consented = formatPublicSharedPlaceLink({ ...baseRow, note_consent_version: 1 });
  assert.equal((legacy.payload as Record<string, unknown>).note, null);
  assert.equal((consented.payload as Record<string, unknown>).note, "Try the tasting menu");
});

test("public shared-place lookup uses immutable sender snapshots without live joins", () => {
  const normalized = publicSharedPlaceLinkSelectSQL.replace(/\s+/g, " ").trim().toLowerCase();

  assert.match(normalized, /sender_display_name, sender_handle, source_verified_at, note_consent_version from shared_place_links/);
  assert.doesNotMatch(normalized, / join /);
  assert.doesNotMatch(normalized, /profiles/);
  assert.doesNotMatch(normalized, /places/);
});

test("formatSharedPlaceLink never attributes generic candidate links", () => {
  const formatted = formatSharedPlaceLink({
    code: "AbC123_x",
    payload: { name: "Kato", lat: 34.04, lng: -118.23 },
    source_place_id: null,
    sender_display_name: null,
    sender_handle: null,
    source_verified_at: null,
  });

  assert.equal(formatted.sender, null);
});

test("isSharedPlaceLinkExpired distinguishes expired links without exposing their payload", () => {
  const now = new Date("2026-07-15T00:00:00.000Z");

  assert.equal(isSharedPlaceLinkExpired("2026-07-14T23:59:59.999Z", now), true);
  assert.equal(isSharedPlaceLinkExpired(new Date("2026-07-15T00:00:00.000Z"), now), true);
  assert.equal(isSharedPlaceLinkExpired("2026-07-15T00:00:00.001Z", now), false);
  assert.equal(isSharedPlaceLinkExpired(null, now), false);
});

test("isEmbeddedSharePayloadToken preserves old base64 JSON share links", () => {
  const payload = Buffer.from(JSON.stringify({
    id: "place_1",
    name: "Kato",
    address: "777 S Alameda St, Los Angeles, CA",
    lat: 34.04,
    lng: -118.23,
    category: "Food",
    rating: 4.8,
    reviewCount: 120,
    priceRange: "$$$",
    hours: "Open",
    sourceLabel: "Instagram",
    sourceURL: "https://www.instagram.com/reel/kato/",
    photoURLs: ["https://example.com/kato.jpg"],
    note: "Tasting menu",
  }), "utf8")
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");

  assert.equal(isEmbeddedSharePayloadToken(payload), true);
  assert.equal(isEmbeddedSharePayloadToken("AbC123_x"), false);
  assert.equal(
    isEmbeddedSharePayloadToken("A".repeat(sharedPlaceEmbeddedTokenMaxCharacters + 1)),
    false,
  );
});
