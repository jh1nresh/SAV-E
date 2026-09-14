-- Draft migration. Apply only to a local/test database until separately approved.
-- Same one-way follower audience as place_visibility('friends'). Never backfill
-- shared stars from imported place metadata or a user's saved/visited status.
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
