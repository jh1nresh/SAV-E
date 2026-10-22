import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { prepareCandidate, reconcileSavedCandidates, reuseCapture } from "./memoryStorage.js";
import {
  SavedPlaceLimitError,
  assertNewSavedPlaceAllowed,
  updateSavedPlaceWithinLimit,
  deleteSavedPlaceGroup,
  deleteSavedPlace,
  savedPlaceDeleteScope,
  consolidatedSavedPlaceGroups,
  savedPlaceGrowthSnapshot,
  assertSavedPlaceGrowthAllowed,
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
  const workflowDecision = server.slice(server.indexOf("async function recordPlaceRecoveryDecision"), server.indexOf("async function insertFinalPlaceForDecision"));
  assert.match(workflowDecision, /pg_advisory_xact_lock/);
  assert.ok(workflowDecision.indexOf("pg_advisory_xact_lock") < workflowDecision.indexOf("lockedWorkflowRun"));
  assert.match(places, /updateSavedPlaceWithinLimit\(pool, userId, placeId, update\)/);
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

// Executes the production transaction helper with a transactional SQL boundary.
// The fake models committed vs tentative rows and owner locks; all venue
// identity/count decisions use the actual production implementation above.
class PlacePatchDatabase {
  rows: Record<string, unknown>[];
  calls: { sql: string; values: unknown[] }[] = [];
  commits = 0;
  rollbacks = 0;
  releases = 0;
  failUpdate = false;
  failDelete = false;
  onQuery?: (sql: string, values: unknown[], working: Record<string, unknown>[]) => { rows: Record<string, unknown>[] } | undefined;
  private tails = new Map<string, Promise<void>>();
  constructor(rows: SavedPlaceIdentity[], readonly tier: "free" | "pro" = "free") {
    this.rows = rows.map(row => ({ user_id: "owner", ...row }));
  }
  async connect() {
    let working: Record<string, unknown>[] | undefined;
    let unlock: (() => void) | undefined;
    const finish = () => { working = undefined; unlock?.(); unlock = undefined; };
    return {
      query: async (sql: string, values: unknown[] = []) => {
        this.calls.push({ sql, values });
        if (sql === "begin") return { rows: [] };
        if (sql.includes("pg_advisory_xact_lock")) {
          assert.equal(sql, "select pg_advisory_xact_lock(hashtextextended($1, 0))");
          const key = String(values[0]);
          const previous = this.tails.get(key);
          let release!: () => void;
          const next = new Promise<void>(resolve => { release = resolve; });
          this.tails.set(key, next);
          await previous;
          const previousUnlock = unlock;
          unlock = () => { release(); previousUnlock?.(); };
          working ??= this.rows.map(row => ({ ...row }));
          return { rows: [] };
        }
        if (sql === "commit") {
          assert.ok(working, "write must stay inside the owner-locked transaction");
          this.rows = working.map(row => ({ ...row }));
          this.commits += 1;
          finish();
          return { rows: [] };
        }
        if (sql === "rollback") { this.rollbacks += 1; finish(); return { rows: [] }; }
        assert.ok(working, `query outside the locked transaction: ${sql}`);
        if (/^(savepoint|release savepoint|rollback to savepoint)/.test(sql)) return { rows: [] };
        if (sql.includes("subscription_entitlements")) {
          return { rows: this.tier === "pro" ? [{ status: "active", expires_at: "2099-01-01" }] : [] };
        }
        if (sql.includes("from places where id") && sql.includes("for update")) {
          assert.deepEqual(values, [values[0], "owner"]);
          return { rows: working.filter(row => row.id === values[0] && row.user_id === values[1]).map(row => ({ ...row })) };
        }
        if (sql.trimStart().startsWith("select ") && sql.includes("from places where user_id")) {
          return { rows: working.filter(row => !row.fixtureTable && row.user_id === values[0]).map(row => ({ ...row })) };
        }
        if (sql.startsWith("update places set") && sql.includes(" returning *")) {
          if (this.failUpdate) throw new Error("fixture update failure");
          const row = working.find(row => row.id === values.at(-2) && row.user_id === values.at(-1));
          if (!row) return { rows: [] };
          const assignments = sql.slice("update places set".length, sql.indexOf(" where "));
          for (const match of assignments.matchAll(/(\w+) = \$(\d+)(?!:)/g)) {
            const value = values[Number(match[2]) - 1];
            row[match[1]] = ["latitude", "longitude"].includes(match[1]) && value != null ? Number(value) : value;
          }
          const earliest = assignments.match(/created_at = least\(created_at, \$(\d+)::timestamptz\)/);
          if (earliest) {
            const incoming = String(values[Number(earliest[1]) - 1]);
            if (Date.parse(incoming) < Date.parse(String(row.created_at))) row.created_at = incoming;
          }
          return { rows: [{ ...row }] };
        }
        if (sql === "insert into places (id, name, user_id) values ($1, $2, $3)") {
          working.push({ id: values[0], name: values[1], user_id: values[2], created_at: "2026-01-01" });
          return { rows: [] };
        }
        if (sql === "delete from places where user_id = $1 and id = any($2::uuid[])") {
          const ids = values[1] as string[];
          for (let index = working.length - 1; index >= 0; index--) {
            if (working[index].user_id === values[0] && ids.includes(String(working[index].id))) working.splice(index, 1);
          }
          if (this.failDelete) throw new Error("fixture delete failure after tentative removal");
          return { rows: [] };
        }
        const extra = this.onQuery?.(sql, values, working);
        if (extra) return extra;
        throw new Error(`Unexpected query: ${sql}`);
      },
      release: () => { assert.equal(unlock, undefined, "transaction must finish before release"); this.releases += 1; },
    };
  }
}

const renamePatch = { sql: "update places set name = $1", values: ["Unique replacement venue"] };
function duplicateCollection(count: number): SavedPlaceIdentity[] {
  const rows = venues(count);
  return [...rows, { ...rows[0], id: "duplicate-row" }];
}

test("PATCH duplicate-to-unique at50 rolls back every field without a durable51st", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(50));
  const before = structuredClone(db.rows);
  await assert.rejects(() => updateSavedPlaceWithinLimit(db as never, "owner", "duplicate-row", {
    sql: "update places set name = $1, note = $2", values: ["Unique replacement venue", "must roll back too"],
  }), SavedPlaceLimitError);
  assert.deepEqual(db.rows, before);
  assert.equal(db.commits, 0);
  assert.equal(db.rollbacks, 1);
  assert.equal(db.releases, 1);
});

test("PATCH49-to50 and Pro growth commit actual replacement rows", async () => {
  for (const [count, tier] of [[49, "free"], [50, "pro"]] as const) {
    const db = new PlacePatchDatabase(duplicateCollection(count), tier);
    const result = await updateSavedPlaceWithinLimit(db as never, "owner", "duplicate-row", renamePatch);
    assert.equal(result?.name, "Unique replacement venue");
    assert.equal(consolidatedSavedPlaces(db.rows).length, count + 1);
    assert.equal(db.commits, 1);
    assert.equal(db.rollbacks, 0);
    assert.equal(db.releases, 1);
  }
});

test("PATCH no-growth edits remain allowed for legacy over-limit accounts", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(60));
  await updateSavedPlaceWithinLimit(db as never, "owner", "duplicate-row", {
    sql: "update places set note = $1", values: ["Private update"],
  });
  await updateSavedPlaceWithinLimit(db as never, "owner", "place-10", renamePatch);
  assert.equal(consolidatedSavedPlaces(db.rows).length, 60);
  assert.equal(db.rows.find(row => row.id === "duplicate-row")?.note, "Private update");
  assert.equal(db.commits, 2);
});

test("PATCH foreign and missing rows return not-found before entitlement or write", async () => {
  for (const id of ["foreign", "missing"]) {
    const db = new PlacePatchDatabase([{ ...venues(1)[0], id: "foreign", user_id: "someone-else" } as SavedPlaceIdentity]);
    assert.equal(await updateSavedPlaceWithinLimit(db as never, "owner", id, renamePatch), undefined);
    assert.equal(db.calls.some(call => call.sql.includes("subscription_entitlements")), false);
    assert.equal(db.calls.some(call => call.sql.startsWith("update places")), false);
    assert.equal(db.rollbacks, 1);
    assert.equal(db.releases, 1);
  }
});

test("PATCH omitted identity preserves dedup but explicit null can split the venue", async () => {
  const rows = venues(50);
  rows[0].google_place_id = "shared-google";
  rows.push({ ...rows[0], id: "duplicate-row", name: "Different name held together by Google ID" });
  const db = new PlacePatchDatabase(rows);
  await updateSavedPlaceWithinLimit(db as never, "owner", "duplicate-row", { sql: "update places set note = $1", values: ["only note"] });
  assert.equal(db.rows.find(row => row.id === "duplicate-row")?.google_place_id, "shared-google");
  await assert.rejects(() => updateSavedPlaceWithinLimit(db as never, "owner", "duplicate-row", {
    sql: "update places set google_place_id = $1", values: [null],
  }), SavedPlaceLimitError);
  assert.equal(db.rows.find(row => row.id === "duplicate-row")?.google_place_id, "shared-google");
});

test("PATCH projection uses actual RETURNING fields and SQL earliest-date semantics", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(50));
  const update = {
    sql: "update places set note = $1, created_at = least(created_at, $2::timestamptz)",
    values: ["accepted note", "2099-01-01T00:00:00Z"],
    rawBody: { id: "other", user_id: "foreign", name: "rejected field", created_at: "1900-01-01" },
  };
  const result = await updateSavedPlaceWithinLimit(db as never, "owner", "duplicate-row", update);
  assert.equal(result?.id, "duplicate-row");
  assert.equal(result?.user_id, "owner");
  assert.equal(result?.name, "Venue 0");
  assert.equal(result?.note, "accepted note");
  assert.equal(result?.created_at, "2026-01-01T00:00:00Z");
  const earlier = await updateSavedPlaceWithinLimit(db as never, "owner", "duplicate-row", {
    sql: "update places set created_at = least(created_at, $1::timestamptz)", values: ["2025-01-01T00:00:00Z"],
  });
  assert.equal(earlier?.created_at, "2025-01-01T00:00:00Z");
});

test("PATCH backdating a representative is projected and rolled back if it splits canonical venues", async () => {
  const bridge: SavedPlaceIdentity[] = [
    { id: "middle", name: "Bridge Cafe", latitude: 25, longitude: 121, created_at: "2026-01-01" },
    { id: "north", name: "Bridge Cafe", latitude: 25.0009, longitude: 121, created_at: "2026-01-02" },
    { id: "south", name: "Bridge Cafe", latitude: 24.9991, longitude: 121, created_at: "2026-01-03" },
  ];
  const rows = [...venues(49), ...bridge];
  assert.equal(consolidatedSavedPlaces(rows).length, 50);
  assert.equal(consolidatedSavedPlaces(rows.map(row => row.id === "north" ? { ...row, created_at: "2025-01-01" } : row)).length, 51);
  const db = new PlacePatchDatabase(rows);
  await assert.rejects(() => updateSavedPlaceWithinLimit(db as never, "owner", "north", {
    sql: "update places set created_at = least(created_at, $1::timestamptz)", values: ["2025-01-01"],
  }), SavedPlaceLimitError);
  assert.equal(db.rows.find(row => row.id === "north")?.created_at, "2026-01-02");
});

test("PATCH and POST contend on the same owner lock and admit only one final slot", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(49));
  async function post() {
    const client = await db.connect();
    try {
      await client.query("begin");
      await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", ["owner"]);
      await assertNewSavedPlaceAllowed(client as never, "owner", { id: "post", name: "New POST venue" });
      await client.query("insert into places (id, name, user_id) values ($1, $2, $3)", ["post", "New POST venue", "owner"]);
      await client.query("commit");
    } catch (error) { await client.query("rollback"); throw error; }
    finally { client.release(); }
  }
  const results = await Promise.allSettled([
    updateSavedPlaceWithinLimit(db as never, "owner", "duplicate-row", renamePatch), post(),
  ]);
  assert.equal(results.filter(result => result.status === "fulfilled").length, 1);
  const rejected = results.find(result => result.status === "rejected");
  assert.ok(rejected?.status === "rejected" && rejected.reason instanceof SavedPlaceLimitError);
  assert.equal(consolidatedSavedPlaces(db.rows).length, 50);
  assert.equal(db.commits, 1);
  assert.equal(db.rollbacks, 1);
  assert.equal(db.releases, 2);
  assert.deepEqual(db.calls.filter(call => call.sql.includes("pg_advisory_xact_lock")).map(call => call.values), [["owner"], ["owner"]]);
});

test("PATCH update failures rollback and release rather than partially committing", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(49));
  const before = structuredClone(db.rows);
  db.failUpdate = true;
  await assert.rejects(() => updateSavedPlaceWithinLimit(db as never, "owner", "duplicate-row", renamePatch), /fixture update failure/);
  assert.deepEqual(db.rows, before);
  assert.equal(db.commits, 0);
  assert.equal(db.rollbacks, 1);
  assert.equal(db.releases, 1);
});

function chronologyFixture(canonicalCount: number): PlacePatchDatabase {
  const rows: Record<string, unknown>[] = [
    ...venues(canonicalCount - 1),
    { id: "middle", name: "Bridge Cafe", latitude: 25, longitude: 121, created_at: "2026-01-01" },
    { id: "north", name: "Bridge Cafe", latitude: 25.0009, longitude: 121, created_at: "2026-01-02" },
    { id: "south", name: "Bridge Cafe", latitude: 24.9991, longitude: 121, created_at: "2026-01-03" },
    { fixtureTable: "captures", id: "capture", source_url: "https://fixture.invalid/bridge", raw_text: "original evidence", created_at: "2025-01-01" },
    { fixtureTable: "place_candidates", id: "candidate", capture_id: "capture", place_id: "north", workflow_run_id: null,
      name: "Bridge Cafe", latitude: 25.0009, longitude: 121, address: "Bridge Road", status: "saved", evidence: [], created_at: "2026-01-02" },
  ];
  const db = new PlacePatchDatabase(rows);
  db.onQuery = (sql, values, working) => {
    const capture = working.find(row => row.fixtureTable === "captures")!;
    const candidate = working.find(row => row.fixtureTable === "place_candidates")!;
    const north = working.find(row => row.id === "north")!;
    if (sql.startsWith("select * from captures")) return { rows: capture.user_id === values[0] ? [{ ...capture }] : [] };
    if (sql.startsWith("update captures set raw_text")) {
      capture.raw_text = values[2]; capture.created_at = values[4] ?? capture.created_at;
      return { rows: [{ ...capture }] };
    }
    if (sql.startsWith("update captures set source_resolution")) {
      capture.source_resolution = JSON.parse(String(values[2])); return { rows: [{ ...capture }] };
    }
    if (sql.startsWith("select created_at from captures")) return { rows: [{ created_at: capture.created_at }] };
    if (sql.startsWith("select * from place_candidates")) return { rows: [{ ...candidate }] };
    if (sql.startsWith("select pc.*")) return { rows: [{ ...candidate, capture_created_at: capture.created_at }] };
    if (sql.startsWith("update place_candidates set created_at")) {
      if (Date.parse(String(candidate.created_at)) > Date.parse(String(values[1]))) candidate.created_at = values[1];
      return { rows: [] };
    }
    if (sql.startsWith("update place_candidates set evidence")) {
      candidate.evidence = JSON.parse(String(values[1])); candidate.created_at = values[2] ?? candidate.created_at;
      return { rows: [{ ...candidate }] };
    }
    if (sql.startsWith("update places")) {
      // All three production backdates carry the same requested earliest date
      // as parameter3; only the owned linked place is changed by these fixtures.
      assert.equal(values.length, 3);
      if (Date.parse(String(north.created_at)) > Date.parse(String(values[2]))) north.created_at = values[2];
      return { rows: [] };
    }
    return undefined;
  };
  return db;
}

for (const route of ["reuseCapture", "prepareCandidate", "reconcileSavedCandidates"] as const) {
  test(`${route} chronology uses the production guard: split at50 rolls back all provenance,49 preserves backdate`, async () => {
    for (const count of [49, 50]) {
      const db = chronologyFixture(count);
      const initial = structuredClone(db.rows);
      const client = await db.connect();
      const mutate = async () => {
        try {
          await client.query("begin");
          await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", ["owner"]);
          const before = await savedPlaceGrowthSnapshot(client as never, "owner");
          if (route === "reuseCapture") {
            await reuseCapture(client as never, "owner", { source_url: "https://fixture.invalid/bridge", raw_text: "new evidence", created_at: "2025-01-01" });
          } else if (route === "prepareCandidate") {
            await prepareCandidate(client as never, { capture_id: "capture", workflow_run_id: null, name: "Bridge Cafe", address: "Bridge Road",
              latitude: 25.0009, longitude: 121, status: "review", evidence: ["new source evidence"] });
          } else {
            await reconcileSavedCandidates(client as never, "owner", "candidate");
          }
          await assertSavedPlaceGrowthAllowed(client as never, "owner", before);
          await client.query("commit");
        } catch (error) { await client.query("rollback"); throw error; }
        finally { client.release(); }
      };
      if (count === 50) {
        await assert.rejects(mutate, SavedPlaceLimitError);
        assert.deepEqual(db.rows, initial, "source/candidate chronology and evidence must rollback with places");
        assert.equal(db.rollbacks, 1);
        assert.equal(db.commits, 0);
      } else {
        await mutate();
        assert.equal(db.rows.find(row => row.id === "north")?.created_at, "2025-01-01");
        assert.equal(consolidatedSavedPlaces(db.rows.filter(row => !row.fixtureTable)).length, 50);
        assert.equal(db.commits, 1);
      }
      assert.equal(db.releases, 1);
      const rawOwnerLock = db.calls.findIndex(call => call.sql.includes("pg_advisory_xact_lock") && call.values[0] === "owner");
      const firstRowLock = db.calls.findIndex(call => call.sql.includes("for update"));
      assert.ok(rawOwnerLock >= 0 && firstRowLock > rawOwnerLock);
    }
  });
}

test("every chronology caller guards the enclosing transaction with owner lock before row locks", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  for (const [start, end] of [
    ["async function handleCaptureSearchRecovery", "// The prior run is locked"],
    ["async function handleMemoryCaptures", "async function handleMemoryCandidates"],
    ["async function handleMemoryCandidates", "async function handleMemoryDecisions"],
    ["async function recordPlaceRecoveryDecision", "async function insertFinalPlaceForDecision"],
  ]) {
    const body = server.slice(server.indexOf(start), server.indexOf(end, server.indexOf(start)));
    assert.match(body, /pg_advisory_xact_lock\(hashtextextended\(\$1, 0\)\).*\[userId\]/);
    assert.match(body, /savedPlaceGrowthSnapshot/);
    assert.match(body, /assertSavedPlaceGrowthAllowed/);
    const firstMutation = Math.min(...["lockedWorkflowRun", "await reuseCapture", "await prepareCandidate", "candidate-decision:"].map(value => {
      const index = body.indexOf(value); return index < 0 ? Infinity : index;
    }));
    assert.ok(body.indexOf("savedPlaceGrowthSnapshot") < firstMutation);
  }
});

test("canonical groups retain ordered representatives, membership and inherited Google identity", () => {
  const first = { id: "a", name: "Cafe", address: "Road", created_at: "2026-01-01" };
  const alias = { ...first, id: "b", created_at: "2026-01-02", google_place_id: "g1" };
  const conflict = { ...alias, id: "c", created_at: "2026-01-03", google_place_id: "g2" };
  const input = [conflict, alias, first];
  const before = structuredClone(input);
  assert.deepEqual(consolidatedSavedPlaceGroups(input), [
    { representative: { ...first, google_place_id: "g1" }, memberIDs: ["a", "b"] },
    { representative: conflict, memberIDs: ["c"] },
  ]);
  assert.deepEqual(consolidatedSavedPlaces(input), [{ ...first, google_place_id: "g1" }, conflict]);
  assert.deepEqual(input, before);
  assert.equal(consolidatedSavedPlaces([{ ...first, google_place_id: "" }, alias])[0].google_place_id, "");
});

test("DELETE representative or alias removes the whole bridge venue at50 without resurfacing siblings", async () => {
  for (const target of ["middle", "north", "south"]) {
    const db = chronologyFixture(50);
    db.rows = db.rows.filter(row => !row.fixtureTable);
    assert.equal(consolidatedSavedPlaces(db.rows).length, 50);
    await deleteSavedPlaceGroup(db as never, "owner", target);
    assert.equal(consolidatedSavedPlaces(db.rows).length, 49);
    assert.equal(db.rows.some(row => ["middle", "north", "south"].includes(String(row.id))), false);
    assert.equal(db.rows.length, 49);
    assert.equal(db.commits, 1);
    assert.equal(db.rollbacks, 0);
    assert.equal(db.releases, 1);
  }
});

test("DELETE legacy sequential savedIDs and repeated requests are idempotent", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(1));
  for (const id of ["duplicate-row", "place-0", "duplicate-row"]) await deleteSavedPlaceGroup(db as never, "owner", id);
  assert.deepEqual(db.rows, []);
  assert.equal(db.calls.filter(call => call.sql.startsWith("delete from places")).length, 1);
  assert.equal(db.commits, 3);
  assert.equal(db.releases, 3);
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const route = server.slice(server.indexOf('if (request.method === "DELETE" && placeId)'), server.indexOf('return sendJson(response, { error: "Unsupported places route"'));
  assert.match(route, /await deleteSavedPlace\(pool, userId, placeId, scope\)/);
  assert.match(route, /return sendJson\(response, null, 204\)/);
  assert.doesNotMatch(route, /404/);
});

test("DELETE foreign or missing IDs succeeds identically without reading or deleting foreign groups", async () => {
  const foreign = { ...venues(1)[0], id: "foreign", user_id: "someone-else" };
  const db = new PlacePatchDatabase([...venues(1), foreign]);
  const before = structuredClone(db.rows);
  for (const id of ["foreign", "missing"]) assert.equal(await deleteSavedPlaceGroup(db as never, "owner", id), undefined);
  assert.deepEqual(db.rows, before);
  assert.equal(db.calls.some(call => call.sql.includes("from places where user_id")), false);
  assert.equal(db.calls.some(call => call.sql.startsWith("delete from places")), false);
  await deleteSavedPlaceGroup(db as never, "owner", "place-0");
  assert.deepEqual(db.rows, [foreign]);
});

test("DELETE does not transitively merge nearby groups or merge conflicting provider identities", async () => {
  const base = { name: "Cafe", longitude: 121 };
  const north = { ...base, id: "north", latitude: 25.0009, created_at: "2026-01-01" };
  const middle = { ...base, id: "middle", latitude: 25, created_at: "2026-01-02" };
  const south = { ...base, id: "south", latitude: 24.9991, created_at: "2026-01-03" };
  const otherProvider = { ...north, id: "provider", google_place_id: "other", created_at: "2026-01-04" };
  const db = new PlacePatchDatabase([{ ...north, google_place_id: "first" }, middle, south, otherProvider]);
  assert.deepEqual(consolidatedSavedPlaceGroups(db.rows).map(group => group.memberIDs), [["north", "middle"], ["south"], ["provider"]]);
  await deleteSavedPlaceGroup(db as never, "owner", "middle");
  assert.deepEqual(db.rows.map(row => row.id), ["south", "provider"]);
});

test("DELETE failure rolls back all tentative aliases and releases the connection", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(1));
  const before = structuredClone(db.rows);
  db.failDelete = true;
  await assert.rejects(() => deleteSavedPlaceGroup(db as never, "owner", "duplicate-row"), /fixture delete failure/);
  assert.deepEqual(db.rows, before);
  assert.equal(db.commits, 0);
  assert.equal(db.rollbacks, 1);
  assert.equal(db.releases, 1);
});

test("DELETE serializes with POST and PATCH using the same owner lock and exposes the freed slot", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(50));
  const post = async () => {
    const client = await db.connect();
    try {
      await client.query("begin");
      await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", ["owner"]);
      await assertNewSavedPlaceAllowed(client as never, "owner", { id: "new", name: "New venue" });
      await client.query("insert into places (id, name, user_id) values ($1, $2, $3)", ["new", "New venue", "owner"]);
      await client.query("commit");
    } catch (error) { await client.query("rollback"); throw error; }
    finally { client.release(); }
  };
  await Promise.all([
    deleteSavedPlaceGroup(db as never, "owner", "duplicate-row"),
    post(),
    updateSavedPlaceWithinLimit(db as never, "owner", "place-1", { sql: "update places set note = $1", values: ["Preserved edit"] }),
  ]);
  assert.equal(consolidatedSavedPlaces(db.rows).length, 50);
  assert.equal(db.rows.some(row => row.id === "place-0" || row.id === "duplicate-row"), false);
  assert.equal(db.rows.find(row => row.id === "place-1")?.note, "Preserved edit");
  assert.deepEqual(db.calls.filter(call => call.sql.includes("pg_advisory_xact_lock")).map(call => call.values), [["owner"], ["owner"], ["owner"]]);
  assert.equal(db.commits, 3);
  assert.equal(db.rollbacks, 0);
  assert.equal(db.releases, 3);
});

test("legacy default row DELETE compensates a committed duplicate POST without deleting existing aliases", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(50));
  const original = structuredClone(db.rows);
  const incoming = { ...db.rows[0], id: "new-review-alias" };
  db.onQuery = (sql, values, working) => {
    if (sql !== "insert fixture saved place") return undefined;
    assert.deepEqual(values, [incoming]);
    working.push({ ...incoming });
    return { rows: [incoming] };
  };
  const client = await db.connect();
  await client.query("begin");
  await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", ["owner"]);
  await assertNewSavedPlaceAllowed(client as never, "owner", incoming);
  await client.query("insert fixture saved place", [incoming]);
  await client.query("commit");
  client.release();
  assert.equal(db.rows.length, original.length + 1);
  // The separate correction request fails after POST committed. The old client
  // sends an unqualified DELETE for only the row created by that POST.
  await deleteSavedPlace(db as never, "owner", "new-review-alias");
  assert.deepEqual(db.rows, original);
  assert.equal(consolidatedSavedPlaces(db.rows).length, 50);
  assert.deepEqual(db.calls.find(call => call.sql.startsWith("delete from places"))?.values, ["owner", ["new-review-alias"]]);
});

test("exact-row bridge deletion preserves Free cap without widening the requested deletion", async () => {
  for (const count of [49, 50]) {
    const db = chronologyFixture(count);
    db.rows = db.rows.filter(row => !row.fixtureTable);
    const before = structuredClone(db.rows);
    if (count === 50) {
      await assert.rejects(() => deleteSavedPlace(db as never, "owner", "middle"), SavedPlaceLimitError);
      assert.deepEqual(db.rows, before);
      assert.equal(db.rollbacks, 1);
    } else {
      await deleteSavedPlace(db as never, "owner", "middle");
      assert.equal(consolidatedSavedPlaces(db.rows).length, 50);
      assert.equal(db.rows.some(row => row.id === "middle"), false);
      assert.ok(db.rows.some(row => row.id === "north") && db.rows.some(row => row.id === "south"));
    }
  }
});

test("exact-row deletion permits Pro regrouping and no-growth legacy over-limit compensation", async () => {
  const bridge = chronologyFixture(50).rows.filter(row => !row.fixtureTable);
  const pro = new PlacePatchDatabase(bridge, "pro");
  await deleteSavedPlace(pro as never, "owner", "middle");
  assert.equal(consolidatedSavedPlaces(pro.rows).length, 51);
  const legacy = new PlacePatchDatabase(duplicateCollection(60));
  await deleteSavedPlace(legacy as never, "owner", "duplicate-row");
  assert.equal(legacy.rows.length, 60);
  assert.equal(consolidatedSavedPlaces(legacy.rows).length, 60);
});

test("exact-row missing and foreign deletion is idempotent with no entitlement check or mutation", async () => {
  const db = new PlacePatchDatabase([{ ...venues(1)[0], user_id: "foreign-owner" } as SavedPlaceIdentity]);
  const before = structuredClone(db.rows);
  for (const id of ["place-0", "missing"]) await deleteSavedPlace(db as never, "owner", id);
  assert.deepEqual(db.rows, before);
  assert.equal(db.calls.some(call => call.sql.includes("subscription_entitlements") || call.sql.startsWith("delete from")), false);
});

test("delete scope defaults to legacy row, accepts explicit group and rejects unknown or repeated scopes", async () => {
  assert.equal(savedPlaceDeleteScope([]), "row");
  assert.equal(savedPlaceDeleteScope(["row"]), "row");
  assert.equal(savedPlaceDeleteScope(["group"]), "group");
  for (const values of [[""], ["all"], ["GROUP"], ["row", "group"], ["group", "group"]]) assert.equal(savedPlaceDeleteScope(values), undefined);
  const db = new PlacePatchDatabase(duplicateCollection(1));
  await assert.rejects(() => deleteSavedPlace(db as never, "owner", "place-0", "all" as never), /Invalid saved place delete scope/);
  assert.deepEqual(db.calls, [], "invalid scope must fail before connection or mutation");
});

test("legacy exact-row rollback serializes with POST and PATCH without freeing a canonical slot", async () => {
  const db = new PlacePatchDatabase(duplicateCollection(50));
  const post = async () => {
    const client = await db.connect();
    try {
      await client.query("begin");
      await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", ["owner"]);
      await assertNewSavedPlaceAllowed(client as never, "owner", { id: "new", name: "New venue" });
      await client.query("insert into places (id, name, user_id) values ($1, $2, $3)", ["new", "New venue", "owner"]);
      await client.query("commit");
    } catch (error) { await client.query("rollback"); throw error; }
    finally { client.release(); }
  };
  const results = await Promise.allSettled([
    deleteSavedPlace(db as never, "owner", "duplicate-row"), post(),
    updateSavedPlaceWithinLimit(db as never, "owner", "place-0", { sql: "update places set note = $1", values: ["Still saved"] }),
  ]);
  assert.equal(results[0].status, "fulfilled");
  assert.ok(results[1].status === "rejected" && results[1].reason instanceof SavedPlaceLimitError);
  assert.equal(results[2].status, "fulfilled");
  assert.equal(db.rows.find(row => row.id === "place-0")?.note, "Still saved");
  assert.equal(consolidatedSavedPlaces(db.rows).length, 50);
  assert.equal(db.releases, 3);
});
