# Wanderly Supabase Auth Notes

> Superseded on 2026-04-27 by the Railway backend migration. Keep this file only as legacy context for why direct Supabase Auth/RLS access was removed.

Date: 2026-04-27

## Legacy State

- The iOS app authenticates users with Privy.
- `PrivyAuthService.currentUserId` exposes `user.id` from Privy.
- `SupabaseService` used to call the `wanderly-api` Edge Function.
- The iOS app retrieves a Privy access token with `PrivyUser.getAccessToken()`.
- `supabase/schema.sql` uses Privy string owner ids.
- User-owned tables use text owner columns, for example `profiles.id text` and `places.user_id text`.

## Blocker

The original app and database auth models did not line up.

Before the service-role API, Supabase REST requests fell back to:

```http
Authorization: Bearer <SUPABASE_ANON_KEY>
```

Under Supabase Auth RLS policies, `auth.uid()` did not equal the Privy user id. For normal anon-key requests it was null, so owner-scoped reads and writes such as `places`, `trips`, and `profiles` were expected to fail once real Supabase configuration was enabled.

There was a second likely mismatch: Privy `user.id` is treated as a Swift `String`, while the original schema expected Supabase user ids to be `uuid`.

## Decision

Keep Privy as the authority and enforce ownership in the backend.

This was first implemented as the `wanderly-api` Supabase Edge Function. It is superseded by the Railway backend migration, which keeps the same Privy token verification model and API contract while replacing Supabase Edge Functions/PostgREST with Railway Node API + Railway Postgres.

The app sends the current Privy access token as `Authorization: Bearer <token>`. The backend verifies the token with `PRIVY_VERIFICATION_KEY` and derives the owner id from the verified `sub` claim.

Do not disable RLS as the MVP shortcut unless the app is strictly local/demo only.

## Rotation Notes

The current checked-out tree contains placeholder values in:

- `Wanderly/Resources/Secrets.plist`
- `WanderlyShareExtension/Secrets.plist`
- `.env.example`

Git history previously contained values that looked like real Privy and Supabase project credentials. If those values were real, rotate them from the provider dashboards before production use:

- Supabase anon key and any exposed project URL/key pairing
- Privy app id/client id configuration, if applicable
- Any Gemini or Google Places keys that were ever committed locally outside the current redacted history check

Supabase CLI v2.72.7 is logged in and the Wanderly project is linked, but `supabase db lint --linked` could not run without `SUPABASE_DB_PASSWORD`.
