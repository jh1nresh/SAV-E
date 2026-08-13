import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  formatListItemRow,
  formatListMemberRow,
  formatListRow,
  formatShareCodeRow,
  listBodyMaxBytes,
  listForMember,
  listItemPayloadMaxBytes,
  listMaxItems,
  listMemberUserIdMaxLength,
  listMembersForViewer,
  listNoteMaxLength,
  listShareURL,
  listTitleMaxLength,
  listsForMember,
  memberRole,
  normalizeListCreate,
  normalizeListItemCreate,
  normalizeListJoin,
  normalizeListMemberUserId,
  normalizeListShareCode,
  normalizeShareCodeCreate,
  referralShareURL,
  shareCodesForOwner,
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

test("member user id and share code path params revalidate before the database", () => {
  assert.equal(normalizeListMemberUserId(" did:privy:friend "), "did:privy:friend");
  assert.equal(normalizeListMemberUserId(""), null);
  assert.equal(normalizeListMemberUserId("   "), null);
  assert.equal(normalizeListMemberUserId(42), null);
  assert.equal(normalizeListMemberUserId("x".repeat(listMemberUserIdMaxLength)), "x".repeat(128));
  assert.equal(normalizeListMemberUserId("x".repeat(listMemberUserIdMaxLength + 1)), null);

  assert.equal(normalizeListShareCode(" AbC123_x "), "AbC123_x");
  assert.equal(normalizeListShareCode("shrt"), null);
  assert.equal(normalizeListShareCode("bad!code"), null);
  assert.equal(normalizeListShareCode("x".repeat(33)), null);
  assert.equal(normalizeListShareCode(7), null);
});

test("listMembersForViewer enforces the viewer's membership in SQL and stays column-explicit", async () => {
  const { calls, query } = capturingQuery();
  await listMembersForViewer(listId, memberId, query);

  assert.equal(calls.length, 1);
  const sql = calls[0].sql;
  assert.match(sql, /from list_members m/);
  assert.match(sql, /join profiles p on p\.id = m\.user_id/);
  assert.match(
    sql,
    /exists \(\s*select 1\s*from list_members viewer\s*where viewer\.list_id = m\.list_id and viewer\.user_id = \$2\s*\)/,
    "the viewer's own membership must gate the row set inside the SQL",
  );
  assert.match(sql, /p\.display_name/);
  assert.doesNotMatch(sql, /select\s+\*/i);
  assert.doesNotMatch(sql, /email/i, "profile email must never be selected");
  assert.doesNotMatch(sql, /phone/i, "profile phone must never be selected");
  assert.doesNotMatch(sql, /privy/i, "privy identifiers must never be selected");
  assert.doesNotMatch(sql, /avatar_url|instagram_id|referral_code/i);
  assert.deepEqual(calls[0].values, [listId, memberId]);

  assert.deepEqual(await listMembersForViewer("not-a-uuid", memberId, query), []);
  assert.equal(calls.length, 1, "invalid uuids must not reach the database");
  await assert.rejects(() => listMembersForViewer(listId, "  ", query), /user id is required/);
});

test("shareCodesForOwner requires the owner role inside the SQL", async () => {
  const { calls, query } = capturingQuery();
  await shareCodesForOwner(listId, memberId, query);

  assert.equal(calls.length, 1);
  const sql = calls[0].sql;
  assert.match(sql, /from list_share_codes c/);
  assert.match(
    sql,
    /exists \(\s*select 1\s*from list_members owner\s*where owner\.list_id = c\.list_id and owner\.user_id = \$2 and owner\.role = 'owner'\s*\)/,
    "only the list owner may enumerate share codes",
  );
  assert.doesNotMatch(sql, /select\s+\*/i);
  assert.deepEqual(calls[0].values, [listId, memberId]);

  assert.deepEqual(await shareCodesForOwner("not-a-uuid", memberId, query), []);
  assert.equal(calls.length, 1, "invalid uuids must not reach the database");
  await assert.rejects(() => shareCodesForOwner(listId, "  ", query), /user id is required/);
});

test("member and share-code formatters keep their contracts and drop private columns", () => {
  const member = formatListMemberRow({
    user_id: "did:privy:friend",
    role: "editor",
    display_name: "Kato",
    created_at: new Date("2026-08-12T00:00:00.123Z"),
    email: "must-not-leak@example.com",
    privy_user_id: "must-not-leak",
  });
  assert.deepEqual(member, {
    user_id: "did:privy:friend",
    role: "editor",
    display_name: "Kato",
    created_at: "2026-08-12T00:00:00Z",
  });
  assert.equal(JSON.stringify(member).includes("must-not-leak"), false);

  const shareCode = formatShareCodeRow({
    code: "AbC123_x",
    role: "viewer",
    expires_at: "2026-11-10T00:00:00Z",
    created_at: new Date("2026-08-12T01:02:03.000Z"),
    created_by: "must-not-leak",
  });
  assert.deepEqual(shareCode, {
    code: "AbC123_x",
    role: "viewer",
    url: listShareURL("AbC123_x"),
    expires_at: "2026-11-10T00:00:00Z",
    created_at: "2026-08-12T01:02:03Z",
  });
  assert.equal(JSON.stringify(shareCode).includes("must-not-leak"), false);
  assert.equal(formatShareCodeRow({ code: null }).url, null);
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

test("member management and share-code revocation enforce ownership rules", () => {
  const serverSource = readFileSync(new URL("../src/server.ts", import.meta.url), "utf8");

  // Members routes live inside the authenticated lists dispatch.
  const authGate = serverSource.indexOf("const userId = await resolveUserId(request);");
  assert.ok(authGate > 0);
  const registration = serverSource.indexOf('resource === "lists" && segments.length <= 4');
  assert.ok(registration > authGate, "lists dispatch (incl. members) must sit after resolveUserId");

  const listsHandler = serverSource.slice(
    serverSource.indexOf("async function handleLists"),
    serverSource.indexOf("async function handleListJoins"),
  );

  // GET members goes through the SQL-side membership guard and 404s non-members.
  const membersRoute = listsHandler.indexOf('sub === "members" && !subId');
  const membersQuery = listsHandler.indexOf("listMembersForViewer(listId, userId");
  assert.ok(membersRoute > 0 && membersQuery > membersRoute);
  assert.match(listsHandler, /rows\.length === 0\) throw new ApiError\(404, "List not found"\)/);
  assert.match(listsHandler, /formatListMemberRow\(row\)/);

  // Owners cannot leave their own list; non-owners may only remove themselves.
  assert.match(
    listsHandler,
    /sendJson\(response, \{ error: "Owners cannot leave their own list" \}, 409\)/,
  );
  assert.match(listsHandler, /\} else if \(targetUserId !== userId\) \{/);
  assert.match(
    listsHandler,
    /delete from list_members\s*where list_id = \$1 and user_id = \$2 and role <> 'owner'/,
    "the member delete must never remove an owner row",
  );

  // Share-code listing and revocation are owner-gated (404, never 403) before any query.
  const listCodesRoute = listsHandler.indexOf('request.method === "GET" && listId && sub === "share-codes" && !subId');
  const listCodesQuery = listsHandler.indexOf("shareCodesForOwner(listId, userId");
  assert.ok(listCodesRoute > 0 && listCodesQuery > listCodesRoute);
  const revokeRoute = listsHandler.indexOf('request.method === "DELETE" && listId && sub === "share-codes" && subId');
  assert.ok(revokeRoute > 0);
  const revokeBranch = listsHandler.slice(revokeRoute);
  const revokeOwnerCheck = revokeBranch.indexOf('role !== "owner"');
  const revokeDelete = revokeBranch.indexOf("delete from list_share_codes where list_id = $1 and code = $2");
  assert.ok(
    revokeOwnerCheck > 0 && revokeDelete > revokeOwnerCheck,
    "owner check must precede the share-code delete",
  );
  assert.match(listsHandler, /normalizeListShareCode\(subId\)/);
  assert.match(listsHandler, /normalizeListMemberUserId\(subId\)/);
  assert.match(listsHandler, /shareCodesForOwner\(listId, userId/);
  assert.match(listsHandler, /formatShareCodeRow\(row\)/);
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
