import { X509Certificate } from "node:crypto";
import { importX509, jwtVerify, decodeProtectedHeader, type JWTPayload } from "jose";

/// SHA-256 fingerprint of Apple Root CA - G3, the anchor for App Store Server
/// API signed data.
///
/// Pinning the fingerprint is what makes chain validation meaningful: without
/// it, any self-signed chain with a well-formed payload would be accepted and
/// anyone could mint themselves a Pro entitlement.
export const APPLE_ROOT_CA_G3_SHA256 =
  "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79";

export const proEntitlementPolicy = {
  policyVersion: "pro-entitlement-v0",
  /// Monthly AI-assist allowance by tier. The free number is inherited from
  /// `betaUsageQuotaPolicy` and is still an unvalidated placeholder; the Pro
  /// number is generous because the real cost ceiling is the subscription
  /// price, not the unit count.
  freeMonthlyLimitUnits: 20,
  proMonthlyLimitUnits: 500,
  /// A transaction signed for a different app is not evidence about this user.
  expectedBundleID: "com.wanderly.app",
  productIDs: ["com.wanderly.app.pro.annual", "com.wanderly.app.pro.monthly"],
} as const;

export type ProEntitlementStatus = "active" | "expired" | "revoked" | "none";

export type VerifiedAppleTransaction = {
  originalTransactionId: string;
  transactionId: string;
  productId: string;
  bundleId: string;
  purchaseDateMs: number;
  expiresDateMs: number | null;
  revocationDateMs: number | null;
  environment: string;
};

/// Resolve tier from stored entitlement state.
///
/// Deliberately time-based rather than trusting a stored boolean: a renewal or
/// cancellation notification can be missed, but an expiry timestamp cannot lie.
export function resolveTier(
  row: { status: ProEntitlementStatus; expires_at: string | null } | undefined,
  now: Date = new Date(),
): "free" | "pro" {
  if (!row) return "free";
  if (row.status === "revoked") return "free";
  if (row.expires_at) {
    const expiresMs = Date.parse(row.expires_at);
    if (Number.isFinite(expiresMs) && expiresMs <= now.getTime()) return "free";
  }
  return row.status === "active" ? "pro" : "free";
}

export function monthlyLimitUnits(tier: "free" | "pro"): number {
  return tier === "pro"
    ? proEntitlementPolicy.proMonthlyLimitUnits
    : proEntitlementPolicy.freeMonthlyLimitUnits;
}

/// Verify a StoreKit 2 signed transaction (JWS carrying an x5c chain).
///
/// Fails closed at every step. A malformed chain, broken signature, unpinned
/// root, wrong bundle ID, or unexpected product yields `null` rather than a
/// partially trusted result: granting Pro incorrectly is worse than making a
/// legitimate buyer press Restore.
export async function verifyAppleSignedTransaction(
  signedTransaction: string,
  options: {
    expectedBundleID?: string;
    allowedProductIDs?: readonly string[];
    /// Overridable so tests can pin their own generated root. Production must
    /// leave this alone.
    trustedRootFingerprints?: readonly string[];
    now?: Date;
  } = {},
): Promise<VerifiedAppleTransaction | null> {
  const expectedBundleID = options.expectedBundleID ?? proEntitlementPolicy.expectedBundleID;
  const allowedProductIDs = options.allowedProductIDs ?? proEntitlementPolicy.productIDs;
  const trustedRoots = options.trustedRootFingerprints ?? [APPLE_ROOT_CA_G3_SHA256];
  const now = options.now ?? new Date();

  let header: ReturnType<typeof decodeProtectedHeader>;
  try {
    header = decodeProtectedHeader(signedTransaction);
  } catch {
    return null;
  }

  const chain = Array.isArray(header.x5c) ? header.x5c : null;
  // Apple sends leaf -> intermediate -> root.
  if (!chain || chain.length < 2 || !chain.every((e: unknown) => typeof e === "string" && e.length > 0)) {
    return null;
  }

  if (!verifyCertificateChain(chain, trustedRoots, now)) return null;

  let payload: JWTPayload;
  try {
    const key = await importX509(derToPem(chain[0]), header.alg ?? "ES256");
    const verified = await jwtVerify(signedTransaction, key, { currentDate: now });
    payload = verified.payload;
  } catch {
    return null;
  }

  const bundleId = stringField(payload.bundleId);
  const productId = stringField(payload.productId);
  const originalTransactionId = stringField(payload.originalTransactionId);
  const transactionId = stringField(payload.transactionId);

  if (!bundleId || bundleId !== expectedBundleID) return null;
  if (!productId || !allowedProductIDs.includes(productId)) return null;
  if (!originalTransactionId || !transactionId) return null;

  const purchaseDateMs = numberField(payload.purchaseDate);
  if (purchaseDateMs === null) return null;

  return {
    originalTransactionId,
    transactionId,
    productId,
    bundleId,
    purchaseDateMs,
    expiresDateMs: numberField(payload.expiresDate),
    revocationDateMs: numberField(payload.revocationDate),
    environment: stringField(payload.environment) ?? "Production",
  };
}

export function statusFor(
  transaction: VerifiedAppleTransaction,
  now: Date = new Date(),
): ProEntitlementStatus {
  if (transaction.revocationDateMs !== null) return "revoked";
  if (transaction.expiresDateMs !== null && transaction.expiresDateMs <= now.getTime()) {
    return "expired";
  }
  return "active";
}

/// Walk leaf -> intermediate -> root, verifying each signature and validity
/// window, then require the root's fingerprint to be pinned.
export function verifyCertificateChain(
  chain: readonly string[],
  trustedRootFingerprints: readonly string[],
  now: Date = new Date(),
): boolean {
  let certs: X509Certificate[];
  try {
    certs = chain.map((der) => new X509Certificate(Buffer.from(der, "base64")));
  } catch {
    return false;
  }

  for (const cert of certs) {
    const from = Date.parse(cert.validFrom);
    const to = Date.parse(cert.validTo);
    if (!Number.isFinite(from) || !Number.isFinite(to)) return false;
    if (now.getTime() < from || now.getTime() > to) return false;
  }

  // Each certificate must be issued and signed by the next one up.
  for (let i = 0; i < certs.length - 1; i += 1) {
    const child = certs[i];
    const parent = certs[i + 1];
    if (!child.checkIssued(parent)) return false;
    if (!child.verify(parent.publicKey)) return false;
  }

  const root = certs[certs.length - 1];
  // The anchor must be self-signed and pinned. Either check alone is
  // insufficient: self-signed proves structure, the fingerprint proves identity.
  if (!root.verify(root.publicKey)) return false;

  const normalized = normalizeFingerprint(root.fingerprint256);
  return trustedRootFingerprints.some((expected) => normalizeFingerprint(expected) === normalized);
}

function normalizeFingerprint(value: string): string {
  return value.replace(/:/g, "").trim().toUpperCase();
}

function derToPem(der: string): string {
  const lines = der.match(/.{1,64}/g)?.join("\n") ?? der;
  return `-----BEGIN CERTIFICATE-----\n${lines}\n-----END CERTIFICATE-----\n`;
}

function stringField(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function numberField(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.trunc(parsed);
  }
  return null;
}
