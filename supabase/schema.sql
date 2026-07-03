-- SAV-E Supabase Schema
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ============================================================
-- Users (Privy-owned profiles)
-- ============================================================
create table public.profiles (
    id text primary key, -- verified Privy access token sub claim
    display_name text not null default '',
    email text,
    avatar_url text,
    is_premium boolean not null default false,
    instagram_id text,  -- for future IG bot linking
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
-- No anon-key table policies. `save-api` uses service role and enforces
-- ownership with the verified Privy subject.

-- ============================================================
-- Places
-- ============================================================
create table public.places (
    id uuid primary key default uuid_generate_v4(),
    user_id text references public.profiles(id) on delete cascade not null,
    name text not null,
    address text not null default '',
    latitude double precision not null,
    longitude double precision not null,
    google_place_id text,
    category text not null default 'food',
    status text not null default 'wantToGo',
    rating double precision,
    note text,
    source_url text,
    source_platform text not null default 'other',
    source_image_url text,
    business_photo_urls text[] default '{}',
    extracted_dishes text[] default '{}',
    price_range text,
    recommender text,
    google_rating double precision,
    google_price_level integer,
    opening_hours text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.places enable row level security;

alter table public.places add column if not exists business_photo_urls text[] default '{}';

create index idx_places_user_id on public.places(user_id);
create index idx_places_category on public.places(category);

-- ============================================================
-- Trips
-- ============================================================
create table public.trips (
    id uuid primary key default uuid_generate_v4(),
    user_id text references public.profiles(id) on delete cascade not null,
    name text not null,
    city text not null default '',
    start_date date,
    end_date date,
    is_optimized boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.trips enable row level security;

create index idx_trips_user_id on public.trips(user_id);

-- ============================================================
-- Trip Stops
-- ============================================================
create table public.trip_stops (
    id uuid primary key default uuid_generate_v4(),
    trip_id uuid references public.trips(id) on delete cascade not null,
    place_id uuid references public.places(id) on delete set null,
    place_name text not null,
    day integer not null default 1,
    order_index integer not null default 0,
    start_time text,
    duration integer,  -- minutes
    note text,
    created_at timestamptz not null default now()
);

alter table public.trip_stops enable row level security;

create index idx_trip_stops_trip_id on public.trip_stops(trip_id);

-- ============================================================
-- Collections
-- ============================================================
create table public.collections (
    id uuid primary key default uuid_generate_v4(),
    user_id text references public.profiles(id) on delete cascade not null,
    name text not null,
    emoji text not null default '📍',
    created_at timestamptz not null default now()
);

create table public.collection_places (
    collection_id uuid references public.collections(id) on delete cascade,
    place_id uuid references public.places(id) on delete cascade,
    primary key (collection_id, place_id)
);

alter table public.collections enable row level security;
alter table public.collection_places enable row level security;

-- ============================================================
-- Updated_at trigger
-- ============================================================
create or replace function public.update_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger update_profiles_updated_at before update on public.profiles
    for each row execute procedure public.update_updated_at();
create trigger update_places_updated_at before update on public.places
    for each row execute procedure public.update_updated_at();
create trigger update_trips_updated_at before update on public.trips
    for each row execute procedure public.update_updated_at();

-- ============================================================
-- IG Bot Account Linking
-- ============================================================
create table public.ig_bot_links (
    id uuid primary key default uuid_generate_v4(),
    user_id text references public.profiles(id) on delete cascade not null,
    ig_user_id text not null unique,      -- Instagram user ID from webhook
    ig_username text,
    verified boolean not null default false,
    verification_code text,               -- 6-digit code sent via DM
    created_at timestamptz not null default now(),
    verified_at timestamptz
);

alter table public.ig_bot_links enable row level security;
-- Insert/update done by backend service role only (webhook handler)

create index idx_ig_bot_links_ig_user_id on public.ig_bot_links(ig_user_id);
create index idx_ig_bot_links_user_id on public.ig_bot_links(user_id);

-- ============================================================
-- Performance Indexes
-- ============================================================

-- Geo bounding box queries (map viewport)
create index idx_places_lat_lng on public.places(latitude, longitude);

-- Full-text search on place name + address
create index idx_places_fts on public.places
    using gin(to_tsvector('english', coalesce(name, '') || ' ' || coalesce(address, '')));

-- Status filter (wantToGo / visited)
create index idx_places_status on public.places(user_id, status);

-- One row per (user, Google place). Partial: unresolved/manual places
-- without a google_place_id stay unconstrained. See migration
-- 20260702120000_places_dedup_google_place_id.sql.
create unique index if not exists places_user_google_place_id_unique
  on public.places (user_id, google_place_id)
  where google_place_id is not null and google_place_id <> '';
