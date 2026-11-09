import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import pg from "pg";
import {
  applyAppleNotification, entitlementTier, EntitlementOwnershipError,
  isEntitlementSchemaUnavailable, storeAppleEntitlement, readEntitlementReadiness,
  appAccountTokenFor, EntitlementBindingRequiredError,
} from "./entitlementPersistence.js";
import { proEntitlementPolicy, type VerifiedAppleTransaction } from "./proEntitlement.js";

const connectionString = process.env.SAVE_ENTITLEMENT_TEST_DATABASE_URL;
const period = 1_900_000_000_000;
function transaction(overrides: Partial<VerifiedAppleTransaction> = {}): VerifiedAppleTransaction {
  return {
    originalTransactionId: randomUUID(), transactionId: randomUUID(),
    productId: proEntitlementPolicy.productIDs[0], bundleId: proEntitlementPolicy.expectedBundleID,
    purchaseDateMs: period, signedDateMs: period + 1, expiresDateMs: period + 100_000,
    revocationDateMs: null, environment: "Sandbox", appAccountToken: appAccountTokenFor("user-a"), ...overrides,
  };
}

// Deliberately opt-in: tests must never create/drop schema on a configured app
// database. The controller owns this local socket-only disposable instance.
async function withDatabase(
  run: (db: pg.Pool) => Promise<void>, legacy = false,
  beforeTables?: (db: pg.Pool, schemaName: string) => Promise<void>,
): Promise<void> {
  const url = new URL(connectionString!);
  assert.equal(url.pathname, "/save_paid_fixture");
  assert.match(url.searchParams.get("host") ?? "", /^\/tmp\/save-paid-readiness-[\w-]+\/socket$/);
  const schemaName = `entitlement_test_${randomUUID().replaceAll("-", "")}`;
  const db = new pg.Pool({ connectionString, options: `-c search_path=${schemaName}`, max: 8 });
  try {
    await db.query(`create schema ${schemaName}`);
    await beforeTables?.(db, schemaName);
    await db.query("create table profiles(id text primary key)");
    await db.query("insert into profiles values ('user-a'), ('user-b')");
    const sql = readFileSync(new URL("../sql/schema.sql", import.meta.url), "utf8");
    let create = sql.slice(sql.indexOf("create table if not exists subscription_entitlements"),
      sql.indexOf("create index if not exists idx_subscription_entitlements_user"));
    if (legacy) {
      create = create.slice(0, create.indexOf("-- Existing rows"))
        .replace("    transaction_id text,\n", "")
        .replace("    purchase_date_ms bigint,\n", "")
        .replace("    signed_date_ms bigint,\n", "");
    }
    await db.query(create);
    await run(db);
  } finally {
    await db.query(`drop schema if exists ${schemaName} cascade`);
    await db.end();
  }
}

test("concurrent first claims bind exactly one owner; a later replay cannot transfer it", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const claim = transaction();
    const results = await Promise.allSettled([
      storeAppleEntitlement(db, "user-a", claim), storeAppleEntitlement(db, "user-b", claim),
    ]);
    const winner = results.findIndex((result) => result.status === "fulfilled");
    assert.ok(winner >= 0);
    assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
    const rejected = results.find((result) => result.status === "rejected") as PromiseRejectedResult;
    assert.ok(rejected.reason instanceof EntitlementOwnershipError);
    const owner = winner === 0 ? "user-a" : "user-b";
    const loser = winner === 0 ? "user-b" : "user-a";
    await assert.rejects(storeAppleEntitlement(db, loser, { ...claim, signedDateMs: period + 30 }), EntitlementOwnershipError);
    assert.equal((await db.query("select user_id from subscription_entitlements")).rows[0].user_id, owner);
    assert.equal(await entitlementTier(db, owner), "pro");
    assert.equal(await entitlementTier(db, loser), "free");
  });
});

test("refund survives receipt replays and delayed events; a later renewal restores access", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const initial = transaction();
    await storeAppleEntitlement(db, "user-a", initial);
    await applyAppleNotification(db, initial, { status: "revoked" }, period + 20);
    assert.equal(await entitlementTier(db, "user-a"), "free");
    const replay = await storeAppleEntitlement(db, "user-a", initial);
    assert.equal(replay.applied, false);
    assert.equal(replay.row.status, "revoked");
    // Re-signing that same refunded transaction must not revive it, either.
    await storeAppleEntitlement(db, "user-a", { ...initial, signedDateMs: period + 1000 });
    assert.equal(await applyAppleNotification(db, initial, { status: "active" }, period + 1001), false);
    assert.equal(await entitlementTier(db, "user-a"), "free");

    const renewal = { ...initial, transactionId: "later-renewal", purchaseDateMs: period + 100_000,
      signedDateMs: period + 100_001, expiresDateMs: period + 200_000 };
    await storeAppleEntitlement(db, "user-a", renewal);
    assert.equal(await entitlementTier(db, "user-a"), "pro");
    // A notification can be signed later but still describe an older period.
    assert.equal(await applyAppleNotification(db, initial, { status: "expired" }, period + 300_000), false);
    assert.equal(await applyAppleNotification(db, initial, { status: "revoked" }, period + 300_001), false);
    assert.equal((await storeAppleEntitlement(db, "user-a", initial)).applied, false);
    assert.equal(await entitlementTier(db, "user-a"), "pro");
    assert.equal((await db.query("select transaction_id from subscription_entitlements")).rows[0].transaction_id, "later-renewal");
  });
});

test("concurrent receipt and refund, and renewal and old expiry, converge safely", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    for (let attempt = 0; attempt < 10; attempt++) {
      const initial = transaction();
      await storeAppleEntitlement(db, "user-a", initial);
      await Promise.all([
        storeAppleEntitlement(db, "user-a", { ...initial, signedDateMs: period + 100 }),
        applyAppleNotification(db, initial, { status: "revoked" }, period + 200),
      ]);
      assert.equal((await storeAppleEntitlement(db, "user-a", initial)).row.status, "revoked");
      const renewal = { ...initial, transactionId: randomUUID(), purchaseDateMs: period + 100_000,
        signedDateMs: period + 100_001, expiresDateMs: period + 200_000 };
      await Promise.all([
        storeAppleEntitlement(db, "user-a", renewal),
        applyAppleNotification(db, initial, { status: "expired" }, period + 300_000),
      ]);
      const row = await db.query("select status, transaction_id from subscription_entitlements where original_transaction_id=$1", [initial.originalTransactionId]);
      assert.equal(row.rows[0].status, "active");
      assert.equal(row.rows[0].transaction_id, renewal.transactionId);
    }
  });
});

test("any eligible subscription grants Pro even when a longer subscription is revoked", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const shorter = transaction();
    const longer = transaction({ expiresDateMs: period + 900_000 });
    await storeAppleEntitlement(db, "user-a", shorter);
    await storeAppleEntitlement(db, "user-a", longer);
    await applyAppleNotification(db, longer, { status: "revoked" }, period + 50);
    assert.equal(await entitlementTier(db, "user-a"), "pro");
    await applyAppleNotification(db, shorter, { status: "revoked" }, period + 50);
    assert.equal(await entitlementTier(db, "user-a"), "free");
    assert.equal(await applyAppleNotification(db, transaction(), { status: "active" }, period + 50), false);
    assert.equal((await db.query("select count(*)::int as total from subscription_entitlements")).rows[0].total, 2);
  });
});

test("ordering migration is idempotent; legacy revocations cannot be revived by old evidence", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const original = transaction();
    await db.query(`insert into subscription_entitlements (user_id, original_transaction_id, product_id, status, environment, expires_at)
      values ('user-a', $1, $2, 'revoked', 'Sandbox', $3)`, [original.originalTransactionId, original.productId, new Date(original.expiresDateMs!)]);
    const migration = readFileSync(new URL("../sql/subscription-entitlement-ordering.sql", import.meta.url), "utf8");
    await db.query(migration);
    await db.query(migration);
    assert.equal((await storeAppleEntitlement(db, "user-a", original)).row.status, "revoked");
    await assert.rejects(storeAppleEntitlement(db, "user-b", original), EntitlementOwnershipError);
    const renewal = { ...original, transactionId: "new-period", purchaseDateMs: original.expiresDateMs!,
      signedDateMs: original.expiresDateMs! + 1, expiresDateMs: original.expiresDateMs! + 100_000 };
    assert.equal((await storeAppleEntitlement(db, "user-a", renewal)).row.status, "active");
  }, true);
});

test("missing ordering schema is a retriable failure, never an acknowledged application", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    assert.deepEqual(await readEntitlementReadiness(db), { component: "entitlement_storage", ready: false, reason: "migration_required" });
    await assert.rejects(applyAppleNotification(db, transaction(), { status: "revoked" }, period + 20), isEntitlementSchemaUnavailable);
    await db.query("drop table subscription_entitlements");
    assert.equal((await readEntitlementReadiness(db)).ready, false);
    await assert.rejects(storeAppleEntitlement(db, "user-a", transaction()), isEntitlementSchemaUnavailable);
  }, true);
});

test("same-period signed versions reject stale/tied expiry regressions and inconsistent identity", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const first = transaction();
    await storeAppleEntitlement(db, "user-a", first);
    // A later-signed update for the same transaction is authoritative.
    const extended = { ...first, signedDateMs: period + 20, expiresDateMs: period + 200_000 };
    assert.equal((await storeAppleEntitlement(db, "user-a", extended)).applied, true);
    assert.equal((await storeAppleEntitlement(db, "user-a", first)).applied, false);
    // Tied evidence cannot shrink expiry, even under opposing concurrent writers.
    await Promise.all([
      storeAppleEntitlement(db, "user-a", { ...extended, expiresDateMs: period + 100_000 }),
      storeAppleEntitlement(db, "user-a", { ...extended, expiresDateMs: period + 300_000 }),
    ]);
    const row = (await db.query("select expires_at from subscription_entitlements")).rows[0];
    assert.equal(row.expires_at.getTime(), period + 300_000);
    assert.equal((await storeAppleEntitlement(db, "user-a", { ...extended, transactionId: "different-id-same-period" })).applied, false);
    assert.equal((await storeAppleEntitlement(db, "user-a", { ...extended, purchaseDateMs: period + 1 })).applied, false);
    // Equal version denial takes precedence; equal version active receipt loses.
    assert.equal(await applyAppleNotification(db, extended, { status: "revoked" }, period + 20), true);
    assert.equal((await storeAppleEntitlement(db, "user-a", extended)).row.status, "revoked");
    assert.equal(await entitlementTier(db, "user-a"), "free");
  });
});

test("only newer explicit refund reversal restores the same transaction; delayed events cannot undo it", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    assert.deepEqual(await readEntitlementReadiness(db), { component: "entitlement_storage", ready: true });
    const initial = transaction();
    await storeAppleEntitlement(db, "user-a", initial);
    await applyAppleNotification(db, initial, { status: "revoked" }, period + 20);
    assert.equal(await applyAppleNotification(db, initial, { status: "active", revocationReversed: true }, period + 19), false);
    assert.equal(await applyAppleNotification(db, initial, { status: "active", revocationReversed: true }, period + 20), false);
    assert.equal(await applyAppleNotification(db, initial, { status: "active" }, period + 21), false);
    assert.equal(await applyAppleNotification(db, initial, { status: "active", revocationReversed: true }, period + 30), true);
    assert.equal(await entitlementTier(db, "user-a"), "pro");
    assert.equal(await applyAppleNotification(db, initial, { status: "revoked" }, period + 20), false);
    assert.equal((await storeAppleEntitlement(db, "user-a", initial)).applied, false);
    assert.equal(await entitlementTier(db, "user-a"), "pro");
    await assert.rejects(storeAppleEntitlement(db, "user-b", { ...initial, signedDateMs: period + 40 }), EntitlementOwnershipError);
    // A genuinely newer refund still revokes access after the reversal.
    assert.equal(await applyAppleNotification(db, initial, { status: "revoked" }, period + 40), true);
    assert.equal(await entitlementTier(db, "user-a"), "free");
  });
});

test("first claim requires the purchasing account's signed token, never first-arrival ownership", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const tokenless = transaction({ appAccountToken: null });
    await assert.rejects(storeAppleEntitlement(db, "user-b", tokenless), /purchase/i);
    const anotherAccount = { ...transaction(), appAccountToken: "01020304-0506-8708-890a-0b0c0d0e0f10" };
    await assert.rejects(storeAppleEntitlement(db, "user-b", anotherAccount), EntitlementOwnershipError);
    assert.equal((await db.query("select count(*)::int as total from subscription_entitlements")).rows[0].total, 0);
  });
});

test("account tokens are stable per Savvy account and independent across accounts", () => {
  const token = appAccountTokenFor("user-a");
  assert.equal(token, "6af12f70-29fd-8d84-a11d-bd2e9b3269b9", "issued tokens must survive future releases");
  assert.match(token, /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.notEqual(token, appAccountTokenFor("user-b"));
  assert.notEqual(token, "user-a");
});

test("concurrent registration binds the signed purchasing account across devices", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const purchased = transaction();
    const results = await Promise.allSettled(Array.from({ length: 20 }, (_, i) =>
      storeAppleEntitlement(db, i % 3 === 0 ? "user-b" : "user-a", purchased)));
    results.forEach((result, i) => {
      if (i % 3 === 0) {
        assert.equal(result.status, "rejected");
        assert.ok((result as PromiseRejectedResult).reason instanceof EntitlementOwnershipError);
      } else {
        assert.equal(result.status, "fulfilled");
      }
    });
    const rows = (await db.query("select user_id from subscription_entitlements")).rows;
    assert.deepEqual(rows, [{ user_id: "user-a" }]);
    // Even Apple evidence containing another account token cannot transfer an
    // original subscription that already has an immutable account owner.
    await assert.rejects(storeAppleEntitlement(db, "user-b", {
      ...purchased, appAccountToken: appAccountTokenFor("user-b"), signedDateMs: period + 20,
    }), EntitlementOwnershipError);
    assert.equal(await entitlementTier(db, "user-a"), "pro");
    assert.equal(await entitlementTier(db, "user-b"), "free");
  });
});

test("legacy tokenless receipts restore only an already recorded matching owner", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const legacy = transaction({ appAccountToken: null });
    await assert.rejects(storeAppleEntitlement(db, "user-a", legacy), EntitlementBindingRequiredError);
    await db.query(`insert into subscription_entitlements (user_id, original_transaction_id, product_id, status, environment, expires_at)
      values ('user-a', $1, $2, 'active', 'Sandbox', $3)`, [legacy.originalTransactionId, legacy.productId, new Date(legacy.expiresDateMs!)]);
    assert.equal((await storeAppleEntitlement(db, "user-a", legacy)).row.user_id, "user-a");
    await assert.rejects(storeAppleEntitlement(db, "user-b", legacy), EntitlementOwnershipError);
    // The exception is for missing historic tokens, never conflicting tokens.
    await assert.rejects(storeAppleEntitlement(db, "user-a", {
      ...legacy, appAccountToken: appAccountTokenFor("user-b"),
    }), EntitlementOwnershipError);
  });
});

test("unregistered webhooks retain evidence; conflicting signed tokens never mutate an owner", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const purchased = transaction();
    assert.equal(await applyAppleNotification(db, purchased, { status: "revoked" }, period + 50), false);
    assert.equal((await db.query("select count(*)::int as total from subscription_entitlements")).rows[0].total, 0);
    assert.equal((await storeAppleEntitlement(db, "user-a", purchased)).row.status, "revoked");
    const active = transaction();
    await storeAppleEntitlement(db, "user-a", active);
    await assert.rejects(applyAppleNotification(db, {
      ...active, appAccountToken: appAccountTokenFor("user-b"),
    }, { status: "revoked" }, period + 50), EntitlementOwnershipError);
    assert.equal(await entitlementTier(db, "user-a"), "pro");
    await applyAppleNotification(db, active, { status: "revoked" }, period + 50);
    // A retried legitimate pre-registration refund is applied after registration.
    assert.equal(await applyAppleNotification(db, purchased, { status: "revoked" }, period + 50), true);
    assert.equal(await entitlementTier(db, "user-a"), "free");
  });
});

test("one-shot pre-registration refund survives an original receipt and later active re-sign", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const purchased = transaction();
    // Sandbox sends one attempt. Successful handling must be durable even
    // while there is no account-bound entitlement row yet.
    assert.equal(await applyAppleNotification(db, purchased, { status: "revoked" }, period + 50), false);
    assert.equal((await db.query("select count(*)::int as total from subscription_entitlements")).rows[0].total, 0);
    const registered = await storeAppleEntitlement(db, "user-a", { ...purchased, signedDateMs: period + 100 });
    assert.equal(registered.row.status, "revoked");
    assert.equal(await entitlementTier(db, "user-a"), "free");
  });
});

test("concurrent first registration and a one-shot refund converge without pending loss", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    for (let attempt = 0; attempt < 12; attempt++) {
      const purchased = transaction();
      const register = () => storeAppleEntitlement(db, "user-a", purchased);
      const refund = () => applyAppleNotification(db, purchased, { status: "revoked" }, period + 50);
      await Promise.all(attempt % 2 === 0 ? [register(), refund()] : [refund(), register()]);
      const row = (await db.query("select user_id, status from subscription_entitlements where original_transaction_id=$1", [purchased.originalTransactionId])).rows[0];
      assert.deepEqual(row, { user_id: "user-a", status: "revoked" });
      assert.equal((await db.query("select count(*)::int as total from pending_subscription_notifications where original_transaction_id=$1", [purchased.originalTransactionId])).rows[0].total, 0);
    }
    assert.equal(await entitlementTier(db, "user-a"), "free");
  });
});

test("pending evidence applies renewal/refund ordering and explicit reversal before registration", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const first = transaction();
    await applyAppleNotification(db, first, { status: "revoked" }, period + 50);
    assert.equal(await applyAppleNotification(db, first, { status: "active" }, period + 100), false);
    const renewal = { ...first, transactionId: "pending-new-period", purchaseDateMs: period + 100_000,
      signedDateMs: period + 100_001, expiresDateMs: period + 200_000 };
    await applyAppleNotification(db, renewal, { status: "active" }, period + 100_001);
    await applyAppleNotification(db, first, { status: "expired" }, period + 300_000);
    const registered = await storeAppleEntitlement(db, "user-a", first);
    assert.equal(registered.row.status, "active");
    assert.equal((await db.query("select transaction_id from subscription_entitlements")).rows[0].transaction_id, renewal.transactionId);
    const second = transaction();
    await applyAppleNotification(db, second, { status: "revoked" }, period + 50);
    await applyAppleNotification(db, second, { status: "active", revocationReversed: true }, period + 60);
    await applyAppleNotification(db, second, { status: "revoked" }, period + 50);
    assert.equal((await storeAppleEntitlement(db, "user-a", second)).row.status, "active");
    assert.equal((await db.query("select count(*)::int as total from pending_subscription_notifications")).rows[0].total, 0);
  });
});

test("pending token conflicts fail closed and cannot be consumed by another account", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const purchased = transaction();
    await applyAppleNotification(db, purchased, { status: "revoked" }, period + 50);
    const altered = { ...purchased, appAccountToken: appAccountTokenFor("user-b") };
    await assert.rejects(applyAppleNotification(db, altered, { status: "active" }, period + 100), EntitlementOwnershipError);
    await assert.rejects(storeAppleEntitlement(db, "user-b", altered), EntitlementOwnershipError);
    assert.equal((await db.query("select count(*)::int as total from subscription_entitlements")).rows[0].total, 0);
    assert.equal((await db.query("select count(*)::int as total from pending_subscription_notifications")).rows[0].total, 1);
    assert.equal((await storeAppleEntitlement(db, "user-a", purchased)).row.status, "revoked");
  });
});

test("missing pending schema rejects first registration/webhook without partially granting access", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    await db.query("drop table pending_subscription_notifications");
    assert.deepEqual(await readEntitlementReadiness(db), { component: "entitlement_storage", ready: false, reason: "migration_required" });
    const purchased = transaction();
    await assert.rejects(storeAppleEntitlement(db, "user-a", purchased), isEntitlementSchemaUnavailable);
    await assert.rejects(applyAppleNotification(db, purchased, { status: "revoked" }, period + 50), isEntitlementSchemaUnavailable);
    assert.equal((await db.query("select count(*)::int as total from subscription_entitlements")).rows[0].total, 0);
  });
});

test("registration rollback preserves pending denial evidence and never partially grants access", { skip: !connectionString }, async () => {
  await withDatabase(async (db) => {
    const purchased = transaction();
    await applyAppleNotification(db, purchased, { status: "revoked" }, period + 50);
    await db.query(`create function reject_pending_delete() returns trigger language plpgsql as $$
      begin raise exception 'synthetic pending delete failure'; end; $$`);
    await db.query(`create trigger fail_pending_delete before delete on pending_subscription_notifications
      for each row execute function reject_pending_delete()`);
    await assert.rejects(storeAppleEntitlement(db, "user-a", purchased), /synthetic pending delete failure/);
    assert.equal((await db.query("select count(*)::int as total from subscription_entitlements")).rows[0].total, 0);
    assert.equal((await db.query("select count(*)::int as total from pending_subscription_notifications")).rows[0].total, 1);
    await db.query("drop trigger fail_pending_delete on pending_subscription_notifications");
    assert.equal((await storeAppleEntitlement(db, "user-a", purchased)).row.status, "revoked");
    assert.equal((await db.query("select count(*)::int as total from pending_subscription_notifications")).rows[0].total, 0);
    assert.equal(await entitlementTier(db, "user-a"), "free");
  });
});

// The normal fixtures above run on plain PostgreSQL without Supabase roles.
// These roles/default ACLs reproduce public-schema browser access separately.
async function withBrowserDefaults(run: (db: pg.Pool) => Promise<void>, legacy = false): Promise<void> {
  const roles = ["anon", "authenticated", "entitlement_public_probe", "entitlement_backend_owner"];
  const createdRoles: string[] = [];
  let database: pg.Pool | undefined;
  try {
    await withDatabase(async (db) => {
      database = db;
      await run(db);
    }, legacy, async (db, schemaName) => {
      database = db;
      for (const role of roles) {
        // Exact standard browser roles exist only in this isolated test cluster.
        // Do not change or delete a role left by some other fixture.
        assert.equal((await db.query("select 1 from pg_roles where rolname=$1", [role])).rowCount, 0);
        await db.query(`create role ${role} nologin nosuperuser nobypassrls`);
        createdRoles.push(role);
      }
      await db.query(`grant usage on schema ${schemaName} to public`);
      await db.query(`alter default privileges in schema ${schemaName} grant all on tables to public, anon, authenticated`);
    });
  } finally {
    // withDatabase dropped its owned schema/default ACLs and closed its pool.
    if (database && createdRoles.length) {
      const cleanup = new pg.Pool({ connectionString });
      try { for (const role of createdRoles.reverse()) await cleanup.query(`drop role ${role}`); }
      finally { await cleanup.end(); }
    }
  }
}

async function assertBrowserRolesDenied(db: pg.Pool): Promise<void> {
  const allowed: string[] = [];
  for (const role of ["anon", "authenticated", "entitlement_public_probe"]) {
    for (const table of ["subscription_entitlements", "pending_subscription_notifications"]) {
      const insert = table === "subscription_entitlements"
        ? `insert into ${table}(user_id,original_transaction_id,product_id,status) values('user-a','client-insert','fixture','active')`
        : `insert into ${table}(original_transaction_id,transaction_id,product_id,status,environment,expires_at,purchase_date_ms,signed_date_ms)
           values('client-insert','fixture-txn','fixture','revoked','Sandbox',now(),1,2)`;
      const operations = [
        ["select", `select * from ${table}`], ["insert", insert],
        ["update", `update ${table} set status='active'`],
        ["delete", `delete from ${table}`], ["truncate", `truncate ${table}`],
      ];
      for (const [operation, sql] of operations) {
        const client = await db.connect();
        try {
          await client.query("begin");
          await client.query(`set local role ${role}`);
          assert.equal((await client.query("select has_schema_privilege(current_schema(), 'usage') as allowed")).rows[0].allowed, true);
          try { await client.query(sql); allowed.push(`${role}:${table}:${operation}`); }
          catch (error) { assert.equal((error as { code: string }).code, "42501"); }
        } finally { await client.query("rollback"); client.release(); }
      }
    }
  }
  assert.deepEqual(allowed, [], "browser roles must have no table read, write or truncate path");
  for (const role of ["anon", "authenticated", "entitlement_public_probe"]) {
    for (const table of ["subscription_entitlements", "pending_subscription_notifications"]) {
      for (const privilege of ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"]) {
        assert.equal((await db.query("select has_table_privilege($1,$2,$3) as allowed", [role, table, privilege])).rows[0].allowed,
          false, `${role}:${table}:${privilege}`);
      }
    }
  }
  const { rows } = await db.query(`select relname, relrowsecurity, relforcerowsecurity from pg_class
    where relnamespace=current_schema()::regnamespace and relname=any($1::text[]) order by relname`,
    [["subscription_entitlements", "pending_subscription_notifications"]]);
  assert.equal(rows.length, 2);
  assert.ok(rows.every(row => row.relrowsecurity && !row.relforcerowsecurity), "both tables need RLS while preserving owner access");
}

async function assertOwnerPaymentFlow(db: pg.Pool): Promise<void> {
  const schemaName = (await db.query("select current_schema() as name")).rows[0].name;
  await db.query("alter table subscription_entitlements owner to entitlement_backend_owner");
  await db.query("alter table pending_subscription_notifications owner to entitlement_backend_owner");
  const owner = new pg.Pool({ connectionString, options: `-c search_path=${schemaName} -c role=entitlement_backend_owner` });
  try {
    const role = (await owner.query("select current_user, rolsuper, rolbypassrls from pg_roles where rolname=current_user")).rows[0];
    assert.equal(role.current_user, "entitlement_backend_owner");
    assert.equal(role.rolsuper, false);
    assert.equal(role.rolbypassrls, false);
    const purchased = transaction();
    assert.equal((await storeAppleEntitlement(owner, "user-a", purchased)).row.status, "active");
    assert.equal((await storeAppleEntitlement(owner, "user-a", { ...purchased, appAccountToken: null })).row.user_id, "user-a");
    await applyAppleNotification(owner, purchased, { status: "revoked" }, period + 50);
    assert.equal(await entitlementTier(owner, "user-a"), "free");
    const pending = transaction();
    await applyAppleNotification(owner, pending, { status: "revoked" }, period + 50);
    assert.equal((await storeAppleEntitlement(owner, "user-a", pending)).row.status, "revoked");
  } finally { await owner.end(); }
}

test("new entitlement tables deny Supabase browser roles despite default ALL grants", { skip: !connectionString }, async () => {
  await withBrowserDefaults(async db => {
    const purchased = transaction();
    await storeAppleEntitlement(db, "user-a", purchased);
    await applyAppleNotification(db, purchased, { status: "revoked" }, period + 50);
    await applyAppleNotification(db, transaction(), { status: "revoked" }, period + 50);
    await assertBrowserRolesDenied(db);
    await assertOwnerPaymentFlow(db);
  });
});

test("ordering migration removes legacy/browser grants without rewriting owners or status", { skip: !connectionString }, async () => {
  await withBrowserDefaults(async db => {
    await db.query(`insert into subscription_entitlements(user_id,original_transaction_id,product_id,status,environment,expires_at)
      values('user-a','legacy-owner','fixture','revoked','Sandbox','2030-01-01')`);
    // Older explicit grants must be removed as well as default grants copied
    // when the table was first created. PUBLIC supplies the probe's privileges.
    await db.query("grant all on subscription_entitlements to public, anon, authenticated");
    const before = (await db.query("select * from subscription_entitlements")).rows;
    const migration = readFileSync(new URL("../sql/subscription-entitlement-ordering.sql", import.meta.url), "utf8");
    await db.query(migration);
    await db.query(migration);
    const after = (await db.query("select * from subscription_entitlements")).rows;
    assert.equal(after.length, before.length);
    for (const key of Object.keys(before[0])) assert.deepEqual(after[0][key], before[0][key], key);
    await assertBrowserRolesDenied(db);
    await assertOwnerPaymentFlow(db);
  }, true);
});
