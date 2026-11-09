import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  decodePercentLayers,
  isGooglePlacesPhotoURL,
  persistableSourceImageURL,
  placeWriteIsSilentPhotoNoop,
  sanitizePlacePatchBody,
  sanitizePlacePostBody,
  sanitizePlaceWorkflowBody,
  sanitizePlaceWriteBody,
} from "./googlePlacesPhotoWrite.js";

const googlePlacePhoto =
  "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=legacy-ref";
const googlePlacesMedia =
  "https://places.googleapis.com/v1/places/ChIJ123/photos/ABC/media";
const googlePhotoReferencePath = "places/ChIJ123/photos/ABC";
const encodedPlacePhoto =
  "https://maps.googleapis.com/maps/api/place/%70hoto?photo_reference=legacy-ref";
const doubleEncodedPlacePhoto =
  "https://maps.googleapis.com/maps/api/place/%2570hoto?photo_reference=legacy-ref";
const encodedPlacesMedia =
  "https://places.googleapis.com/v1/places/ChIJ123/%70hotos/ABC/media";
const ownImport = "https://cdn.instagram.com/private-post.jpg";
const friendImport = "https://example.com/friend-share.jpg";
const marketplacePhoto = "https://cdn.example.com/marketplace/photo/123.jpg";
const workplacePhoto = "https://example.com/workplace/photo.png";

const identityFields = {
  name: "Harbor Oven",
  address: "Da'an, Taipei",
  latitude: 25.033,
  longitude: 121.565,
  google_place_id: "ChIJ-harbor-oven",
  status: "saved",
};

function placeFieldsFromServer(): string[] {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const start = server.indexOf("const placeFields = [");
  const end = server.indexOf("] as const;", start);
  return [...server.slice(start, end).matchAll(/"([^"]+)"/g)].map((match) => match[1]);
}

function persistColumns(body: Record<string, unknown>, allowed: readonly string[]): Record<string, unknown> {
  const allowedSet = new Set(allowed);
  return Object.fromEntries(
    Object.entries(body).filter(([key, value]) => allowedSet.has(key) && value !== undefined),
  );
}

test("POST ignores business_photo_urls and stores Google source_image_url as null", () => {
  const stored = sanitizePlaceWriteBody({
    ...identityFields,
    business_photo_urls: [googlePlacePhoto, ownImport],
    source_image_url: googlePlacePhoto,
  });

  assert.equal("business_photo_urls" in stored, false, "retired column is dropped, not written");
  assert.equal(stored.source_image_url, null);
  assert.equal(stored.name, identityFields.name);
  assert.equal(stored.address, identityFields.address);
  assert.equal(stored.latitude, identityFields.latitude);
  assert.equal(stored.longitude, identityFields.longitude);
  assert.equal(stored.google_place_id, identityFields.google_place_id);
  assert.equal(stored.status, "saved");
});

test("POST keeps a non-Google import image and still ignores business_photo_urls", () => {
  const stored = sanitizePlaceWriteBody({
    ...identityFields,
    business_photo_urls: [ownImport],
    source_image_url: ownImport,
  });

  assert.equal("business_photo_urls" in stored, false);
  assert.equal(stored.source_image_url, ownImport);
});

test("percent-decode catches encoded Google photo paths including stacked encoding", () => {
  assert.equal(decodePercentLayers("place/%70hoto"), "place/photo");
  assert.equal(decodePercentLayers("place/%2570hoto"), "place/photo");
  assert.equal(isGooglePlacesPhotoURL(encodedPlacePhoto), true);
  assert.equal(isGooglePlacesPhotoURL(doubleEncodedPlacePhoto), true);
  assert.equal(isGooglePlacesPhotoURL(encodedPlacesMedia), true);
  assert.equal(persistableSourceImageURL(encodedPlacePhoto), null);
  assert.equal(persistableSourceImageURL(doubleEncodedPlacePhoto), null);
});

test("non-string source_image_url is invalid and stored as null", () => {
  assert.equal(persistableSourceImageURL(["https://example.com/own.jpg"]), null);
  assert.equal(persistableSourceImageURL({ url: ownImport }), null);
  assert.equal(persistableSourceImageURL(12), null);
  assert.equal(persistableSourceImageURL(true), null);
  assert.equal(persistableSourceImageURL(null), null);
  assert.equal(persistableSourceImageURL(undefined), undefined);
});

test("place/photo match is host- or resource-name scoped so marketplace photos survive", () => {
  assert.equal(isGooglePlacesPhotoURL(marketplacePhoto), false);
  assert.equal(isGooglePlacesPhotoURL(workplacePhoto), false);
  assert.equal(persistableSourceImageURL(marketplacePhoto), marketplacePhoto);
  assert.equal(persistableSourceImageURL(workplacePhoto), workplacePhoto);
  assert.equal(persistableSourceImageURL(googlePlacePhoto), null);
  assert.equal(persistableSourceImageURL(googlePlacesMedia), null);
  assert.equal(persistableSourceImageURL(googlePhotoReferencePath), null);
  assert.equal(
    persistableSourceImageURL("https://example.com/img.jpg?photo_reference=abc"),
    null,
  );
  assert.equal(persistableSourceImageURL(friendImport), friendImport);
});

test("googleusercontent lookalike hosts remain non-Google images", () => {
  for (const url of [
    "https://attackergoogleusercontent.com/p/photo.jpg?signature=a%2Fb",
    "https://googleusercontent.com.attacker.example/p/photo.jpg",
  ]) {
    assert.equal(isGooglePlacesPhotoURL(url), false);
    assert.equal(persistableSourceImageURL(url), url);
  }
});

const googleusercontentPlacesPaths = {
  "/places/": "https://lh3.googleusercontent.com/places/ANXAkqG-places-path",
  "/place-photos/": "https://lh3.googleusercontent.com/place-photos/AF1Qip-place-photos",
  "/p/": "https://lh3.googleusercontent.com/p/AF1Qip-generic",
  "/gps-cs-s/": "https://lh3.googleusercontent.com/gps-cs-s/photo-token",
  "/gps-proxy/": "https://lh5.googleusercontent.com/gps-proxy/proxy-token",
} as const;

const googleusercontentAvatarPaths = {
  "/a/": "https://lh3.googleusercontent.com/a/ACg8oc-avatar",
  "/a-/": "https://lh3.googleusercontent.com/a-/AOh14Gh-avatar",
} as const;

test("lh*.googleusercontent.com Places paths are Google photos; avatars are not", () => {
  for (const [label, url] of Object.entries(googleusercontentPlacesPaths)) {
    assert.equal(isGooglePlacesPhotoURL(url), true, `${label} must match`);
    assert.equal(persistableSourceImageURL(url), null, `${label} must persist as null`);
  }
  const encodedP = "https://lh3.googleusercontent.com/%70/AF1Qip-encoded";
  assert.equal(isGooglePlacesPhotoURL(encodedP), true);
  assert.equal(persistableSourceImageURL(encodedP), null);
  for (const [label, url] of Object.entries(googleusercontentAvatarPaths)) {
    assert.equal(isGooglePlacesPhotoURL(url), false, `${label} must stay`);
    assert.equal(persistableSourceImageURL(url), url, `${label} must persist`);
  }
});

test("PATCH ignores business_photo_urls, nulls Google source_image_url, keeps non-Google", () => {
  const googlePatch = sanitizePlaceWriteBody({
    note: "keep me",
    business_photo_urls: [googlePlacesMedia],
    source_image_url: googlePlacesMedia,
  });
  assert.equal("business_photo_urls" in googlePatch, false);
  assert.equal(googlePatch.source_image_url, null);
  assert.equal(googlePatch.note, "keep me");

  const ownPatch = sanitizePlaceWriteBody({
    business_photo_urls: [friendImport],
    source_image_url: friendImport,
  });
  assert.equal("business_photo_urls" in ownPatch, false);
  assert.equal(ownPatch.source_image_url, friendImport);
});

test("PATCH that only sends the retired photo column is a silent no-op", () => {
  assert.equal(
    placeWriteIsSilentPhotoNoop({ business_photo_urls: [googlePlacePhoto] }),
    true,
  );
  assert.equal(placeWriteIsSilentPhotoNoop({}), false);
  assert.equal(placeWriteIsSilentPhotoNoop({ name: "Harbor Oven" }), false);
  assert.equal(
    placeWriteIsSilentPhotoNoop({
      business_photo_urls: [googlePlacePhoto],
      source_image_url: googlePlacePhoto,
    }),
    false,
    "a Google source_image_url still writes null; that is not a no-op",
  );
});

const writeSites = [
  {
    name: "POST /places",
    persist(raw: Record<string, unknown>) {
      return persistColumns(
        sanitizePlacePostBody(raw, "owner-1"),
        [...placeFieldsFromServer(), "user_id"],
      );
    },
  },
  {
    name: "PATCH /places/:id",
    persist(raw: Record<string, unknown>) {
      return persistColumns(sanitizePlacePatchBody(raw).persist, placeFieldsFromServer());
    },
  },
  {
    name: "insertFinalPlaceForDecision",
    persist(raw: Record<string, unknown>) {
      return persistColumns(sanitizePlaceWorkflowBody(raw), placeFieldsFromServer());
    },
  },
] as const;

for (const site of writeSites) {
  test(`${site.name} rejects percent-encoded Google photo bypass`, () => {
    const stored = site.persist({
      ...identityFields,
      source_image_url: encodedPlacePhoto,
      business_photo_urls: [doubleEncodedPlacePhoto],
    });
    assert.equal(stored.source_image_url, null, `${site.name} must not store encoded place/%70hoto`);
    assert.equal("business_photo_urls" in stored, false);
    assert.equal(stored.name, identityFields.name);
    assert.equal(stored.google_place_id, identityFields.google_place_id);
  });

  test(`${site.name} rejects non-string source_image_url instead of passing it through`, () => {
    const stored = site.persist({
      ...identityFields,
      source_image_url: { nested: googlePlacePhoto },
    });
    assert.equal(stored.source_image_url, null, `${site.name} must store null for object source_image_url`);
    assert.equal(stored.latitude, identityFields.latitude);
  });

  test(`${site.name} keeps non-Google import images and marketplace/photo lookalikes`, () => {
    const stored = site.persist({
      ...identityFields,
      source_image_url: marketplacePhoto,
      business_photo_urls: [ownImport],
    });
    assert.equal(stored.source_image_url, marketplacePhoto);
    assert.equal("business_photo_urls" in stored, false);
  });

  for (const [label, url] of Object.entries(googleusercontentPlacesPaths)) {
    test(`${site.name} nulls googleusercontent Places path ${label}`, () => {
      const stored = site.persist({
        ...identityFields,
        source_image_url: url,
      });
      assert.equal(stored.source_image_url, null, `${site.name} ${label}`);
      assert.equal(stored.google_place_id, identityFields.google_place_id);
    });
  }

  for (const [label, url] of Object.entries(googleusercontentAvatarPaths)) {
    test(`${site.name} keeps googleusercontent avatar path ${label}`, () => {
      const stored = site.persist({
        ...identityFields,
        source_image_url: url,
      });
      assert.equal(stored.source_image_url, url, `${site.name} ${label}`);
    });
  }
}

test("PATCH handler treats retired-photo-only body as a silent no-op, not a cap update", () => {
  const photoOnly = sanitizePlacePatchBody({
    id: "place-1",
    user_id: "attacker",
    created_at: "2026-01-01T00:00:00.000Z",
    business_photo_urls: [googlePlacePhoto],
  });
  assert.equal(photoOnly.silentPhotoNoop, true);
  assert.deepEqual(photoOnly.persist, {});

  const encodedClear = sanitizePlacePatchBody({
    source_image_url: encodedPlacePhoto,
  });
  assert.equal(encodedClear.silentPhotoNoop, false);
  assert.equal(encodedClear.persist.source_image_url, null);
});

test("placeFields no longer writes business_photo_urls and every place write sanitizes", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const fieldsStart = server.indexOf("const placeFields = [");
  const fieldsEnd = server.indexOf("] as const;", fieldsStart);
  const placeFields = server.slice(fieldsStart, fieldsEnd);
  assert.match(placeFields, /"source_image_url"/);
  assert.doesNotMatch(placeFields, /business_photo_urls/);

  const handlePlaces = server.slice(
    server.indexOf("async function handlePlaces"),
    server.indexOf("function providerCoordinateFieldError"),
  );
  assert.match(handlePlaces, /sanitizePlacePostBody\(rawBody, userId\)/);
  assert.match(handlePlaces, /sanitizePlacePatchBody\(rawBody\)/);
  const noopStart = handlePlaces.indexOf("if (silentPhotoNoop)");
  assert.ok(noopStart >= 0, "photo-only PATCH is a silent 200");
  const noopBlock = handlePlaces.slice(
    noopStart,
    handlePlaces.indexOf('return sendJson(response, { error: "No writable fields" }', noopStart),
  );
  assert.match(
    noopBlock,
    /select \* from places where id = \$1 and user_id = \$2 limit 1/,
    "photo-only PATCH reads the current row instead of updateSavedPlaceWithinLimit",
  );
  assert.doesNotMatch(
    noopBlock,
    /updateSavedPlaceWithinLimit/,
    "silent photo no-op must not call the #293 cap update path",
  );
  assert.match(handlePlaces, /updateSavedPlaceWithinLimit\(pool, userId, placeId, update\)/);

  const workflowInsert = server.slice(
    server.indexOf("async function insertFinalPlaceForDecision"),
    server.indexOf("async function validateDecisionReferences"),
  );
  assert.match(workflowInsert, /sanitizePlaceWorkflowBody\(decision\.finalPlace\)/);
  assert.match(workflowInsert, /assertNewSavedPlaceAllowed/);
});
