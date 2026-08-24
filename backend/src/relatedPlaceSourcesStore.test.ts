import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { PgRelatedPlaceSourcesStore } from "./relatedPlaceSourcesStore.js";

test("the store reads only an owner-scoped place pack", async () => {
  const calls: Array<{ sql: string; values: readonly unknown[] }> = [];
  const store = new PgRelatedPlaceSourcesStore(async (sql, values) => {
    calls.push({ sql, values });
    return {
      rows: [{
        pack: { sources: [], coverage: [] },
        fetched_at: new Date("2026-08-23T12:00:00.000Z"),
        requested_platforms: ["instagram"],
        max_results_per_platform: 3,
        query_set: ["site:instagram.com venue"],
      }],
    };
  });

  const result = await store.load("place-id", "owner-id");

  assert.deepEqual(calls[0]?.values, ["place-id", "owner-id"]);
  assert.match(calls[0]?.sql ?? "", /where place_id = \$1 and user_id = \$2/);
  assert.equal(result?.fetchedAt, "2026-08-23T12:00:00.000Z");
  assert.deepEqual(result?.querySet, ["site:instagram.com venue"]);
});

test("the store upserts one current pack per place", async () => {
  const calls: Array<{ sql: string; values: readonly unknown[] }> = [];
  const store = new PgRelatedPlaceSourcesStore(async (sql, values) => {
    calls.push({ sql, values });
    return { rows: [] };
  });

  await store.save("place-id", "owner-id", {
    pack: { sources: [], coverage: [{ status: "partial" }] },
    fetchedAt: "2026-08-23T12:00:00.000Z",
    requestedPlatforms: ["instagram", "youtube"],
    maxResultsPerPlatform: 3,
    querySet: ["instagram query", "youtube query"],
  });

  assert.match(calls[0]?.sql ?? "", /on conflict \(place_id\) do update/);
  assert.deepEqual(calls[0]?.values.slice(0, 2), ["place-id", "owner-id"]);
  assert.deepEqual(calls[0]?.values.slice(4), [
    ["instagram", "youtube"],
    3,
    ["instagram query", "youtube query"],
  ]);
});

test("schema bounds storage to one owner-private pack per place", () => {
  const schema = readFileSync(new URL("../sql/schema.sql", import.meta.url), "utf8");
  const table = schema.slice(
    schema.indexOf("create table if not exists related_place_source_packs"),
    schema.indexOf("create table if not exists follows"),
  );

  assert.match(table, /place_id uuid primary key/);
  assert.match(table, /foreign key \(place_id, user_id\) references places\(id, user_id\) on delete cascade/);
  assert.match(table, /pack jsonb not null/);
  assert.match(table, /fetched_at timestamptz not null/);
  assert.match(table, /query_set text\[\] not null/);
  assert.match(table, /max_results_per_platform between 1 and 5/);
});
