import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  formatListItemRow,
  formatListRow,
  listBodyMaxBytes,
  listForMember,
  listItemPayloadMaxBytes,
  listMaxItems,
  listNoteMaxLength,
  listShareURL,
  listTitleMaxLength,
  listsForMember,
  memberRole,
  normalizeListCreate,
  normalizeListItemCreate,
  normalizeListJoin,
  normalizeShareCodeCreate,
  referralShareURL,
} from "./listContracts.js";

const memberId = "did:privy:member";
const listId = "550e8400-e29b-41d4-a716-446655440000";

function capturingQuery(rows: Record<string, unknown>[] = []) {
  const calls: { sql: string; values: readonly unknown[] }[] = [];
  const query = async (sql: string, values: readonly unknown[]) => {
    calls.push({ sql, values });
    return { rows };
  };
  return { calls, query };
}

test("list create normalizer bounds title, note, and client-supplied id", () => {
  assert.deepEqual(normalizeListCreate({ title: "  Tokyo eats  " }), {
    id: undefined,
    title: "Tokyo eats",
    note: null,
  });
  assert.deepEqual(normalizeListCreate({ id: listId, title: "Tokyo", note: " ramen " }), {
    id: listId,
    title: "Tokyo",
    note: "ramen",
  });

  assert.throws(() => normalizeListCreate({}), /title is required/);
  assert.throws(() => normalizeListCreate({ title: "   " }), /title is required/);
  assert.throws(() => normalizeListCreate({ title: 42 }), /title must be a string/);
  assert.throws(
    () => normalizeListCreate({ title: "x".repeat(listTitleMaxLength + 1) }),
    /120 characters or fewer/,
  );
  assert.throws(
    () => normalizeListCreate({ title: "ok", note: "x".repeat(listNoteMaxLength + 1) }),
    /500 characters or fewer/,
  );
  assert.throws(() => normalizeListCreate({ id: "not-a-uuid", title: "ok" }), /id must be a UUID/);
  assert.throws(() => normalizeListCreate({ id: 7, title: "ok" }), /id must be a string/);
});

test("list item normalizer requires an object payload under the byte cap", () => {
  const payload = { name: "Kato", lat: 34.04 };
  assert.deepEqual(normalizeListItemCreate({ payload }), { payload });

  assert.throws(() => normalizeListItemCreate({}), /payload is required/);
  assert.throws(() => normalizeListItemCreate({ payload: null }), /payload is required/);
  assert.throws(() => normalizeListItemCreate({ payload: "text" }), /payload is required/);
  assert.throws(() => normalizeListItemCreate({ payload: [1, 2, 3] }), /payload is required/);
  assert.throws(
    () => normalizeListItemCreate({ payload: { note: "x".repeat(listItemPayloadMaxBytes) } }),
    /payload is too large/,
  );
  assert.equal(listItemPayloadMaxBytes, 8 * 1024);
  assert.equal(listBodyMaxBytes, 16 * 1024);
  assert.equal(listMaxItems, 200);
});

test("list join normalizer revalidates the share code shape", () => {
  assert.deepEqual(normalizeListJoin({ code: " AbC123_x " }), { code: "AbC123_x" });

  assert.throws(() => normalizeListJoin({}), /code is required/);
  assert.throws(() => normalizeListJoin({ code: "shrt" }), /code is invalid/);
  assert.throws(() => normalizeListJoin({ code: "bad!code" }), /code is invalid/);
  assert.throws(() => normalizeListJoin({ code: "x".repeat(33) }), /code is invalid/);
});

test("share code normalizer accepts only editor or viewer", () => {
  assert.deepEqual(normalizeShareCodeCreate({ role: "editor" }), { role: "editor" });
  assert.deepEqual(normalizeShareCodeCreate({ role: "viewer" }), { role: "viewer" });

  assert.throws(() => normalizeShareCodeCreate({}), /role must be editor or viewer/);
  assert.throws(() => normalizeShareCodeCreate({ role: "owner" }), /role must be editor or viewer/);
  assert.throws(() => normalizeShareCodeCreate({ role: "admin" }), /role must be editor or viewer/);
});

test("listsForMember scopes by membership with column-explicit SQL", async () => {
  const { calls, query } = capturingQuery();
  await listsForMember(memberId, query);

  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /join list_members m on m\.list_id = l\.id and m\.user_id = \$1/);
  assert.match(calls[0].sql, /m\.role as viewer_role/);
  assert.match(calls[0].sql, /from list_items li/);
  assert.doesNotMatch(calls[0].sql, /select\s+\*/i);
  assert.deepEqual(calls[0].values, [memberId]);

  await assert.rejects(() => listsForMember("  ", query), /user id is required/);
});

test("listForMember requires a uuid and returns the membership row", async () => {
  const row = { id: listId, viewer_role: "editor" };
  const { calls, query } = capturingQuery([row]);

  assert.equal(await listForMember("not-a-uuid", memberId, query), null);
  assert.equal(calls.length, 0, "invalid uuids must not reach the database");

  assert.equal(await listForMember(listId, memberId, query), row);
  assert.match(calls[0].sql, /where l\.id = \$2/);
  assert.deepEqual(calls[0].values, [memberId, listId]);
});

test("memberRole reads a single membership row scoped to the caller", async () => {
  const { calls, query } = capturingQuery([{ role: "viewer" }]);

  assert.equal(await memberRole(listId, memberId, query), "viewer");
  assert.match(calls[0].sql, /from list_members/);
  assert.match(calls[0].sql, /where list_id = \$1 and user_id = \$2/);
  assert.deepEqual(calls[0].values, [listId, memberId]);

  const empty = capturingQuery([]);
  assert.equal(await memberRole(listId, memberId, empty.query), null);
  assert.equal(await memberRole("not-a-uuid", memberId, empty.query), null);
});

test("list formatter keeps the response contract and drops private columns", () => {
  const formatted = formatListRow({
    id: listId,
    title: "Tokyo",
    note: null,
    owner_id: "did:privy:owner",
    viewer_role: "editor",
    privy_user_id: "must-not-leak",
    owner_email: "must-not-leak@example.com",
    items: [{
      id: "650e8400-e29b-41d4-a716-446655440000",
      payload: { name: "Kato" },
      added_by: "did:privy:owner",
      created_at: "2026-08-12T01:02:03.000Z",
      internal_marker: "must-not-leak",
    }],
    created_at: new Date("2026-08-12T00:00:00.123Z"),
    updated_at: "2026-08-12T01:02:03Z",
  });

  assert.deepEqual(Object.keys(formatted).sort(), [
    "created_at",
    "id",
    "items",
    "note",
    "owner_id",
    "title",
    "updated_at",
    "viewer_role",
  ]);
  assert.equal(formatted.created_at, "2026-08-12T00:00:00Z");
  const items = formatted.items as Record<string, unknown>[];
  assert.deepEqual(Object.keys(items[0]).sort(), ["added_by", "created_at", "id", "payload"]);
  assert.equal(items[0].created_at, "2026-08-12T01:02:03Z");
  assert.equal(JSON.stringify(formatted).includes("must-not-leak"), false);

  assert.deepEqual(formatListItemRow({ id: "x", payload: {}, added_by: null, created_at: null }), {
    id: "x",
    payload: {},
    added_by: null,
    created_at: null,
  });
});

test("share and referral URLs use the vercel host contracts the app parses", () => {
  assert.equal(listShareURL("AbC123_x"), "https://sav-e-app.vercel.app/list?c=AbC123_x");
  assert.equal(listShareURL("AbC123_x", "https://example.com/list/"), "https://example.com/list?c=AbC123_x");
  assert.equal(referralShareURL("ref123"), "https://sav-e-app.vercel.app/r/ref123");
});

test("lists routes are authenticated and enforce membership ACL in SQL", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");

  const authGate = serverSource.indexOf("const userId = await resolveUserId(request);");
  assert.ok(authGate > 0);
  assert.ok(
    serverSource.indexOf('resource === "lists"') > authGate,
    "lists routes must be registered after resolveUserId",
  );
  assert.ok(serverSource.indexOf('resource === "list-joins"') > authGate);
  assert.ok(serverSource.indexOf('id === "referral"') > authGate);

  const listsHandler = serverSource.slice(
    serverSource.indexOf("async function handleLists"),
    serverSource.indexOf("async function handleListJoins"),
  );

  assert.match(listsHandler, /setHeader\("Cache-Control", "private, no-store"\)/);
  assert.match(listsHandler, /setHeader\("Vary", "Authorization"\)/);
  assert.match(listsHandler, /on conflict \(id\) do nothing/);
  assert.match(listsHandler, /List id conflict/, "a foreign client-supplied id must 409, not leak");
  assert.match(listsHandler, /values \(\$1, \$2, 'owner'\)/);

  // Member check happens before the item insert, and viewers are read-only.
  const roleCheck = listsHandler.indexOf("await memberRole(");
  const itemInsert = listsHandler.indexOf("insert into list_items");
  assert.ok(roleCheck > 0 && itemInsert > roleCheck, "memberRole must gate the item insert");
  assert.match(listsHandler, /sendJson\(response, \{ error: "Viewers cannot add to this list" \}, 403\)/);
  assert.match(listsHandler, /count\(\*\)::int as item_count from list_items/);
  assert.match(listsHandler, /update lists set updated_at = now\(\) where id = \$1/);

  // Only the owner can mint share codes, and the check precedes the mint.
  const ownerCheck = listsHandler.indexOf('role !== "owner"');
  const mint = listsHandler.indexOf("uniqueListShareCode()");
  assert.ok(ownerCheck > 0 && mint > ownerCheck, "owner check must precede share-code mint");
  assert.match(listsHandler, /insert into list_share_codes \(list_id, code, role, created_by\)/);
  assert.match(listsHandler, /Unsupported lists route/);
});

test("list joins upgrade viewer to editor but never downgrade, and expire with 410", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const handler = serverSource.slice(
    serverSource.indexOf("async function handleListJoins"),
    serverSource.indexOf("async function handleMyReferral"),
  );

  assert.match(handler, /expires_at is null or expires_at > now\(\)/);
  assert.match(handler, /ApiError\(404, "List link not found"\)/);
  assert.match(handler, /ApiError\(410, "List link expired"\)/);
  assert.match(handler, /on conflict \(list_id, user_id\) do update set role = case/);
  assert.match(handler, /when list_members\.role = 'owner' then 'owner'/);
  assert.match(handler, /when excluded\.role = 'editor' then 'editor'/);
  assert.match(handler, /else list_members\.role/);
  assert.match(handler, /listForMember\(listId, userId/);
});

test("own referral endpoint mints idempotently and never overwrites a code", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");
  const handler = serverSource.slice(
    serverSource.indexOf("async function handleMyReferral"),
    serverSource.indexOf("async function uniqueListShareCode"),
  );

  assert.match(handler, /setHeader\("Cache-Control", "private, no-store"\)/);
  assert.match(handler, /update profiles set referral_code = \$2 where id = \$1 and referral_code is null/);
  assert.match(handler, /randomBytes\(6\)\.toString\("base64url"\)/);
  assert.match(handler, /isUniqueViolationError\(error\)/);
  assert.match(handler, /referralShareURL\(code\)/);

  const shareCodeMint = serverSource.slice(
    serverSource.indexOf("async function uniqueListShareCode"),
    serverSource.indexOf("function isUniqueViolationError"),
  );
  assert.match(shareCodeMint, /select code from list_share_codes where code = \$1/);
  assert.match(shareCodeMint, /randomBytes\(6\)\.toString\("base64url"\)/);
});

test("lists schema is idempotent with role and code constraints", () => {
  const schema = readFileSync(new URL("../sql/schema.sql", import.meta.url), "utf8");

  assert.match(schema, /create table if not exists lists \(/);
  assert.match(schema, /create table if not exists list_items \(/);
  assert.match(schema, /create table if not exists list_members \(/);
  assert.match(schema, /create table if not exists list_share_codes \(/);

  assert.match(schema, /owner_id text references profiles\(id\) on delete cascade not null/);
  assert.match(schema, /list_id uuid references lists\(id\) on delete cascade not null/);
  assert.match(schema, /added_by text references profiles\(id\) on delete set null/);
  assert.match(schema, /payload jsonb not null/);
  assert.match(schema, /constraint list_members_role_check check \(role in \('owner', 'editor', 'viewer'\)\)/);
  assert.match(schema, /constraint list_members_unique_member unique \(list_id, user_id\)/);
  assert.match(schema, /constraint list_share_codes_code_check check \(code ~ '\^\[A-Za-z0-9_-\]\{6,32\}\$'\)/);
  assert.match(schema, /constraint list_share_codes_role_check check \(role in \('editor', 'viewer'\)\)/);
  assert.match(schema, /expires_at timestamptz default \(now\(\) \+ interval '90 days'\)/);
  assert.match(schema, /create index if not exists idx_lists_owner on lists\(owner_id\)/);
  assert.match(schema, /create index if not exists idx_list_items_list on list_items\(list_id\)/);
  assert.match(schema, /create index if not exists idx_list_members_user on list_members\(user_id\)/);
  assert.match(schema, /create trigger update_lists_updated_at before update on lists/);

  // The referral endpoint reuses the existing profiles.referral_code column.
  assert.match(schema, /alter table profiles add column if not exists referral_code text/);
  assert.match(schema, /idx_profiles_referral_code on profiles\(referral_code\) where referral_code is not null/);
});
