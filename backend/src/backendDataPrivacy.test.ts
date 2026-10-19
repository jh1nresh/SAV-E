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
  const list = sql.match(/managed_tables text\[\] := array\[([\s\S]*?)\]/i)?.[1]
    ?? sql.match(/foreach managed_table in array array\[([\s\S]*?)\]/i)?.[1]
    ?? "";
  return [...list.matchAll(/'([a-z_]+)'/g)].map(match => match[1]).sort();
}

test("privacy allowlists cover every backend schema table without including unrelated tables", () => {
  assert.ok(managedTables.length > 0);
  assert.equal(new Set(managedTables).size, managedTables.length);
  assert.deepEqual(staticAllowlist(privacySQL), managedTables, "each new backend table needs an explicit reviewed privacy entry");
  assert.deepEqual(staticAllowlist(schemaSQL.slice(schemaSQL.indexOf(marker))), managedTables, "fresh install and upgrade must cover the same tables");
  assert.equal(schemaSQL.slice(schemaSQL.indexOf(marker)), privacySQL.slice(privacySQL.indexOf(marker)), "fresh schema and upgrade must share the same privacy boundary");
});

test("fresh schema privacy guard runs before DDL and documents transactional apply", () => {
  const guard = schemaSQL.search(/Global default table grants to browser roles require separate authorized remediation/);
  const tableGrantGuard = schemaSQL.search(/from pg_class c\s+cross join lateral aclexplode\(coalesce\(c\.relacl/);
  const ddl = schemaSQL.search(/\bcreate\s+(extension|table)\b/i);
  assert.ok(guard >= 0 && ddl >= 0 && guard < ddl, "fresh-schema guard must run before DDL");
  assert.ok(tableGrantGuard >= 0 && tableGrantGuard < ddl, "re-apply table-grant refusal must run before DDL");
  const readme = readFileSync(new URL("../README.md", import.meta.url), "utf8");
  assert.match(readme, /psql "\$DATABASE_URL" -v ON_ERROR_STOP=1 -1 -f backend\/sql\/schema\.sql/);
  assert.match(privacySQL, /pg_has_role\(browser\.oid, granted\.oid, 'MEMBER'\)/);
  assert.match(schemaSQL, /pg_has_role\(browser\.oid, granted\.oid, 'MEMBER'\)/);
  assert.match(privacySQL, /a\.grantor <> current_user::regrole/);
  assert.match(schemaSQL, /a\.grantor <> current_user::regrole/);
  assert.match(privacySQL, /Managed table ownership by a browser role requires separate authorized remediation/);
  assert.match(schemaSQL, /Managed table ownership by a browser role requires separate authorized remediation/);
  assert.match(privacySQL, /Browser-role column grants require separate authorized remediation/);
  assert.match(schemaSQL, /Browser-role column grants require separate authorized remediation/);
  assert.doesNotMatch(privacySQL, /pg_has_role\(browser\.oid, granted\.oid, 'USAGE'\)/);
  assert.doesNotMatch(schemaSQL, /pg_has_role\(browser\.oid, granted\.oid, 'USAGE'\)/);
  const repoRoot = new URL("../../", import.meta.url);
  const markdown = readdirSync(repoRoot, { recursive: true, encoding: "utf8" })
    .filter(name => name.endsWith(".md") && !name.includes("node_modules/"));
  const unsafeApply = /psql "\$DATABASE_URL" -f (?:backend\/)?sql\/schema\.sql/;
  for (const name of markdown) {
    const text = readFileSync(new URL(name, repoRoot), "utf8");
    assert.doesNotMatch(text, unsafeApply, name);
    for (const line of text.split("\n")) {
      if (!/psql/.test(line) || !/-f/.test(line) || !/schema\.sql/.test(line) || /mistake/i.test(line)) continue;
      assert.match(line, /-v ON_ERROR_STOP=1 -1/, `${name}: ${line}`);
    }
  }
  const runbook = readFileSync(new URL("../../docs/2026-08-04-backend-rebuild-runbook.md", import.meta.url), "utf8");
  assert.doesNotMatch(runbook, /schema\.sql is idempotent/);
});

type Fixture = { db: pg.Pool; schema: string };
async function withFixture(run: (fixture: Fixture) => Promise<void>, options: { browser?: boolean; legacy?: boolean; partial?: boolean; install?: boolean } = {}): Promise<void> {
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
    } else if (options.install !== false) {
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

test("fresh schema privacy guard fails before DDL when global browser defaults exist", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await fixture.db.query("alter default privileges grant select on tables to public");
    try {
      await assert.rejects(fixture.db.query(schemaSQL), /global.*default|default.*global/i);
      const names = (await fixture.db.query(`select relname from pg_class
        where relnamespace=current_schema()::regnamespace and relkind='r' order by 1`)).rows.map(row => row.relname);
      assert.deepEqual(names, ["privacy_unrelated_sentinel"], "refused fresh schema must not create managed tables");
    } finally { await fixture.db.query("alter default privileges revoke select on tables from public"); }
  }, { browser: true, install: false });
});

async function withMembershipParent(fixture: Fixture, run: () => Promise<void>): Promise<void> {
  assert.equal((await fixture.db.query("select 1 from pg_roles where rolname='privacy_browser_parent'")).rowCount, 0, "do not borrow another fixture's parent role");
  await fixture.db.query("create role privacy_browser_parent nologin nosuperuser inherit nobypassrls");
  try { await run(); }
  finally {
    await fixture.db.query("revoke privacy_browser_parent from anon, authenticated");
    await fixture.db.query("drop owned by privacy_browser_parent");
    await fixture.db.query("drop role if exists privacy_browser_parent");
  }
}

test("privacy migration refuses table grants inherited through browser-role membership", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await withMembershipParent(fixture, async () => {
      await fixture.db.query("grant privacy_browser_parent to anon, authenticated");
      await fixture.db.query("grant all on places to privacy_browser_parent");
      assert.equal((await fixture.db.query("select has_table_privilege('anon','places','TRUNCATE') as allowed")).rows[0].allowed, true, "membership fixture must reproduce inherited TRUNCATE");
      const state = async () => (await fixture.db.query(`select jsonb_build_object(
        'tables',(select jsonb_agg(jsonb_build_array(relname,relrowsecurity,relacl::text) order by relname) from pg_class where relnamespace=current_schema()::regnamespace),
        'defaults',(select jsonb_agg(jsonb_build_array(defaclnamespace,defaclacl::text) order by defaclnamespace) from pg_default_acl where defaclrole=current_user::regrole),
        'members',(select pg_has_role('anon','privacy_browser_parent','USAGE')) ) as state`)).rows[0].state;
      const before = await state();
      await assert.rejects(fixture.db.query(privacySQL), /inherit|membership/i);
      assert.deepEqual(await state(), before, "membership refusal must leave existing access and defaults unchanged");
    });
  }, { browser: true, legacy: true });
});

test("privacy migration refuses SET-able NOINHERIT browser-role memberships", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await withMembershipParent(fixture, async () => {
      await fixture.db.query("grant privacy_browser_parent to anon, authenticated with inherit false, set true");
      await fixture.db.query("revoke all on places from public, anon, authenticated");
      await fixture.db.query("grant all on places to privacy_browser_parent");
      assert.equal((await fixture.db.query("select has_table_privilege('anon','places','SELECT') as allowed")).rows[0].allowed, false, "NOINHERIT membership must not grant effective SELECT");
      assert.equal((await fixture.db.query("select pg_has_role('anon','privacy_browser_parent','USAGE') as allowed")).rows[0].allowed, false, "USAGE must miss SET-able NOINHERIT membership");
      assert.equal((await fixture.db.query("select pg_has_role('anon','privacy_browser_parent','MEMBER') as allowed")).rows[0].allowed, true);
      const client = await fixture.db.connect();
      try {
        await client.query("begin");
        await client.query("set local role anon");
        await client.query("set local role privacy_browser_parent");
        assert.equal((await client.query("select name from places where false")).rowCount, 0, "SET ROLE parent must be able to read places");
      } finally {
        await client.query("rollback");
        client.release();
      }
      const state = async () => (await fixture.db.query(`select jsonb_build_object(
        'tables',(select jsonb_agg(jsonb_build_array(relname,relrowsecurity,relacl::text) order by relname) from pg_class where relnamespace=current_schema()::regnamespace),
        'defaults',(select jsonb_agg(jsonb_build_array(defaclnamespace,defaclacl::text) order by defaclnamespace) from pg_default_acl where defaclrole=current_user::regrole),
        'members',(select pg_has_role('anon','privacy_browser_parent','MEMBER')),
        'inherit',(select pg_has_role('anon','privacy_browser_parent','USAGE')) ) as state`)).rows[0].state;
      const before = await state();
      await assert.rejects(fixture.db.query(privacySQL), /inherit|membership/i);
      assert.deepEqual(await state(), before, "NOINHERIT membership refusal must leave existing access and defaults unchanged");
    });
  }, { browser: true, legacy: true });
});

test("fresh schema guard refuses existing inherited table grants before any DDL", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await fixture.db.query("create table places(id int primary key, name text)");
    await withMembershipParent(fixture, async () => {
      await fixture.db.query("grant privacy_browser_parent to anon, authenticated");
      await fixture.db.query("grant all on places to privacy_browser_parent");
      await assert.rejects(fixture.db.query(schemaSQL), /inherit|membership/i);
      const names = (await fixture.db.query(`select relname from pg_class
        where relnamespace=current_schema()::regnamespace and relkind='r' order by 1`)).rows.map(row => row.relname);
      assert.deepEqual(names, ["places", "privacy_unrelated_sentinel"], "refused re-apply must not create managed tables");
    });
  }, { browser: true, install: false });
});

async function withDelegatedGrantor(fixture: Fixture, run: () => Promise<void>): Promise<void> {
  assert.equal((await fixture.db.query("select 1 from pg_roles where rolname='privacy_delegated_grantor'")).rowCount, 0, "do not borrow another fixture's delegated grantor");
  await fixture.db.query("create role privacy_delegated_grantor nologin nosuperuser inherit nobypassrls");
  await fixture.db.query("grant privacy_delegated_grantor to current_user");
  try { await run(); }
  finally {
    await fixture.db.query("reset role");
    await fixture.db.query("revoke privacy_delegated_grantor from current_user");
    await fixture.db.query("drop owned by privacy_delegated_grantor");
    await fixture.db.query("drop role if exists privacy_delegated_grantor");
  }
}

test("privacy migration refuses browser grants issued by a delegated grantor", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await withDelegatedGrantor(fixture, async () => {
      await fixture.db.query("grant all on places to privacy_delegated_grantor with grant option");
      await fixture.db.query("set role privacy_delegated_grantor");
      await fixture.db.query("grant truncate on places to public, anon, authenticated");
      await fixture.db.query("reset role");
      assert.equal((await fixture.db.query("select has_table_privilege('anon','places','TRUNCATE') as allowed")).rows[0].allowed, true, "delegated grantor fixture must reproduce browser TRUNCATE");
      const ownerRevoke = async () => {
        await fixture.db.query("revoke all on places from public, anon, authenticated");
        return (await fixture.db.query("select has_table_privilege('anon','places','TRUNCATE') as allowed")).rows[0].allowed;
      };
      assert.equal(await ownerRevoke(), true, "owner REVOKE must leave the foreign-grantor TRUNCATE");
      await fixture.db.query("set role privacy_delegated_grantor");
      await fixture.db.query("grant truncate on places to public, anon, authenticated");
      await fixture.db.query("reset role");
      const state = async () => (await fixture.db.query(`select jsonb_build_object(
        'tables',(select jsonb_agg(jsonb_build_array(relname,relrowsecurity,relacl::text) order by relname) from pg_class where relnamespace=current_schema()::regnamespace),
        'defaults',(select jsonb_agg(jsonb_build_array(defaclnamespace,defaclacl::text) order by defaclnamespace) from pg_default_acl where defaclrole=current_user::regrole),
        'grantors',(select jsonb_agg(jsonb_build_array(grantor,grantee,privilege_type) order by 1,2,3)
          from aclexplode((select relacl from pg_class where oid='places'::regclass))) ) as state`)).rows[0].state;
      const before = await state();
      await assert.rejects(fixture.db.query(privacySQL), /grantor/i);
      assert.deepEqual(await state(), before, "foreign-grantor refusal must leave existing access and defaults unchanged");
    });
  }, { browser: true, legacy: true });
});

test("fresh schema guard refuses foreign-grantor browser grants before any DDL", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await fixture.db.query("create table places(id int primary key, name text)");
    await withDelegatedGrantor(fixture, async () => {
      await fixture.db.query("grant all on places to privacy_delegated_grantor with grant option");
      await fixture.db.query("set role privacy_delegated_grantor");
      await fixture.db.query("grant truncate on places to public, anon, authenticated");
      await fixture.db.query("reset role");
      await assert.rejects(fixture.db.query(schemaSQL), /grantor/i);
      const names = (await fixture.db.query(`select relname from pg_class
        where relnamespace=current_schema()::regnamespace and relkind='r' order by 1`)).rows.map(row => row.relname);
      assert.deepEqual(names, ["places", "privacy_unrelated_sentinel"], "refused re-apply must not create managed tables");
    });
  }, { browser: true, install: false });
});

test("privacy migration refuses managed tables owned by a browser role", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await fixture.db.query("alter table places owner to anon");
    const state = async () => (await fixture.db.query(`select jsonb_build_object(
      'tables',(select jsonb_agg(jsonb_build_array(relname,relowner::regrole::text,relrowsecurity,relacl::text) order by relname) from pg_class where relnamespace=current_schema()::regnamespace),
      'defaults',(select jsonb_agg(jsonb_build_array(defaclnamespace,defaclacl::text) order by defaclnamespace) from pg_default_acl where defaclrole=current_user::regrole)) as state`)).rows[0].state;
    const before = await state();
    await assert.rejects(fixture.db.query(privacySQL), /owner|ownership/i);
    assert.deepEqual(await state(), before, "browser-owner refusal must leave existing access and defaults unchanged");
  }, { browser: true, legacy: true });
});

test("fresh schema guard refuses browser-owned tables before any DDL", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await fixture.db.query("create table places(id int primary key, name text)");
    await fixture.db.query("alter table places owner to anon");
    await assert.rejects(fixture.db.query(schemaSQL), /owner|ownership/i);
    const names = (await fixture.db.query(`select relname from pg_class
      where relnamespace=current_schema()::regnamespace and relkind='r' order by 1`)).rows.map(row => row.relname);
    assert.deepEqual(names, ["places", "privacy_unrelated_sentinel"], "refused re-apply must not create managed tables");
  }, { browser: true, install: false });
});

test("privacy migration refuses column-level browser grants that survive table revoke", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await withMembershipParent(fixture, async () => {
      await fixture.db.query("grant privacy_browser_parent to anon, authenticated");
      await fixture.db.query("revoke all on places from public, anon, authenticated");
      await fixture.db.query("grant select (name) on places to privacy_browser_parent");
      assert.equal((await fixture.db.query("select has_column_privilege('anon','places','name','SELECT') as allowed")).rows[0].allowed, true, "column fixture must reproduce inherited column SELECT");
      await fixture.db.query("revoke all on places from public, anon, authenticated");
      assert.equal((await fixture.db.query("select has_column_privilege('anon','places','name','SELECT') as allowed")).rows[0].allowed, true, "table REVOKE must leave inherited column SELECT");
      const state = async () => (await fixture.db.query(`select jsonb_build_object(
        'tables',(select jsonb_agg(jsonb_build_array(relname,relrowsecurity,relacl::text) order by relname) from pg_class where relnamespace=current_schema()::regnamespace),
        'columns',(select jsonb_agg(jsonb_build_array(c.relname,a.attname,a.attacl::text) order by 1,2)
          from pg_attribute a join pg_class c on c.oid=a.attrelid
          where a.attacl is not null and c.relnamespace=current_schema()::regnamespace),
        'defaults',(select jsonb_agg(jsonb_build_array(defaclnamespace,defaclacl::text) order by defaclnamespace) from pg_default_acl where defaclrole=current_user::regrole)) as state`)).rows[0].state;
      const before = await state();
      await assert.rejects(fixture.db.query(privacySQL), /column/i);
      assert.deepEqual(await state(), before, "column-grant refusal must leave existing access and defaults unchanged");
    });
  }, { browser: true, legacy: true });
});

test("fresh schema guard refuses column-level browser grants before any DDL", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await fixture.db.query("create table places(id int primary key, name text)");
    await fixture.db.query("revoke all on places from public, anon, authenticated");
    await fixture.db.query("grant select (name) on places to public, anon, authenticated");
    await assert.rejects(fixture.db.query(schemaSQL), /column/i);
    const names = (await fixture.db.query(`select relname from pg_class
      where relnamespace=current_schema()::regnamespace and relkind='r' order by 1`)).rows.map(row => row.relname);
    assert.deepEqual(names, ["places", "privacy_unrelated_sentinel"], "refused re-apply must not create managed tables");
  }, { browser: true, install: false });
});

test("privacy migration refuses global defaults inherited through browser-role membership", { skip: !connectionString }, async () => {
  await withFixture(async fixture => {
    await withMembershipParent(fixture, async () => {
      await fixture.db.query("grant privacy_browser_parent to anon, authenticated");
      await fixture.db.query("alter default privileges grant select on tables to privacy_browser_parent");
      try {
        const state = async () => (await fixture.db.query(`select jsonb_build_object(
          'tables',(select jsonb_agg(jsonb_build_array(relname,relrowsecurity,relacl::text) order by relname) from pg_class where relnamespace=current_schema()::regnamespace),
          'defaults',(select jsonb_agg(jsonb_build_array(defaclnamespace,defaclacl::text) order by defaclnamespace) from pg_default_acl where defaclrole=current_user::regrole)) as state`)).rows[0].state;
        const before = await state();
        await assert.rejects(fixture.db.query(privacySQL), /global.*default|inherit|membership/i);
        assert.deepEqual(await state(), before, "inherited global default refusal must leave existing access unchanged");
      } finally { await fixture.db.query("alter default privileges revoke select on tables from privacy_browser_parent"); }
    });
  }, { browser: true, legacy: true });
});
