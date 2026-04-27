# Wanderly Supabase Auth Notes

Date: 2026-04-27

## Current State

- The iOS app authenticates users with Privy.
- `PrivyAuthService.currentUserId` exposes `user.id` from Privy.
- `SupabaseService` sends the Supabase anon key as `apikey`.
- `SupabaseService.accessToken` exists but is not set anywhere in the app.
- `supabase/schema.sql` uses Supabase Auth RLS policies with `auth.uid()`.
- User-owned tables use `uuid` owner columns, for example `profiles.id uuid` and `places.user_id uuid`.

## Blocker

The app and database auth models do not currently line up.

With the current code, Supabase REST requests fall back to:

```http
Authorization: Bearer <SUPABASE_ANON_KEY>
```

Under the schema RLS policies, `auth.uid()` will not equal the Privy user id. For normal anon-key requests it will be null, so owner-scoped reads and writes such as `places`, `trips`, and `profiles` are expected to fail once real Supabase configuration is enabled.

There is a second likely mismatch: Privy `user.id` is treated as a Swift `String`, while the schema expects Supabase user ids to be `uuid`. If Privy ids are not UUID strings that correspond to `auth.users.id`, inserts into owner columns will fail before RLS policy checks.

## Required Decision

Pick one auth bridge before relying on Supabase persistence:

1. Use Supabase Auth as the database authority, and map Privy login into a Supabase-compatible JWT/session before calling PostgREST.
2. Keep Privy as the authority, move database writes behind a backend/service-role API, and enforce ownership in that backend.
3. Change schema/RLS to validate a Privy-compatible JWT claim, if Supabase accepts the chosen JWT issuer/audience configuration.

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
