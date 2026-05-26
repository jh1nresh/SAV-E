# Railway Backend Migration

## Goal

Move SAV-E persistence from Supabase Edge Functions/PostgREST to a Railway-hosted backend with Railway Postgres, because the current project has no production data and Supabase deployment is blocked on provider-specific secrets.

## Non-goals

- Do not change Privy as the authentication authority.
- Do not redesign iOS persistence models.
- Do not migrate existing production rows; there is no data to preserve.

## Backend Contract

The Railway API must keep the same mobile-facing routes currently used by `SupabaseService`:

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

Every non-`OPTIONS` route must require `Authorization: Bearer <Privy access token>`.

The backend must verify:

- issuer: `privy.io`
- audience: `PRIVY_APP_ID`
- signature: `PRIVY_VERIFICATION_KEY`

The verified Privy `sub` claim is the owner id for profiles, places, trips, collections, and future IG bot links.

## Data Model

Use ordinary Postgres tables equivalent to the current Supabase schema:

- `profiles`
- `places`
- `trips`
- `trip_stops`
- `collections`
- `collection_places`
- `ig_bot_links`

Supabase RLS is not used on Railway. Ownership is enforced in backend SQL predicates.

## Deployment

Railway service environment variables:

- `DATABASE_URL` from Railway Postgres
- `PRIVY_APP_ID`
- `PRIVY_VERIFICATION_KEY`
- optional `PORT`, provided by Railway

iOS uses:

- `SAVE_API_URL=https://<railway-service-domain>`

`SAVE_API_URL` is the canonical backend URL. The old `SUPABASE_URL` fallback should be removed to avoid accidental calls to the retired Supabase function.

## Acceptance Criteria

- Backend compiles with TypeScript.
- Schema can be applied to Postgres from `backend/sql/schema.sql`.
- API routes preserve the existing JSON shape expected by `SupabaseService`.
- iOS still builds after config/doc updates.
- README documents Railway deploy and env setup.
