-- Pending additive migration. Founder-owned apply, after friend-ratings.sql.
-- Never run on boot. Existing explicit restaurant shares retain visited meaning.
-- Do not backfill from private places.note/rating/status or general visibility.
alter table friend_restaurant_ratings alter column stars drop not null;
alter table friend_restaurant_ratings add column if not exists caption text;
alter table friend_restaurant_ratings add column if not exists shared_status text not null default 'visited';
do $$ begin
    if not exists (select 1 from pg_constraint where conrelid = 'friend_restaurant_ratings'::regclass and conname = 'shared_posts_status_check') then
        alter table friend_restaurant_ratings add constraint shared_posts_status_check check (shared_status in ('wantToGo', 'visited'));
    end if;
    if not exists (select 1 from pg_constraint where conrelid = 'friend_restaurant_ratings'::regclass and conname = 'shared_posts_caption_check') then
        alter table friend_restaurant_ratings add constraint shared_posts_caption_check check (char_length(caption) <= 500);
    end if;
    if not exists (select 1 from pg_constraint where conrelid = 'friend_restaurant_ratings'::regclass and conname = 'shared_posts_rating_status_check') then
        alter table friend_restaurant_ratings add constraint shared_posts_rating_status_check check (stars is null or shared_status = 'visited');
    end if;
end $$;
