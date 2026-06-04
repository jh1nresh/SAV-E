import assert from "node:assert/strict";
import test from "node:test";
import {
  formatSharedPlaceLink,
  isEmbeddedSharePayloadToken,
  normalizeSharedPlaceLinkCreate,
} from "./shareLinks.js";

test("normalizeSharedPlaceLinkCreate stores public place payload for short code resolving", () => {
  const link = normalizeSharedPlaceLinkCreate({
    source_place_id: "550e8400-e29b-41d4-a716-446655440000",
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
  });

  assert.equal(link.sourcePlaceId, "550e8400-e29b-41d4-a716-446655440000");
  assert.equal(link.payload.name, "A Cheng Goose");
  assert.equal(link.payload.lat, 25.055);
  assert.equal(link.payload.photoURLs.length, 3);
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
});
