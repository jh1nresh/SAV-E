-- Move SAV-E ownership from Supabase Auth UUIDs to verified Privy subject strings.
-- Direct anon-key access remains denied by RLS; the Edge Function uses service role
-- and enforces ownership in code.

drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();

drop policy if exists "Users can read own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can read own places" on public.places;
drop policy if exists "Users can insert own places" on public.places;
drop policy if exists "Users can update own places" on public.places;
drop policy if exists "Users can delete own places" on public.places;
drop policy if exists "Users can read own trips" on public.trips;
drop policy if exists "Users can insert own trips" on public.trips;
drop policy if exists "Users can update own trips" on public.trips;
drop policy if exists "Users can delete own trips" on public.trips;
drop policy if exists "Users can read own trip stops" on public.trip_stops;
drop policy if exists "Users can insert own trip stops" on public.trip_stops;
drop policy if exists "Users can update own trip stops" on public.trip_stops;
drop policy if exists "Users can delete own trip stops" on public.trip_stops;
drop policy if exists "Users can manage own collections" on public.collections;
drop policy if exists "Users can manage own collection places" on public.collection_places;
drop policy if exists "Users can read own ig links" on public.ig_bot_links;
drop policy if exists "Users can delete own ig links" on public.ig_bot_links;

alter table public.places drop constraint if exists places_user_id_fkey;
alter table public.trips drop constraint if exists trips_user_id_fkey;
alter table public.collections drop constraint if exists collections_user_id_fkey;
alter table public.ig_bot_links drop constraint if exists ig_bot_links_user_id_fkey;
alter table public.profiles drop constraint if exists profiles_id_fkey;

alter table public.profiles alter column id type text using id::text;
alter table public.places alter column user_id type text using user_id::text;
alter table public.trips alter column user_id type text using user_id::text;
alter table public.collections alter column user_id type text using user_id::text;
alter table public.ig_bot_links alter column user_id type text using user_id::text;

alter table public.places
    add constraint places_user_id_fkey foreign key (user_id) references public.profiles(id) on delete cascade;
alter table public.trips
    add constraint trips_user_id_fkey foreign key (user_id) references public.profiles(id) on delete cascade;
alter table public.collections
    add constraint collections_user_id_fkey foreign key (user_id) references public.profiles(id) on delete cascade;
alter table public.ig_bot_links
    add constraint ig_bot_links_user_id_fkey foreign key (user_id) references public.profiles(id) on delete cascade;

comment on table public.profiles is 'Privy-owned profiles. id is the verified Privy access token sub claim.';
comment on column public.places.user_id is 'Verified Privy access token sub claim. Set only by save-api.';
comment on column public.trips.user_id is 'Verified Privy access token sub claim. Set only by save-api.';
