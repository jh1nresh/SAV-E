import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  isGooglePlacesPhotoURL,
  persistableSourceImageURL,
  placeWriteIsSilentPhotoNoop,
  sanitizePlaceWriteBody,
} from "./googlePlacesPhotoWrite.js";

const googlePlacePhoto =
  "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=legacy-ref";
const googlePlacesMedia =
  "https://places.googleapis.com/v1/places/ChIJ123/photos/ABC/media";
const googlePhotoReferencePath = "places/ChIJ123/photos/ABC";
const ownImport = "https://cdn.instagram.com/private-post.jpg";
const friendImport = "https://example.com/friend-share.jpg";

const identityFields = {
  name: "Harbor Oven",
  address: "Da'an, Taipei",
  latitude: 25.033,
  longitude: 121.565,
  google_place_id: "ChIJ-harbor-oven",
  status: "saved",
};

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

test("POST nulls Places media URLs, photo_reference query, and photo name paths", () => {
  assert.equal(persistableSourceImageURL(googlePlacesMedia), null);
  assert.equal(persistableSourceImageURL(googlePhotoReferencePath), null);
  assert.equal(
    persistableSourceImageURL("https://example.com/img.jpg?photo_reference=abc"),
    null,
  );
  assert.equal(persistableSourceImageURL(friendImport), friendImport);
  assert.equal(persistableSourceImageURL(null), null);
  assert.equal(persistableSourceImageURL(undefined), undefined);
  assert.equal(isGooglePlacesPhotoURL(ownImport), false);
  assert.equal(isGooglePlacesPhotoURL(googlePlacePhoto), true);
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
  assert.match(handlePlaces, /sanitizePlaceWriteBody\(withOwner\(rawBody, userId\)\)/);
  assert.match(handlePlaces, /const writable = writableFields\(rawBody/);
  assert.match(handlePlaces, /sanitizePlaceWriteBody\(writable\)/);
  const noopStart = handlePlaces.indexOf("if (placeWriteIsSilentPhotoNoop(writable))");
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
  assert.match(workflowInsert, /sanitizePlaceWriteBody\(decision\.finalPlace\)/);
  assert.match(workflowInsert, /assertNewSavedPlaceAllowed/);
});
