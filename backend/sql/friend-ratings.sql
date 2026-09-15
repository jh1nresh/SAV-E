-- Pending additive migration. Founder-owned apply. Never run on boot.
-- Merge does not migrate. The app does not auto-apply SQL.
-- Same one-way follower audience as place_visibility('friends'). Never backfill
-- shared stars from imported place metadata or a user's saved/visited status.
--
-- Requires `places` (from schema.sql). Idempotent: IF NOT EXISTS throughout.
-- Composite FK (place_id, user_id) -> places(id, user_id) needs a unique
-- index on those referenced columns. A database can already have `places`
-- without idx_places_id_user_id (the #241 prod apply failure). Create that
-- index first so this file is self-contained on a fresh or drifted apply.

-- 1. Prerequisite unique index (also declared in schema.sql).
create unique index if not exists idx_places_id_user_id on places(id, user_id);

-- 2. Rating row, then composite owner FK that depends on the index above.
create table if not exists friend_restaurant_ratings (
    place_id uuid primary key,
    user_id text not null,
    stars double precision not null check (stars >= 1 and stars <= 5),
    shared_at timestamptz,
    updated_at timestamptz not null default now(),
    foreign key (place_id, user_id) references places(id, user_id) on delete cascade
);

-- Attribution is resolved on read against the current follow and visibility.
-- No author name, stars, notes or visit details are copied into the saved place.
create table if not exists friend_rating_saves (
    recipient_place_id uuid not null references places(id) on delete cascade,
    source_place_id uuid not null references friend_restaurant_ratings(place_id) on delete cascade,
    primary key (recipient_place_id, source_place_id)
);
