import assert from "node:assert/strict";
import test from "node:test";
import { listFollowedFriends } from "./followList.js";

test("follow list is owner-scoped and exposes only public relationship fields", async () => {
  let capturedSql = "";
  let capturedValues: readonly unknown[] = [];
  const result = await listFollowedFriends("viewer-123", async (sql, values) => {
    capturedSql = sql;
    capturedValues = values;
    return {
      rows: [{
        follow_id: "follow-1",
        display_name: "Memo Friend",
        handle: "memo-friend",
        avatar_url: "https://example.com/avatar.jpg",
        referral_code: "SAVE-FRIEND",
        following_id: "private-profile-id",
        privy_user_id: "private-privy-id",
        email: "private@example.com",
        phone: "+15550000000",
      }],
    };
  });

  assert.match(capturedSql, /where f\.follower_id = \$1/);
  assert.deepEqual(capturedValues, ["viewer-123"]);
  assert.deepEqual(result, [{
    id: "follow-1",
    displayName: "Memo Friend",
    handle: "memo-friend",
    avatarUrl: "https://example.com/avatar.jpg",
  }]);
  assert.deepEqual(Object.keys(result[0] ?? {}).sort(), [
    "avatarUrl",
    "displayName",
    "handle",
    "id",
  ]);
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
