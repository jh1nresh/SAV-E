# Backend Service-Role API Spec

> Superseded by `specs/railway-backend-migration.md` on 2026-04-27. The API contract remains, but deployment moved from Supabase Edge Functions to Railway backend + Railway Postgres.

Date: 2026-04-27

## Goal

Move SAV-E persistence behind a backend API so the iOS app no longer relies on Supabase Auth `auth.uid()` matching Privy user ids.

## Decision

Use a Supabase Edge Function named `save-api` as the database boundary.

The iOS app sends the current Privy access token in:

```http
Authorization: Bearer <privy_access_token>
```

The Edge Function verifies the Privy token, derives the owner id from the verified token `sub` claim, and performs database reads/writes with `SUPABASE_SERVICE_ROLE_KEY`.

The client must not send or choose `user_id`.

## API

All routes are under `/functions/v1/save-api`.

- `GET /places`
- `POST /places`
- `PATCH /places/:id`
- `DELETE /places/:id`
- `GET /trips`
- `POST /trips`
- `PATCH /trips/:id`
- `DELETE /trips/:id`
- `GET /profile`
- `PATCH /profile`

## Database Ownership

Privy ids are strings, not guaranteed UUIDs. Owner columns must use `text`:

- `profiles.id text`
- `places.user_id text`
- `trips.user_id text`
- `collections.user_id text`
- `ig_bot_links.user_id text`

Direct client access through anon-key PostgREST should remain denied. Ownership enforcement lives in the Edge Function by filtering every row-level operation by the verified Privy subject.

## Acceptance Criteria

- iOS build passes.
- Edge Function type-checks with Deno.
- The app retrieves Privy access tokens through the Swift SDK.
- `SupabaseService` calls the Edge Function instead of PostgREST for places, trips, and profile operations.
- Writes ignore caller-supplied `user_id` and use the verified backend subject.
- Migration documents the required Privy string owner conversion.
