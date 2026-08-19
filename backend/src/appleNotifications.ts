import { importX509, jwtVerify, decodeProtectedHeader, type JWTPayload } from "jose";

import {
  APPLE_ROOT_CA_G3_SHA256,
  proEntitlementPolicy,
  statusFor,
  verifyCertificateChain,
  type ProEntitlementStatus,
  type VerifiedAppleTransaction,
} from "./proEntitlement.js";

/// App Store Server Notifications v2.
///
/// Apple posts a signed payload whose `data.signedTransactionInfo` is itself a
/// signed JWS. Both layers are verified against the same pinned chain used for
/// client-submitted transactions -- deliberately reusing that path rather than
/// writing a second, weaker one.

export type AppleNotificationType =
  | "DID_RENEW"
  | "EXPIRED"
  | "DID_CHANGE_RENEWAL_STATUS"
  | "REVOKE"
  | "REFUND"
  | "GRACE_PERIOD_EXPIRED"
  | "SUBSCRIBED"
  | "DID_FAIL_TO_RENEW"
  | "OTHER";

export type VerifiedAppleNotification = {
  notificationType: AppleNotificationType;
  subtype: string | null;
  notificationUUID: string | null;
  transaction: VerifiedAppleTransaction;
};

/// How a notification should change stored entitlement state.
///
/// `ignore` is a first-class outcome: an unrecognized notification must be
/// acknowledged and dropped, never retried forever and never guessed at.
export type NotificationEffect =
  | { kind: "update"; status: ProEntitlementStatus; expiresAt: string | null }
  | { kind: "ignore"; reason: string };

/// Decide the effect without touching the database, so the mapping is testable
/// on its own.
export function notificationEffect(
  notification: VerifiedAppleNotification,
  now: Date = new Date(),
): NotificationEffect {
  const { notificationType, subtype, transaction } = notification;
  const expiresAt = transaction.expiresDateMs === null
    ? null
    : new Date(transaction.expiresDateMs).toISOString();

  switch (notificationType) {
    case "DID_RENEW":
    case "SUBSCRIBED":
      return { kind: "update", status: "active", expiresAt };

    case "EXPIRED":
    case "GRACE_PERIOD_EXPIRED":
      return { kind: "update", status: "expired", expiresAt };

    case "REVOKE":
    case "REFUND":
      // A refund is a revocation for entitlement purposes: access ends now,
      // regardless of the period the user paid for.
      return { kind: "update", status: "revoked", expiresAt };

    case "DID_CHANGE_RENEWAL_STATUS":
      // Auto-renew was turned off or back on. The user keeps what they paid
      // for until the period ends, so status is derived from the transaction
      // rather than forced.
      return { kind: "update", status: statusFor(transaction, now), expiresAt };

    case "DID_FAIL_TO_RENEW":
      // Billing retry is in progress. Apple sends EXPIRED or
      // GRACE_PERIOD_EXPIRED if it ultimately fails, so do not revoke early.
      return { kind: "ignore", reason: `billing retry in progress (${subtype ?? "no subtype"})` };

    default:
      return { kind: "ignore", reason: `unhandled notification type` };
  }
}

/// Verify Apple's signed notification payload and the transaction nested inside
/// it. Returns `null` on any failure; the caller must not act on a partially
/// trusted notification.
export async function verifyAppleNotification(
  signedPayload: string,
  options: {
    expectedBundleID?: string;
    allowedProductIDs?: readonly string[];
    trustedRootFingerprints?: readonly string[];
    now?: Date;
  } = {},
): Promise<VerifiedAppleNotification | null> {
  const now = options.now ?? new Date();
  const trustedRoots = options.trustedRootFingerprints ?? [APPLE_ROOT_CA_G3_SHA256];

  const outer = await verifySignedJWS(signedPayload, trustedRoots, now);
  if (!outer) return null;

  const data = objectField(outer.responseBodyV2DecodedPayload ?? outer.data);
  const signedTransactionInfo = data && typeof data.signedTransactionInfo === "string"
    ? data.signedTransactionInfo
    : null;
  if (!signedTransactionInfo) return null;

  const inner = await verifySignedJWS(signedTransactionInfo, trustedRoots, now);
  if (!inner) return null;

  const transaction = readTransaction(inner, {
    expectedBundleID: options.expectedBundleID ?? proEntitlementPolicy.expectedBundleID,
    allowedProductIDs: options.allowedProductIDs ?? proEntitlementPolicy.productIDs,
  });
  if (!transaction) return null;

  return {
    notificationType: normalizeType(outer.notificationType),
    subtype: stringField(outer.subtype),
    notificationUUID: stringField(outer.notificationUUID),
    transaction,
  };
}

async function verifySignedJWS(
  token: string,
  trustedRoots: readonly string[],
  now: Date,
): Promise<JWTPayload | null> {
  let header: ReturnType<typeof decodeProtectedHeader>;
  try {
    header = decodeProtectedHeader(token);
  } catch {
    return null;
  }

  const chain = Array.isArray(header.x5c) ? header.x5c : null;
  if (!chain || chain.length < 2 || !chain.every((e: unknown) => typeof e === "string" && e.length > 0)) {
    return null;
  }
  if (!verifyCertificateChain(chain, trustedRoots, now)) return null;

  try {
    const key = await importX509(derToPem(chain[0]), header.alg ?? "ES256");
    const { payload } = await jwtVerify(token, key, { currentDate: now });
    return payload;
  } catch {
    return null;
  }
}

function readTransaction(
  payload: JWTPayload,
  limits: { expectedBundleID: string; allowedProductIDs: readonly string[] },
): VerifiedAppleTransaction | null {
  const bundleId = stringField(payload.bundleId);
  const productId = stringField(payload.productId);
  const originalTransactionId = stringField(payload.originalTransactionId);
  const transactionId = stringField(payload.transactionId);

  if (!bundleId || bundleId !== limits.expectedBundleID) return null;
  if (!productId || !limits.allowedProductIDs.includes(productId)) return null;
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

const KNOWN_TYPES = new Set<AppleNotificationType>([
  "DID_RENEW",
  "EXPIRED",
  "DID_CHANGE_RENEWAL_STATUS",
  "REVOKE",
  "REFUND",
  "GRACE_PERIOD_EXPIRED",
  "SUBSCRIBED",
  "DID_FAIL_TO_RENEW",
]);

function normalizeType(value: unknown): AppleNotificationType {
  const raw = stringField(value);
  if (raw && KNOWN_TYPES.has(raw as AppleNotificationType)) {
    return raw as AppleNotificationType;
  }
  return "OTHER";
}

function objectField(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
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
