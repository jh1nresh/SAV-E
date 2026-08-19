import assert from "node:assert/strict";
import test from "node:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { X509Certificate } from "node:crypto";
import { SignJWT, importPKCS8 } from "jose";

import {
  APPLE_ROOT_CA_G3_SHA256,
  monthlyLimitUnits,
  proEntitlementPolicy,
  resolveTier,
  statusFor,
  verifyAppleSignedTransaction,
  verifyCertificateChain,
} from "./proEntitlement.js";

// ---------------------------------------------------------------------------
// Test PKI
//
// A real leaf -> intermediate -> root chain is generated so chain validation is
// actually exercised. Testing against a hand-written stub would prove nothing
// about the code path that gates paid access.
// ---------------------------------------------------------------------------

type TestPKI = {
  chain: string[];
  leafPrivateKeyPem: string;
  rootFingerprint: string;
  dir: string;
};

function openssl(args: string[], cwd: string): void {
  execFileSync("openssl", args, { cwd, stdio: "pipe" });
}

function buildTestPKI(): TestPKI {
  const dir = mkdtempSync(join(tmpdir(), "save-pki-"));

  // Root (self-signed)
  openssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "root.key"], dir);
  openssl([
    "req", "-x509", "-new", "-key", "root.key", "-sha256", "-days", "3650",
    "-subj", "/CN=Test Root CA", "-out", "root.pem",
  ], dir);

  // Intermediate, signed by root
  openssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "int.key"], dir);
  openssl(["req", "-new", "-key", "int.key", "-subj", "/CN=Test Intermediate", "-out", "int.csr"], dir);
  execFileSync("bash", ["-c",
    "printf 'basicConstraints=critical,CA:TRUE\\nkeyUsage=critical,keyCertSign\\n' > int.ext",
  ], { cwd: dir });
  openssl([
    "x509", "-req", "-in", "int.csr", "-CA", "root.pem", "-CAkey", "root.key",
    "-CAcreateserial", "-days", "3650", "-sha256", "-extfile", "int.ext", "-out", "int.pem",
  ], dir);

  // Leaf, signed by intermediate
  openssl(["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key"], dir);
  openssl(["pkcs8", "-topk8", "-nocrypt", "-in", "leaf.key", "-out", "leaf.pkcs8.pem"], dir);
  openssl(["req", "-new", "-key", "leaf.key", "-subj", "/CN=Test Leaf", "-out", "leaf.csr"], dir);
  openssl([
    "x509", "-req", "-in", "leaf.csr", "-CA", "int.pem", "-CAkey", "int.key",
    "-CAcreateserial", "-days", "3650", "-sha256", "-out", "leaf.pem",
  ], dir);

  const readDerBase64 = (pemFile: string): string => {
    const pem = execFileSync("cat", [pemFile], { cwd: dir }).toString();
    return pem
      .replace(/-----BEGIN CERTIFICATE-----/g, "")
      .replace(/-----END CERTIFICATE-----/g, "")
      .replace(/\s+/g, "");
  };

  const rootPem = execFileSync("cat", ["root.pem"], { cwd: dir }).toString();
  const rootFingerprint = new X509Certificate(rootPem).fingerprint256;

  return {
    chain: [readDerBase64("leaf.pem"), readDerBase64("int.pem"), readDerBase64("root.pem")],
    leafPrivateKeyPem: execFileSync("cat", ["leaf.pkcs8.pem"], { cwd: dir }).toString(),
    rootFingerprint,
    dir,
  };
}

async function signTransaction(
  pki: TestPKI,
  claims: Record<string, unknown>,
  chainOverride?: string[],
): Promise<string> {
  const key = await importPKCS8(pki.leafPrivateKeyPem, "ES256");
  return new SignJWT(claims as never)
    .setProtectedHeader({ alg: "ES256", x5c: chainOverride ?? pki.chain })
    .sign(key);
}

function validClaims(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    bundleId: proEntitlementPolicy.expectedBundleID,
    productId: proEntitlementPolicy.productIDs[0],
    originalTransactionId: "2000000900000001",
    transactionId: "2000000900000002",
    purchaseDate: 1_755_000_000_000,
    expiresDate: 1_790_000_000_000,
    environment: "Sandbox",
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// Pinned anchor
// ---------------------------------------------------------------------------

test("the pinned Apple root fingerprint is the documented Apple Root CA - G3 value", () => {
  // Verified against https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
  assert.equal(
    APPLE_ROOT_CA_G3_SHA256.replace(/:/g, ""),
    "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179".toUpperCase(),
  );
});

test("production verification does not trust a self-signed chain", async () => {
  const pki = buildTestPKI();
  try {
    const token = await signTransaction(pki, validClaims());
    // No trustedRootFingerprints override: falls back to the real Apple pin.
    const result = await verifyAppleSignedTransaction(token);
    assert.equal(result, null, "a non-Apple chain must never grant entitlement");
  } finally {
    rmSync(pki.dir, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// Chain validation
// ---------------------------------------------------------------------------

test("a well-formed chain validates against its own pinned root", () => {
  const pki = buildTestPKI();
  try {
    assert.equal(verifyCertificateChain(pki.chain, [pki.rootFingerprint]), true);
  } finally {
    rmSync(pki.dir, { recursive: true, force: true });
  }
});

test("a chain whose root is not pinned is rejected", () => {
  const pki = buildTestPKI();
  try {
    assert.equal(verifyCertificateChain(pki.chain, [APPLE_ROOT_CA_G3_SHA256]), false);
  } finally {
    rmSync(pki.dir, { recursive: true, force: true });
  }
});

test("a chain with the intermediate removed is rejected", () => {
  const pki = buildTestPKI();
  try {
    const broken = [pki.chain[0], pki.chain[2]];
    assert.equal(verifyCertificateChain(broken, [pki.rootFingerprint]), false);
  } finally {
    rmSync(pki.dir, { recursive: true, force: true });
  }
});

test("garbage certificate data is rejected rather than throwing", () => {
  assert.equal(verifyCertificateChain(["not-a-cert", "also-not"], [APPLE_ROOT_CA_G3_SHA256]), false);
});

// ---------------------------------------------------------------------------
// Transaction verification
// ---------------------------------------------------------------------------

test("a correctly signed transaction on a pinned chain verifies", async () => {
  const pki = buildTestPKI();
  try {
    const token = await signTransaction(pki, validClaims());
    const result = await verifyAppleSignedTransaction(token, {
      trustedRootFingerprints: [pki.rootFingerprint],
    });
    assert.ok(result);
    assert.equal(result!.originalTransactionId, "2000000900000001");
    assert.equal(result!.productId, proEntitlementPolicy.productIDs[0]);
    assert.equal(result!.environment, "Sandbox");
  } finally {
    rmSync(pki.dir, { recursive: true, force: true });
  }
});

test("a transaction for another app is rejected", async () => {
  const pki = buildTestPKI();
  try {
    const token = await signTransaction(pki, validClaims({ bundleId: "com.someone.else" }));
    const result = await verifyAppleSignedTransaction(token, {
      trustedRootFingerprints: [pki.rootFingerprint],
    });
    assert.equal(result, null);
  } finally {
    rmSync(pki.dir, { recursive: true, force: true });
  }
});

test("a transaction for an unknown product is rejected", async () => {
  const pki = buildTestPKI();
  try {
    const token = await signTransaction(pki, validClaims({ productId: "com.wanderly.app.pro.lifetime" }));
    const result = await verifyAppleSignedTransaction(token, {
      trustedRootFingerprints: [pki.rootFingerprint],
    });
    assert.equal(result, null);
  } finally {
    rmSync(pki.dir, { recursive: true, force: true });
  }
});

test("a tampered payload fails signature verification", async () => {
  const pki = buildTestPKI();
  try {
    const token = await signTransaction(pki, validClaims());
    const [header, , signature] = token.split(".");
    const forged = Buffer.from(
      JSON.stringify(validClaims({ originalTransactionId: "9999999999999999" })),
    ).toString("base64url");
    const tampered = `${header}.${forged}.${signature}`;

    const result = await verifyAppleSignedTransaction(tampered, {
      trustedRootFingerprints: [pki.rootFingerprint],
    });
    assert.equal(result, null);
  } finally {
    rmSync(pki.dir, { recursive: true, force: true });
  }
});

test("malformed input returns null instead of throwing", async () => {
  assert.equal(await verifyAppleSignedTransaction(""), null);
  assert.equal(await verifyAppleSignedTransaction("not.a.jwt"), null);
});

// ---------------------------------------------------------------------------
// Tier resolution
// ---------------------------------------------------------------------------

test("tier resolution is time-based and defaults to free", () => {
  const now = new Date("2026-08-19T00:00:00Z");

  assert.equal(resolveTier(undefined, now), "free");
  assert.equal(resolveTier({ status: "none", expires_at: null }, now), "free");
  assert.equal(resolveTier({ status: "revoked", expires_at: "2027-01-01T00:00:00Z" }, now), "free");

  // Active but already past its expiry: a missed renewal notification must not
  // keep someone Pro forever.
  assert.equal(resolveTier({ status: "active", expires_at: "2026-08-18T00:00:00Z" }, now), "free");

  assert.equal(resolveTier({ status: "active", expires_at: "2026-09-19T00:00:00Z" }, now), "pro");
  assert.equal(resolveTier({ status: "active", expires_at: null }, now), "pro");
});

test("status reflects revocation before expiry", () => {
  const now = new Date("2026-08-19T00:00:00Z");
  const base = {
    originalTransactionId: "1",
    transactionId: "2",
    productId: proEntitlementPolicy.productIDs[0],
    bundleId: proEntitlementPolicy.expectedBundleID,
    purchaseDateMs: 1_700_000_000_000,
    environment: "Production",
  };

  assert.equal(statusFor({ ...base, expiresDateMs: null, revocationDateMs: 1 }, now), "revoked");
  assert.equal(
    statusFor({ ...base, expiresDateMs: now.getTime() - 1, revocationDateMs: null }, now),
    "expired",
  );
  assert.equal(
    statusFor({ ...base, expiresDateMs: now.getTime() + 86_400_000, revocationDateMs: null }, now),
    "active",
  );
});

test("allowance is tier-dependent", () => {
  assert.equal(monthlyLimitUnits("free"), proEntitlementPolicy.freeMonthlyLimitUnits);
  assert.equal(monthlyLimitUnits("pro"), proEntitlementPolicy.proMonthlyLimitUnits);
  assert.ok(monthlyLimitUnits("pro") > monthlyLimitUnits("free"));
});
