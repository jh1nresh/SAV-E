# Pending SQL apply

Additive files in this directory are founder-owned. Merge is not a migrate.
The backend never applies these on boot. Do not re-apply to production from a
hygiene or docs PR.

## Order

1. `schema.sql` — new empty database only. Existing prod already has `places`.
2. Pending additive files, oldest first:
   - `analysis-usage.sql` — if those tables are not already present
   - `friend-ratings.sql` — creates `idx_places_id_user_id` if missing, then
     the Friends rating tables. Safe on a database that has `places` but lacks
     that composite unique index.
3. Verify (read-only), then Railway-deploy the backend, then iOS.

`friend-ratings.sql` is self-contained for the composite FK: it creates
`idx_places_id_user_id` with `IF NOT EXISTS` before
`references places(id, user_id)`.

## Apply

From `backend/`:

```bash
# Dry-read: prints statement order and a redacted psql command. No writes.
./scripts/apply-sql.sh friend-ratings.sql

# Local or founder-owned apply. Requires DATABASE_URL. Not invoked on boot.
./scripts/apply-sql.sh friend-ratings.sql --apply
```

If the URL still carries `sslmode=no-verify`, modern libpq rejects it. The
helper strips the query string and uses `PGSSLMODE=require` for that `psql`
invocation only. Equivalent manual path used in production applies:

```bash
PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -v ON_ERROR_STOP=1 -1 \
  -f backend/sql/friend-ratings.sql
```

Valid libpq `sslmode` / `PGSSLMODE` values: `disable`, `allow`, `prefer`,
`require`, `verify-ca`, `verify-full`. Prefer `require`. Do not set
`no-verify` on new applies.

Leave an already-working Railway service `PGSSLMODE` alone. Node `pg` still
accepts the legacy `no-verify` token so a live service variable is not a
blocker; `psql` is the client that rejects it.

## Verify after apply

```bash
PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -tAc \
  "select to_regclass('public.idx_places_id_user_id') is not null,
          to_regclass('public.friend_restaurant_ratings') is not null,
          to_regclass('public.friend_rating_saves') is not null;"
```

Expect `t|t|t`. Then deploy the backend. Then iOS.
