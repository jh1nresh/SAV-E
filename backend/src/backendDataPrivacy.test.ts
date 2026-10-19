import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import test from "node:test";
import pg from "pg";
import { resolveProfileSubject } from "./accountStatus.js";
import { AnalysisUsageStore } from "./analysisUsage.js";
import { reuseCapture } from "./memoryStorage.js";
import { putFriendRating } from "./friendRatings.js";
import { PgSendbluePlaceStore, sendblueSavedPlacesTableSql } from "./sendbluePlaceStore.js";
import { conversationStateTableSql } from "./sendblueBot.js";
import { reviewsTableSql } from "./sendblueReviewStore.js";
import { verifiedVisitsTableSql } from "./sendblueReceiptStore.js";
import { sllrBuyerTableSql } from "./sllrBuyerStore.js";
import { appAccountTokenFor, applyAppleNotification, entitlementTier, storeAppleEntitlement } from "./entitlementPersistence.js";
import { proEntitlementPolicy, type VerifiedAppleTransaction } from "./proEntitlement.js";

const schemaSQL = readFileSync(new URL("../sql/schema.sql", import.meta.url), "utf8");
const privacySQL = readFileSync(new URL("../sql/backend-data-privacy.sql", import.meta.url), "utf8");
const marker = "-- Backend-owned table privacy boundary";
const tableNames = (sql: string) => [...sql.matchAll(/\bcreate\s+table\s+(?:if\s+not\s+exists\s+)?(\w+)/gim)].map(match => match[1]);
const sourceSQL = ["../sql/", "../src/"].flatMap(folder => readdirSync(new URL(folder, import.meta.url), { recursive: true, encoding: "utf8", withFileTypes: false })
  .filter(name => name.endsWith(".sql") || (name.endsWith(".ts") && !name.endsWith(".test.ts")))
  .map(name => readFileSync(new URL(folder + name, import.meta.url), "utf8"))).join("\n");
const managedTables = [...new Set(tableNames(sourceSQL))].sort();
const coreTables = tableNames(schemaSQL).sort();
const optionalTables = managedTables.filter(name => !coreTables.includes(name));
const optionalSQL = [
  // The provider migration targets public in production; qualify its identical
  // DDL to this fixture's search_path instead of touching any shared schema.
  readFileSync(new URL("../../supabase/migrations/20260815010000_places_provider_coordinates.sql", import.meta.url), "utf8").replaceAll("public.places", "places"),
  readFileSync(new URL("../sql/friend-ratings.sql", import.meta.url), "utf8"),
  readFileSync(new URL("../sql/link-place-intelligence.sql", import.meta.url), "utf8"),
  sendblueSavedPlacesTableSql, conversationStateTableSql, reviewsTableSql, verifiedVisitsTableSql, sllrBuyerTableSql,
];
const privileges = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"];
const browserRoles = ["anon", "authenticated", "privacy_public_probe"];
const fixtureRoles = [...browserRoles, "privacy_backend_owner", "privacy_other_creator", "service_role"];
const connectionString = process.env.SAVE_ENTITLEMENT_TEST_DATABASE_URL;

function staticAllowlist(sql: string): string[] {
  const list = sql.match(/foreach managed_table in array array\[([\s\S]*?)\]/i)?.[1] ?? "";
  return [...list.matchAll(/'([a-z_]+)'/g)].map(match => match[1]).sort();
}

test("privacy allowlists cover every backend schema table without including unrelated tables", () => {
  assert.ok(managedTables.length > 0);
  assert.equal(new Set(managedTables).size, managedTables.length);
  assert.deepEqual(staticAllowlist(privacySQL), managedTables, "each new backend table needs an explicit reviewed privacy entry");
  assert.deepEqual(staticAllowlist(schemaSQL.slice(schemaSQL.indexOf(marker))), managedTables, "fresh install and upgrade must cover the same tables");
});

type Fixture = { db: pg.Pool; schema: string };
async function withFixture(run: (fixture: Fixture) => Promise<void>, options: { browser?: boolean; legacy?: boolean; partial?: boolean } = {}): Promise<void> {
  const url = new URL(connectionString!);
  assert.equal(url.pathname, "/save_paid_fixture");
  assert.match(url.searchParams.get("host") ?? "", /^\/tmp\/save-paid-readiness-[\w-]+\/socket$/);
  const schema = `privacy_test_${randomUUID().replaceAll("-", "")}`;
  const db = new pg.Pool({ connectionString, options: `-c search_path=${schema}`, max: 5 });
  const created: string[] = [];
  try {
    await db.query(`create schema ${schema}`);
    if (options.browser) {
      for (const role of fixtureRoles) {
        assert.equal((await db.query("select 1 from pg_roles where rolname=$1", [role])).rowCount, 0, "do not borrow or delete another fixture's roles");
        await db.query(`create role ${role} nologin nosuperuser ${role === "service_role" ? "bypassrls" : "nobypassrls"}`);
        created.push(role);
      }
      await db.query(`grant usage on schema ${schema} to public`);
      await db.query(`alter default privileges in schema ${schema} grant all on tables to public, anon, authenticated, service_role`);
      await db.query(`alter default privileges in schema ${schema} grant all on sequences to service_role`);
      await db.query(`grant create on schema ${schema} to privacy_other_creator`);
      await db.query(`alter default privileges for role privacy_other_creator in schema ${schema} grant all on tables to public, anon, authenticated`);
    }
    await db.query("create table privacy_unrelated_sentinel(id int primary key, private_note text)");
    await db.query("insert into privacy_unrelated_sentinel values(1,'untouched sentinel')");
    if (options.partial) {
      await db.query("create table profiles(id text primary key, private_note text)");
      await db.query("insert into profiles values('partial-owner','PRIVATE partial record')");
    } else {
      const privacyStart = schemaSQL.indexOf(marker);
      await db.query(options.legacy && privacyStart >= 0 ? schemaSQL.slice(0, privacyStart) : schemaSQL);
      for (const sql of optionalSQL) await db.query(sql);
    }
    await run({ db, schema });
  } finally {
    await db.query(`drop schema if exists ${schema} cascade`);
    for (const role of created.reverse()) await db.query(`drop role ${role}`);
    await db.end();
  }
}

async function rolePool(fixture: Fixture, role: string, run: (db: pg.Pool) => Promise<void>): Promise<void> {
  const db = new pg.Pool({ connectionString, options: `-c search_path=${fixture.schema} -c role=${role}`, max: 3 });
  try { await run(db); } finally { await db.end(); }
}

async function assertBrowserBoundary({ db, schema }: Fixture, tables = managedTables): Promise<void> {
  const allowed: string[] = [];
  const columns = await db.query(`select c.relname, a.attname from pg_class c join pg_attribute a on a.attrelid=c.oid
    where c.relnamespace=$1::regnamespace and a.attnum=1 and not a.attisdropped`, [schema]);
  for (const role of browserRoles) {
    for (const table of tables) {
      const first = columns.rows.find(row => row.relname === table)?.attname;
      assert.match(first, /^\w+$/);
      const operations = [
        ["SELECT", `select * from ${table}`],
        ["INSERT", `insert into ${table} select * from ${table} where false`],
        ["UPDATE", `update ${table} set ${first}=${first} where false`],
        ["DELETE", `delete from ${table} where false`],
        ["TRUNCATE", `truncate ${table} cascade`],
      ];
      for (const [operation, sql] of operations) {
        const client = await db.connect();
        try {
          await client.query("begin");
          await client.query(`set local role ${role}`);
          try { await client.query(sql); allowed.push(`${role}:${table}:${operation}`); }
          catch (error) { assert.equal((error as { code: string }).code, "42501", `${role}:${table}:${operation}`); }
        } finally { await client.query("rollback"); client.release(); }
      }
    }
  }
  assert.equal(allowed.length, 0, `${allowed.length} browser operations allowed; examples: ${allowed.slice(0, 8).join(", ")}`);
  for (const role of browserRoles) {
    const rows = (await db.query(`select c.relname, p.privilege, has_table_privilege($1,c.oid,p.privilege) as allowed
      from pg_class c cross join unnest($3::text[]) p(privilege)
      where c.relnamespace=$2::regnamespace and c.relname=any($4::text[])`, [role, schema, privileges, tables])).rows;
    assert.equal(rows.length, tables.length * privileges.length);
    assert.ok(rows.every(row => !row.allowed), `${role} must have no effective table privileges`);
  }
  const rows = (await db.query(`select relname, relrowsecurity, relforcerowsecurity from pg_class
    where relnamespace=$1::regnamespace and relname=any($2::text[])`, [schema, tables])).rows;
  assert.equal(rows.length, tables.length);
  assert.ok(rows.every(row => row.relrowsecurity && !row.relforcerowsecurity));
}

async function assertUnrelatedAndDefaults(fixture: Fixture): Promise<void> {
  await fixture.db.query("create table privacy_future_sentinel(id int)");
  await rolePool(fixture, "privacy_other_creator", db => db.query("create table privacy_other_creator_sentinel(id int)").then(() => {}));
  for (const role of browserRoles) {
    await rolePool(fixture, role, async db => {
      assert.equal((await db.query("select private_note from privacy_unrelated_sentinel")).rows[0].private_note, "untouched sentinel");
      for (const privilege of privileges) {
        assert.equal((await db.query("select has_table_privilege(current_user,$1,$2) as allowed", ["privacy_unrelated_sentinel", privilege])).rows[0].allowed, true);
        assert.equal((await db.query("select has_table_privilege(current_user,$1,$2) as allowed", ["privacy_other_creator_sentinel", privilege])).rows[0].allowed, true, "other creators' defaults stay untouched");
        assert.equal((await db.query("select has_table_privilege(current_user,$1,$2) as allowed", ["privacy_future_sentinel", privilege])).rows[0].allowed, false, "later tables created by this schema owner start private");
      }
      await assert.rejects(db.query("select * from privacy_future_sentinel"), (error: unknown) => (error as { code: string }).code === "42501");
      const client = await db.connect();
      try {
        await client.query("begin");
        await client.query("insert into privacy_unrelated_sentinel values(2,'client fixture')");
        await client.query("update privacy_unrelated_sentinel set private_note='client updated' where id=2");
        await client.query("delete from privacy_unrelated_sentinel where id=2");
        await client.query("truncate privacy_unrelated_sentinel");
      } finally { await client.query("rollback"); client.release(); }
    });
  }
  await rolePool(fixture, "service_role", async db => {
    await db.query("insert into privacy_future_sentinel values(1)");
    assert.equal((await db.query("select * from privacy_future_sentinel")).rowCount, 1, "server-role defaults remain available");
  });
}

async function backendFlow(db: pg.Pool, owner: string): Promise<void> {
  await db.query("insert into profiles(id,display_name,email) values($1,'Private fixture','private@example.invalid')", [owner]);
  assert.equal((await resolveProfileSubject(owner, (sql, values) => db.query(sql, [...values]))).profileId, owner);
  const place = randomUUID(), capture = randomUUID();
  await db.query("insert into places(id,user_id,name,latitude,longitude,note,google_place_id) values($1,$2,'Private place',25,121,'PRIVATE NOTE','fixture-venue')", [place, owner]);
  await db.query("update places set note='PRIVATE UPDATED' where id=$1 and user_id=$2", [place, owner]);
  await putFriendRating(db, owner, place, { stars: 4, eaten: true, shared: false });
  const sendblue = new PgSendbluePlaceStore(db);
  assert.equal(await sendblue.save(owner, { name: "Private message place", area: "Fixture" }), 1);
  assert.equal((await sendblue.list(owner))[0].name, "Private message place");
  await db.query("insert into captures(id,user_id,source_type,source_url,raw_text) values($1,$2,'url','https://fixture.invalid/private','PRIVATE CLUE')", [capture, owner]);
  const captureClient = await db.connect();
  try {
    assert.equal((await reuseCapture(captureClient, owner, { source_url: "https://fixture.invalid/private" }))?.id, capture);
    assert.equal(await reuseCapture(captureClient, `${owner}-other`, { source_url: "https://fixture.invalid/private" }), undefined);
  } finally { captureClient.release(); }
  const store = new AnalysisUsageStore(db, () => ({ enabled: false }));
  const analysis = randomUUID();
  await store.start(owner, analysis);
  await assert.rejects(store.owner(`${owner}-other`, analysis));
  await store.finish(owner, analysis, "source_only", [capture]);
  assert.equal((await store.summary(owner, analysis)).analysis_id, analysis);
  assert.equal((await db.query("select outcome from analysis_sessions where id=$1", [analysis])).rows[0].outcome, "source_only");
  const start = Date.now();
  const transaction: VerifiedAppleTransaction = {
    originalTransactionId: randomUUID(), transactionId: randomUUID(), appAccountToken: appAccountTokenFor(owner),
    productId: proEntitlementPolicy.productIDs[0], bundleId: proEntitlementPolicy.expectedBundleID,
    purchaseDateMs: start - 10, signedDateMs: start, expiresDateMs: start + 60_000, revocationDateMs: null, environment: "Sandbox",
  };
  await storeAppleEntitlement(db, owner, transaction);
  assert.equal(await entitlementTier(db, owner), "pro");
  await applyAppleNotification(db, transaction, { status: "revoked" }, start + 10);
  assert.equal(await entitlementTier(db, owner), "free");
}

async function assertBackendRoles(fixture: Fixture): Promise<void> {
  for (const table of managedTables) await fixture.db.query(`alter table ${table} owner to privacy_backend_owner`);
  await rolePool(fixture, "privacy_backend_owner", async db => {
    const flags = (await db.query("select rolsuper,rolbypassrls from pg_roles where rolname=current_user")).rows[0];
    assert.deepEqual(flags, { rolsuper: false, rolbypassrls: false });
    await backendFlow(db, "owner-backend");
  });
  await rolePool(fixture, "service_role", async db => {
    const flags = (await db.query("select rolsuper,rolbypassrls from pg_roles where rolname=current_user")).rows[0];
    assert.deepEqual(flags, { rolsuper: false, rolbypassrls: true });
    await backendFlow(db, "service-backend");
  });
}

test("privacy migration supports plain PostgreSQL and absent optional tables", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    assert.equal((await fixture.db.query("select count(*)::int as n from pg_roles where rolname=any($1::text[])", [fixtureRoles])).rows[0].n, 0);
    const before = (await fixture.db.query("select * from profiles")).rows;
    await fixture.db.query(privacySQL);
    await fixture.db.query(privacySQL);
    assert.deepEqual((await fixture.db.query("select * from profiles")).rows, before);
    assert.equal((await fixture.db.query("select relrowsecurity from pg_class where oid='profiles'::regclass")).rows[0].relrowsecurity, true);
  }, { partial: true });
});

test("fresh schema blocks browser CRUD/truncate across all managed tables while preserving backend roles", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await backendFlow(fixture.db, "seed-private");
    await assertBrowserBoundary(fixture, coreTables);
    for (const role of browserRoles) {
      for (const table of optionalTables) {
        for (const privilege of privileges) assert.equal((await fixture.db.query("select has_table_privilege($1,$2,$3) as allowed", [role, table, privilege])).rows[0].allowed, false, "future optional/runtime tables inherit private defaults");
      }
    }
    await fixture.db.query(privacySQL);
    await assertBrowserBoundary(fixture);
    await assertUnrelatedAndDefaults(fixture);
    await assertBackendRoles(fixture);
  }, { browser: true });
});

test("legacy privacy upgrade is idempotent, preserves private records, and only changes managed table access", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await backendFlow(fixture.db, "legacy-private");
    for (const table of managedTables) await fixture.db.query(`grant all on ${table} to public, anon, authenticated`);
    const snapshot = async () => (await fixture.db.query(`select jsonb_build_object(
      'profile',(select to_jsonb(p) from profiles p where id='legacy-private'),
      'place',(select to_jsonb(p) from places p where user_id='legacy-private'),
      'capture',(select to_jsonb(c) from captures c where user_id='legacy-private'),
      'analysis',(select to_jsonb(a) from analysis_sessions a where user_id='legacy-private'),
      'entitlement',(select to_jsonb(e) from subscription_entitlements e where user_id='legacy-private')) as state`)).rows[0].state;
    const before = await snapshot();
    await fixture.db.query(privacySQL);
    await fixture.db.query(privacySQL);
    assert.deepEqual(await snapshot(), before);
    await assertBrowserBoundary(fixture);
    await assertUnrelatedAndDefaults(fixture);
    await assertBackendRoles(fixture);
  }, { browser: true, legacy: true });
});

test("privacy migration refuses global browser default grants without changing tables or defaults", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await fixture.db.query("alter default privileges grant select on tables to public");
    try {
      const state = async () => (await fixture.db.query(`select jsonb_build_object(
        'tables',(select jsonb_agg(jsonb_build_array(relname,relrowsecurity,relacl::text) order by relname) from pg_class where relnamespace=current_schema()::regnamespace),
        'defaults',(select jsonb_agg(jsonb_build_array(defaclnamespace,defaclacl::text) order by defaclnamespace) from pg_default_acl where defaclrole=current_user::regrole)) as state`)).rows[0].state;
      const before = await state();
      await assert.rejects(fixture.db.query(privacySQL), /global.*default|default.*global/i);
      assert.deepEqual(await state(), before, "refusal must leave existing access and defaults unchanged");
    } finally { await fixture.db.query("alter default privileges revoke select on tables from public"); }
  }, { browser: true, legacy: true });
});
