import assert from "node:assert/strict";
import test from "node:test";

import {
  buildTrekKml,
  normalizeTrekKmlExportRequest,
  trekKmlPlacesSql,
  trekKmlResponseHeaders,
} from "./trekKmlExport.js";

const placeIds = [
  "11111111-1111-4111-8111-111111111111",
  "22222222-2222-4222-8222-222222222222",
];

test("normalizes an explicit bounded list of unique place UUIDs", () => {
  assert.deepEqual(normalizeTrekKmlExportRequest({ place_ids: placeIds }), placeIds);
});

test("rejects missing, empty, oversized, invalid, and duplicate place selections", () => {
  assert.throws(() => normalizeTrekKmlExportRequest({}), /place_ids must be an array/);
  assert.throws(() => normalizeTrekKmlExportRequest({ place_ids: [] }), /between 1 and 100/);
  assert.throws(
    () => normalizeTrekKmlExportRequest({ place_ids: Array.from({ length: 101 }, () => placeIds[0]) }),
    /between 1 and 100/,
  );
  assert.throws(() => normalizeTrekKmlExportRequest({ place_ids: ["not-a-uuid"] }), /invalid UUID/);
  assert.throws(() => normalizeTrekKmlExportRequest({ place_ids: [placeIds[0], placeIds[0]] }), /duplicates/);
});

test("builds TREK-compatible KML with escaped text and longitude-latitude coordinate order", () => {
  const kml = buildTrekKml([
    {
      id: placeIds[0],
      name: "茶館 & <View>",
      address: "1 \"Main\" St > Plaza",
      latitude: 25.033,
      longitude: 121.5654,
      category: "café",
      status: "wantToGo",
    },
  ]);

  assert.match(kml, /^<\?xml version="1\.0" encoding="UTF-8"\?>/);
  assert.match(kml, /xmlns="http:\/\/www\.opengis\.net\/kml\/2\.2"/);
  assert.match(kml, /<name>茶館 &amp; &lt;View&gt;<\/name>/);
  assert.match(kml, /Address: 1 &quot;Main&quot; St &gt; Plaza/);
  assert.match(kml, /<coordinates>121\.5654,25\.033,0<\/coordinates>/);
  assert.doesNotMatch(kml, /茶館 & <View>/);
});

test("exports only the bounded place projection", () => {
  const kml = buildTrekKml([
    {
      id: placeIds[0],
      name: "Safe Place",
      address: "Safe Address",
      latitude: 34.05,
      longitude: -118.25,
      category: "food",
      status: "visited",
      note: "private birthday note",
      source_url: "https://private.example/source",
      evidence: ["private evidence"],
    } as never,
  ]);

  assert.match(kml, /Safe Place/);
  assert.doesNotMatch(kml, /private birthday note|private\.example|private evidence/);
});

test("removes invalid XML control characters without dropping emoji", () => {
  const kml = buildTrekKml([
    {
      id: placeIds[0],
      name: "Tea\u0001 😀",
      address: "Los Angeles",
      latitude: 34.05,
      longitude: -118.25,
      category: "cafe",
      status: "wantToGo",
    },
  ]);

  assert.match(kml, /Tea 😀/);
  assert.doesNotMatch(kml, /\u0001/);
});

test("fails closed when a selected place has unusable coordinates", () => {
  assert.throws(
    () => buildTrekKml([
      {
        id: placeIds[0],
        name: "Broken Place",
        address: "",
        latitude: 91,
        longitude: 10,
        category: "other",
        status: "wantToGo",
      },
    ]),
    /invalid coordinates/,
  );
  assert.throws(
    () => buildTrekKml([
      {
        id: placeIds[0],
        name: "Unresolved Place",
        address: "",
        latitude: 0,
        longitude: 0,
        category: "other",
        status: "wantToGo",
      },
    ]),
    /invalid coordinates/,
  );
});

test("rejects oversized place fields and aggregate export text before XML expansion", () => {
  const place = {
    id: placeIds[0],
    name: "Safe Place",
    address: "Safe Address",
    latitude: 34.05,
    longitude: -118.25,
    category: "food",
    status: "visited",
  };

  assert.throws(
    () => buildTrekKml([{ ...place, name: "x".repeat(513) }]),
    /place name exceeds 512 bytes/,
  );
  assert.throws(
    () => buildTrekKml(Array.from({ length: 65 }, () => ({ ...place, address: "x".repeat(4096) }))),
    /export text exceeds 262144 bytes/,
  );
});

test("owner-scoped SQL selects only KML fields and preserves request order", () => {
  const normalized = trekKmlPlacesSql.replace(/\s+/g, " ").trim().toLowerCase();

  assert.match(normalized, /where user_id = \$1/);
  assert.match(normalized, /id = any\(\$2::uuid\[\]\)/);
  assert.match(normalized, /order by array_position\(\$2::uuid\[\], id\)/);
  assert.doesNotMatch(normalized, /note|source_url|source_image_url|business_photo_urls|extracted_dishes|opening_hours/);
});

test("KML response headers prevent caching and content sniffing", () => {
  assert.deepEqual(trekKmlResponseHeaders(), {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Expose-Headers": "Content-Disposition",
    "Cache-Control": "private, no-store",
    "Content-Disposition": 'attachment; filename="save-map-stamps.kml"',
    "Content-Type": "application/vnd.google-earth.kml+xml; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
  });
});
