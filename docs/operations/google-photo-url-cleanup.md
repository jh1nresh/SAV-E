# Google photo URL cleanup (founder Mac)

[Documentation index](../README.md) · SQL: [`backend/sql/google-photo-url-cleanup.sql`](../../backend/sql/google-photo-url-cleanup.sql), [`backend/sql/google-photo-url-verify.sql`](../../backend/sql/google-photo-url-verify.sql)

HoP 2026-10-21: stored Google Places photo URLs must be cleared for G5 **before App Store submission**. Agents and this PR must **not** run any step. Merge is not apply.

## Sequence

1. Merge [#306](https://github.com/jh1nresh/SAV-E/pull/306).
2. Ship / install that app version. It no longer reads `places.business_photo_urls`. Photos load live from `google_place_id`.
3. On your Mac, BACKUP, then CLEANUP, then VERIFY.
4. Only then submit to the App Store.

Do not add these files to `backend/sql/README.md` apply order. The backend never applies them on boot.

## Preconditions (Mac)

From `SAV-E/backend`, Railway CLI logged in and linked to project **save-backend**, service **save-backend**. `DATABASE_URL` lives on that service and points at the **external** Postgres (not a Railway volume). `railway run` injects it into a **local** command.

You need local `pg_dump` and `psql` (Homebrew `postgresql` or Postgres.app on `PATH`).

The pooler URL may carry `sslmode=no-verify`, which modern `psql`/`pg_dump` reject. Strip the query string and set `PGSSLMODE=require` for that process only. Do not change the Railway service `PGSSLMODE`.

```bash
cd backend
railway status    # project save-backend, service save-backend
which pg_dump psql
```

## 1. BACKUP

Redirects are on your Mac. Dump `public.places` (includes `id` and `business_photo_urls`) plus a narrow CSV of the photo columns.

```bash
cd backend
stamp=$(date +%Y%m%dT%H%M%S)
backup="$HOME/Desktop/savvy-places-photo-backup-$stamp.sql"
narrow="$HOME/Desktop/savvy-places-photo-columns-$stamp.csv"

railway run --service save-backend -- bash -c \
  'PGSSLMODE=require pg_dump --no-owner --no-privileges --data-only -t public.places "${DATABASE_URL%%\?*}"' \
  > "$backup"

railway run --service save-backend -- bash -c \
  'PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -v ON_ERROR_STOP=1 -c "set search_path to public" -c "\\copy (select id, business_photo_urls, source_image_url from places) to stdout csv header"' \
  > "$narrow"

ls -l "$backup" "$narrow"
```

Stop if either file is empty. Keep both until after App Store submission.

## 2. CLEANUP

Single transaction. Clears every `business_photo_urls` array. Nulls `source_image_url` only when it looks like a Google Places photo URL / photo name. Does not drop columns.

```bash
cd backend
railway run --service save-backend -- bash -c \
  'PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -v ON_ERROR_STOP=1 -1 -c "set search_path to public" -f sql/google-photo-url-cleanup.sql'
```

Expect `BEGIN` / `UPDATE` / `COMMIT`. If it errors, the transaction rolls back. Cleanup and verification decode layered URL escapes and compare parsed host/path boundaries; non-Google source URL bytes remain unchanged. Invalid UTF-8/NUL escapes or non-ASCII hosts requiring IDNA normalization deliberately stop the operation. Inspect those rows separately before a newly authorized run; an error is never a clean verification result.

## 3. VERIFY

Expect `0|0`.

```bash
cd backend
railway run --service save-backend -- bash -c \
  'PGSSLMODE=require psql "${DATABASE_URL%%\?*}" -v ON_ERROR_STOP=1 -c "set search_path to public" -f sql/google-photo-url-verify.sql'
```

Non-zero leftover counts mean cleanup did not finish. Do not submit. Restore from the Desktop dump only with a separate, explicit approval.

## What this does not cover

- Local vault JSON on devices: the #306 app ignores stored `businessPhotoUrls` when hydrating a Place. Old files are not remotely wiped.
- Shared-list payloads: Google photo URLs are dropped at persist; they are not in Postgres `places`.
- Column removal: out of scope. `google_place_id` stays.
