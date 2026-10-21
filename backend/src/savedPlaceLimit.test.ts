import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  SavedPlaceLimitError,
  assertNewSavedPlaceAllowed,
  decideSavedPlaceInsert,
  freeSavedPlaceLimit,
} from "./savedPlaceLimit.js";

test("free tier allows the 50th place and parks the 51st", () => {
  assert.equal(freeSavedPlaceLimit, 50);
  assert.equal(decideSavedPlaceInsert({ tier: "free", savedPlaceCount: 49, isNewPlace: true }), "allowed");
  assert.equal(decideSavedPlaceInsert({ tier: "free", savedPlaceCount: 50, isNewPlace: true }), "over_free_limit");
  assert.equal(decideSavedPlaceInsert({ tier: "free", savedPlaceCount: 60, isNewPlace: true }), "over_free_limit");
});

test("dedup and Pro inserts stay allowed after the free count is full", () => {
  assert.equal(decideSavedPlaceInsert({ tier: "free", savedPlaceCount: 50, isNewPlace: false }), "allowed");
  assert.equal(decideSavedPlaceInsert({ tier: "pro", savedPlaceCount: 9_999, isNewPlace: true }), "allowed");
});

test("structured over-limit error is what the client parks on", () => {
  const error = new SavedPlaceLimitError();
  assert.equal(error.status, 403);
  assert.deepEqual(error.body, {
    error: "saved_place_limit",
    code: "over_free_limit",
    limit: 50,
  });
});

test("assertNewSavedPlaceAllowed counts after entitlement and rejects a free 51st", async () => {
  const calls: string[] = [];
  const client = {
    query: async (sql: string) => {
      calls.push(sql);
      if (sql.includes("subscription_entitlements")) return { rows: [] };
      if (sql.includes("count(*)")) return { rows: [{ count: 50 }] };
      return { rows: [] };
    },
  };

  await assert.rejects(
    () => assertNewSavedPlaceAllowed(client as never, "owner"),
    (error: unknown) => error instanceof SavedPlaceLimitError,
  );
  assert.ok(calls.some((sql) => sql.includes("subscription_entitlements")));
  assert.ok(calls.some((sql) => sql.includes("count(*)")));
});

test("assertNewSavedPlaceAllowed lets Pro create past 50", async () => {
  const client = {
    query: async (sql: string) => {
      if (sql.includes("subscription_entitlements")) {
        return { rows: [{ status: "active", expires_at: "2099-01-01T00:00:00Z" }] };
      }
      if (sql.includes("count(*)")) return { rows: [{ count: 50 }] };
      return { rows: [] };
    },
  };

  await assertNewSavedPlaceAllowed(client as never, "pro-owner");
});

test("place create and shared-post save enforce the cap after dedup", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const places = server.slice(
    server.indexOf("async function handlePlaces"),
    server.indexOf("function providerCoordinateFieldError"),
  );
  const posts = readFileSync(new URL("../src/sharedPosts.ts", import.meta.url), "utf8");
  const ratings = readFileSync(new URL("../src/friendRatings.ts", import.meta.url), "utf8");

  assert.match(places, /pg_advisory_xact_lock/);
  assert.match(places, /assertNewSavedPlaceAllowed/);
  assert.match(posts, /assertNewSavedPlaceAllowed/);
  assert.match(ratings, /assertNewSavedPlaceAllowed/);
  assert.match(server, /error instanceof SavedPlaceLimitError/);
  assert.match(server, /error\.body, error\.status/);
});
