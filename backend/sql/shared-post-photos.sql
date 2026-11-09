-- Pending additive migration: apply after shared-posts.sql, before backend rollout.
-- Founder-owned apply; never run on boot. No private-place photo backfill.
alter table friend_restaurant_ratings
  add column if not exists photo_data bytea[] not null default '{}';
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'friend_restaurant_ratings'::regclass and conname = 'shared_posts_photos_check') then
    alter table friend_restaurant_ratings add constraint shared_posts_photos_check check (
      cardinality(photo_data) <= 3 and array_position(photo_data, null) is null
      and coalesce(octet_length(photo_data[1]), 0) <= 262144
      and coalesce(octet_length(photo_data[2]), 0) <= 262144
      and coalesce(octet_length(photo_data[3]), 0) <= 262144
    );
  end if;
end $$;

-- Older servers and the settings rating-withdrawal route only clear shared_at.
-- Enforce removal here too, so an old client cannot later resurrect photo consent.
create or replace function clear_withdrawn_shared_post_photos() returns trigger
language plpgsql as $$
begin
  if new.shared_at is null then new.photo_data := '{}'::bytea[]; end if;
  return new;
end $$;
create or replace trigger clear_withdrawn_shared_post_photos
  before insert or update on friend_restaurant_ratings
  for each row execute function clear_withdrawn_shared_post_photos();
