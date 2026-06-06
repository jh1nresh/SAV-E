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

alter table profiles add column if not exists handle text;
alter table profiles add column if not exists referral_code text;
alter table profiles add column if not exists trusted_guide_count integer not null default 0;
alter table profiles add column if not exists ai_planning_credits integer not null default 0;
alter table profiles add column if not exists profile_stamp_unlocked_at timestamptz;

create unique index if not exists idx_profiles_handle on profiles(lower(handle)) where handle is not null;
create unique index if not exists idx_profiles_referral_code on profiles(referral_code) where referral_code is not null;

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

create index if not exists idx_places_user_id on places(user_id);
create index if not exists idx_places_category on places(category);
create index if not exists idx_places_lat_lng on places(latitude, longitude);
create index if not exists idx_places_status on places(user_id, status);
create index if not exists idx_places_fts on places
    using gin(to_tsvector('english', coalesce(name, '') || ' ' || coalesce(address, '')));

alter table places add column if not exists business_photo_urls text[] default '{}';

create table if not exists follows (
    id uuid primary key default gen_random_uuid(),
    follower_id text references profiles(id) on delete cascade not null,
    following_id text references profiles(id) on delete cascade not null,
    lens text not null default 'friends',
    source text not null default 'manual',
    referral_code text,
    created_at timestamptz not null default now(),
    constraint follows_unique_pair unique (follower_id, following_id),
    constraint follows_not_self check (follower_id <> following_id),
    constraint follows_lens_check check (lens in ('forYou', 'friends', 'trending')),
    constraint follows_source_check check (source in ('manual', 'referral', 'app_clip_handoff'))
);

create index if not exists idx_follows_follower on follows(follower_id, created_at desc);
create index if not exists idx_follows_following on follows(following_id, created_at desc);

create table if not exists place_visibility (
    place_id uuid primary key references places(id) on delete cascade,
    user_id text references profiles(id) on delete cascade not null,
    visibility text not null default 'private',
    allow_friend_signal boolean not null default false,
    allow_trending_signal boolean not null default false,
    published_at timestamptz,
    updated_at timestamptz not null default now(),
    constraint place_visibility_value_check check (visibility in ('private', 'friends', 'public_link', 'public_guide'))
);

create index if not exists idx_place_visibility_user on place_visibility(user_id, visibility);
create index if not exists idx_place_visibility_signal on place_visibility(visibility, allow_friend_signal, allow_trending_signal);

create table if not exists place_social_signals (
    id uuid primary key default gen_random_uuid(),
    place_id uuid references places(id) on delete cascade not null,
    viewer_user_id text references profiles(id) on delete cascade,
    actor_user_id text references profiles(id) on delete cascade,
    signal_type text not null,
    lens text not null default 'forYou',
    friend_count integer not null default 0,
    save_count integer not null default 0,
    trending_score double precision not null default 0,
    category_rank integer,
    source_label text not null default '',
    referrer_id text references profiles(id) on delete set null,
    referral_code text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint place_social_signals_type_check check (signal_type in ('friend_saved', 'trending', 'referral_guide')),
    constraint place_social_signals_lens_check check (lens in ('forYou', 'friends', 'trending')),
    constraint place_social_signals_score_check check (trending_score >= 0)
);

create index if not exists idx_place_social_signals_viewer on place_social_signals(viewer_user_id, lens, created_at desc);
create index if not exists idx_place_social_signals_place on place_social_signals(place_id, signal_type);
create index if not exists idx_place_social_signals_trending on place_social_signals(lens, trending_score desc);

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

create table if not exists place_claims (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    place_id uuid references places(id) on delete cascade not null,
    claim_type text not null,
    claim text not null,
    agent_usable_summary text not null default '',
    author_type text not null default 'self',
    author_public_handle text,
    author_relationship text not null default 'self',
    proof_level text not null default 'source_backed',
    evidence_refs text[] not null default '{}',
    visibility text not null default 'private',
    confidence double precision not null default 0.5,
    context jsonb not null default '{}'::jsonb,
    ratings jsonb not null default '{}'::jsonb,
    observed_at timestamptz,
    expires_or_stale_after timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint place_claims_proof_level_check check (
        proof_level in (
            'source_backed',
            'user_confirmed_place',
            'visited_self_reported',
            'friend_verified',
            'receipt_backed',
            'merchant_confirmed',
            'network_reputation'
        )
    ),
    constraint place_claims_visibility_check check (
        visibility in ('private', 'link_shared', 'public', 'permissioned', 'paid')
    ),
    constraint place_claims_confidence_check check (confidence >= 0 and confidence <= 1)
);

create index if not exists idx_place_claims_user_place on place_claims(user_id, place_id, created_at desc);
create index if not exists idx_place_claims_proof on place_claims(user_id, proof_level);
create index if not exists idx_place_claims_type on place_claims(user_id, claim_type);
create index if not exists idx_place_claims_visibility on place_claims(user_id, visibility);

create table if not exists claim_usage_receipts (
    id uuid primary key default gen_random_uuid(),
    claim_id uuid references place_claims(id) on delete cascade not null,
    place_id uuid references places(id) on delete cascade not null,
    consumer_agent_id text not null default 'unknown_agent',
    consumer_user_id text references profiles(id) on delete set null,
    action text not null,
    outcome text not null default 'unknown',
    created_at timestamptz not null default now(),
    constraint claim_usage_receipts_action_check check (
        action in ('recommended_to_user', 'cited', 'saved_to_vault', 'adapted_collection')
    ),
    constraint claim_usage_receipts_outcome_check check (outcome in ('accepted', 'rejected', 'unknown'))
);

create index if not exists idx_claim_usage_receipts_claim on claim_usage_receipts(claim_id, created_at desc);
create index if not exists idx_claim_usage_receipts_place on claim_usage_receipts(place_id, created_at desc);
create index if not exists idx_claim_usage_receipts_agent on claim_usage_receipts(consumer_agent_id, created_at desc);

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

create table if not exists shared_place_links (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    user_id text references profiles(id) on delete cascade not null,
    source_place_id uuid references places(id) on delete set null,
    payload jsonb not null,
    expires_at timestamptz,
    created_at timestamptz not null default now(),
    constraint shared_place_links_code_check check (code ~ '^[A-Za-z0-9_-]{6,32}$')
);

create index if not exists idx_shared_place_links_user_id on shared_place_links(user_id, created_at desc);
create index if not exists idx_shared_place_links_source_place_id on shared_place_links(source_place_id);

create table if not exists work_orders (
    id uuid primary key default gen_random_uuid(),
    workflow_id text not null,
    listing_id text not null,
    user_id text references profiles(id) on delete cascade not null,
    intent text not null,
    input_type text not null default 'url',
    input_ref text,
    source_url text,
    evaluator_policy_id text not null,
    settlement_mode text not null,
    budget_policy jsonb not null default '{}'::jsonb,
    status text not null default 'queued',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint work_orders_status_check check (status in ('queued', 'running', 'completed', 'failed', 'needs_review', 'cancelled'))
);

create index if not exists idx_work_orders_user_id on work_orders(user_id, created_at desc);
create index if not exists idx_work_orders_listing on work_orders(listing_id, status, created_at desc);

create table if not exists workflow_runs (
    id uuid primary key default gen_random_uuid(),
    work_order_id uuid references work_orders(id) on delete set null,
    workflow_id text not null,
    listing_id text not null,
    user_id text references profiles(id) on delete cascade not null,
    source_url text,
    source_type text not null default 'url',
    status text not null default 'queued',
    result_type text,
    confidence double precision,
    evidence_tier text not null default 'none',
    result_evidence_refs text[] not null default '{}',
    result_candidate_refs text[] not null default '{}',
    credit_reserved integer not null default 1,
    credit_settlement text not null default 'pending',
    receipt_id uuid,
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    updated_at timestamptz not null default now(),
    constraint workflow_runs_status_check check (status in ('queued', 'running', 'completed', 'failed', 'needs_review')),
    constraint workflow_runs_result_type_check check (result_type is null or result_type in ('confirmed_map_stamp', 'review_candidate', 'source_only_clue', 'technical_failure')),
    constraint workflow_runs_evidence_tier_check check (evidence_tier in ('none', 'weak', 'likely', 'confirmed')),
    constraint workflow_runs_confidence_check check (confidence is null or (confidence >= 0 and confidence <= 1)),
    constraint workflow_runs_credit_reserved_check check (credit_reserved > 0),
    constraint workflow_runs_credit_settlement_check check (credit_settlement in ('pending', 'consumed', 'refunded', 'partial'))
);

create index if not exists idx_workflow_runs_user_id on workflow_runs(user_id, created_at desc);
create index if not exists idx_workflow_runs_listing on workflow_runs(listing_id, status, created_at desc);
alter table workflow_runs add column if not exists work_order_id uuid references work_orders(id) on delete set null;
create index if not exists idx_workflow_runs_work_order_id on workflow_runs(work_order_id, created_at desc);

create table if not exists workflow_steps (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    step_key text not null,
    status text not null default 'queued',
    input jsonb not null default '{}'::jsonb,
    output jsonb not null default '{}'::jsonb,
    error text,
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    constraint workflow_steps_status_check check (status in ('queued', 'running', 'succeeded', 'failed', 'skipped'))
);

create index if not exists idx_workflow_steps_run_id on workflow_steps(run_id, created_at);

create table if not exists source_artifacts (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    artifact_type text not null,
    source_url text,
    storage_ref text,
    extracted_text text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists idx_source_artifacts_run_id on source_artifacts(run_id);

create table if not exists evidence_items (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    artifact_id uuid references source_artifacts(id) on delete set null,
    evidence_type text not null,
    summary text not null default '',
    payload jsonb not null default '{}'::jsonb,
    confidence double precision not null default 0,
    created_at timestamptz not null default now(),
    constraint evidence_items_confidence_check check (confidence >= 0 and confidence <= 1)
);

create index if not exists idx_evidence_items_run_id on evidence_items(run_id);

alter table place_candidates add column if not exists workflow_run_id uuid references workflow_runs(id) on delete set null;
create index if not exists idx_place_candidates_workflow_run_id on place_candidates(workflow_run_id);

create table if not exists user_decisions (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    user_id text references profiles(id) on delete cascade not null,
    action text not null,
    edited_payload jsonb not null default '{}'::jsonb,
    reason text,
    created_at timestamptz not null default now(),
    constraint user_decisions_action_check check (action in ('confirm', 'edit', 'reject', 'needs_more_evidence'))
);

create index if not exists idx_user_decisions_run_id on user_decisions(run_id, created_at desc);

create table if not exists workflow_receipts (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    workflow_id text not null,
    verdict text not null,
    settlement text not null,
    evaluator_summary text not null default '',
    evidence_refs text[] not null default '{}',
    candidate_refs text[] not null default '{}',
    receipt_hash text not null,
    anchor_status text not null default 'offchain',
    private_url text,
    created_at timestamptz not null default now(),
    constraint workflow_receipts_verdict_check check (verdict in ('pass', 'partial', 'fail', 'refund', 'dispute')),
    constraint workflow_receipts_settlement_check check (settlement in ('credit_consumed', 'credit_refunded', 'partial', 'manual_review')),
    constraint workflow_receipts_anchor_status_check check (anchor_status in ('offchain', 'batch_anchored', 'onchain'))
);

create unique index if not exists idx_workflow_receipts_hash on workflow_receipts(receipt_hash);
create index if not exists idx_workflow_receipts_run_id on workflow_receipts(run_id, created_at desc);

create table if not exists clearing_blocks (
    id uuid primary key default gen_random_uuid(),
    chain_namespace text not null,
    user_id text references profiles(id) on delete cascade,
    block_number bigint not null,
    previous_block_hash text,
    merkle_root text not null,
    receipt_count integer not null,
    block_hash text not null,
    signer_agent_id text not null default 'save-backend',
    anchor_status text not null default 'offchain',
    anchor_chain text,
    anchor_tx_hash text,
    created_at timestamptz not null default now(),
    constraint clearing_blocks_receipt_count_check check (receipt_count > 0),
    constraint clearing_blocks_anchor_status_check check (anchor_status in ('offchain', 'batch_anchored', 'onchain'))
);

create unique index if not exists idx_clearing_blocks_namespace_user_number on clearing_blocks(chain_namespace, (coalesce(user_id, '')), block_number);
create unique index if not exists idx_clearing_blocks_hash on clearing_blocks(block_hash);
create index if not exists idx_clearing_blocks_user_id on clearing_blocks(user_id, created_at desc);

create table if not exists clearing_block_items (
    id uuid primary key default gen_random_uuid(),
    block_id uuid references clearing_blocks(id) on delete cascade not null,
    receipt_id uuid references workflow_receipts(id) on delete cascade not null,
    receipt_hash text not null,
    merkle_proof text[] not null default '{}',
    position integer not null,
    created_at timestamptz not null default now(),
    constraint clearing_block_items_position_check check (position >= 0)
);

create unique index if not exists idx_clearing_block_items_receipt_id on clearing_block_items(receipt_id);
create index if not exists idx_clearing_block_items_block_id on clearing_block_items(block_id, position);

create table if not exists credit_ledger (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete set null,
    user_id text references profiles(id) on delete cascade not null,
    delta integer not null,
    reason text not null,
    settlement text not null default 'pending',
    created_at timestamptz not null default now(),
    constraint credit_ledger_settlement_check check (settlement in ('pending', 'consumed', 'refunded', 'partial'))
);

create index if not exists idx_credit_ledger_user_id on credit_ledger(user_id, created_at desc);
create index if not exists idx_credit_ledger_run_id on credit_ledger(run_id);

create table if not exists workflow_reputation_snapshots (
    id uuid primary key default gen_random_uuid(),
    listing_id text not null,
    workflow_id text not null,
    run_count integer not null default 0,
    pass_count integer not null default 0,
    partial_count integer not null default 0,
    fail_count integer not null default 0,
    refund_count integer not null default 0,
    confirmed_save_count integer not null default 0,
    user_rejection_count integer not null default 0,
    hallucination_report_count integer not null default 0,
    created_at timestamptz not null default now()
);

create index if not exists idx_workflow_reputation_listing on workflow_reputation_snapshots(listing_id, created_at desc);

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

drop trigger if exists update_place_visibility_updated_at on place_visibility;
create trigger update_place_visibility_updated_at before update on place_visibility
    for each row execute procedure update_updated_at();

drop trigger if exists update_place_social_signals_updated_at on place_social_signals;
create trigger update_place_social_signals_updated_at before update on place_social_signals
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

drop trigger if exists update_place_claims_updated_at on place_claims;
create trigger update_place_claims_updated_at before update on place_claims
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

drop trigger if exists update_work_orders_updated_at on work_orders;
create trigger update_work_orders_updated_at before update on work_orders
    for each row execute procedure update_updated_at();

drop trigger if exists update_workflow_runs_updated_at on workflow_runs;
create trigger update_workflow_runs_updated_at before update on workflow_runs
    for each row execute procedure update_updated_at();
