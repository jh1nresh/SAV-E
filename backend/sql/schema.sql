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

create table if not exists captures (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    source_type text not null default 'url',
    source_url text,
    raw_text text,
    title text,
    status text not null default 'review',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint captures_source_type_check check (source_type in ('url', 'note', 'screenshot', 'video', 'file', 'manual')),
    constraint captures_status_check check (status in ('review', 'investigating', 'resolved', 'archived'))
);

create index if not exists idx_captures_user_id on captures(user_id, created_at desc);
create index if not exists idx_captures_status on captures(user_id, status);

create table if not exists place_candidates (
    id uuid primary key default gen_random_uuid(),
    capture_id uuid references captures(id) on delete cascade not null,
    place_id uuid references places(id) on delete set null,
    name text not null,
    address text not null default '',
    city text not null default '',
    latitude double precision,
    longitude double precision,
    evidence jsonb not null default '[]'::jsonb,
    confidence double precision not null default 0,
    missing_info text[] not null default '{}',
    status text not null default 'review',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint place_candidates_confidence_check check (confidence >= 0 and confidence <= 1),
    constraint place_candidates_status_check check (status in ('review', 'confirmed', 'rejected', 'saved', 'needs_more_evidence'))
);

create index if not exists idx_place_candidates_capture_id on place_candidates(capture_id);
create index if not exists idx_place_candidates_status on place_candidates(status);

create table if not exists agent_decisions (
    id uuid primary key default gen_random_uuid(),
    candidate_id uuid references place_candidates(id) on delete cascade not null,
    action text not null,
    reason text,
    created_at timestamptz not null default now(),
    constraint agent_decisions_action_check check (action in ('confirmed', 'rejected', 'saved_place', 'added_to_trip', 'needs_more_evidence'))
);

create index if not exists idx_agent_decisions_candidate_id on agent_decisions(candidate_id);

create table if not exists agent_capabilities (
    id text primary key,
    agent_family text not null,
    vertical text not null,
    action text not null,
    description text not null default '',
    risk_level text not null default 'read',
    input_schema jsonb not null default '{}'::jsonb,
    output_schema jsonb not null default '{}'::jsonb,
    enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint agent_capabilities_family_check check (agent_family in ('R8', 'SLR', 'BYR', 'NEG', 'VFY')),
    constraint agent_capabilities_risk_check check (risk_level in ('read', 'quote', 'hold', 'purchase')),
    constraint agent_capabilities_action_unique unique (agent_family, vertical, action)
);

create index if not exists idx_agent_capabilities_family on agent_capabilities(agent_family, vertical);
create index if not exists idx_agent_capabilities_enabled on agent_capabilities(enabled);

create table if not exists recommendation_sets (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    capture_id uuid references captures(id) on delete set null,
    prompt text not null default '',
    summary text not null default '',
    context jsonb not null default '{}'::jsonb,
    status text not null default 'draft',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint recommendation_sets_status_check check (status in ('draft', 'review', 'accepted', 'archived'))
);

create index if not exists idx_recommendation_sets_user_id on recommendation_sets(user_id, created_at desc);
create index if not exists idx_recommendation_sets_capture_id on recommendation_sets(capture_id);

create table if not exists recommendation_items (
    id uuid primary key default gen_random_uuid(),
    recommendation_set_id uuid references recommendation_sets(id) on delete cascade not null,
    place_candidate_id uuid references place_candidates(id) on delete set null,
    place_id uuid references places(id) on delete set null,
    rank integer not null default 0,
    title text not null,
    rationale text not null default '',
    r8_score double precision,
    slr_status text not null default 'not_checked',
    evidence jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now(),
    constraint recommendation_items_r8_score_check check (r8_score is null or (r8_score >= 0 and r8_score <= 1)),
    constraint recommendation_items_slr_status_check check (slr_status in ('not_checked', 'available', 'unavailable', 'needs_handoff', 'error'))
);

create index if not exists idx_recommendation_items_set_id on recommendation_items(recommendation_set_id, rank);
create index if not exists idx_recommendation_items_candidate_id on recommendation_items(place_candidate_id);

create table if not exists agent_tool_calls (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    capability_id text references agent_capabilities(id) on delete restrict not null,
    capture_id uuid references captures(id) on delete set null,
    recommendation_set_id uuid references recommendation_sets(id) on delete set null,
    input jsonb not null default '{}'::jsonb,
    output jsonb,
    status text not null default 'pending',
    error text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint agent_tool_calls_status_check check (status in ('pending', 'running', 'succeeded', 'failed', 'cancelled'))
);

create index if not exists idx_agent_tool_calls_user_id on agent_tool_calls(user_id, created_at desc);
create index if not exists idx_agent_tool_calls_capability_id on agent_tool_calls(capability_id);
create index if not exists idx_agent_tool_calls_recommendation_set_id on agent_tool_calls(recommendation_set_id);

insert into agent_capabilities (id, agent_family, vertical, action, description, risk_level, input_schema, output_schema)
values
    (
        'R8.rank_places',
        'R8',
        'places',
        'rank_places',
        'Rank candidate places against user taste, trip context, and constraints.',
        'read',
        '{"type":"object","required":["candidates"],"properties":{"candidates":{"type":"array"},"context":{"type":"object"}}}'::jsonb,
        '{"type":"object","required":["ranked_items"],"properties":{"ranked_items":{"type":"array"}}}'::jsonb
    ),
    (
        'R8.explain_match',
        'R8',
        'places',
        'explain_match',
        'Explain why a candidate matches or does not match the user taste profile.',
        'read',
        '{"type":"object","required":["candidate"],"properties":{"candidate":{"type":"object"},"user_memory":{"type":"object"}}}'::jsonb,
        '{"type":"object","required":["reasons"],"properties":{"reasons":{"type":"array"},"warnings":{"type":"array"}}}'::jsonb
    ),
    (
        'SLR.restaurants.search_availability',
        'SLR',
        'restaurants',
        'search_availability',
        'Check restaurant availability or handoff links without confirming a reservation.',
        'quote',
        '{"type":"object","required":["party_size","date"],"properties":{"party_size":{"type":"number"},"date":{"type":"string"},"place":{"type":"object"}}}'::jsonb,
        '{"type":"object","required":["options"],"properties":{"options":{"type":"array"},"handoff_url":{"type":"string"}}}'::jsonb
    ),
    (
        'SLR.flights.search_itineraries',
        'SLR',
        'flights',
        'search_itineraries',
        'Search flight itinerary options without booking or payment.',
        'quote',
        '{"type":"object","required":["origin","destination","departure_date"],"properties":{"origin":{"type":"string"},"destination":{"type":"string"},"departure_date":{"type":"string"},"return_date":{"type":"string"}}}'::jsonb,
        '{"type":"object","required":["itineraries"],"properties":{"itineraries":{"type":"array"},"handoff_url":{"type":"string"}}}'::jsonb
    )
on conflict (id) do update
set agent_family = excluded.agent_family,
    vertical = excluded.vertical,
    action = excluded.action,
    description = excluded.description,
    risk_level = excluded.risk_level,
    input_schema = excluded.input_schema,
    output_schema = excluded.output_schema,
    enabled = true,
    updated_at = now();

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

drop trigger if exists update_captures_updated_at on captures;
create trigger update_captures_updated_at before update on captures
    for each row execute procedure update_updated_at();

drop trigger if exists update_place_candidates_updated_at on place_candidates;
create trigger update_place_candidates_updated_at before update on place_candidates
    for each row execute procedure update_updated_at();

drop trigger if exists update_agent_capabilities_updated_at on agent_capabilities;
create trigger update_agent_capabilities_updated_at before update on agent_capabilities
    for each row execute procedure update_updated_at();

drop trigger if exists update_recommendation_sets_updated_at on recommendation_sets;
create trigger update_recommendation_sets_updated_at before update on recommendation_sets
    for each row execute procedure update_updated_at();

drop trigger if exists update_agent_tool_calls_updated_at on agent_tool_calls;
create trigger update_agent_tool_calls_updated_at before update on agent_tool_calls
    for each row execute procedure update_updated_at();
