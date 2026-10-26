import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  clipListPlaceIdentities,
  isGooglePlaceId,
  promoteGooglePlaceId,
  clipListSaveResponse,
  clipOnePlaceQuotaDecision,
  FREE_LIST_SAVE_LIMIT,
  planClipListSave,
  uniqueClipListItems,
  clipListPlacesAreNearbyDuplicate,
  existingPlaceMatchingClipIdentity,
} from "./clipListSave.js";
import { SavedPlaceLimitError } from "./savedPlaceLimit.js";

const cafe = (id: string, name = "Onibus Coffee") => ({
  id,
  name,
  latitude: 35.644,
  longitude: 139.699,
});

test("SL1 dedupes the list first and keeps list order", () => {
  const plan = planClipListSave({
    items: [
      cafe("a"),
      { id: "a", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
      cafe("b", "Katsu Midori"),
      { name: "Onibus Coffee", latitude: 35.644, longitude: 139.699, provider_place_id: "a" },
    ],
    existingIdentities: [],
    savedPlaceCount: 0,
  });

  assert.deepEqual(plan.toInsert.map((item) => item.id), ["a", "b"]);
  assert.equal(plan.newlySaved, 2);
  assert.equal(plan.alreadySaved, 2);
  assert.equal(plan.overCap, 0);
});

test("google and provider place ids share one identity", () => {
  const existing = clipListPlaceIdentities({
    google_place_id: "ChIJ123",
    name: "Renamed Stamp",
    latitude: 35.0,
    longitude: 139.0,
  });
  const plan = planClipListSave({
    items: [{ provider_place_id: "ChIJ123", name: "Starbucks", latitude: 40.7, longitude: -74.0 }],
    existingIdentities: existing,
    savedPlaceCount: 1,
  });
  assert.equal(plan.alreadySaved, 1);
  assert.equal(plan.newlySaved, 0);
});

test("primary Google provider id is promoted to google_place_id", () => {
  const unique = uniqueClipListItems([
    { provider_place_id: "ChIJ123", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
  ]);
  assert.equal(unique[0]?.google_place_id, "ChIJ123");
  assert.equal(
    uniqueClipListItems([
      { provider_place_id: "EicABC", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
    ])[0]?.google_place_id,
    "EicABC",
  );
  assert.equal(
    uniqueClipListItems([
      { provider_place_id: "IhoXYZ", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
    ])[0]?.google_place_id,
    "IhoXYZ",
  );
  assert.equal(
    promoteGooglePlaceId({ provider_place_id: "id-a", name: "Onibus Coffee" }).google_place_id,
    undefined,
  );
  const plan = planClipListSave({
    items: [{ provider_place_id: "id-a", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 }],
    existingIdentities: [],
    savedPlaceCount: 0,
  });
  assert.equal(plan.toInsert[0]?.google_place_id, undefined);
});

test("explicit opaque Google provenance survives planning without a prefix allowlist", () => {
  const known = { ...cafe("source-id"), google_place_id: "opaque-google-venue" };
  assert.equal(promoteGooglePlaceId(known).google_place_id, "opaque-google-venue");
  const planned = uniqueClipListItems([cafe("first-id"), known]);
  assert.equal(planned.length, 1);
  assert.equal(planned[0]?.google_place_id, "opaque-google-venue");
  assert.equal(promoteGooglePlaceId({ google_place_id: "11111111-1111-4111-8111-111111111111" }).google_place_id, undefined);
});

test("merged Clip items keep a later GCJ-02 provider reference", () => {
  const unique = uniqueClipListItems([
    { id: "id-a", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
    {
      id: "amap-onibus",
      name: "Onibus Coffee",
      latitude: 35.644,
      longitude: 139.699,
      coordinate_system: "GCJ-02",
      location_provider: "amap",
      provider_map_url: "https://uri.amap.com/marker?position=139.699,35.644",
    },
  ]);
  assert.equal(unique.length, 1);
  assert.equal(unique[0]?.coordinate_system, "GCJ-02");
  assert.equal(unique[0]?.location_provider, "amap");
  assert.equal(unique[0]?.provider_map_url, "https://uri.amap.com/marker?position=139.699,35.644");
});

test("every merged extra identity is used for account dedupe", () => {
  const items = [
    { id: "id-a", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
    { id: "id-b", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
    { id: "ChIJ123", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
  ];
  const unique = uniqueClipListItems(items);
  assert.equal(unique.length, 1);
  assert.deepEqual(unique[0]?.extra_place_ids, ["id-b", "ChIJ123"]);
  assert.equal(unique[0]?.google_place_id, "ChIJ123");
  assert.equal(isGooglePlaceId("id-b"), false);
  assert.equal(isGooglePlaceId("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"), false);
  assert.equal(isGooglePlaceId("ChIJ123"), true);
  assert.equal(isGooglePlaceId("GhIJ456"), true);
  assert.equal(isGooglePlaceId("EicABC"), true);
  assert.equal(isGooglePlaceId("IhoXYZ"), true);
  assert.equal(isGooglePlaceId("eicabc"), true);
  assert.equal(isGooglePlaceId("ihoXYZ"), true);
  assert.equal(isGooglePlaceId("id-c"), false);
  const existing = {
    id: "owned",
    google_place_id: "ChIJ123",
    name: "Renamed Stamp",
    latitude: 1,
    longitude: 2,
  };
  const plan = planClipListSave({
    items,
    existingIdentities: clipListPlaceIdentities(existing),
    existingPlaces: [existing],
    savedPlaceCount: 1,
  });
  assert.deepEqual(plan.toInsert, []);
  assert.equal(plan.newlySaved, 0);
  assert.equal(plan.alreadySaved, 3);
});

test("SL1 merges every group a later item bridges", () => {
  const plan = planClipListSave({
    items: [
      { id: "id-a", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
      { id: "id-c", name: "Katsu Midori", latitude: 35.690, longitude: 139.700 },
      { id: "id-c", name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
    ],
    existingIdentities: [],
    savedPlaceCount: 0,
  });
  assert.equal(plan.toInsert.length, 1);
  assert.equal(plan.toInsert[0]?.id, "id-a");
  assert.equal(plan.toInsert[0]?.google_place_id, undefined);
  assert.deepEqual(plan.toInsert[0]?.extra_place_ids, ["id-c"]);
  assert.equal(plan.newlySaved, 1);
  assert.equal(plan.alreadySaved, 2);
});

test("SL1 records skipped identities so transitive duplicates collapse", () => {
  const plan = planClipListSave({
    items: [
      { name: "Onibus Coffee", latitude: 35.644, longitude: 139.699 },
      {
        name: "Onibus Coffee",
        latitude: 35.644,
        longitude: 139.699,
        provider_place_id: "shop-b",
      },
      { name: "Katsu Midori", latitude: 35.67, longitude: 139.77, provider_place_id: "shop-b" },
    ],
    existingIdentities: [],
    savedPlaceCount: 0,
  });
  assert.deepEqual(plan.toInsert.map((item) => item.name), ["Onibus Coffee"]);
  assert.equal(plan.alreadySaved, 2);
  assert.equal(plan.newlySaved, 1);
});

test("SL1 skips places already on the account", () => {
  const existing = new Set(clipListPlaceIdentities(cafe("a")));
  const plan = planClipListSave({
    items: [cafe("a"), cafe("b", "Katsu Midori")],
    existingIdentities: existing,
    savedPlaceCount: 10,
  });

  assert.deepEqual(plan.toInsert.map((item) => item.id), ["b"]);
  assert.equal(plan.alreadySaved, 1);
  assert.equal(plan.newlySaved, 1);
});

test("same-name venues within 120m are account duplicates", () => {
  const owned = cafe("owned");
  const drifted = {
    id: "sender-uuid",
    name: "Onibus Coffee",
    latitude: 35.6444,
    longitude: 139.699,
  };
  assert.equal(clipListPlacesAreNearbyDuplicate(owned, drifted), true);
  assert.equal(
    clipListPlacesAreNearbyDuplicate(owned, { ...drifted, latitude: 35.66 }),
    false,
  );
  assert.equal(uniqueClipListItems([owned, drifted]).length, 1);
  const plan = planClipListSave({
    items: [drifted],
    existingIdentities: clipListPlaceIdentities(owned),
    existingPlaces: [owned],
    savedPlaceCount: 12,
  });
  assert.equal(plan.newlySaved, 0);
  assert.equal(plan.alreadySaved, 1);
  assert.equal(plan.toInsert.length, 0);
});

test("SL2 fills remaining quota in list order and counts overflow", () => {
  const plan = planClipListSave({
    items: [
      cafe("1", "One"),
      cafe("2", "Two"),
      cafe("3", "Three"),
      cafe("4", "Four"),
    ],
    existingIdentities: [],
    savedPlaceCount: 48,
    limit: FREE_LIST_SAVE_LIMIT,
  });

  assert.deepEqual(plan.toInsert.map((item) => item.name), ["One", "Two"]);
  assert.equal(plan.newlySaved, 2);
  assert.equal(plan.overCap, 2);
  assert.equal(plan.remaining, 0);
});

test("one-place Clip save uses the same planner as a list", () => {
  const duplicate = planClipListSave({
    items: [cafe("a")],
    existingIdentities: clipListPlaceIdentities(cafe("a")),
    savedPlaceCount: 12,
  });
  assert.deepEqual(duplicate.toInsert, []);
  assert.equal(duplicate.newlySaved, 0);
  assert.equal(duplicate.alreadySaved, 1);
  assert.equal(duplicate.overCap, 0);

  const atCap = planClipListSave({
    items: [cafe("new", "Blue Bottle")],
    existingIdentities: [],
    savedPlaceCount: 50,
  });
  assert.deepEqual(atCap.toInsert, []);
  assert.equal(atCap.newlySaved, 0);
  assert.equal(atCap.alreadySaved, 0);
  assert.equal(atCap.overCap, 1);
  assert.equal(clipOnePlaceQuotaDecision(duplicate), "duplicate");
  assert.equal(clipOnePlaceQuotaDecision(atCap), "cap");
  assert.equal(
    clipOnePlaceQuotaDecision(planClipListSave({
      items: [cafe("new")],
      existingIdentities: [],
      savedPlaceCount: 12,
    })),
    "insert",
  );
  assert.deepEqual(new SavedPlaceLimitError().body, {
    error: "saved_place_limit",
    code: "over_free_limit",
    limit: 50,
  });
});

test("SL2 #293 section B: a full account saves none and reports remaining 0", () => {
  const plan = planClipListSave({
    items: [cafe("1", "One"), cafe("2", "Two")],
    existingIdentities: [],
    savedPlaceCount: 50,
  });

  assert.deepEqual(plan.toInsert, []);
  assert.equal(plan.newlySaved, 0);
  assert.equal(plan.overCap, 2);
  assert.equal(plan.remaining, 0);
});

test("SL3 response exposes the three real counts", () => {
  const owned = cafe("11111111-1111-1111-1111-111111111111");
  const plan = planClipListSave({
    items: [owned, cafe("new", "Blue Bottle"), cafe("overflow", "Tsukiji")],
    existingIdentities: clipListPlaceIdentities(owned),
    existingPlaces: [owned],
    savedPlaceCount: 49,
  });
  const body = clipListSaveResponse(plan);

  assert.equal(body.newly_saved, 1);
  assert.equal(body.already_saved, 1);
  assert.equal(body.over_cap, 1);
  assert.equal(body.remaining, 0);
  assert.equal(body.limit, 50);
  assert.deepEqual(body.saved, []);
  assert.equal(body.already[0]?.id, "11111111-1111-1111-1111-111111111111");
  assert.equal(body.already[0]?.name, "Onibus Coffee");

  const withRows = clipListSaveResponse(plan, [
    {
      id: "22222222-2222-2222-2222-222222222222",
      provider_place_id: "new",
      name: "Blue Bottle",
      latitude: 35.682,
      longitude: 139.798,
      category: "cafe",
    },
  ]);
  assert.equal(withRows.saved[0]?.id, "22222222-2222-2222-2222-222222222222");
  assert.equal(withRows.saved[0]?.provider_place_id, "new");
  assert.equal(withRows.newly_saved, 1);
});

test("zero-insert duplicates return canonical already rows", () => {
  const owned = cafe("11111111-1111-1111-1111-111111111111");
  const plan = planClipListSave({
    items: [owned, { ...owned, provider_place_id: "11111111-1111-1111-1111-111111111111" }],
    existingIdentities: clipListPlaceIdentities(owned),
    existingPlaces: [owned],
    savedPlaceCount: 12,
  });
  assert.equal(plan.newlySaved, 0);
  assert.equal(plan.alreadySaved, 2);
  assert.equal(plan.overCap, 0);
  const body = clipListSaveResponse(plan);
  assert.deepEqual(body.saved, []);
  assert.equal(body.already.length, 1);
  assert.equal(body.already[0]?.id, "11111111-1111-1111-1111-111111111111");
  assert.equal(body.already[0]?.name, "Onibus Coffee");
});

test("SL4 POST /places list writes are one transactional call", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const handler = server.slice(
    server.indexOf("async function handlePlaces"),
    server.indexOf("function providerCoordinateFieldError"),
  );

  assert.match(handler, /readJson\(request, clipListPlacesBodyMaxBytes\)/);
  assert.match(handler, /Array\.isArray\(rawBody\.places\)/);
  assert.match(
    handler,
    /if \(Array\.isArray\(rawBody\.places\)\) \{\s*return await saveClipListPlaces/,
    "one-place Clip saves in { places: [item] } must use the quota planner",
  );
  assert.match(handler, /planClipListSave/);
  const planner = readFileSync(new URL("../src/clipListSave.ts", import.meta.url), "utf8");
  assert.match(planner, /export function uniqueClipListItems/);
  assert.match(planner, /matched\.slice\(1\)/);
  assert.match(planner, /extra_place_ids/);
  assert.match(handler, /begin/);
  assert.match(handler, /commit/);
  assert.match(handler, /rollback/);
  assert.match(handler, /clipListSaveResponse\(plan, inserted\)/);
  assert.match(handler, /existingPlaces: existing\.rows/);
  assert.match(handler, /saveClipListPlaces/);
  assert.match(handler, /items\.length > listMaxItems/);
  assert.doesNotMatch(handler, /items\.length > 100/);
  assert.match(handler, /inserted\.push\(rows\[0\]\)/);
  assert.doesNotMatch(
    handler.slice(handler.indexOf("Array.isArray(rawBody.places)")),
    /for \(const .+ of rawBody\.places\)[\s\S]{0,80}await fetch/,
  );
});

test("HoP R2 A1: phone Clip import increments that account by one and does not copy to another Privy user", () => {
  const item = {
    id: "quarter-sheets-pizza-club",
    name: "Quarter Sheets Pizza Club",
    latitude: 34.0779,
    longitude: -118.2543,
    google_place_id: "ChIJClipPhoneHandoff",
  };
  const phone = planClipListSave({
    items: [item],
    existingIdentities: [],
    savedPlaceCount: 0,
  });
  assert.equal(phone.newlySaved, 1);
  assert.equal(phone.alreadySaved, 0);
  assert.equal(phone.toInsert.length, 1);
  assert.equal(
    clipListSaveResponse(phone, [{ ...item, id: "11111111-1111-1111-1111-111111111111" }]).newly_saved,
    1,
    "server count for the phone account goes +1",
  );

  const email = planClipListSave({
    items: [],
    existingIdentities: [],
    savedPlaceCount: 0,
  });
  assert.equal(email.newlySaved, 0, "a different Privy account does not inherit the phone import");
  assert.equal(clipListSaveResponse(email).newly_saved, 0);

  const phoneAgain = planClipListSave({
    items: [item],
    existingIdentities: clipListPlaceIdentities(item),
    savedPlaceCount: 1,
  });
  assert.equal(phoneAgain.newlySaved, 0);
  assert.equal(phoneAgain.alreadySaved, 1);

  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  assert.match(
    server,
    /from places where user_id = \$1/,
    "Clip/list inserts count only the signed-in Privy profile",
  );
  assert.doesNotMatch(
    server,
    /update places[\s\S]{0,80}set user_id/,
    "saves are not moved onto a different Privy account",
  );
});

test("H-3 same identity different row matches an existing place", () => {
  const owned = {
    id: "11111111-1111-4111-8111-111111111111",
    name: "Onibus Coffee",
    latitude: 35.644,
    longitude: 139.699,
    google_place_id: "ChIJSameIdentity",
  };
  const incomingDifferentRow = {
    id: "22222222-2222-4222-8222-222222222222",
    name: "Onibus Coffee",
    latitude: 35.6441,
    longitude: 139.6991,
    google_place_id: "ChIJSameIdentity",
  };
  const nearbyRename = {
    id: "33333333-3333-4333-8333-333333333333",
    name: "Onibus Coffee",
    latitude: 35.6442,
    longitude: 139.699,
  };
  const otherVenue = {
    id: "44444444-4444-4444-8444-444444444444",
    name: "Blue Bottle",
    latitude: 35.682,
    longitude: 139.798,
    google_place_id: "ChIJOtherVenue",
  };

  assert.equal(
    existingPlaceMatchingClipIdentity([owned], incomingDifferentRow)?.id,
    owned.id,
    "same Google id is one place even when the row id differs",
  );
  assert.equal(
    existingPlaceMatchingClipIdentity([owned], nearbyRename)?.id,
    owned.id,
    "same name within 120m is one place even when the row id differs",
  );
  assert.equal(
    existingPlaceMatchingClipIdentity([owned], otherVenue),
    undefined,
    "a different venue must still occupy a new slot",
  );
});

test("Pro or unknown-tier batches keep undefined unlimited snapshot and still dedupe", () => {
  const owned = Array.from({ length: 60 }, (_, i) => cafe(`owned-${i}`, `Owned ${i}`));
  const incoming = cafe("new", "New Place");
  const plan = planClipListSave({
    items: [owned[0], incoming, { ...incoming }],
    existingIdentities: owned.flatMap(clipListPlaceIdentities),
    existingPlaces: owned,
    savedPlaceCount: undefined,
  });
  assert.deepEqual(plan.toInsert.map((place) => place.id), ["new"]);
  assert.equal(plan.alreadySaved, 2);
  assert.equal(plan.overCap, 0);
  assert.equal(plan.limit, null);
  assert.equal(plan.remaining, null);
  const response = JSON.parse(JSON.stringify(clipListSaveResponse(plan, plan.toInsert)));
  assert.equal(response.newly_saved, 1);
  assert.equal(response.over_cap, 0);
  assert.equal(response.limit, null);
});

test("batch route forwards the entitlement snapshot without converting unlimited to a free count", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const handler = server.slice(server.indexOf("async function saveClipListPlaces"), server.indexOf("function providerCoordinateFieldError"));
  assert.match(handler, /savedPlaceCount: savedPlaceCountBefore,/);
  assert.doesNotMatch(handler, /savedPlaceCountBefore \?\? existing\.rows\.length/);
});
