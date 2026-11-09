import { createHash } from "node:crypto";
import type { Pool } from "pg";
import { resolveTier, statusFor, type ProEntitlementStatus, type VerifiedAppleTransaction } from "./proEntitlement.js";

type QueryDatabase = Pick<Pool, "query">;
type Database = Pick<Pool, "query" | "connect">;
export type StoredEntitlement = {
  user_id: string;
  status: ProEntitlementStatus;
  product_id: string;
  environment: string;
  expires_at: Date | string | null;
};

export class EntitlementOwnershipError extends Error {
  constructor() { super("Subscription is already associated with another account"); }
}

export class EntitlementBindingRequiredError extends Error {
  constructor() { super("Start the purchase from this Savvy account before restoring it"); }
}

/// Stable UUIDv8, scoped to this app/purpose. This is a correlation identifier,
/// not a credential. Keep the namespace/derivation unchanged across releases so
/// the same Savvy account can restore its signed purchases across devices.
export function appAccountTokenFor(userId: string): string {
  if (!userId) throw new Error("Savvy account is required");
  const bytes = createHash("sha256")
    .update("com.wanderly.app:app-account-token:v1\0").update(userId).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x80;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// A purchase identifies a period; signedDate versions evidence about that
// period. A late-signed refund for an older period must not revoke a renewal.
// Revocation survives generic receipts, even when re-signed. Only an explicit
// newer Apple refund reversal or a distinct later renewal may restore access.
// Legacy rows have no signed ordering evidence. Seed them only without reducing
// their known expiry; a legacy revocation needs a new period beyond that expiry.
function mayReplace(incoming: string, revocationReversed = false): string {
  const value = (column: string) => `${incoming}.${column}`;
  const rank = (prefix: string) => `(case ${prefix}.status when 'revoked' then 3 when 'expired' then 2 when 'active' then 1 else 0 end)`;
  const reversal = revocationReversed
    ? `or ${value("signed_date_ms")} > current.signed_date_ms` : "";
  return `(
    (current.purchase_date_ms is null and (
      (current.expires_at is null and current.status <> 'revoked') or
      (${value("expires_at")} >= current.expires_at and (
        current.status <> 'revoked' or ${value("status")} = 'revoked' or
        ${value("purchase_date_ms")} >= extract(epoch from current.expires_at) * 1000
      ))
    )) or
    (${value("purchase_date_ms")} > current.purchase_date_ms and ${value("transaction_id")} <> current.transaction_id) or
    (${value("purchase_date_ms")} = current.purchase_date_ms and ${value("transaction_id")} = current.transaction_id
      and (current.status <> 'revoked' or ${value("status")} = 'revoked' ${reversal})
      and (${value("signed_date_ms")} > current.signed_date_ms or
        (${value("signed_date_ms")} = current.signed_date_ms and (
          ${rank(incoming)} > ${rank("current")} or
          (${rank(incoming)} = ${rank("current")} and ${value("expires_at")} >= current.expires_at)))))
  )`;
}

function values(transaction: VerifiedAppleTransaction, status: ProEntitlementStatus, signedDateMs: number): unknown[] {
  return [transaction.originalTransactionId, transaction.productId, status, transaction.environment,
    new Date(transaction.expiresDateMs!).toISOString(), transaction.transactionId,
    transaction.purchaseDateMs, signedDateMs];
}

// Both paths serialize one original subscription while merging unowned signed
// evidence and account ownership. In particular a one-shot Sandbox refund can
// commit before registration without being lost or creating a user binding.
async function withSubscriptionLock<T>(db: Database, originalId: string, run: (tx: QueryDatabase) => Promise<T>): Promise<T> {
  const tx = await db.connect();
  try {
    await tx.query("begin");
    await tx.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [`savvy:subscription:${originalId}`]);
    const result = await run(tx);
    await tx.query("commit");
    return result;
  } catch (error) {
    await tx.query("rollback");
    throw error;
  } finally { tx.release(); }
}

/// PostgreSQL also checks immutable ownership in the conflict update itself.
async function writeEntitlement(
  db: QueryDatabase, userId: string, transaction: VerifiedAppleTransaction,
  status: ProEntitlementStatus, signedDateMs: number, allowCreate: boolean, revocationReversed = false,
): Promise<{ applied: boolean; row: StoredEntitlement }> {
  const { rows } = await db.query<StoredEntitlement>(
    `insert into subscription_entitlements as current (
       original_transaction_id, product_id, status, environment, expires_at,
       transaction_id, purchase_date_ms, signed_date_ms, user_id, last_verified_at
     ) select $1, $2, $3, $4, $5, $6, $7, $8, $9, now()
       where $10::boolean or exists (
         select 1 from subscription_entitlements where original_transaction_id = $1 and user_id = $9
       )
     on conflict (original_transaction_id) do update set
       product_id = excluded.product_id, status = excluded.status,
       environment = excluded.environment, expires_at = excluded.expires_at,
       transaction_id = excluded.transaction_id, purchase_date_ms = excluded.purchase_date_ms,
       signed_date_ms = excluded.signed_date_ms, last_verified_at = now()
     where current.user_id = excluded.user_id and ${mayReplace("excluded", revocationReversed)}
     returning current.*`,
    [...values(transaction, status, signedDateMs), userId, allowCreate],
  );
  if (rows[0]) return { applied: true, row: rows[0] };
  const existing = await db.query<StoredEntitlement>(
    "select * from subscription_entitlements where original_transaction_id = $1", [transaction.originalTransactionId],
  );
  if (!existing.rows[0]) throw new EntitlementBindingRequiredError();
  if (existing.rows[0].user_id !== userId) throw new EntitlementOwnershipError();
  return { applied: false, row: existing.rows[0] };
}

type PendingNotification = {
  original_transaction_id: string; transaction_id: string; app_account_token: string | null;
  product_id: string; status: ProEntitlementStatus; environment: string; expires_at: Date;
  purchase_date_ms: string; signed_date_ms: string; revocation_reversed: boolean;
};

export async function storeAppleEntitlement(
  db: Database, userId: string, transaction: VerifiedAppleTransaction,
): Promise<{ applied: boolean; row: StoredEntitlement }> {
  const hasSignedBinding = transaction.appAccountToken !== null;
  if (hasSignedBinding && transaction.appAccountToken !== appAccountTokenFor(userId)) {
    throw new EntitlementOwnershipError();
  }
  return withSubscriptionLock(db, transaction.originalTransactionId, async (tx) => {
    const existing = await tx.query<{ user_id: string }>(
      "select user_id from subscription_entitlements where original_transaction_id = $1", [transaction.originalTransactionId],
    );
    const owner = existing.rows[0]?.user_id;
    if (owner && owner !== userId) throw new EntitlementOwnershipError();
    if (!owner && !hasSignedBinding) throw new EntitlementBindingRequiredError();
    const pending = (await tx.query<PendingNotification>(
      "select * from pending_subscription_notifications where original_transaction_id = $1", [transaction.originalTransactionId],
    )).rows[0];
    if (pending) {
      if (pending.app_account_token !== null && pending.app_account_token !== appAccountTokenFor(userId)) {
        throw new EntitlementOwnershipError();
      }
      // Seed signed server state BEFORE the client receipt. This preserves a
      // pending refund even against a later re-sign of the same active receipt.
      const evidence: VerifiedAppleTransaction = {
        ...transaction, transactionId: pending.transaction_id, appAccountToken: pending.app_account_token,
        productId: pending.product_id, environment: pending.environment,
        purchaseDateMs: Number(pending.purchase_date_ms), signedDateMs: Number(pending.signed_date_ms),
        expiresDateMs: pending.expires_at.getTime(),
      };
      await writeEntitlement(tx, userId, evidence, pending.status, evidence.signedDateMs,
        hasSignedBinding, pending.revocation_reversed);
    }
    const result = await writeEntitlement(tx, userId, transaction, statusFor(transaction), transaction.signedDateMs, hasSignedBinding);
    await tx.query("delete from pending_subscription_notifications where original_transaction_id = $1", [transaction.originalTransactionId]);
    return result;
  });
}

async function retainPendingNotification(
  db: QueryDatabase, transaction: VerifiedAppleTransaction,
  effect: { status: ProEntitlementStatus; revocationReversed?: true }, signedDateMs: number,
): Promise<void> {
  const existing = (await db.query<{ app_account_token: string | null }>(
    "select app_account_token from pending_subscription_notifications where original_transaction_id = $1", [transaction.originalTransactionId],
  )).rows[0];
  if (existing?.app_account_token && transaction.appAccountToken && existing.app_account_token !== transaction.appAccountToken) {
    throw new EntitlementOwnershipError();
  }
  await db.query(
    `insert into pending_subscription_notifications as current (
       original_transaction_id, product_id, status, environment, expires_at,
       transaction_id, purchase_date_ms, signed_date_ms, app_account_token, revocation_reversed
     ) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
     on conflict (original_transaction_id) do update set
       product_id = excluded.product_id, status = excluded.status, environment = excluded.environment,
       expires_at = excluded.expires_at, transaction_id = excluded.transaction_id,
       purchase_date_ms = excluded.purchase_date_ms, signed_date_ms = excluded.signed_date_ms,
       app_account_token = coalesce(current.app_account_token, excluded.app_account_token),
       revocation_reversed = excluded.revocation_reversed
     where ${mayReplace("excluded", effect.revocationReversed === true)}`,
    [...values(transaction, effect.status, signedDateMs), transaction.appAccountToken, effect.revocationReversed === true],
  );
}

/// Unknown subscriptions retain signed event state without assigning any owner.
/// Acknowledge only after the pending state or known entitlement commits.
export async function applyAppleNotification(
  db: Database, transaction: VerifiedAppleTransaction,
  effect: { status: ProEntitlementStatus; revocationReversed?: true }, notificationSignedDateMs: number,
): Promise<boolean> {
  return withSubscriptionLock(db, transaction.originalTransactionId, async (tx) => {
    const { rows } = await tx.query<{ user_id: string }>(
      `select user_id, transaction_id, purchase_date_ms, signed_date_ms
       from subscription_entitlements where original_transaction_id = $1`, [transaction.originalTransactionId],
    );
    const owner = rows[0]?.user_id;
    const signedDateMs = Math.max(transaction.signedDateMs, notificationSignedDateMs);
    if (!owner) {
      await retainPendingNotification(tx, transaction, effect, signedDateMs);
      return false;
    }
    if (transaction.appAccountToken !== null && transaction.appAccountToken !== appAccountTokenFor(owner)) {
      throw new EntitlementOwnershipError();
    }
    const { rowCount } = await tx.query(
      `update subscription_entitlements as current set
         product_id = incoming.product_id, status = incoming.status,
         environment = incoming.environment, expires_at = incoming.expires_at,
         transaction_id = incoming.transaction_id, purchase_date_ms = incoming.purchase_date_ms,
         signed_date_ms = incoming.signed_date_ms, last_verified_at = now()
       from (values ($1::text, $2::text, $3::text, $4::text, $5::timestamptz, $6::text, $7::bigint, $8::bigint))
         as incoming(original_transaction_id, product_id, status, environment, expires_at, transaction_id, purchase_date_ms, signed_date_ms)
       where current.original_transaction_id = incoming.original_transaction_id and current.user_id = $9
         and ${mayReplace("incoming", effect.revocationReversed === true)}`,
      [...values(transaction, effect.status, signedDateMs), owner],
    );
    return (rowCount ?? 0) > 0;
  });
}

export async function entitlementTier(db: QueryDatabase, userId: string): Promise<"free" | "pro"> {
  const { rows } = await db.query<StoredEntitlement>(
    `select status, expires_at from subscription_entitlements
     where user_id = $1 and status = 'active' and expires_at > now()`, [userId],
  );
  return rows.some((row) => resolveTier(row) === "pro") ? "pro" : "free";
}

export function isEntitlementSchemaUnavailable(error: unknown): boolean {
  const code = (error as { code?: unknown } | null)?.code;
  return code === "42P01" || code === "42703";
}

/// Storage readiness only: this does not assert App Store setup, product demand,
/// provider availability, or approval to enable purchases.
export async function readEntitlementReadiness(db: QueryDatabase): Promise<{
  component: "entitlement_storage"; ready: boolean; reason?: "migration_required" | "storage_unavailable";
}> {
  try {
    await db.query(`select user_id, original_transaction_id, product_id, status,
      environment, expires_at, transaction_id, purchase_date_ms, signed_date_ms,
      last_verified_at from subscription_entitlements limit 0`);
    await db.query(`select original_transaction_id, transaction_id, app_account_token,
      product_id, status, environment, expires_at, purchase_date_ms, signed_date_ms,
      revocation_reversed from pending_subscription_notifications limit 0`);
    return { component: "entitlement_storage", ready: true };
  } catch (error) {
    return { component: "entitlement_storage", ready: false,
      reason: isEntitlementSchemaUnavailable(error) ? "migration_required" : "storage_unavailable" };
  }
}
