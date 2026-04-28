create extension if not exists pgcrypto;

create table if not exists profiles (
    id text primary key,
    display_name text not null default '',
    email text,
    avatar_url text,
    is_premium boolean not null default false,
    instagram_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists places (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
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
    extracted_dishes text[] default '{}',
    price_range text,
    recommender text,
    google_rating double precision,
    google_price_level integer,
    opening_hours text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_places_user_id on places(user_id);
create index if not exists idx_places_category on places(category);
create index if not exists idx_places_lat_lng on places(latitude, longitude);
create index if not exists idx_places_status on places(user_id, status);
create index if not exists idx_places_fts on places
    using gin(to_tsvector('english', coalesce(name, '') || ' ' || coalesce(address, '')));

create table if not exists trips (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    name text not null,
    city text not null default '',
    start_date date,
    end_date date,
    is_optimized boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_trips_user_id on trips(user_id);

create table if not exists trip_stops (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid references trips(id) on delete cascade not null,
    place_id uuid references places(id) on delete set null,
    place_name text not null,
    day integer not null default 1,
    order_index integer not null default 0,
    start_time text,
    duration integer,
    note text,
    created_at timestamptz not null default now()
);

create index if not exists idx_trip_stops_trip_id on trip_stops(trip_id);

create table if not exists collections (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    name text not null,
    emoji text not null default '📍',
    created_at timestamptz not null default now()
);

create table if not exists collection_places (
    collection_id uuid references collections(id) on delete cascade,
    place_id uuid references places(id) on delete cascade,
    primary key (collection_id, place_id)
);

create table if not exists ig_bot_links (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    ig_user_id text not null unique,
    ig_username text,
    verified boolean not null default false,
    verification_code text,
    created_at timestamptz not null default now(),
    verified_at timestamptz
);

create index if not exists idx_ig_bot_links_ig_user_id on ig_bot_links(ig_user_id);
create index if not exists idx_ig_bot_links_user_id on ig_bot_links(user_id);

create or replace function update_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists update_profiles_updated_at on profiles;
create trigger update_profiles_updated_at before update on profiles
    for each row execute procedure update_updated_at();

drop trigger if exists update_places_updated_at on places;
create trigger update_places_updated_at before update on places
    for each row execute procedure update_updated_at();

drop trigger if exists update_trips_updated_at on trips;
create trigger update_trips_updated_at before update on trips
    for each row execute procedure update_updated_at();
