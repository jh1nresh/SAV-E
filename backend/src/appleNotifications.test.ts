import assert from "node:assert/strict";
import test from "node:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { X509Certificate } from "node:crypto";
import { SignJWT, importPKCS8 } from "jose";

import { proEntitlementPolicy, type VerifiedAppleTransaction } from "./proEntitlement.js";
import {
  notificationEffect,
  verifyAppleNotification,
  type VerifiedAppleNotification,
} from "./appleNotifications.js";

// ---------------------------------------------------------------------------
// Test PKI (mirrors proEntitlement.test.ts)
// ---------------------------------------------------------------------------

type TestPKI = { chain: string[]; leafKeyPem: string; rootFingerprint: string; dir: string };

function openssl(args: string[], cwd: string): void {
  execFileSync("openssl", args, { cwd, stdio: "pipe" });
}

function buildTestPKI(): TestPKI {
  const dir = mkdtempSync(join(tmpdir(), "save-assn-"));

  openssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "root.key"], dir);
  openssl(["req", "-x509", "-new", "-key", "root.key", "-sha256", "-days", "3650",
    "-subj", "/CN=Test Root CA", "-out", "root.pem"], dir);

  openssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "int.key"], dir);
  openssl(["req", "-new", "-key", "int.key", "-subj", "/CN=Test Intermediate", "-out", "int.csr"], dir);
  execFileSync("bash", ["-c",
    "printf 'basicConstraints=critical,CA:TRUE\\nkeyUsage=critical,keyCertSign\\n' > int.ext"],
    { cwd: dir });
  openssl(["x509", "-req", "-in", "int.csr", "-CA", "root.pem", "-CAkey", "root.key",
    "-CAcreateserial", "-days", "3650", "-sha256", "-extfile", "int.ext", "-out", "int.pem"], dir);

  openssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key"], dir);
  openssl(["pkcs8", "-topk8", "-nocrypt", "-in", "leaf.key", "-out", "leaf.pkcs8.pem"], dir);
  openssl(["req", "-new", "-key", "leaf.key", "-subj", "/CN=Test Leaf", "-out", "leaf.csr"], dir);
  openssl(["x509", "-req", "-in", "leaf.csr", "-CA", "int.pem", "-CAkey", "int.key",
    "-CAcreateserial", "-days", "3650", "-sha256", "-out", "leaf.pem"], dir);

  const der = (f: string) => readFileSync(join(dir, f), "utf8")
    .replace(/-----BEGIN CERTIFICATE-----/g, "")
    .replace(/-----END CERTIFICATE-----/g, "")
    .replace(/\s+/g, "");

  return {
    chain: [der("leaf.pem"), der("int.pem"), der("root.pem")],
    leafKeyPem: readFileSync(join(dir, "leaf.pkcs8.pem"), "utf8"),
    rootFingerprint: new X509Certificate(readFileSync(join(dir, "root.pem"), "utf8")).fingerprint256,
    dir,
  };
}

async function sign(pki: TestPKI, claims: Record<string, unknown>): Promise<string> {
  const key = await importPKCS8(pki.leafKeyPem, "ES256");
  return new SignJWT(claims as never)
    .setProtectedHeader({ alg: "ES256", x5c: pki.chain })
    .sign(key);
}

const EXPIRES_FUTURE = 1_790_000_000_000;

function transactionClaims(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    bundleId: proEntitlementPolicy.expectedBundleID,
    productId: proEntitlementPolicy.productIDs[0],
    originalTransactionId: "2000000900000001",
    transactionId: "2000000900000002",
    purchaseDate: 1_755_000_000_000,
    expiresDate: EXPIRES_FUTURE,
    environment: "Sandbox",
    ...overrides,
  };
}

/// Build the two-layer payload Apple actually sends.
async function signNotification(
  pki: TestPKI,
  notificationType: string,
  opts: { subtype?: string; transaction?: Record<string, unknown> } = {},
): Promise<string> {
  const signedTransactionInfo = await sign(pki, transactionClaims(opts.transaction));
  return sign(pki, {
    notificationType,
    subtype: opts.subtype,
    notificationUUID: "11111111-2222-3333-4444-555555555555",
    data: { signedTransactionInfo },
  });
}

function withPKI(fn: (pki: TestPKI) => Promise<void> | void): () => Promise<void> {
  return async () => {
    const pki = buildTestPKI();
    try {
      await fn(pki);
    } finally {
      rmSync(pki.dir, { recursive: true, force: true });
    }
  };
}

// ---------------------------------------------------------------------------
// Signature verification
// ---------------------------------------------------------------------------

test("a validly signed notification verifies and exposes its transaction", withPKI(async (pki) => {
  const payload = await signNotification(pki, "DID_RENEW");
  const result = await verifyAppleNotification(payload, {
    trustedRootFingerprints: [pki.rootFingerprint],
  });

  assert.ok(result);
  assert.equal(result!.notificationType, "DID_RENEW");
  assert.equal(result!.transaction.originalTransactionId, "2000000900000001");
}));

test("production verification rejects a self-signed notification", withPKI(async (pki) => {
  const payload = await signNotification(pki, "DID_RENEW");
  // No fingerprint override: falls back to the real Apple pin.
  assert.equal(await verifyAppleNotification(payload), null);
}));

test("a notification whose inner transaction is for another app is rejected", withPKI(async (pki) => {
  const payload = await signNotification(pki, "DID_RENEW", {
    transaction: { bundleId: "com.someone.else" },
  });
  assert.equal(
    await verifyAppleNotification(payload, { trustedRootFingerprints: [pki.rootFingerprint] }),
    null,
  );
}));

test("a notification with no nested transaction is rejected", withPKI(async (pki) => {
  const payload = await sign(pki, {
    notificationType: "DID_RENEW",
    data: {},
  });
  assert.equal(
    await verifyAppleNotification(payload, { trustedRootFingerprints: [pki.rootFingerprint] }),
    null,
  );
}));

test("malformed notification input returns null instead of throwing", async () => {
  assert.equal(await verifyAppleNotification(""), null);
  assert.equal(await verifyAppleNotification("not.a.jwt"), null);
});

// ---------------------------------------------------------------------------
// Effect mapping
// ---------------------------------------------------------------------------

function notification(
  type: string,
  overrides: Partial<VerifiedAppleTransaction> = {},
  subtype: string | null = null,
): VerifiedAppleNotification {
  return {
    notificationType: type as VerifiedAppleNotification["notificationType"],
    subtype,
    notificationUUID: "uuid",
    transaction: {
      originalTransactionId: "1",
      transactionId: "2",
      productId: proEntitlementPolicy.productIDs[0],
      bundleId: proEntitlementPolicy.expectedBundleID,
      purchaseDateMs: 1_755_000_000_000,
      expiresDateMs: EXPIRES_FUTURE,
      revocationDateMs: null,
      environment: "Sandbox",
      ...overrides,
    },
  };
}

test("a renewal extends entitlement", () => {
  const effect = notificationEffect(notification("DID_RENEW"));
  assert.equal(effect.kind, "update");
  assert.equal(effect.kind === "update" && effect.status, "active");
  assert.equal(
    effect.kind === "update" && effect.expiresAt,
    new Date(EXPIRES_FUTURE).toISOString(),
  );
});

test("expiry and grace-period expiry mark the entitlement expired", () => {
  for (const type of ["EXPIRED", "GRACE_PERIOD_EXPIRED"]) {
    const effect = notificationEffect(notification(type));
    assert.equal(effect.kind === "update" && effect.status, "expired", type);
  }
});

test("a refund is treated as a revocation, not a scheduled expiry", () => {
  // The paid-for period may still be in the future; access must end anyway.
  const effect = notificationEffect(notification("REFUND"));
  assert.equal(effect.kind === "update" && effect.status, "revoked");
});

test("REVOKE marks the entitlement revoked", () => {
  const effect = notificationEffect(notification("REVOKE"));
  assert.equal(effect.kind === "update" && effect.status, "revoked");
});

/// Turning auto-renew off must NOT end access early — the user paid for the
/// current period.
test("disabling auto-renew keeps access until the period ends", () => {
  const now = new Date(1_760_000_000_000);
  const effect = notificationEffect(
    notification("DID_CHANGE_RENEWAL_STATUS", {}, "AUTO_RENEW_DISABLED"),
    now,
  );
  assert.equal(effect.kind === "update" && effect.status, "active");
});

/// A billing retry is not yet a cancellation. Apple sends EXPIRED or
/// GRACE_PERIOD_EXPIRED if it ultimately fails.
test("a failed renewal does not revoke early", () => {
  const effect = notificationEffect(notification("DID_FAIL_TO_RENEW"));
  assert.equal(effect.kind, "ignore");
});

test("an unrecognized notification type is ignored rather than guessed at", () => {
  const effect = notificationEffect(notification("CONSUMPTION_REQUEST"));
  assert.equal(effect.kind, "ignore");
});

test("the effect mapping is deterministic across repeated deliveries", () => {
  // Idempotency at the decision layer: the same input always yields the same
  // effect, so a duplicate delivery converges instead of compounding.
  const first = notificationEffect(notification("DID_RENEW"));
  const second = notificationEffect(notification("DID_RENEW"));
  assert.deepEqual(first, second);
});

// ---------------------------------------------------------------------------
// Route guarantees
// ---------------------------------------------------------------------------

test("the webhook updates but never inserts entitlement rows", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const start = server.indexOf("async function handleAppleServerNotification");
  assert.notEqual(start, -1);
  const handler = server.slice(start, server.indexOf("\nasync function recordGeminiFailure", start));

  // An insert here would let a forged delivery mint entitlement against an
  // arbitrary user.
  assert.doesNotMatch(handler, /insert\s+into/i);
  assert.match(handler, /update subscription_entitlements/);
  assert.match(handler, /where original_transaction_id = \$1/);

  // Unknown subscription: acknowledge, do not create.
  assert.match(handler, /rowCount === 0/);

  // An unverified payload must not be acknowledged with 200.
  assert.match(handler, /Notification could not be verified.*400/s);
});

test("the webhook is routed before the bearer-token gate", () => {
  const server = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const route = server.indexOf('url.pathname === "/v0/notifications/apple"');
  const authGate = server.indexOf("const userId = await resolveUserId(request)");

  assert.notEqual(route, -1);
  assert.ok(route < authGate, "Apple has no user session; the route must precede auth");
});

test("notification verification reuses the pinned chain path", () => {
  const source = readFileSync(new URL("../src/appleNotifications.ts", import.meta.url), "utf8");
  // A second, weaker verification path would undo the strength of the first.
  assert.match(source, /verifyCertificateChain/);
  assert.match(source, /APPLE_ROOT_CA_G3_SHA256/);
});
