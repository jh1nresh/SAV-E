import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { deleteAccount } from "./accountDeletion.js";

test("deleteAccount removes Savvy data before the external identity", async () => {
  const events: string[] = [];

  await deleteAccount({
    deleteProfile: async () => {
      events.push("profile");
    },
    deletePrivyUser: async () => {
      events.push("privy");
    },
  });

  assert.deepEqual(events, ["profile", "privy"]);
});

test("deleteAccount never removes the identity when profile deletion throws", async () => {
  let deletedPrivyUser = false;

  await assert.rejects(
    () => deleteAccount({
      deleteProfile: async () => {
        throw new Error("database unavailable");
      },
      deletePrivyUser: async () => {
        deletedPrivyUser = true;
      },
    }),
    /database unavailable/,
  );

  assert.equal(deletedPrivyUser, false);
});

test("deleteAccount retries external identity deletion after profile data is already absent", async () => {
  let deletedPrivyUser = false;

  await deleteAccount({
    deleteProfile: async () => {},
    deletePrivyUser: async () => {
      deletedPrivyUser = true;
    },
  });

  assert.equal(deletedPrivyUser, true);
});

test("account deletion route runs before ensureProfile and remains owner scoped", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const routeIndex = serverSource.indexOf('resource === "account"');
  const ensureIndex = serverSource.indexOf("await ensureProfile(userId)");

  assert.ok(routeIndex >= 0, "account deletion route must be registered");
  assert.ok(ensureIndex >= 0, "ensureProfile call must remain visible to this regression test");
  assert.ok(routeIndex < ensureIndex, "account deletion must run before ensureProfile");
  const routeBlock = serverSource.slice(routeIndex, ensureIndex);
  assert.match(routeBlock, /request\.method !== "DELETE"/);
  assert.match(routeBlock, /verifiedPrivySubject\(token\)/);
  assert.match(routeBlock, /delete from profiles where id = \$1/);
  assert.match(routeBlock, /\[userId\]/);
  assert.match(routeBlock, /privyUserProvisioner\.deleteUser\(privyUserId\)/);
});
