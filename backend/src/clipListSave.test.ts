import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  clipListPlaceIdentities,
  clipListSaveResponse,
  FREE_LIST_SAVE_LIMIT,
  planClipListSave,
} from "./clipListSave.js";

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
  const plan = planClipListSave({
    items: [cafe("owned"), cafe("new", "Blue Bottle"), cafe("overflow", "Tsukiji")],
    existingIdentities: clipListPlaceIdentities(cafe("owned")),
    savedPlaceCount: 49,
  });
  const body = clipListSaveResponse(plan);

  assert.equal(body.newly_saved, 1);
  assert.equal(body.already_saved, 1);
  assert.equal(body.over_cap, 1);
  assert.equal(body.remaining, 0);
  assert.equal(body.limit, 50);
});

test("SL4 POST /places list writes are one transactional call", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const handler = server.slice(
    server.indexOf("async function handlePlaces"),
    server.indexOf("function providerCoordinateFieldError"),
  );

  assert.match(handler, /Array\.isArray\(rawBody\.places\)/);
  assert.match(handler, /planClipListSave/);
  assert.match(handler, /begin/);
  assert.match(handler, /commit/);
  assert.match(handler, /rollback/);
  assert.match(handler, /clipListSaveResponse/);
  assert.match(handler, /saveClipListPlaces/);
  assert.doesNotMatch(
    handler.slice(handler.indexOf("Array.isArray(rawBody.places)")),
    /for \(const .+ of rawBody\.places\)[\s\S]{0,80}await fetch/,
  );
});
