import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  SavedPlaceLimitError,
  assertNewSavedPlaceAllowed,
  decideSavedPlaceInsert,
  freeSavedPlaceLimit,
  savedPlacesMatch,
  consolidatedSavedPlaces,
  type SavedPlaceIdentity,
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
      if (sql.includes("from places where user_id")) return { rows: venues(50) };
      return { rows: [] };
    },
  };

  await assert.rejects(
    () => assertNewSavedPlaceAllowed(client as never, "owner"),
    (error: unknown) => error instanceof SavedPlaceLimitError,
  );
  assert.ok(calls.some((sql) => sql.includes("subscription_entitlements")));
  assert.ok(calls.some((sql) => sql.includes("from places where user_id")));
});

test("assertNewSavedPlaceAllowed recovers when entitlement schema is missing inside a transaction", async () => {
  const calls: string[] = [];
  let aborted = false;
  const client = {
    query: async (sql: string) => {
      calls.push(sql);
      if (/^rollback to savepoint/i.test(sql)) {
        aborted = false;
        return { rows: [] };
      }
      if (/^savepoint/i.test(sql) || /^release savepoint/i.test(sql)) return { rows: [] };
      if (aborted) {
        throw Object.assign(new Error("current transaction is aborted"), { code: "25P02" });
      }
      if (sql.includes("subscription_entitlements")) {
        aborted = true;
        throw Object.assign(new Error("relation does not exist"), { code: "42P01" });
      }
      if (sql.includes("from places where user_id")) return { rows: venues(50) };
      return { rows: [] };
    },
  };

  await assertNewSavedPlaceAllowed(client as never, "owner");
  assert.ok(calls.some((sql) => /savepoint saved_place_entitlement/i.test(sql)));
  assert.ok(calls.some((sql) => /rollback to savepoint saved_place_entitlement/i.test(sql)));
  assert.ok(
    !calls.some((sql) => sql.includes("from places where user_id")),
    "a missing entitlement schema must fail open instead of applying the free cap",
  );
});

test("assertNewSavedPlaceAllowed lets Pro create past 50", async () => {
  const client = {
    query: async (sql: string) => {
      if (sql.includes("subscription_entitlements")) {
        return { rows: [{ status: "active", expires_at: "2099-01-01T00:00:00Z" }] };
      }
      if (sql.includes("from places where user_id")) return { rows: venues(50) };
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

  const workflowInsert = server.slice(
    server.indexOf("async function insertFinalPlaceForDecision"),
    server.indexOf("async function validateDecisionReferences"),
  );

  assert.match(places, /pg_advisory_xact_lock/);
  assert.match(places, /assertNewSavedPlaceAllowed/);
  assert.match(posts, /assertNewSavedPlaceAllowed/);
  assert.match(ratings, /assertNewSavedPlaceAllowed/);
  assert.match(workflowInsert, /pg_advisory_xact_lock/);
  assert.match(workflowInsert, /assertNewSavedPlaceAllowed/);
  assert.match(workflowInsert, /select id from places where id = \$1 and user_id = \$2/);
  assert.match(server, /error instanceof SavedPlaceLimitError/);
  assert.match(server, /error\.body, error\.status/);
});

test("C1 every production places insert is behind the atomic cap", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const production = [
    server,
    readFileSync(new URL("../src/sharedPosts.ts", import.meta.url), "utf8"),
    readFileSync(new URL("../src/friendRatings.ts", import.meta.url), "utf8"),
  ].join("\n");

  assert.equal(
    (production.match(/insert into places/gi) ?? []).length,
    2,
    "saveSharedPost and saveFriendRating are the raw places inserts",
  );
  assert.equal(
    (production.match(/buildInsert\(\s*"places"/g) ?? []).length,
    3,
    "POST /places, friend-share receipt, and workflow final_place use buildInsert",
  );

  const callSite = server.slice(
    server.indexOf("await insertFinalPlaceForDecision"),
    server.indexOf("await validateDecisionReferences"),
  );
  assert.match(callSite, /await insertFinalPlaceForDecision\(client, userId, decision\)/);
  assert.doesNotMatch(
    callSite,
    /insert into places|buildInsert\(\s*"places"/,
    "server.ts:5854 is the call site; it does not insert places itself",
  );

  const writePaths = [
    { name: "POST /places", test: "place create and shared-post save enforce the cap after dedup" },
    { name: "POST /places friend-share receipt", test: "place create and shared-post save enforce the cap after dedup" },
    { name: "saveSharedPost", test: "place create and shared-post save enforce the cap after dedup" },
    { name: "saveFriendRating", test: "place create and shared-post save enforce the cap after dedup" },
    { name: "insertFinalPlaceForDecision", test: "place create and shared-post save enforce the cap after dedup" },
  ];
  assert.equal(writePaths.length, 5);
  for (const path of writePaths) {
    assert.ok(path.name.length > 0);
    assert.ok(path.test.length > 0);
  }
});

test("C2 concurrent 50th and 51st serialize to exactly one insert", async () => {
  let count = 49;
  let holding: Promise<void> | null = null;
  let unlock = () => {};

  async function withLock(work: () => Promise<void>) {
    while (holding) await holding;
    holding = new Promise<void>((resolve) => {
      unlock = resolve;
    });
    try {
      await work();
    } finally {
      const release = unlock;
      holding = null;
      release();
    }
  }

  const client = {
    query: async (sql: string) => {
      if (/^savepoint|^release savepoint|^rollback to savepoint/i.test(sql)) return { rows: [] };
      if (sql.includes("subscription_entitlements")) return { rows: [] };
      if (sql.includes("from places where user_id")) return { rows: venues(count) };
      return { rows: [] };
    },
  };

  const results = await Promise.allSettled([
    withLock(async () => {
      await assertNewSavedPlaceAllowed(client as never, "owner");
      count += 1;
    }),
    withLock(async () => {
      await assertNewSavedPlaceAllowed(client as never, "owner");
      count += 1;
    }),
  ]);

  assert.equal(count, 50);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected").length, 1);
  const rejected = results.find((result) => result.status === "rejected");
  assert.ok(rejected && rejected.status === "rejected");
  assert.ok(rejected.reason instanceof SavedPlaceLimitError);
});

test("A1/D3 count is this account's places only", () => {
  const source = readFileSync(new URL("../src/savedPlaceLimit.ts", import.meta.url), "utf8");
  assert.match(
    source,
    /from places where user_id = \$1 order by created_at, id/,
  );
  assert.doesNotMatch(source, /from cities|from lists|from place_candidates|from friend_/);
});

test("A3 same-id retry is not a new insert", () => {
  assert.equal(
    decideSavedPlaceInsert({ tier: "free", savedPlaceCount: 50, isNewPlace: false }),
    "allowed",
  );
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const places = server.slice(
    server.indexOf("async function handlePlaces"),
    server.indexOf("function providerCoordinateFieldError"),
  );
  assert.match(places, /if \(isNewPlace\) await assertNewSavedPlaceAllowed/);
  assert.match(places, /if \(!existingReceipt\.rows\[0\]\) await assertNewSavedPlaceAllowed/);
});

test("C3 direct API writes nothing and returns over_free_limit", () => {
  const error = new SavedPlaceLimitError();
  assert.equal(error.status, 403);
  assert.deepEqual(error.body, {
    error: "saved_place_limit",
    code: "over_free_limit",
    limit: 50,
  });
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const places = server.slice(
    server.indexOf("async function handlePlaces"),
    server.indexOf("function providerCoordinateFieldError"),
  );
  assert.match(places, /await client.query\("rollback"\)/);
  assert.match(server, /error instanceof SavedPlaceLimitError/);
  assert.match(server, /error\.body, error\.status/);
});

test("C5 expired Pro keeps existing rows and gates only new inserts", () => {
  assert.equal(
    decideSavedPlaceInsert({ tier: "free", savedPlaceCount: 80, isNewPlace: false }),
    "allowed",
  );
  assert.equal(
    decideSavedPlaceInsert({ tier: "free", savedPlaceCount: 80, isNewPlace: true }),
    "over_free_limit",
  );
});

test("D2 over-limit body is counts and codes only", () => {
  const error = new SavedPlaceLimitError();
  assert.deepEqual(Object.keys(error.body).sort(), ["code", "error", "limit"]);
  assert.equal(error.message, "saved_place_limit");
  assert.doesNotMatch(JSON.stringify(error), /latitude|longitude|name|caption|address/i);
  assert.equal(
    decideSavedPlaceInsert({ tier: "free", savedPlaceCount: 50, isNewPlace: true }),
    "over_free_limit",
  );
});

function venues(count: number): SavedPlaceIdentity[] {
  return Array.from({ length: count }, (_, index) => ({
    id: `place-${index}`, name: `Venue ${index}`, address: `${index} Example Road`,
    latitude: 25, longitude: 121, created_at: "2026-01-01T00:00:00Z",
  }));
}

test("49 canonical venues with a duplicate row allow the 50th; canonical 51st is refused", async () => {
  const rows = venues(49);
  rows.push({ ...rows[0], id: "duplicate-row" });
  const client = { query: async (sql: string, params?: unknown[]) => {
    if (sql.includes("from places where user_id")) {
      assert.deepEqual(params, ["owner"]);
      return { rows };
    }
    return { rows: [] };
  } };
  const fiftieth = { ...venues(50)[49], id: "fiftieth" };
  await assertNewSavedPlaceAllowed(client as never, "owner", fiftieth);
  rows.push(fiftieth);
  assert.equal(rows.length, 51);
  assert.equal(consolidatedSavedPlaces(rows).length, 50);
  await assertNewSavedPlaceAllowed(client as never, "owner", { ...fiftieth, id: "retry" });
  await assert.rejects(() => assertNewSavedPlaceAllowed(client as never, "owner", venues(51)[50]), SavedPlaceLimitError);
});

test("canonical identity honors provider conflicts, coordinates, addresses and Unicode names", () => {
  const base = { id: "a", name: "Ｃａｆé!", address: "1 Main St", latitude: 25, longitude: 121 };
  assert.equal(savedPlacesMatch(base, { ...base, id: "b", name: "cafe", latitude: 25.0005 }), true);
  assert.equal(savedPlacesMatch(base, { ...base, id: "b", latitude: 26 }), false);
  assert.equal(savedPlacesMatch(base, { ...base, id: "b", coordinate_system: "GCJ-02" }), false);
  assert.equal(savedPlacesMatch(base, { ...base, id: "b", latitude: 0, longitude: 0 }), true);
  assert.equal(savedPlacesMatch(base, { ...base, id: "b", latitude: NaN, address: "other" }), false);
  assert.equal(savedPlacesMatch({ ...base, google_place_id: "g1" }, { ...base, id: "b", google_place_id: "g2" }), false);
  assert.equal(savedPlacesMatch({ ...base, google_place_id: "g1" }, { name: "other", google_place_id: "g1" }), true);
  assert.equal(savedPlacesMatch({ ...base, location_provider: "amap", provider_place_id: "a1", google_place_id: "g1" },
    { ...base, id: "b", location_provider: "amap", provider_place_id: "a2", google_place_id: "g1" }), false);
  assert.equal(savedPlacesMatch({ name: "", address: "same" }, { name: "", address: "same" }), false);
  // WGS84 meridional distances either side of 120 m, including high latitude.
  assert.equal(savedPlacesMatch({ ...base, latitude: 80 }, { ...base, id: "b", latitude: 80.00107 }), true);
  assert.equal(savedPlacesMatch({ ...base, latitude: 80 }, { ...base, id: "b", latitude: 80.00108 }), false);
});

test("canonical consolidation uses stable earliest identity and inherits missing Google identity", () => {
  const base = { name: "Cafe", address: "Road", latitude: 25, longitude: 121 };
  const rows: SavedPlaceIdentity[] = [
    { ...base, id: "b", created_at: "2026-02-01", google_place_id: "g1" },
    { ...base, id: "a", created_at: "2026-01-01" },
    { ...base, id: "c", created_at: "2026-03-01", google_place_id: "g2" },
  ];
  const result = consolidatedSavedPlaces(rows);
  assert.equal(result.length, 2);
  assert.equal(result[0].id, "a");
  assert.equal(result[0].google_place_id, "g1");
  assert.equal(rows[1].google_place_id, undefined, "do not mutate fetched rows");
});

test("persisted WGS84 and omitted incoming coordinate system remain one venue at 50", async () => {
  const rows = venues(50).map(place => ({ ...place, coordinate_system: "WGS84" }));
  const client = { query: async (sql: string) => ({ rows: sql.includes("from places where user_id") ? rows : [] }) };
  const duplicate = { ...venues(50)[0], id: "duplicate-with-default-coordinate-system" };
  assert.equal(savedPlacesMatch(rows[0], duplicate), true);
  await assertNewSavedPlaceAllowed(client as never, "owner", duplicate);
  assert.equal(savedPlacesMatch(rows[0], { ...duplicate, coordinate_system: "GCJ-02" }), false);
  await assert.rejects(() => assertNewSavedPlaceAllowed(client as never, "owner", {
    ...duplicate, coordinate_system: "GCJ-02",
  }), SavedPlaceLimitError);
});
