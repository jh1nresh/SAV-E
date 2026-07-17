import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  accountStatusResponse,
  accountStatusSql,
  evaluateAccountConfirmationRequest,
  evaluateAccountStatusRequest,
  opaqueAccountRef,
  resolveProfileSubject,
  stableAccountRefSecret,
} from "./accountStatus.js";

const secret = "test-account-ref-secret-at-least-32-characters";
const subject = "did:privy:test-private-subject";

function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    profile_id: "private-profile-id",
    profile_customized: false,
    places_count: 0,
    review_items_count: 0,
    conflicting_binding: false,
    ...overrides,
  };
}

function transactionHooks(events: string[] = []) {
  return {
    beginTransaction: async () => { events.push("begin"); },
    lockSubject: async (lockedSubject: string) => {
      assert.equal(lockedSubject, subject);
      events.push("lock");
    },
    commitTransaction: async () => { events.push("commit"); },
    rollbackTransaction: async () => { events.push("rollback"); },
  };
}

test("account status rejects unsupported methods without auth or database work", async () => {
  let verified = false;
  let queried = false;
  const result = await evaluateAccountStatusRequest({
    method: "POST",
    authorizationHeader: `Bearer token`,
    accountRefSecret: secret,
    verifySubject: async () => { verified = true; return subject; },
    query: async () => { queried = true; return { rows: [] }; },
  });

  assert.deepEqual(result, { statusCode: 405, body: { error: "Method not allowed" } });
  assert.equal(verified, false);
  assert.equal(queried, false);
});

test("account status returns generic 401 for missing, malformed, or rejected bearer tokens", async () => {
  for (const authorizationHeader of [undefined, "token", "Bearer", "Basic abc"]) {
    let queried = false;
    const result = await evaluateAccountStatusRequest({
      method: "GET",
      authorizationHeader,
      accountRefSecret: secret,
      verifySubject: async () => subject,
      query: async () => { queried = true; return { rows: [] }; },
    });
    assert.deepEqual(result, { statusCode: 401, body: { error: "Unauthorized" } });
    assert.equal(queried, false);
  }

  let queried = false;
  const rejected = await evaluateAccountStatusRequest({
    method: "GET",
    authorizationHeader: "Bearer expired-token",
    accountRefSecret: secret,
    verifySubject: async () => { throw new Error("JWT expired with private details"); },
    query: async () => { queried = true; return { rows: [] }; },
  });
  assert.deepEqual(rejected, { statusCode: 401, body: { error: "Unauthorized" } });
  assert.equal(queried, false);
});

test("account status fails closed without a stable ref secret and never queries", async () => {
  let queried = false;
  const result = await evaluateAccountStatusRequest({
    method: "GET",
    authorizationHeader: "Bearer valid-token",
    verifySubject: async () => subject,
    query: async () => { queried = true; return { rows: [] }; },
  });

  assert.deepEqual(result, { statusCode: 503, body: { error: "Account verification unavailable" } });
  assert.equal(queried, false);
});

test("account status performs one bound read and does not create a missing profile", async () => {
  const calls: Array<{ sql: string; values: readonly unknown[] }> = [];
  const result = await evaluateAccountStatusRequest({
    method: "GET",
    authorizationHeader: "Bearer valid-token",
    accountRefSecret: secret,
    verifySubject: async (token) => {
      assert.equal(token, "valid-token");
      return subject;
    },
    query: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [] };
    },
  });

  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].values, [subject]);
  assert.equal((result.body as { state?: string }).state, "new");
});

test("account states distinguish empty, ready, and split profile bindings", () => {
  const empty = accountStatusResponse([row()], subject, secret);
  assert.equal(empty.state, "empty");
  assert.deepEqual(empty.counts, { stamps: 0, review_items: 0 });

  for (const readyRow of [
    row({ profile_customized: true }),
    row({ places_count: 3 }),
    row({ review_items_count: 2 }),
  ]) {
    assert.equal(accountStatusResponse([readyRow], subject, secret).state, "ready");
  }

  const split = accountStatusResponse([
    row({ profile_id: subject }),
    row({ profile_id: "mapped-private-profile" }),
  ], subject, secret);
  assert.equal(split.state, "recovery_required");
  assert.equal(split.account_ref, null);
  assert.equal(split.counts, null);
  assert.equal(split.recovery_reason, "split_profile_binding");

  const conflicting = accountStatusResponse([
    row({ profile_id: subject, conflicting_binding: true, places_count: 3 }),
  ], subject, secret);
  assert.equal(conflicting.state, "recovery_required");
  assert.equal(conflicting.account_ref, null);
  assert.equal(conflicting.recovery_reason, "conflicting_profile_binding");
});

test("hidden capture history cannot make a visibly empty profile ready", () => {
  const empty = accountStatusResponse([row({ memory_items_count: 99 })], subject, secret);
  assert.equal(empty.state, "empty");
  assert.deepEqual(empty.counts, { stamps: 0, review_items: 0 });
});

test("one logical profile is not misclassified when only one row is returned", () => {
  const response = accountStatusResponse([
    row({ profile_id: subject, profile_customized: true }),
  ], subject, secret);
  assert.equal(response.state, "ready");
});

test("serialized account status never exposes identity or profile fields", () => {
  const privateEmail = "private-user@example.com";
  const responses = [
    accountStatusResponse([], subject, secret),
    accountStatusResponse([row({ email: privateEmail })], subject, secret),
    accountStatusResponse([row({ profile_customized: true })], subject, secret),
    accountStatusResponse([row(), row({ profile_id: "another-private-profile" })], subject, secret),
  ];

  for (const response of responses) {
    const serialized = JSON.stringify(response);
    assert.doesNotMatch(serialized, /did:privy|private-profile-id|another-private-profile|private-user@example\.com/);
    assert.doesNotMatch(serialized, /display_name|privy_user_id|email|subject|token/);
  }
});

test("opaque account refs are stable, domain scoped, and rotate with the secret", () => {
  const first = opaqueAccountRef("canonical-profile", secret);
  const second = opaqueAccountRef("canonical-profile", secret);
  const otherProfile = opaqueAccountRef("other-profile", secret);
  const rotated = opaqueAccountRef("canonical-profile", `${secret}-rotated`);

  assert.equal(first, second);
  assert.notEqual(first, otherProfile);
  assert.notEqual(first, rotated);
  assert.match(first, /^save_account_[A-Za-z0-9_-]{43}$/);
  assert.doesNotMatch(first, /canonical-profile/);
});

test("account ref secret prefers the dedicated key and never falls back to guest state", () => {
  assert.equal(stableAccountRefSecret({
    SAVE_ACCOUNT_REF_SECRET: " dedicated ",
    SAVE_MY_SAVES_SECRET: "my-saves",
  }), "dedicated");
  assert.equal(stableAccountRefSecret({ SAVE_MY_SAVES_SECRET: " my-saves " }), "my-saves");
  assert.equal(stableAccountRefSecret({ SAVE_GUEST_SESSION_SECRET: "guest-only" }), undefined);
});

test("account confirmation authenticates, binds the expected ref, and creates only a missing profile", async () => {
  const expectedAccountRef = opaqueAccountRef(subject, secret);
  let created = 0;
  let queryCount = 0;
  const events: string[] = [];
  const result = await evaluateAccountConfirmationRequest({
    method: "POST",
    authorizationHeader: "Bearer valid-token",
    accountRefSecret: secret,
    expectedAccountRef,
    verifySubject: async () => subject,
    ...transactionHooks(events),
    query: async () => {
      queryCount += 1;
      events.push("query");
      return queryCount === 1
        ? { rows: [] }
        : { rows: [row({ profile_id: subject })] };
    },
    createProfile: async (profileId) => {
      assert.equal(profileId, subject);
      created += 1;
      events.push("create");
    },
  });

  assert.equal(result.statusCode, 200);
  assert.equal((result.body as { state?: string }).state, "empty");
  assert.equal(created, 1);
  assert.equal(queryCount, 2);
  assert.deepEqual(events, ["begin", "lock", "query", "create", "query", "commit"]);
});

test("account confirmation fails closed on auth, malformed refs, mismatches, and recovery states", async () => {
  const validRef = opaqueAccountRef(subject, secret);
  for (const scenario of [
    { authorizationHeader: undefined, expectedAccountRef: validRef, verifyThrows: false, expectedStatus: 401 },
    { authorizationHeader: "Bearer rejected", expectedAccountRef: validRef, verifyThrows: true, expectedStatus: 401 },
    { authorizationHeader: "Bearer valid", expectedAccountRef: "raw-profile-id", verifyThrows: false, expectedStatus: 400 },
    { authorizationHeader: "Bearer valid", expectedAccountRef: opaqueAccountRef("other", secret), verifyThrows: false, expectedStatus: 409 },
  ]) {
    let created = false;
    let queried = false;
    const events: string[] = [];
    const result = await evaluateAccountConfirmationRequest({
      method: "POST",
      authorizationHeader: scenario.authorizationHeader,
      accountRefSecret: secret,
      expectedAccountRef: scenario.expectedAccountRef,
      verifySubject: async () => {
        if (scenario.verifyThrows) throw new Error("private verification detail");
        return subject;
      },
      ...transactionHooks(events),
      query: async () => { queried = true; return { rows: [] }; },
      createProfile: async () => { created = true; },
    });
    assert.equal(result.statusCode, scenario.expectedStatus);
    assert.equal(created, false);
    if (scenario.expectedStatus < 409) assert.equal(queried, false);
    if (scenario.expectedStatus < 409) assert.deepEqual(events, []);
    if (scenario.expectedStatus === 409) assert.deepEqual(events, ["begin", "lock", "rollback"]);
  }

  let created = false;
  const conflictEvents: string[] = [];
  const conflict = await evaluateAccountConfirmationRequest({
    method: "POST",
    authorizationHeader: "Bearer valid",
    accountRefSecret: secret,
    expectedAccountRef: validRef,
    verifySubject: async () => subject,
    ...transactionHooks(conflictEvents),
    query: async () => ({ rows: [row({ profile_id: subject, conflicting_binding: true })] }),
    createProfile: async () => { created = true; },
  });
  assert.equal(conflict.statusCode, 409);
  assert.equal(created, false);
  assert.deepEqual(conflictEvents, ["begin", "lock", "rollback"]);
});

test("account confirmation rolls back when the final read changes or a transaction step fails", async () => {
  const validRef = opaqueAccountRef(subject, secret);
  const mismatchEvents: string[] = [];
  let queryCount = 0;
  const mismatch = await evaluateAccountConfirmationRequest({
    method: "POST",
    authorizationHeader: "Bearer valid",
    accountRefSecret: secret,
    expectedAccountRef: validRef,
    verifySubject: async () => subject,
    ...transactionHooks(mismatchEvents),
    query: async () => {
      queryCount += 1;
      return queryCount === 1
        ? { rows: [] }
        : { rows: [row({ profile_id: subject }), row({ profile_id: "mapped-profile" })] };
    },
    createProfile: async () => { mismatchEvents.push("create"); },
  });
  assert.equal(mismatch.statusCode, 409);
  assert.deepEqual(mismatchEvents, ["begin", "lock", "create", "rollback"]);

  const failureEvents: string[] = [];
  await assert.rejects(evaluateAccountConfirmationRequest({
    method: "POST",
    authorizationHeader: "Bearer valid",
    accountRefSecret: secret,
    expectedAccountRef: validRef,
    verifySubject: async () => subject,
    ...transactionHooks(failureEvents),
    query: async () => { throw new Error("query failed"); },
    createProfile: async () => { throw new Error("must not create"); },
  }), /query failed/);
  assert.deepEqual(failureEvents, ["begin", "lock", "rollback"]);
});

test("profile subject resolution rejects a raw-id row bound to another Privy subject", async () => {
  const calls: Array<{ sql: string; values: readonly unknown[] }> = [];
  const conflict = await resolveProfileSubject(subject, async (sql, values) => {
    calls.push({ sql, values });
    return calls.length === 1
      ? { rows: [] }
      : { rows: [{ privy_user_id: "did:privy:someone-else" }] };
  });
  assert.deepEqual(conflict, { profileId: subject, conflictingRawBinding: true });
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[0].values, [subject]);
  assert.deepEqual(calls[1].values, [subject]);

  let mappedQueryCount = 0;
  const mapped = await resolveProfileSubject(subject, async () => {
    mappedQueryCount += 1;
    return mappedQueryCount === 1
      ? { rows: [{ id: "canonical-profile" }] }
      : { rows: [] };
  });
  assert.deepEqual(mapped, { profileId: "canonical-profile", conflictingRawBinding: false });
  assert.equal(mappedQueryCount, 2);

  let splitQueryCount = 0;
  const split = await resolveProfileSubject(subject, async () => {
    splitQueryCount += 1;
    return splitQueryCount === 1
      ? { rows: [{ id: "canonical-profile" }] }
      : { rows: [{ privy_user_id: null }] };
  });
  assert.deepEqual(split, { profileId: "canonical-profile", conflictingRawBinding: true });
});

test("account status SQL is parameterized, read-only, and owner scoped", () => {
  const normalized = accountStatusSql.replace(/\s+/g, " ").trim().toLowerCase();
  assert.match(normalized, /^select /);
  assert.doesNotMatch(normalized, /\b(insert|update|delete|merge|call|truncate|alter|drop)\b/);
  assert.match(normalized, /where p\.id = \$1 or p\.privy_user_id = \$1/);
  assert.match(normalized, /pl\.user_id = p\.id/);
  assert.match(normalized, /c\.user_id = p\.id/);
  assert.match(normalized, /pc\.status in \('review', 'confirmed', 'needs_more_evidence', 'source_only'\)/);
  assert.match(normalized, /p\.privy_user_id <> \$1/);
  assert.doesNotMatch(normalized, /memory_items_count/);
});

test("account status route runs before ensureProfile and stays outside the mutation path", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const routeIndex = serverSource.indexOf('resource === "account-status"');
  const ensureIndex = serverSource.indexOf("await ensureProfile(userId)");

  assert.ok(routeIndex >= 0, "account-status route must be registered");
  assert.ok(ensureIndex >= 0, "ensureProfile call must remain visible to this regression test");
  assert.ok(routeIndex < ensureIndex, "account-status must run before ensureProfile");
  const routeBlock = serverSource.slice(routeIndex, ensureIndex);
  assert.doesNotMatch(routeBlock, /ensureProfile\s*\(/);
  assert.match(routeBlock, /segments\[1\] !== "confirm"/);
  assert.match(routeBlock, /evaluateAccountConfirmationRequest/);
  assert.match(routeBlock, /beginTransaction/);
  assert.match(routeBlock, /lockProfileSubject/);
  assert.match(routeBlock, /commitTransaction/);
  assert.match(routeBlock, /rollbackTransaction/);
  assert.match(routeBlock, /Cache-Control/);
  assert.match(routeBlock, /Vary/);

  const confirmStart = routeBlock.indexOf('if (segments[1] === "confirm")');
  const confirmBlock = routeBlock.slice(confirmStart);
  const methodGateIndex = confirmBlock.indexOf('request.method !== "POST"');
  const bodyReadIndex = confirmBlock.indexOf("readJson(request");
  const clientAcquireIndex = confirmBlock.indexOf("pool.connect()");
  assert.ok(methodGateIndex >= 0, "confirm must reject unsupported methods before acquiring resources");
  assert.ok(methodGateIndex < bodyReadIndex, "confirm method gate must run before reading the body");
  assert.ok(methodGateIndex < clientAcquireIndex, "confirm method gate must run before acquiring a client");
  assert.match(confirmBlock, /finally\s*{\s*client\.release\(\)/s);

  const linkStart = serverSource.indexOf("async function linkPrivyUserToProfile");
  const linkEnd = serverSource.indexOf("async function ensurePrivyPhoneProfile");
  const linkBlock = serverSource.slice(linkStart, linkEnd);
  assert.match(linkBlock, /pool\.connect\(\)/);
  assert.match(linkBlock, /client\.query\("begin"\)/);
  assert.match(linkBlock, /lockProfileSubject\(client, privyUserId\)/);
  assert.match(linkBlock, /for update/i);
  assert.match(linkBlock, /client\.query\("commit"\)/);
  assert.match(linkBlock, /client\.query\("rollback"\)/);
  assert.match(linkBlock, /client\.release\(\)/);

  const resolverStart = serverSource.indexOf("async function profileIdForPrivySubject");
  const resolverEnd = serverSource.indexOf("async function verifiedPrivySubject");
  const resolverBlock = serverSource.slice(resolverStart, resolverEnd);
  const resolverLockIndex = resolverBlock.indexOf("lockProfileSubject(client, privySubject)");
  const resolverReadIndex = resolverBlock.indexOf("resolveProfileSubject(");
  const resolverInsertIndex = resolverBlock.indexOf("insert into profiles");
  const resolverCommitIndex = resolverBlock.indexOf('client.query("commit")');
  assert.match(resolverBlock, /pool\.connect\(\)/);
  assert.match(resolverBlock, /client\.query\("begin"\)/);
  assert.ok(resolverLockIndex >= 0, "bearer resolution must take the shared subject lock");
  assert.ok(resolverLockIndex < resolverReadIndex, "bearer resolution must read after taking the lock");
  assert.ok(resolverReadIndex < resolverInsertIndex, "bearer resolution must choose the profile before inserting");
  assert.ok(resolverInsertIndex < resolverCommitIndex, "bearer profile must exist before releasing the lock");
  assert.match(resolverBlock, /client\.query\("rollback"\)/);
  assert.match(resolverBlock, /finally\s*{\s*client\.release\(\)/s);
});
