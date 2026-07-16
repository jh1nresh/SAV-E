import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  FollowListInputError,
  listFollowedFriends,
  listFollowedFriendsPage,
  normalizeFollowListOptions,
  unfollowByRelationshipId,
} from "./followList.js";

const firstId = "11111111-1111-4111-8111-111111111111";
const secondId = "22222222-2222-4222-8222-222222222222";
const thirdId = "33333333-3333-4333-8333-333333333333";

test("versioned follow list is owner-scoped, searchable, and returns an opaque next cursor", async () => {
  let capturedSql = "";
  let capturedValues: readonly unknown[] = [];
  const page = await listFollowedFriendsPage(
    "viewer-123",
    normalizeFollowListOptions({ search: " @Memo  Friend ", limit: "2", cursor: null }),
    async (sql, values) => {
      capturedSql = sql;
      capturedValues = values;
      return {
        rows: [
          followedRow(firstId, "2026-07-16T03:00:00.000Z", "Memo Friend"),
          followedRow(secondId, "2026-07-16T02:00:00.000Z", "Second Friend"),
          followedRow(thirdId, "2026-07-16T01:00:00.000Z", "Third Friend"),
        ],
      };
    },
  );

  assert.match(capturedSql, /where f\.follower_id = \$1/);
  assert.match(capturedSql, /ilike \$2/);
  assert.match(capturedSql, /\(f\.created_at, f\.id\) < \(\$3::timestamptz, \$4::uuid\)/);
  assert.deepEqual(capturedValues, ["viewer-123", "%Memo Friend%", null, null, 3]);
  assert.deepEqual(page.items.map((friend) => friend.id), [firstId, secondId]);
  assert.ok(page.nextCursor);
  assert.doesNotMatch(page.nextCursor ?? "", /Memo|2026|2222/);
  assert.deepEqual(Object.keys(page.items[0] ?? {}).sort(), ["avatarUrl", "displayName", "handle", "id"]);
});

test("next page cursor binds timestamp, relationship id, and normalized search", async () => {
  const firstPage = await listFollowedFriendsPage(
    "viewer-123",
    normalizeFollowListOptions({ search: "memo", limit: "1", cursor: null }),
    async () => ({
      rows: [
        followedRow(firstId, "2026-07-16T03:00:00.000Z", "Memo One"),
        followedRow(secondId, "2026-07-16T02:00:00.000Z", "Memo Two"),
      ],
    }),
  );
  let capturedValues: readonly unknown[] = [];

  await listFollowedFriendsPage(
    "viewer-123",
    normalizeFollowListOptions({ search: "memo", limit: "1", cursor: firstPage.nextCursor }),
    async (_sql, values) => {
      capturedValues = values;
      return { rows: [] };
    },
  );

  assert.deepEqual(capturedValues, [
    "viewer-123",
    "%memo%",
    "2026-07-16T03:00:00.000Z",
    firstId,
    2,
  ]);
  assert.throws(
    () => normalizeFollowListOptions({ search: "different", limit: "1", cursor: firstPage.nextCursor }),
    FollowListInputError,
  );
});

test("search and pagination input are bounded before database work", () => {
  assert.deepEqual(
    normalizeFollowListOptions({ search: " @alice  smith ", limit: null, cursor: null }),
    { search: "alice smith", limit: 20, cursor: null },
  );
  assert.throws(
    () => normalizeFollowListOptions({ search: "a".repeat(65), limit: null, cursor: null }),
    FollowListInputError,
  );
  assert.throws(
    () => normalizeFollowListOptions({ search: "alice", limit: "51", cursor: null }),
    FollowListInputError,
  );
  assert.throws(
    () => normalizeFollowListOptions({ search: "alice", limit: "20", cursor: "not-a-cursor" }),
    FollowListInputError,
  );
});

test("search wildcards remain bound data instead of changing SQL", async () => {
  let capturedSql = "";
  let capturedValues: readonly unknown[] = [];
  await listFollowedFriendsPage(
    "viewer-123",
    normalizeFollowListOptions({ search: "%_\\", limit: "20", cursor: null }),
    async (sql, values) => {
      capturedSql = sql;
      capturedValues = values;
      return { rows: [] };
    },
  );

  assert.doesNotMatch(capturedSql, /%_\\/);
  assert.equal(capturedValues[1], "%\\%\\_\\\\%");
});

test("legacy follow list preserves the array response and 100 row bound", async () => {
  let capturedValues: readonly unknown[] = [];
  const result = await listFollowedFriends("viewer-123", async (_sql, values) => {
    capturedValues = values;
    return { rows: [followedRow(firstId, "2026-07-16T03:00:00.000Z", "Memo Friend")] };
  });

  assert.deepEqual(capturedValues, ["viewer-123", null, null, null, 101]);
  assert.equal(result[0]?.displayName, "Memo Friend");
});

test("unfollow deletes only the authenticated owner's relationship and is idempotent", async () => {
  let capturedSql = "";
  let capturedValues: readonly unknown[] = [];
  await unfollowByRelationshipId("viewer-123", firstId, async (sql, values) => {
    capturedSql = sql;
    capturedValues = values;
    return { rows: [] };
  });

  assert.match(capturedSql, /where id = \$1\s+and follower_id = \$2/);
  assert.deepEqual(capturedValues, [firstId, "viewer-123"]);
  await assert.rejects(
    unfollowByRelationshipId("viewer-123", "not-a-uuid", async () => ({ rows: [] })),
    FollowListInputError,
  );
});

test("unfollow response keeps the shared CORS response headers", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  assert.match(serverSource, /return sendJson\(response, null, 204\);/);
});

test("follow list fails closed without an authenticated user id", async () => {
  let queried = false;
  await assert.rejects(
    listFollowedFriends(" ", async () => {
      queried = true;
      return { rows: [] };
    }),
    /Authenticated user id is required/,
  );
  assert.equal(queried, false);
});

function followedRow(id: string, createdAt: string, displayName: string) {
  return {
    follow_id: id,
    created_at: createdAt,
    display_name: displayName,
    handle: displayName.toLowerCase().replace(/\s+/g, "-"),
    avatar_url: "https://example.com/avatar.jpg",
    referral_code: "SAVE-FRIEND",
    following_id: "private-profile-id",
    privy_user_id: "private-privy-id",
    email: "private@example.com",
    phone: "+15550000000",
  };
}
