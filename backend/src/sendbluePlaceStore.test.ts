import assert from "node:assert/strict";
import test from "node:test";
import { PgSendbluePlaceStore, type Queryable } from "./sendbluePlaceStore.js";

// Records every SQL statement and lets each test script the rows returned.
class FakeQuery implements Queryable {
  public statements: { sql: string; values?: unknown[] }[] = [];
  constructor(private readonly responder: (sql: string, values?: unknown[]) => Record<string, unknown>[]) {}
  async query(sql: string, values?: unknown[]): Promise<{ rows: Record<string, unknown>[] }> {
    this.statements.push({ sql, values });
    return { rows: this.responder(sql, values) };
  }
}

test("save de-dups: existing name → UPDATE refreshes created_at, no INSERT", async () => {
  const db = new FakeQuery((sql) => {
    if (sql.includes("update sendblue_saved_places")) return [{ id: 7 }]; // row exists
    if (sql.includes("count(distinct")) return [{ count: 3 }];
    return [];
  });
  const store = new PgSendbluePlaceStore(db);

  const count = await store.save("+15551234567", { name: "Aquarela", area: "Cabo" }, "https://ig/x");

  assert.equal(count, 3);
  const inserts = db.statements.filter((s) => s.sql.includes("insert into sendblue_saved_places"));
  const updates = db.statements.filter((s) => s.sql.includes("update sendblue_saved_places"));
  assert.equal(inserts.length, 0, "must not insert a duplicate when the name already exists");
  assert.equal(updates.length, 1, "must update the existing row instead");
});

test("save inserts when the name is new", async () => {
  const db = new FakeQuery((sql) => {
    if (sql.includes("update sendblue_saved_places")) return []; // no existing row
    if (sql.includes("count(distinct")) return [{ count: 1 }];
    return [];
  });
  const store = new PgSendbluePlaceStore(db);

  const count = await store.save("+15551234567", { name: "Aquarela" });

  assert.equal(count, 1);
  const inserts = db.statements.filter((s) => s.sql.includes("insert into sendblue_saved_places"));
  assert.equal(inserts.length, 1);
});

test("list maps rows to SavedPlace and passes the limit", async () => {
  const created = new Date("2026-01-02T03:04:05Z");
  const db = new FakeQuery(() => [
    { name: "Aquarela", area: "Cabo", category: "restaurant", source_url: "https://ig/x", created_at: created },
    { name: "Cafe", area: null, category: null, source_url: null, created_at: created },
  ]);
  const store = new PgSendbluePlaceStore(db);

  const places = await store.list("+15551234567", 5);

  assert.equal(places.length, 2);
  assert.deepEqual(places[0], {
    name: "Aquarela",
    area: "Cabo",
    category: "restaurant",
    sourceUrl: "https://ig/x",
    createdAt: created,
  });
  assert.equal(places[1]?.area, undefined);
  assert.deepEqual(db.statements[0]?.values, ["+15551234567", 5]);
});

test("list with an area filter uses ILIKE and passes the area param", async () => {
  const db = new FakeQuery(() => [
    { name: "Cafe Leon Dore", area: "Los Angeles", category: "cafe", source_url: null, created_at: null },
  ]);
  const store = new PgSendbluePlaceStore(db);

  const places = await store.list("+15551234567", { area: "LA", limit: 10 });

  assert.equal(places.length, 1);
  assert.equal(places[0]?.name, "Cafe Leon Dore");
  // Area-filtered query must use ILIKE and pass [phone, area, limit].
  const stmt = db.statements[0];
  assert.ok(stmt?.sql.includes("ilike"), "area filter must use ILIKE");
  assert.deepEqual(stmt?.values, ["+15551234567", "LA", 10]);
});

test("list with a bare number arg stays backward-compatible (no area)", async () => {
  const db = new FakeQuery(() => []);
  const store = new PgSendbluePlaceStore(db);

  await store.list("+15551234567", 7);

  const stmt = db.statements[0];
  assert.ok(!stmt?.sql.includes("ilike"), "no area filter when called with a number");
  assert.deepEqual(stmt?.values, ["+15551234567", 7]);
});

test("distinctAreas returns unique non-empty areas", async () => {
  const db = new FakeQuery((sql) => {
    assert.ok(sql.includes("distinct area"), "must select distinct area");
    return [{ area: "Los Angeles" }, { area: "Taipei" }];
  });
  const store = new PgSendbluePlaceStore(db);

  const areas = await store.distinctAreas("+15551234567");

  assert.deepEqual(areas, ["Los Angeles", "Taipei"]);
  assert.deepEqual(db.statements[0]?.values, ["+15551234567"]);
});
