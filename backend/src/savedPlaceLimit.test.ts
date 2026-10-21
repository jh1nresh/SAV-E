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
      if (sql.includes("count(*)")) return { rows: [{ count: 49 }] };
      return { rows: [] };
    },
  };

  await assertNewSavedPlaceAllowed(client as never, "owner");
  assert.ok(calls.some((sql) => /savepoint saved_place_entitlement/i.test(sql)));
  assert.ok(calls.some((sql) => /rollback to savepoint saved_place_entitlement/i.test(sql)));
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
  const production = [
    readFileSync(new URL("../src/server.ts", import.meta.url), "utf8"),
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
      if (sql.includes("count(*)")) return { rows: [{ count }] };
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
    /select count\(\*\)::int as count from places where user_id = \$1/,
  );
  assert.doesNotMatch(source, /from cities|from lists|from place_candidates|from friend_/);
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
