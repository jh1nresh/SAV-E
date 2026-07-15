import { createHmac } from "node:crypto";

export type FriendShareEventBody = Record<string, unknown>;

export const friendShareEventTypes = [
  "friend_share_link_created",
  "friend_share_receipt_opened",
  "friend_share_save_tapped",
  "friend_share_saved",
  "friend_share_duplicate_blocked",
  "friend_share_open_failed",
] as const;

export type FriendShareEventType = typeof friendShareEventTypes[number];

export const friendShareClientEventTypes = [
  "friend_share_receipt_opened",
  "friend_share_save_tapped",
  "friend_share_open_failed",
] as const satisfies readonly FriendShareEventType[];

export const friendSharePublicEventTypes = [
  "friend_share_receipt_opened",
  "friend_share_open_failed",
] as const satisfies readonly FriendShareEventType[];

export const friendShareVerifiedCohortPredicate = "link.source_verified_at is not null";

export const friendSharePlaceOriginConflictClause = `on conflict (user_id, origin_shared_place_link_id)
where origin_shared_place_link_id is not null
do update set origin_shared_place_link_id = excluded.origin_shared_place_link_id`;

export const friendShareSurfaces = ["web", "ios", "app_clip"] as const;
export type FriendShareSurface = typeof friendShareSurfaces[number];

export const friendShareOpenFailureReasons = [
  "expired",
  "malformed_payload",
  "network_error",
  "server_error",
  "unsupported_route",
  "unknown",
] as const;
export type FriendShareOpenFailureReason = typeof friendShareOpenFailureReasons[number];

export interface FriendShareClientEvent {
  eventType: typeof friendShareClientEventTypes[number];
  surface: FriendShareSurface;
  reasonCode: FriendShareOpenFailureReason | null;
  recipientPlaceId: string | null;
}

export type FriendShareExpiryDisposition = "accept" | "link_expired" | "reason_mismatch";

export interface FriendShareRecipientMetricsRow {
  link_id: string;
  recipient_user_id: string;
  receipt_opened: number | string;
  save_tapped: number | string;
  saved: number | string;
  duplicate_blocked: number | string;
  open_failed: number | string;
  last_activity_at: Date | string;
}

export interface FriendShareShareMetricsRow {
  link_id: string;
  sender_user_id: string;
  events_total: number | string;
  receipt_opened: number | string;
  save_tapped: number | string;
  saved: number | string;
  duplicate_blocked: number | string;
  open_failed: number | string;
  identified_recipient_sessions: number | string;
  account_recipient_users: number | string;
  guest_recipient_sessions: number | string;
  account_recipient_users_succeeded: number | string;
  guest_recipient_sessions_succeeded: number | string;
  account_recipient_users_open_failed: number | string;
  guest_recipient_sessions_open_failed: number | string;
  anonymous_events: number | string;
  last_activity_at: Date | string;
}

export type FriendShareOpaqueRefScope = "share" | "sender" | "recipient";

export function friendShareCodeFromPlaceCreate(body: FriendShareEventBody): string | undefined {
  const snakePresent = Object.hasOwn(body, "friend_share_code");
  const camelPresent = Object.hasOwn(body, "friendShareCode");
  const snakeCode = optionalString(body.friend_share_code);
  const camelCode = optionalString(body.friendShareCode);

  if (snakePresent && body.friend_share_code !== null && snakeCode === undefined) {
    throw new Error("friend_share_code must be a string");
  }
  if (camelPresent && body.friendShareCode !== null && camelCode === undefined) {
    throw new Error("friendShareCode must be a string");
  }
  if (snakeCode && camelCode && snakeCode !== camelCode) {
    throw new Error("friend_share_code and friendShareCode must match");
  }

  const code = snakeCode ?? camelCode;
  if (code && !friendShareCodePattern.test(code)) {
    throw new Error("friend_share_code is invalid");
  }
  return code;
}

export function friendShareExclusiveOpenFailurePredicate(
  eventAlias: string,
  terminalAlias: string,
  window?: { startsAt: string; endsAt: string },
): string {
  const windowPredicate = window
    ? `\n    and ${terminalAlias}.created_at >= ${window.startsAt}\n    and ${terminalAlias}.created_at <= ${window.endsAt}`
    : "";
  return `${eventAlias}.event_type = 'friend_share_open_failed'
  and ${eventAlias}.recipient_user_id is not null
  and not exists (
    select 1
    from friend_share_events ${terminalAlias}
    where ${terminalAlias}.shared_place_link_id = ${eventAlias}.shared_place_link_id
      and ${terminalAlias}.recipient_user_id = ${eventAlias}.recipient_user_id
      and ${terminalAlias}.event_type in ('friend_share_saved', 'friend_share_duplicate_blocked')${windowPredicate}
  )`;
}

export function normalizeFriendShareClientEvent(
  body: FriendShareEventBody,
  access: "public" | "authenticated",
): FriendShareClientEvent {
  const allowedFields = new Set([
    "event_type",
    "eventType",
    "surface",
    "reason_code",
    "reasonCode",
    ...(access === "authenticated" ? ["code", "recipient_place_id", "recipientPlaceId"] : []),
  ]);
  const unexpectedField = Object.keys(body).find((key) => !allowedFields.has(key));
  if (unexpectedField) throw new Error(`Unexpected friend share event field: ${unexpectedField}`);

  const eventType = stringValue(body.event_type ?? body.eventType);
  const allowedTypes: readonly string[] = access === "public"
    ? friendSharePublicEventTypes
    : friendShareClientEventTypes;
  if (!eventType || !allowedTypes.includes(eventType)) {
    throw new Error(`event_type is not allowed for ${access} friend share events`);
  }

  const surface = stringValue(body.surface);
  if (!surface || !friendShareSurfaces.includes(surface as FriendShareSurface)) {
    throw new Error("surface must be web, ios, or app_clip");
  }

  const reasonCode = stringValue(body.reason_code ?? body.reasonCode);
  if (eventType === "friend_share_open_failed") {
    if (!reasonCode || !friendShareOpenFailureReasons.includes(reasonCode as FriendShareOpenFailureReason)) {
      throw new Error("reason_code is required for friend_share_open_failed");
    }
  } else if (reasonCode) {
    throw new Error("reason_code is only allowed for friend_share_open_failed");
  }

  const hasRecipientPlaceId = Object.hasOwn(body, "recipient_place_id")
    || Object.hasOwn(body, "recipientPlaceId");
  if (hasRecipientPlaceId) {
    throw new Error("recipient_place_id is not allowed for client-authored events");
  }

  return {
    eventType: eventType as FriendShareClientEvent["eventType"],
    surface: surface as FriendShareSurface,
    reasonCode: reasonCode ? reasonCode as FriendShareOpenFailureReason : null,
    recipientPlaceId: null,
  };
}

export function friendShareEventExpiryDisposition(
  event: FriendShareClientEvent,
  linkExpired: boolean,
): FriendShareExpiryDisposition {
  if (event.reasonCode === "expired" && !linkExpired) return "reason_mismatch";
  if (linkExpired && event.eventType !== "friend_share_open_failed") return "link_expired";
  return "accept";
}

export function friendShareEventSummary(rows: FriendShareEventBody[]): FriendShareEventBody {
  const counts = Object.fromEntries(friendShareEventTypes.map((eventType) => [eventType, 0])) as Record<FriendShareEventType, number>;
  const observedRecipients = new Set<string>();
  const accountRecipients = new Set<string>();
  const guestRecipients = new Set<string>();
  const savedRecipients = new Set<string>();
  const duplicateRecipients = new Set<string>();
  const failedRecipients = new Set<string>();
  let anonymousEvents = 0;

  for (const row of rows) {
    const eventType = stringValue(row.event_type) as FriendShareEventType | undefined;
    if (!eventType || !friendShareEventTypes.includes(eventType)) continue;
    counts[eventType] += 1;

    const recipientId = stringValue(row.recipient_user_id);
    if (!recipientId) {
      anonymousEvents += 1;
      continue;
    }
    observedRecipients.add(recipientId);
    (isGuestRecipientId(recipientId) ? guestRecipients : accountRecipients).add(recipientId);
    if (eventType === "friend_share_saved") savedRecipients.add(recipientId);
    if (eventType === "friend_share_duplicate_blocked") duplicateRecipients.add(recipientId);
    if (eventType === "friend_share_open_failed") failedRecipients.add(recipientId);
  }

  for (const recipientId of savedRecipients) failedRecipients.delete(recipientId);
  for (const recipientId of duplicateRecipients) failedRecipients.delete(recipientId);

  return {
    counts,
    identified_recipient_sessions: observedRecipients.size,
    account_recipient_users: accountRecipients.size,
    guest_recipient_sessions: guestRecipients.size,
    identified_recipient_sessions_saved: savedRecipients.size,
    identified_recipient_sessions_duplicate_blocked: duplicateRecipients.size,
    identified_recipient_sessions_open_failed: failedRecipients.size,
    anonymous_events: anonymousEvents,
  };
}

export function friendShareRecipientMetrics(
  rows: FriendShareRecipientMetricsRow[],
  token: string,
): FriendShareEventBody[] {
  return rows.map((row) => {
    const saved = count(row.saved);
    const duplicateBlocked = count(row.duplicate_blocked);
    const succeeded = saved > 0 || duplicateBlocked > 0;
    const openFailed = succeeded ? 0 : count(row.open_failed);
    const outcome = succeeded
      ? "success"
      : openFailed > 0
        ? "failure"
        : "unresolved";

    return {
      share_ref: friendShareOpaqueRef("share", row.link_id, token),
      recipient_ref: friendShareOpaqueRef("recipient", row.recipient_user_id, token),
      identity_kind: isGuestRecipientId(row.recipient_user_id) ? "guest" : "account",
      receipt_opened: count(row.receipt_opened),
      save_tapped: count(row.save_tapped),
      saved,
      duplicate_blocked: duplicateBlocked,
      open_failed: openFailed,
      outcome,
      last_activity_date: new Date(row.last_activity_at).toISOString().slice(0, 10),
    };
  });
}

export function friendShareShareMetrics(
  rows: FriendShareShareMetricsRow[],
  token: string,
): FriendShareEventBody[] {
  return rows.map((row) => ({
    share_ref: friendShareOpaqueRef("share", row.link_id, token),
    sender_ref: friendShareOpaqueRef("sender", row.sender_user_id, token),
    events_total: count(row.events_total),
    receipt_opened: count(row.receipt_opened),
    save_tapped: count(row.save_tapped),
    saved: count(row.saved),
    duplicate_blocked: count(row.duplicate_blocked),
    open_failed: count(row.open_failed),
    identified_recipient_sessions: count(row.identified_recipient_sessions),
    account_recipient_users: count(row.account_recipient_users),
    guest_recipient_sessions: count(row.guest_recipient_sessions),
    account_recipient_users_succeeded: count(row.account_recipient_users_succeeded),
    guest_recipient_sessions_succeeded: count(row.guest_recipient_sessions_succeeded),
    account_recipient_users_open_failed: count(row.account_recipient_users_open_failed),
    guest_recipient_sessions_open_failed: count(row.guest_recipient_sessions_open_failed),
    anonymous_events: count(row.anonymous_events),
    last_activity_date: new Date(row.last_activity_at).toISOString().slice(0, 10),
  }));
}

export function friendShareOpaqueRef(
  scope: FriendShareOpaqueRefScope,
  rawId: string,
  token: string,
): string {
  return `save_friend_${scope}_${createHmac("sha256", token)
    .update(`friend-share-${scope}-ref:v0\0`)
    .update(rawId)
    .digest("base64url")
    .slice(0, 22)}`;
}

export function recipientPlaceMatchesSharedPayload(
  recipientPlace: FriendShareEventBody,
  sharedPayloadValue: unknown,
): boolean {
  const sharedPayload = objectValue(sharedPayloadValue);
  if (!sharedPayload) return false;

  const recipientName = normalizedComparableText(recipientPlace.name);
  const sharedName = normalizedComparableText(sharedPayload.name);
  if (!recipientName || !sharedName || recipientName !== sharedName) return false;

  const recipientAddress = normalizedComparableText(recipientPlace.address);
  const sharedAddress = normalizedComparableText(sharedPayload.address);
  if (recipientAddress && sharedAddress && recipientAddress === sharedAddress) return true;

  return coordinatesWithinMeters(
    recipientPlace.latitude,
    recipientPlace.longitude,
    sharedPayload.lat,
    sharedPayload.lng,
    250,
  );
}

export function isSelfFriendShareRecipient(senderUserId: unknown, recipientUserId: unknown): boolean {
  const sender = stringValue(senderUserId);
  const recipient = stringValue(recipientUserId);
  return Boolean(sender && recipient && sender === recipient);
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}

function optionalString(value: unknown): string | undefined {
  if (value === undefined || value === null) return undefined;
  return stringValue(value);
}

const friendShareCodePattern = /^[A-Za-z0-9_-]{6,32}$/;

function objectValue(value: unknown): FriendShareEventBody | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as FriendShareEventBody
    : undefined;
}

function normalizedComparableText(value: unknown): string | undefined {
  const text = stringValue(value);
  if (!text) return undefined;
  const normalized = text.normalize("NFKC").toLocaleLowerCase("en-US").replace(/[\p{P}\p{S}\s]+/gu, "");
  return normalized || undefined;
}

function coordinatesWithinMeters(
  leftLatitudeValue: unknown,
  leftLongitudeValue: unknown,
  rightLatitudeValue: unknown,
  rightLongitudeValue: unknown,
  maxMeters: number,
): boolean {
  const leftLatitude = finiteCoordinate(leftLatitudeValue, 90);
  const leftLongitude = finiteCoordinate(leftLongitudeValue, 180);
  const rightLatitude = finiteCoordinate(rightLatitudeValue, 90);
  const rightLongitude = finiteCoordinate(rightLongitudeValue, 180);
  if (
    leftLatitude === undefined
    || leftLongitude === undefined
    || rightLatitude === undefined
    || rightLongitude === undefined
  ) return false;

  const radians = Math.PI / 180;
  const latitudeDelta = (rightLatitude - leftLatitude) * radians;
  const longitudeDelta = (rightLongitude - leftLongitude) * radians;
  const a = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(leftLatitude * radians)
      * Math.cos(rightLatitude * radians)
      * Math.sin(longitudeDelta / 2) ** 2;
  const distance = 2 * 6_371_000 * Math.asin(Math.min(1, Math.sqrt(a)));
  return distance <= maxMeters;
}

function finiteCoordinate(value: unknown, bound: number): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= bound
    ? value
    : undefined;
}

function count(value: number | string): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.trunc(parsed) : 0;
}

function isGuestRecipientId(recipientId: string): boolean {
  return recipientId.startsWith("guest_");
}
