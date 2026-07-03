-- Places de-duplication, DB layer.
--
-- The client dedup gate (Place.matches: google_place_id → normalized source
-- URL → name+proximity) stops duplicate submissions, but a stale client can
-- still write a second row for the same venue. This makes the strongest
-- identity — (user_id, google_place_id) — unique at the database.
--
-- source_url is intentionally NOT constrained: one caption/post legitimately
-- yields multiple places (multi-place captions are a supported flow).

-- 1) Remove existing duplicates, keeping the earliest row per
--    (user_id, google_place_id). Ties broken by id so the delete is
--    deterministic.
delete from public.places a
using public.places b
where a.user_id = b.user_id
  and a.google_place_id = b.google_place_id
  and a.google_place_id is not null
  and a.google_place_id <> ''
  and (
    a.created_at > b.created_at
    or (a.created_at = b.created_at and a.id > b.id)
  );

-- 2) Enforce uniqueness going forward. Partial index: rows without a
--    google_place_id (manual notes, unresolved clues) stay unconstrained.
create unique index if not exists places_user_google_place_id_unique
  on public.places (user_id, google_place_id)
  where google_place_id is not null and google_place_id <> '';
