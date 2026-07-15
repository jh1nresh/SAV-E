import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  friendShareCodeFromPlaceCreate,
  friendShareEventSummary,
  friendShareEventExpiryDisposition,
  friendShareExclusiveOpenFailurePredicate,
  friendShareOpaqueRef,
  friendSharePlaceOriginConflictClause,
  friendShareRecipientMetrics,
  friendShareShareMetrics,
  friendShareVerifiedCohortPredicate,
  isSelfFriendShareRecipient,
  normalizeFriendShareClientEvent,
  recipientPlaceMatchesSharedPayload,
} from "./friendShareEvents.js";

test("receipt place creates accept one bounded snake or camel short code", () => {
  assert.equal(friendShareCodeFromPlaceCreate({ friend_share_code: "AbC123_x" }), "AbC123_x");
  assert.equal(friendShareCodeFromPlaceCreate({ friendShareCode: "AbC123_x" }), "AbC123_x");
  assert.equal(friendShareCodeFromPlaceCreate({
    friend_share_code: "AbC123_x",
    friendShareCode: "AbC123_x",
  }), "AbC123_x");
  assert.equal(friendShareCodeFromPlaceCreate({ friend_share_code: null }), undefined);
  assert.throws(
    () => friendShareCodeFromPlaceCreate({ friend_share_code: 123 }),
    /must be a string/,
  );
  assert.throws(
    () => friendShareCodeFromPlaceCreate({ friend_share_code: "bad", friendShareCode: "Different1" }),
    /must match/,
  );
  assert.throws(
    () => friendShareCodeFromPlaceCreate({ friend_share_code: "bad!" }),
    /invalid/,
  );
});

test("public friend share events accept only bounded open receipts", () => {
  assert.deepEqual(normalizeFriendShareClientEvent({
    event_type: "friend_share_receipt_opened",
    surface: "web",
  }, "public"), {
    eventType: "friend_share_receipt_opened",
    surface: "web",
    reasonCode: null,
    recipientPlaceId: null,
  });

  assert.throws(() => normalizeFriendShareClientEvent({
    event_type: "friend_share_saved",
    surface: "web",
  }, "public"), /not allowed/);
  assert.throws(() => normalizeFriendShareClientEvent({
    event_type: "friend_share_link_created",
    surface: "ios",
  }, "authenticated"), /not allowed/);
  assert.throws(() => normalizeFriendShareClientEvent({
    event_type: "friend_share_receipt_opened",
    surface: "web",
    recipient_place_id: "550e8400-e29b-41d4-a716-446655440000",
  }, "public"), /Unexpected/);
});

test("friend share failures require bounded reasons and reject arbitrary payload fields", () => {
  assert.throws(() => normalizeFriendShareClientEvent({
    event_type: "friend_share_open_failed",
    surface: "app_clip",
    reason_code: "expired",
    note: "must not be stored",
    latitude: 25.033,
    longitude: 121.565,
  }, "public"), /Unexpected/);

  assert.deepEqual(normalizeFriendShareClientEvent({
    event_type: "friend_share_open_failed",
    surface: "app_clip",
    reason_code: "expired",
  }, "public"), {
    eventType: "friend_share_open_failed",
    surface: "app_clip",
    reasonCode: "expired",
    recipientPlaceId: null,
  });

  assert.throws(() => normalizeFriendShareClientEvent({
    event_type: "friend_share_open_failed",
    surface: "web",
    reason_code: "raw network stack trace",
  }, "authenticated"), /reason_code/);
  assert.throws(() => normalizeFriendShareClientEvent({
    event_type: "friend_share_saved",
    surface: "ios",
    reason_code: "unknown",
  }, "authenticated"), /not allowed/);
});

test("client-authored terminal events are rejected", () => {
  const recipientPlaceId = "550e8400-e29b-41d4-a716-446655440000";

  assert.throws(() => normalizeFriendShareClientEvent({
    code: "AbC123_x",
    event_type: "friend_share_saved",
    surface: "web",
    recipient_place_id: recipientPlaceId,
  }, "authenticated"), /not allowed/);
  assert.throws(() => normalizeFriendShareClientEvent({
    code: "AbC123_x",
    event_type: "friend_share_duplicate_blocked",
    surface: "web",
    recipient_place_id: recipientPlaceId,
  }, "authenticated"), /not allowed/);
  assert.throws(() => normalizeFriendShareClientEvent({
    code: "AbC123_x",
    event_type: "friend_share_save_tapped",
    surface: "web",
    recipient_place_id: recipientPlaceId,
  }, "authenticated"), /not allowed/);
});

test("authenticated expired failures are recordable while live mismatches and expired actions fail", () => {
  const expiredFailure = normalizeFriendShareClientEvent({
    code: "AbC123_x",
    event_type: "friend_share_open_failed",
    surface: "web",
    reason_code: "expired",
  }, "authenticated");
  const opened = normalizeFriendShareClientEvent({
    code: "AbC123_x",
    event_type: "friend_share_receipt_opened",
    surface: "web",
  }, "authenticated");
  const saveTapped = normalizeFriendShareClientEvent({
    code: "AbC123_x",
    event_type: "friend_share_save_tapped",
    surface: "web",
  }, "authenticated");

  assert.equal(friendShareEventExpiryDisposition(expiredFailure, true), "accept");
  assert.equal(friendShareEventExpiryDisposition(expiredFailure, false), "reason_mismatch");
  assert.equal(friendShareEventExpiryDisposition(opened, true), "link_expired");
  assert.equal(friendShareEventExpiryDisposition(saveTapped, true), "link_expired");
});

test("share owners cannot be counted as their own recipients", () => {
  assert.equal(isSelfFriendShareRecipient("account-owner", "account-owner"), true);
  assert.equal(isSelfFriendShareRecipient("account-owner", "account-friend"), false);
  assert.equal(isSelfFriendShareRecipient("account-owner", null), false);
});

test("recipient terminal receipts must match the shared place deterministically", () => {
  const shared = {
    name: "A Cheng Goose 阿城鵝肉",
    address: "No. 105, Jilin Rd, Taipei",
    lat: 25.055,
    lng: 121.533,
    sourceURL: "https://www.instagram.com/reel/example/?utm_source=share&igsh=tracking",
  };

  assert.equal(recipientPlaceMatchesSharedPayload({
    name: "Unrelated local label",
    address: "Elsewhere",
    latitude: 0,
    longitude: 0,
    source_url: "https://www.instagram.com/reel/example/",
  }, shared), false, "source URL alone cannot assert place identity");
  assert.equal(recipientPlaceMatchesSharedPayload({
    name: "A Cheng Goose 阿城鵝肉",
    address: "Different transcription",
    latitude: 25.0555,
    longitude: 121.5335,
    source_url: null,
  }, shared), true, "same name and nearby coordinates match");
  assert.equal(recipientPlaceMatchesSharedPayload({
    name: "A Cheng Goose - 阿城鵝肉",
    address: "No. 105, Jilin Rd, Taipei",
    latitude: 35,
    longitude: -118,
    source_url: null,
  }, shared), true, "same normalized name and address match");
  assert.equal(recipientPlaceMatchesSharedPayload({
    name: "A Cheng Goose 阿城鵝肉",
    address: "Unrelated address",
    latitude: 25.5,
    longitude: 121.9,
    source_url: "https://example.com/unrelated",
  }, shared), false, "same name alone cannot assert success");
});

test("an owned source id cannot verify an unrelated shared payload", () => {
  const ownedSource = {
    name: "Kato",
    address: "777 S Alameda St, Los Angeles, CA",
    latitude: 34.04,
    longitude: -118.23,
    source_url: "https://www.instagram.com/reel/kato/",
  };

  assert.equal(recipientPlaceMatchesSharedPayload(ownedSource, {
    name: "Kato",
    address: "777 S Alameda St, Los Angeles, CA",
    lat: 34.04,
    lng: -118.23,
    sourceURL: "https://www.instagram.com/reel/kato/?utm_source=share",
  }), true);
  assert.equal(recipientPlaceMatchesSharedPayload(ownedSource, {
    name: "Unrelated Restaurant",
    address: "Another city",
    lat: 40.7,
    lng: -74,
    sourceURL: "https://example.com/unrelated",
  }), false);
});

test("terminal receipt schema is idempotent and deduplicates exact authenticated outcomes", () => {
  const schema = readFileSync(new URL("../sql/schema.sql", import.meta.url), "utf8");

  assert.match(schema, /add column if not exists recipient_place_id uuid references places\(id\)/i);
  assert.match(schema, /create unique index if not exists idx_friend_share_events_terminal_receipt_unique/i);
  assert.match(schema, /shared_place_link_id, recipient_user_id, recipient_place_id/i);
  assert.match(schema, /friend_share_events_terminal_surface_check/i);
  assert.match(schema, /event_type not in \('friend_share_saved', 'friend_share_duplicate_blocked'\)/i);
  assert.match(schema, /or surface = 'server'/i);
  assert.match(schema, /idx_friend_share_events_recipient_client_unique/i);
  assert.match(schema, /coalesce\(reason_code, ''\)/i);
  assert.match(schema, /create unique index if not exists idx_friend_share_events_public_open_unique/i);
  assert.match(schema, /create unique index if not exists idx_friend_share_events_public_failure_unique/i);
  assert.match(schema, /add column if not exists sender_display_name text/i);
  assert.match(schema, /add column if not exists sender_handle text/i);
  assert.match(schema, /add column if not exists source_verified_at timestamptz/i);
  assert.match(schema, /column_name = 'note_consent_version'[\s\S]*payload = payload - 'note'/i);
  assert.match(schema, /where note_consent_version is null[\s\S]*payload \? 'note'/i);
  assert.doesNotMatch(
    schema,
    /update shared_place_links link[\s\S]*source_verified_at = link\.created_at/i,
    "legacy links were never payload-matched and must remain neutral",
  );
  assert.match(schema, /add column if not exists origin_shared_place_link_id uuid/i);
  assert.match(schema, /foreign key \(origin_shared_place_link_id\)[\s\S]*references shared_place_links\(id\)[\s\S]*on delete set null/i);
  assert.match(schema, /create unique index if not exists idx_places_user_origin_shared_place_link_unique[\s\S]*on places\(user_id, origin_shared_place_link_id\)[\s\S]*where origin_shared_place_link_id is not null/i);
  assert.match(friendSharePlaceOriginConflictClause, /on conflict \(user_id, origin_shared_place_link_id\)/i);
  assert.equal(friendShareVerifiedCohortPredicate, "link.source_verified_at is not null");
});

test("same-link failure predicates exclude recipients with a terminal receipt in the window", () => {
  const predicate = friendShareExclusiveOpenFailurePredicate(
    "event",
    "terminal_event",
    { startsAt: "$1", endsAt: "$2" },
  );

  assert.match(predicate, /terminal_event\.shared_place_link_id = event\.shared_place_link_id/);
  assert.match(predicate, /terminal_event\.recipient_user_id = event\.recipient_user_id/);
  assert.match(predicate, /friend_share_saved', 'friend_share_duplicate_blocked/);
  assert.match(predicate, /terminal_event\.created_at >= \$1/);
  assert.match(predicate, /terminal_event\.created_at <= \$2/);
});

test("friend share summaries expose counts without recipient identities", () => {
  const summary = friendShareEventSummary([
    { event_type: "friend_share_link_created", recipient_user_id: null },
    { event_type: "friend_share_receipt_opened", recipient_user_id: null },
    { event_type: "friend_share_saved", recipient_user_id: "recipient-a" },
    { event_type: "friend_share_saved", recipient_user_id: "recipient-a" },
    { event_type: "friend_share_duplicate_blocked", recipient_user_id: "recipient-b" },
    { event_type: "friend_share_open_failed", recipient_user_id: "recipient-b" },
    { event_type: "friend_share_open_failed", recipient_user_id: "recipient-c" },
    { event_type: "friend_share_receipt_opened", recipient_user_id: "guest_00000000-0000-4000-8000-000000000000" },
  ]);

  assert.equal(summary.identified_recipient_sessions, 4);
  assert.equal(summary.account_recipient_users, 3);
  assert.equal(summary.guest_recipient_sessions, 1);
  assert.equal(summary.identified_recipient_sessions_saved, 1);
  assert.equal(summary.identified_recipient_sessions_duplicate_blocked, 1);
  assert.equal(summary.identified_recipient_sessions_open_failed, 1);
  assert.equal(summary.anonymous_events, 2);
  assert.equal("recipient-a" in summary, false);
});

test("internal recipient metrics pseudonymize users and keep unresolved separate from failure", () => {
  const metrics = friendShareRecipientMetrics([
    {
      link_id: "private-link-a",
      recipient_user_id: "private-recipient-a",
      receipt_opened: 1,
      save_tapped: 1,
      saved: 1,
      duplicate_blocked: 0,
      open_failed: 1,
      last_activity_at: "2026-07-15T03:00:00Z",
    },
    {
      link_id: "private-link-a",
      recipient_user_id: "private-recipient-b",
      receipt_opened: 1,
      save_tapped: 0,
      saved: 0,
      duplicate_blocked: 0,
      open_failed: 0,
      last_activity_at: "2026-07-15T02:00:00Z",
    },
    {
      link_id: "private-link-b",
      recipient_user_id: "private-recipient-c",
      receipt_opened: 0,
      save_tapped: 0,
      saved: 0,
      duplicate_blocked: 0,
      open_failed: 1,
      last_activity_at: "2026-07-15T01:00:00Z",
    },
    {
      link_id: "private-link-b",
      recipient_user_id: "guest_00000000-0000-4000-8000-000000000000",
      receipt_opened: 1,
      save_tapped: 0,
      saved: 0,
      duplicate_blocked: 0,
      open_failed: 0,
      last_activity_at: "2026-07-15T00:30:00Z",
    },
  ], "internal-token-that-is-at-least-32-characters");

  assert.match(String(metrics[0].recipient_ref), /^save_friend_recipient_/);
  assert.match(String(metrics[0].share_ref), /^save_friend_share_/);
  assert.equal(metrics[0].identity_kind, "account");
  assert.equal(metrics[0].outcome, "success");
  assert.equal(metrics[0].open_failed, 0, "a later terminal receipt must suppress failure");
  assert.equal(metrics[1].outcome, "unresolved");
  assert.equal(metrics[2].outcome, "failure");
  assert.equal(metrics[3].identity_kind, "guest");
  assert.equal(metrics[3].outcome, "unresolved");
  assert.equal(JSON.stringify(metrics).includes("private-recipient"), false);
  assert.equal(JSON.stringify(metrics).includes("private-link"), false);
});

test("public receipt handler disables storage on success and terminal errors", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const handler = serverSource.slice(
    serverSource.indexOf("async function handleSharedPlaceLinkPublic"),
    serverSource.indexOf("async function handlePublicFriendShareEvent"),
  );

  assert.match(handler, /setHeader\("Cache-Control", "private, no-store"\)/);
  assert.match(handler, /setHeader\("Referrer-Policy", "no-referrer"\)/);
  assert.match(handler, /Shared place link not found/);
  assert.match(handler, /Shared place link expired/);
});

test("friend share event retries return the existing bounded receipt for every recipient kind", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const handler = serverSource.slice(
    serverSource.indexOf("async function insertFriendShareEvent"),
    serverSource.indexOf("async function handleSharedPlaceLinks"),
  );

  assert.match(handler, /on conflict do nothing/i);
  assert.match(handler, /recipient_user_id is not distinct from \$2/i);
  assert.doesNotMatch(handler, /if \(!recipientUserId\)/i);
});

test("place create route wraps only receipt saves and keeps origin internal", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const handler = serverSource.slice(
    serverSource.indexOf("async function handlePlaces"),
    serverSource.indexOf("async function handleTrips"),
  );

  assert.match(handler, /friendShareCodeFromPlaceCreate\(rawBody\)/);
  assert.match(handler, /friendShareLinkIsExpired\(link\)/);
  assert.match(handler, /isSelfFriendShareRecipient\(link\.user_id, userId\)/);
  assert.match(handler, /recipientPlaceMatchesSharedPayload\(body, link\.payload\)/);
  assert.match(handler, /returning \*, \(xmax = 0\) as friend_share_receipt_created/);
  assert.match(handler, /friend_share_receipt_created[\s\S]*friend_share_saved[\s\S]*friend_share_duplicate_blocked/);
  assert.match(handler, /insert into friend_share_events[\s\S]*'server'/);
  assert.match(handler, /place: formatPlace\(canonicalPlace\)/);
  assert.match(handler, /outcome: created === true \? "saved" : "already_saved"/);
  assert.match(handler, /sendJson\(response, formatPlace\(rows\[0\]\), 201\)/,
    "generic POST /places must retain its original unwrapped response");
  assert.match(serverSource, /origin_shared_place_link_id: _originSharedPlaceLinkId/);
});

test("friend share opaque refs are stable, scoped, and token-rotatable", () => {
  const token = "internal-token-that-is-at-least-32-characters";
  const shareRef = friendShareOpaqueRef("share", "private-link-id", token);

  assert.equal(shareRef, friendShareOpaqueRef("share", "private-link-id", token));
  assert.notEqual(shareRef, friendShareOpaqueRef("sender", "private-link-id", token));
  assert.notEqual(shareRef, friendShareOpaqueRef("share", "private-link-id", `${token}-rotated`));
  assert.equal(shareRef.includes("private-link-id"), false);
});

test("internal share metrics return no raw code, link id, sender id, or display name", () => {
  const metrics = friendShareShareMetrics([
    {
      link_id: "private-link-id",
      sender_user_id: "private-sender-id",
      events_total: 6,
      receipt_opened: 2,
      save_tapped: 1,
      saved: 1,
      duplicate_blocked: 0,
      open_failed: 1,
      identified_recipient_sessions: 2,
      account_recipient_users: 1,
      guest_recipient_sessions: 1,
      account_recipient_users_succeeded: 1,
      guest_recipient_sessions_succeeded: 0,
      account_recipient_users_open_failed: 0,
      guest_recipient_sessions_open_failed: 1,
      anonymous_events: 2,
      last_activity_at: "2026-07-15T03:00:00Z",
    },
  ], "internal-token-that-is-at-least-32-characters");

  assert.match(String(metrics[0].share_ref), /^save_friend_share_/);
  assert.match(String(metrics[0].sender_ref), /^save_friend_sender_/);
  assert.equal(JSON.stringify(metrics).includes("private-link-id"), false);
  assert.equal(JSON.stringify(metrics).includes("private-sender-id"), false);
  assert.equal("code" in metrics[0], false);
  assert.equal("sender_display_name" in metrics[0], false);
  assert.equal(metrics[0].account_recipient_users, 1);
  assert.equal(metrics[0].guest_recipient_sessions, 1);
});
