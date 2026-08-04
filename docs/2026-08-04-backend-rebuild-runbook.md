# Backend Rebuild Runbook (new Railway + new Supabase)

> Last updated: 2026-08-04
> Trigger: old Railway/Supabase projects being replaced. Current prod API
> (`wanderly-api-production.up.railway.app`) still serves live data until
> cutover — don't tear it down before the data decision below.

## 0. Founder decisions / actions (blocking)

1. **Data**: old DB is alive behind the current API.
   - Keep data → from a machine with the OLD `DATABASE_URL`:
     `pg_dump --no-owner --no-privileges -Fc "$OLD_DATABASE_URL" -f save-prod.dump`
   - Fresh start → skip the dump; new DB starts empty (all Map Stamps /
     clues / profiles are gone for existing accounts).
2. `railway login` (browser OAuth).
3. Create the new Supabase project in the dashboard (2 clicks) and copy its
   **pooled connection string** (DATABASE_URL). Secrets stay out of the
   assistant context: paste values only into Railway dashboard / your shell.
4. Collect: `PRIVY_APP_ID`, `PRIVY_VERIFICATION_KEY` (Privy dashboard),
   `GEMINI_API_KEY`, `GOOGLE_PLACES_API_KEY`, `GOOGLE_GEOCODING_API_KEY`.

## 1. Schema into the new DB (you export DATABASE_URL first)

```bash
export DATABASE_URL='postgresql://...'   # new Supabase pooled URL
psql "$DATABASE_URL" -f backend/sql/schema.sql
for f in supabase/migrations/*.sql; do psql "$DATABASE_URL" -f "$f"; done
# optional data restore:
# pg_restore --no-owner --no-privileges -d "$DATABASE_URL" save-prod.dump
```

`schema.sql` is idempotent (`create table if not exists`), migrations are
ordered by filename.

## 2. New Railway project + deploy

```bash
cd backend
railway init            # create/link new project, e.g. save-backend
railway up              # railway.json already defines NIXPACKS + healthcheck
railway domain          # generate the public URL
```

Set variables in the Railway dashboard (required): `DATABASE_URL`,
`PRIVY_APP_ID`, `PRIVY_VERIFICATION_KEY`. Functional: `GEMINI_API_KEY`,
`GOOGLE_PLACES_API_KEY`, `GOOGLE_GEOCODING_API_KEY`,
`SAVE_GUEST_SESSION_SECRET`, evidence-rubric `SAVE_EVIDENCE_RUBRIC_URL` /
`SAVE_EVIDENCE_RUBRIC_TOKEN`. SLLR/Sendblue vars are optional (bot
features).

Smoke test: `curl https://<new-domain>/` → `{"ok":true,"service":"save-backend"}`.

## 3. Point the app at the new API

- `.env` / `.env.local`: `SAVE_API_URL=https://<new-domain>` (legacy
  `WANDERLY_API_URL` same value).
- Rebuild iOS app; verify sign-in, Saves list, and pet selection.

## 4. Cutover notes

- The new deploy runs current `main` — the pet-selection 400
  ("No writable fields") disappears without further changes.
- Keep the old Railway service until the new one passes smoke tests.
- Update `~/brain` + `.env.example` if the domain naming changes.
