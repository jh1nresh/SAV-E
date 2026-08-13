# Collaborative Lists v2 — Server-backed lists + ACL, and closing the friend-invite loop

> Status: in progress (branch `claude/lists-server-acl`)
> Supersedes the sharing section of `2026-05-26-collaborative-lists-v1.md` (local base64 links stay as offline fallback).

## Problem

1. Lists are device-local UserDefaults snapshots. Sharing embeds the whole list
   as base64 in the URL: no sync, roles are a client-side honor system
   (`r=viewer` → `r=editor` by editing the URL), size-capped, and not scoped
   per account.
2. The friend loop is receive-only: users can paste someone's referral code,
   but nothing in the app ever shows their own code/link
   (`SaveReferralProfile.referralURL` has zero call sites; `UserProfile` has no
   code/handle fields). Nobody can invite anyone.

## P1 story (independently testable)

A signed-in user creates a list, shares a short link, and a second signed-in
user opens it: the second user becomes a member with the role the owner chose
(enforced server-side), sees the list's current items, and — if editor — adds
an item the owner then sees. Separately, any user can copy their own invite
link from Passport Connections and a friend who opens it ends up following
them.

## Acceptance criteria

1. `POST /v0/lists` creates a list (accepts client-supplied uuid for
   offline-first idempotency) + owner membership, in one transaction.
2. `GET /v0/lists` returns every list the caller is a member of, with items
   and the caller's role. `GET /v0/lists/:id` is member-only (404 otherwise).
3. `POST /v0/lists/:id/share-codes` (owner only) mints a short code bound to a
   server-stored role (viewer|editor); response includes
   `https://sav-e-app.vercel.app/list?c=<code>`.
4. `POST /v0/list-joins {code}` registers membership with the code's role
   (editor upgrades viewer; owner never downgraded) and returns the list.
   Expired/unknown code → 404/410.
5. `POST /v0/lists/:id/items` requires owner/editor (viewer → 403); item is a
   jsonb snapshot matching `SaveListItem`.
6. iOS: when the API is configured, lists load from the server; create/add
   are optimistic local writes with fire-and-forget server sync; share uses
   the short-code URL (falls back to legacy base64 link when offline);
   opening a `?c=` link joins server-side. Legacy `?d=` links still import a
   local snapshot.
7. iOS: Passport Connections Friends 段新增「我的邀請連結」share row backed by
   `GET /v0/me/referral` (mints/returns the caller's referral code + URL).
8. Backend tests (node:test, injected-query fakes + source-text pins) cover:
   membership ACL in SQL, role upgrade on join, viewer-cannot-edit, share-code
   shape/expiry, and referral-code mint idempotency.

## Out of scope

- Realtime sync/conflict resolution (poll-on-open only), item deletion UI,
  member management UI, revoking share codes, migrating existing local lists
  to the server automatically, resurrecting the dead drawer friends/lists UI
  (`AIDrawerView` `commandTabBar` tree — separate cleanup).

## Data contract (backend)

Tables (idempotent DDL appended to `backend/sql/schema.sql`): `lists`
(owner_id, title, note, timestamps), `list_items` (list_id, added_by, payload
jsonb, created_at), `list_members` (list_id, user_id, role
owner|editor|viewer, unique(list_id, user_id)), `list_share_codes` (list_id,
code unique `^[A-Za-z0-9_-]{6,32}$`, role editor|viewer, created_by,
expires_at default now()+90d).

Limits: title ≤ 120 chars, note ≤ 500, item payload ≤ 8 KiB, ≤ 200 items per
list, body cap 16 KiB.

## Verification

- `cd backend && npm test` (build + node --test)
- iOS: `xcodebuild build` generic sim + `-only-testing:SAVETests` focused run
- Deploy note: applying `schema.sql` to production Railway Postgres is a
  human-approved step (`psql "$DATABASE_URL" -f backend/sql/schema.sql`).
