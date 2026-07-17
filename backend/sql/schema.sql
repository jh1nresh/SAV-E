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
alter table profiles add column if not exists privy_user_id text;
alter table profiles add column if not exists pet_preset text;
alter table profiles add column if not exists pet_name text;
alter table profiles add column if not exists pet_selected_at timestamptz;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'profiles_pet_preset_check') then
        alter table profiles add constraint profiles_pet_preset_check
            check (pet_preset is null or pet_preset in ('sprout', 'spark', 'cloud'));
    end if;
end $$;

create unique index if not exists idx_profiles_handle on profiles(lower(handle)) where handle is not null;
create unique index if not exists idx_profiles_referral_code on profiles(referral_code) where referral_code is not null;
create unique index if not exists idx_profiles_privy_user_id on profiles(privy_user_id) where privy_user_id is not null;

create table if not exists user_channels (
    id uuid primary key default gen_random_uuid(),
    profile_id text references profiles(id) on delete cascade not null,
    channel text not null,
    channel_user_id text not null,
    phone_e164 text,
    verified_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint user_channels_channel_check check (channel in ('imessage', 'sms', 'line', 'whatsapp', 'sendblue'))
);

create unique index if not exists user_channels_channel_user_unique
    on user_channels(channel, channel_user_id);
create index if not exists user_channels_profile_idx
    on user_channels(profile_id, channel);

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
    origin_shared_place_link_id uuid,
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
alter table places add column if not exists origin_shared_place_link_id uuid;

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
    source_resolution jsonb,
    status text not null default 'review',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint captures_source_type_check check (source_type in ('url', 'note', 'screenshot', 'video', 'file', 'manual')),
    constraint captures_status_check check (status in ('review', 'investigating', 'resolved', 'archived')),
    constraint captures_source_resolution_check check (
        source_resolution is null or (
            jsonb_typeof(source_resolution) = 'object'
            and source_resolution ?& array['original_url', 'resolved_url', 'redirect_chain', 'status']
            and jsonb_typeof(source_resolution -> 'original_url') = 'string'
            and jsonb_typeof(source_resolution -> 'resolved_url') = 'string'
            and jsonb_typeof(source_resolution -> 'redirect_chain') = 'array'
            and source_resolution ->> 'status' in ('resolved', 'blocked_login', 'expired', 'opaque_unresolved')
        )
    )
);

create index if not exists idx_captures_user_id on captures(user_id, created_at desc);
create index if not exists idx_captures_status on captures(user_id, status);
alter table captures add column if not exists source_resolution jsonb;
do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'captures_source_resolution_check'
          and conrelid = 'captures'::regclass
    ) then
        alter table captures add constraint captures_source_resolution_check check (
            source_resolution is null or (
                jsonb_typeof(source_resolution) = 'object'
                and source_resolution ?& array['original_url', 'resolved_url', 'redirect_chain', 'status']
                and jsonb_typeof(source_resolution -> 'original_url') = 'string'
                and jsonb_typeof(source_resolution -> 'resolved_url') = 'string'
                and jsonb_typeof(source_resolution -> 'redirect_chain') = 'array'
                and source_resolution ->> 'status' in ('resolved', 'blocked_login', 'expired', 'opaque_unresolved')
            )
        );
    end if;
end $$;

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

alter table place_candidates drop constraint if exists place_candidates_status_check;
alter table place_candidates add constraint place_candidates_status_check check (
    status in ('review', 'confirmed', 'rejected', 'saved', 'needs_more_evidence', 'source_only')
);

create table if not exists place_claims (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    place_id uuid references places(id) on delete cascade not null,
    claim_type text not null,
    claim text not null,
    idempotency_key text,
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

alter table place_claims add column if not exists idempotency_key text;
alter table place_claims drop constraint if exists place_claims_experience_review_check;
alter table place_claims add constraint place_claims_experience_review_check check (
    claim_type <> 'experience_review' or (
        proof_level = 'visited_self_reported'
        and visibility = 'private'
        and author_type = 'self'
        and author_relationship = 'self'
        and author_public_handle is null
        and observed_at is not null
        and idempotency_key is not null
        and coalesce(context->>'occasion', '') in ('general', 'solo', 'date', 'friends', 'work', 'travel')
        and coalesce(ratings->>'would_return', '') in ('yes', 'no', 'unsure')
    )
);

create index if not exists idx_place_claims_user_place on place_claims(user_id, place_id, created_at desc);
create index if not exists idx_place_claims_proof on place_claims(user_id, proof_level);
create index if not exists idx_place_claims_type on place_claims(user_id, claim_type);
create index if not exists idx_place_claims_visibility on place_claims(user_id, visibility);
create unique index if not exists idx_place_claims_experience_idempotency
    on place_claims(user_id, place_id, idempotency_key)
    where claim_type = 'experience_review' and idempotency_key is not null;

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

create table if not exists recommendation_analysis_receipts (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    product text not null default 'save',
    receipt_type text not null default 'recommendation_analysis',
    agent_id text not null,
    capability text not null,
    input_hash text not null,
    output_hash text not null,
    private_payload_ref text not null,
    private_payload jsonb not null default '{}'::jsonb,
    public_summary jsonb not null default '{}'::jsonb,
    preference_signals text[] not null default '{}',
    evaluator_verdict text not null,
    settlement_state text not null,
    created_at timestamptz not null default now(),
    constraint recommendation_analysis_receipts_product_check check (product = 'save'),
    constraint recommendation_analysis_receipts_type_check check (receipt_type = 'recommendation_analysis'),
    constraint recommendation_analysis_receipts_verdict_check check (
        evaluator_verdict in ('pass', 'partial', 'fail', 'manual_review')
    ),
    constraint recommendation_analysis_receipts_settlement_check check (
        settlement_state in ('not_settled', 'pending', 'settled', 'refunded', 'manual_review')
    )
);

create unique index if not exists idx_recommendation_analysis_receipts_ref
    on recommendation_analysis_receipts(private_payload_ref);
create index if not exists idx_recommendation_analysis_receipts_user
    on recommendation_analysis_receipts(user_id, created_at desc);
create index if not exists idx_recommendation_analysis_receipts_hashes
    on recommendation_analysis_receipts(input_hash, output_hash);

-- Explicit preference memory is separate from saved places and request-local
-- taste signals. Removed/corrected rows remain tombstones for sync/audit.
create table if not exists memory_preferences (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    preference_type text not null,
    normalized_value text not null,
    context text not null default 'general',
    polarity text not null,
    source text not null,
    evidence_refs text[] not null default '{}',
    evidence_count integer not null default 0,
    confidence double precision not null default 1,
    status text not null,
    corrected_from_id uuid references memory_preferences(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint memory_preferences_polarity_check check (polarity in ('like', 'dislike', 'constraint')),
    constraint memory_preferences_source_check check (source in ('explicit', 'inferred')),
    constraint memory_preferences_status_check check (status in ('proposed', 'active', 'corrected', 'removed')),
    constraint memory_preferences_confidence_check check (confidence >= 0 and confidence <= 1),
    constraint memory_preferences_evidence_count_check check (evidence_count >= 0)
);
create index if not exists idx_memory_preferences_user_status
    on memory_preferences(user_id, status, updated_at desc);

-- Outcomes reference opaque records and versions; private queries/notes/source
-- payloads are deliberately excluded and no preference mutation is triggered.
create table if not exists recommendation_outcomes (
    id uuid primary key default gen_random_uuid(),
    user_id text references profiles(id) on delete cascade not null,
    recommendation_id text not null,
    labels text[] not null,
    label_source text not null,
    candidate_ids uuid[] not null default '{}',
    place_ids uuid[] not null default '{}',
    memory_refs text[] not null default '{}',
    evidence_refs text[] not null default '{}',
    correction_class text,
    receipt_ref text,
    model_version text,
    retrieval_version text,
    created_at timestamptz not null default now(),
    constraint recommendation_outcomes_label_source_check check (
        label_source in ('explicit_user', 'evaluator', 'deterministic_outcome')
    ),
    constraint recommendation_outcomes_labels_check check (cardinality(labels) > 0)
);
create index if not exists idx_recommendation_outcomes_user_created
    on recommendation_outcomes(user_id, created_at desc);

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
    sender_display_name text,
    sender_handle text,
    source_verified_at timestamptz,
    note_consent_version integer,
    payload jsonb not null,
    expires_at timestamptz default (now() + interval '30 days'),
    created_at timestamptz not null default now(),
    constraint shared_place_links_code_check check (code ~ '^[A-Za-z0-9_-]{6,32}$')
);

alter table shared_place_links
    alter column expires_at set default (now() + interval '30 days');

alter table shared_place_links
    add column if not exists sender_display_name text;
alter table shared_place_links
    add column if not exists sender_handle text;
alter table shared_place_links
    add column if not exists source_verified_at timestamptz;

do $$
begin
    if not exists (
        select 1
        from information_schema.columns
        where table_schema = current_schema()
          and table_name = 'shared_place_links'
          and column_name = 'note_consent_version'
    ) then
        alter table shared_place_links add column note_consent_version integer;
        update shared_place_links set payload = payload - 'note';
    end if;
end
$$;

update shared_place_links
set payload = payload - 'note'
where note_consent_version is null
  and payload ? 'note';

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'shared_place_links_note_consent_check'
          and conrelid = 'shared_place_links'::regclass
    ) then
        alter table shared_place_links
            add constraint shared_place_links_note_consent_check check (
                note_consent_version is null or note_consent_version = 1
            );
    end if;
end
$$;

update shared_place_links
set expires_at = created_at + interval '30 days'
where expires_at is null
   or expires_at <= created_at
   or expires_at > created_at + interval '30 days';

alter table shared_place_links
    alter column expires_at set not null;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'shared_place_links_expiry_check'
          and conrelid = 'shared_place_links'::regclass
    ) then
        alter table shared_place_links
            add constraint shared_place_links_expiry_check check (
                expires_at > created_at
                and expires_at <= created_at + interval '30 days'
            );
    end if;
end
$$;

create index if not exists idx_shared_place_links_user_id on shared_place_links(user_id, created_at desc);
create index if not exists idx_shared_place_links_source_place_id on shared_place_links(source_place_id);

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'places_origin_shared_place_link_id_fkey'
          and conrelid = 'places'::regclass
    ) then
        alter table places
            add constraint places_origin_shared_place_link_id_fkey
            foreign key (origin_shared_place_link_id)
            references shared_place_links(id)
            on delete set null;
    end if;
end
$$;

create unique index if not exists idx_places_user_origin_shared_place_link_unique
    on places(user_id, origin_shared_place_link_id)
    where origin_shared_place_link_id is not null;

create table if not exists friend_share_events (
    id uuid primary key default gen_random_uuid(),
    shared_place_link_id uuid references shared_place_links(id) on delete cascade not null,
    sender_user_id text references profiles(id) on delete cascade not null,
    recipient_user_id text references profiles(id) on delete set null,
    recipient_place_id uuid references places(id) on delete set null,
    event_type text not null,
    surface text not null,
    reason_code text,
    created_at timestamptz not null default now(),
    constraint friend_share_events_type_check check (event_type in (
        'friend_share_link_created',
        'friend_share_receipt_opened',
        'friend_share_save_tapped',
        'friend_share_saved',
        'friend_share_duplicate_blocked',
        'friend_share_open_failed'
    )),
    constraint friend_share_events_surface_check check (surface in ('server', 'web', 'ios', 'app_clip')),
    constraint friend_share_events_terminal_surface_check check (
        event_type not in ('friend_share_saved', 'friend_share_duplicate_blocked')
        or surface = 'server'
    ),
    constraint friend_share_events_reason_check check (
        (event_type = 'friend_share_open_failed' and reason_code in (
            'expired',
            'malformed_payload',
            'network_error',
            'server_error',
            'unsupported_route',
            'unknown'
        ))
        or (event_type <> 'friend_share_open_failed' and reason_code is null)
    )
);

alter table friend_share_events
    add column if not exists recipient_place_id uuid references places(id) on delete set null;

create index if not exists idx_friend_share_events_link on friend_share_events(shared_place_link_id, created_at desc);
create index if not exists idx_friend_share_events_sender on friend_share_events(sender_user_id, created_at desc);
create index if not exists idx_friend_share_events_recipient on friend_share_events(recipient_user_id, created_at desc)
    where recipient_user_id is not null;
create unique index if not exists idx_friend_share_events_terminal_receipt_unique
    on friend_share_events(shared_place_link_id, recipient_user_id, recipient_place_id)
    where recipient_user_id is not null
      and recipient_place_id is not null
      and event_type in ('friend_share_saved', 'friend_share_duplicate_blocked');

create unique index if not exists idx_friend_share_events_recipient_client_unique
    on friend_share_events(
        shared_place_link_id,
        recipient_user_id,
        event_type,
        surface,
        coalesce(reason_code, '')
    )
    where recipient_user_id is not null
      and event_type in (
          'friend_share_receipt_opened',
          'friend_share_save_tapped',
          'friend_share_open_failed'
      );

create unique index if not exists idx_friend_share_events_public_open_unique
    on friend_share_events(shared_place_link_id, surface)
    where recipient_user_id is null
      and event_type = 'friend_share_receipt_opened';

create unique index if not exists idx_friend_share_events_public_failure_unique
    on friend_share_events(shared_place_link_id, surface, reason_code)
    where recipient_user_id is null
      and event_type = 'friend_share_open_failed';

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
    current_attempt_no integer not null default 1,
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
    constraint workflow_runs_attempt_check check (current_attempt_no > 0),
    constraint workflow_runs_credit_reserved_check check (credit_reserved > 0),
    constraint workflow_runs_credit_settlement_check check (credit_settlement in ('pending', 'consumed', 'refunded', 'partial'))
);

create index if not exists idx_workflow_runs_user_id on workflow_runs(user_id, created_at desc);
create index if not exists idx_workflow_runs_listing on workflow_runs(listing_id, status, created_at desc);
alter table workflow_runs add column if not exists work_order_id uuid references work_orders(id) on delete set null;
alter table workflow_runs add column if not exists current_attempt_no integer not null default 1;
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'workflow_runs_attempt_check'
          and conrelid = 'workflow_runs'::regclass
    ) then
        alter table workflow_runs add constraint workflow_runs_attempt_check check (current_attempt_no > 0);
    end if;
end $$;
create index if not exists idx_workflow_runs_work_order_id on workflow_runs(work_order_id, created_at desc);

create table if not exists workflow_steps (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    attempt_no integer not null default 1,
    step_key text not null,
    status text not null default 'queued',
    input jsonb not null default '{}'::jsonb,
    output jsonb not null default '{}'::jsonb,
    error text,
    error_code text,
    input_hash text,
    output_hash text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    constraint workflow_steps_status_check check (status in ('queued', 'running', 'succeeded', 'failed', 'skipped'))
);

create index if not exists idx_workflow_steps_run_id on workflow_steps(run_id, created_at);
alter table workflow_steps add column if not exists attempt_no integer not null default 1;
alter table workflow_steps add column if not exists error_code text;
alter table workflow_steps add column if not exists input_hash text;
alter table workflow_steps add column if not exists output_hash text;
alter table workflow_steps add column if not exists metadata jsonb not null default '{}'::jsonb;
create unique index if not exists idx_workflow_steps_attempt_key on workflow_steps(run_id, attempt_no, step_key);

create table if not exists source_artifacts (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    attempt_no integer not null default 1,
    artifact_type text not null,
    source_url text,
    storage_ref text,
    extracted_text text,
    content_hash text,
    privacy text not null default 'private',
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists idx_source_artifacts_run_id on source_artifacts(run_id);
alter table source_artifacts add column if not exists attempt_no integer not null default 1;
alter table source_artifacts add column if not exists content_hash text;
alter table source_artifacts add column if not exists privacy text not null default 'private';

create table if not exists evidence_items (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    attempt_no integer not null default 1,
    artifact_id uuid references source_artifacts(id) on delete set null,
    evidence_type text not null,
    summary text not null default '',
    payload jsonb not null default '{}'::jsonb,
    confidence double precision not null default 0,
    created_at timestamptz not null default now(),
    constraint evidence_items_confidence_check check (confidence >= 0 and confidence <= 1)
);

create index if not exists idx_evidence_items_run_id on evidence_items(run_id);
alter table evidence_items add column if not exists attempt_no integer not null default 1;

alter table place_candidates add column if not exists workflow_run_id uuid references workflow_runs(id) on delete set null;
create index if not exists idx_place_candidates_workflow_run_id on place_candidates(workflow_run_id);

create table if not exists user_decisions (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    user_id text references profiles(id) on delete cascade not null,
    attempt_no integer not null default 1,
    candidate_id uuid references place_candidates(id) on delete set null,
    final_place_id uuid references places(id) on delete set null,
    action text not null,
    edited_payload jsonb not null default '{}'::jsonb,
    reason text,
    reason_code text,
    idempotency_key text not null,
    before_hash text,
    after_hash text,
    created_at timestamptz not null default now(),
    constraint user_decisions_action_check check (action in (
        'confirm', 'edit', 'reject', 'source_only', 'wrong_place', 'wrong_city',
        'wrong_branch', 'merge_existing', 'needs_more_evidence', 'investigate_more'
    ))
);

create index if not exists idx_user_decisions_run_id on user_decisions(run_id, created_at desc);
alter table user_decisions add column if not exists attempt_no integer not null default 1;
alter table user_decisions add column if not exists candidate_id uuid references place_candidates(id) on delete set null;
alter table user_decisions add column if not exists final_place_id uuid references places(id) on delete set null;
alter table user_decisions add column if not exists reason_code text;
alter table user_decisions add column if not exists idempotency_key text;
alter table user_decisions add column if not exists before_hash text;
alter table user_decisions add column if not exists after_hash text;
update user_decisions set idempotency_key = 'legacy:' || id::text where idempotency_key is null;
alter table user_decisions alter column idempotency_key set not null;
alter table user_decisions drop constraint if exists user_decisions_action_check;
update user_decisions set action = 'source_only' where action = 'save_source_only';
alter table user_decisions add constraint user_decisions_action_check check (action in (
    'confirm', 'edit', 'reject', 'source_only', 'wrong_place', 'wrong_city',
    'wrong_branch', 'merge_existing', 'needs_more_evidence', 'investigate_more'
));
create unique index if not exists idx_user_decisions_idempotency on user_decisions(run_id, idempotency_key);

create table if not exists workflow_receipts (
    id uuid primary key default gen_random_uuid(),
    run_id uuid references workflow_runs(id) on delete cascade not null,
    workflow_id text not null,
    workflow_version text not null default 'v0',
    operator_id text,
    requester_id text references profiles(id) on delete set null,
    receipt_type text not null default 'decision',
    attempt_no integer not null default 1,
    result_revision integer not null default 1,
    idempotency_key text not null,
    supersedes_receipt_id uuid references workflow_receipts(id) on delete set null,
    is_current boolean not null default true,
    failure_code text,
    failed_step text,
    retryable boolean,
    decision_id uuid references user_decisions(id) on delete set null,
    job_id text,
    agent_id text not null default 'SAV-E',
    model_provenance jsonb not null default '{}'::jsonb,
    model_provenance_bucket text not null default 'unknown',
    input_hash text,
    output_hash text,
    permission_snapshot jsonb not null default '{}'::jsonb,
    tool_trace_refs text[] not null default '{}',
    latency_ms integer,
    cost_estimate jsonb,
    failure_reason text,
    user_feedback_action text,
    quality_delta numeric not null default 0,
    reputation_delta numeric not null default 0,
    verdict text not null,
    settlement text not null,
    evaluator_summary text not null default '',
    evidence_refs text[] not null default '{}',
    candidate_refs text[] not null default '{}',
    receipt_hash text not null,
    anchor_status text not null default 'offchain',
    private_url text,
    privacy_validated boolean not null default false,
    created_at timestamptz not null default now(),
    constraint workflow_receipts_type_check check (receipt_type in ('analysis', 'decision')),
    constraint workflow_receipts_verdict_check check (verdict in ('pass', 'partial', 'fail', 'refund', 'dispute')),
    constraint workflow_receipts_settlement_check check (settlement in ('credit_consumed', 'credit_refunded', 'partial', 'manual_review')),
    constraint workflow_receipts_anchor_status_check check (anchor_status in ('offchain', 'batch_anchored', 'onchain')),
    constraint workflow_receipts_attempt_check check (attempt_no > 0 and result_revision > 0)
);

alter table workflow_receipts add column if not exists receipt_type text not null default 'decision';
alter table workflow_receipts add column if not exists attempt_no integer not null default 1;
alter table workflow_receipts add column if not exists result_revision integer not null default 1;
alter table workflow_receipts add column if not exists idempotency_key text;
alter table workflow_receipts add column if not exists supersedes_receipt_id uuid references workflow_receipts(id) on delete set null;
alter table workflow_receipts add column if not exists is_current boolean not null default true;
alter table workflow_receipts add column if not exists failure_code text;
alter table workflow_receipts add column if not exists failed_step text;
alter table workflow_receipts add column if not exists retryable boolean;
alter table workflow_receipts add column if not exists decision_id uuid references user_decisions(id) on delete set null;
alter table workflow_receipts add column if not exists workflow_version text not null default 'v0';
alter table workflow_receipts add column if not exists operator_id text;
alter table workflow_receipts add column if not exists requester_id text references profiles(id) on delete set null;
alter table workflow_receipts add column if not exists job_id text;
alter table workflow_receipts add column if not exists agent_id text not null default 'SAV-E';
alter table workflow_receipts add column if not exists model_provenance jsonb not null default '{}'::jsonb;
alter table workflow_receipts add column if not exists model_provenance_bucket text not null default 'unknown';
alter table workflow_receipts add column if not exists input_hash text;
alter table workflow_receipts add column if not exists output_hash text;
alter table workflow_receipts add column if not exists permission_snapshot jsonb not null default '{}'::jsonb;
alter table workflow_receipts add column if not exists tool_trace_refs text[] not null default '{}';
alter table workflow_receipts add column if not exists latency_ms integer;
alter table workflow_receipts add column if not exists cost_estimate jsonb;
alter table workflow_receipts add column if not exists failure_reason text;
alter table workflow_receipts add column if not exists user_feedback_action text;
alter table workflow_receipts add column if not exists quality_delta numeric not null default 0;
alter table workflow_receipts add column if not exists reputation_delta numeric not null default 0;
alter table workflow_receipts add column if not exists privacy_validated boolean not null default false;

update workflow_receipts set user_feedback_action = 'source_only'
where user_feedback_action = 'save_source_only';
update workflow_receipts set idempotency_key = 'legacy:' || id::text where idempotency_key is null;
alter table workflow_receipts alter column idempotency_key set not null;

with original_decode_failure_pairs as (
    select lr.run_id
    from workflow_receipts lr
    join workflow_runs r on r.id = lr.run_id
    where lr.receipt_type = 'analysis'
      and lr.idempotency_key like 'legacy:%'
      and lr.idempotency_key not like 'legacy:decode-failure-duplicate:%'
      and r.result_type = 'technical_failure'
      and r.credit_settlement = 'pending'
      and not exists (
          select 1
          from workflow_receipts current_generation
          where current_generation.run_id = lr.run_id
            and current_generation.receipt_type = 'analysis'
            and current_generation.idempotency_key not like 'legacy:%'
      )
    group by lr.run_id
    having count(*) = 2
       and count(*) filter (where lr.verdict in ('pass', 'partial')) = 1
       and count(*) filter (where lr.verdict in ('fail', 'refund')) = 1
       and max(lr.created_at) filter (where lr.verdict in ('pass', 'partial'))
           < max(lr.created_at) filter (where lr.verdict in ('fail', 'refund'))
)
update workflow_receipts wr
set idempotency_key = 'legacy:decode-failure-duplicate:' || wr.id::text
from original_decode_failure_pairs pair
where wr.run_id = pair.run_id
  and wr.receipt_type = 'analysis'
  and wr.verdict in ('fail', 'refund')
  and wr.idempotency_key like 'legacy:%';

with legacy_receipts as (
    select wr.*
    from workflow_receipts wr
    where wr.idempotency_key like 'legacy:%'
      and not exists (
          select 1
          from workflow_receipts current_generation
          where current_generation.run_id = wr.run_id
            and current_generation.receipt_type = wr.receipt_type
            and current_generation.idempotency_key not like 'legacy:%'
      )
), legacy_groups as (
    select
        lr.run_id,
        lr.receipt_type,
        (
            lr.receipt_type = 'analysis'
            and count(*) = 2
            and count(*) filter (where lr.verdict in ('pass', 'partial')) = 1
            and count(*) filter (where lr.verdict in ('fail', 'refund')) = 1
            and max(lr.created_at) filter (where lr.verdict in ('pass', 'partial'))
                < max(lr.created_at) filter (where lr.verdict in ('fail', 'refund'))
            and (
                count(*) filter (
                    where lr.idempotency_key like 'legacy:decode-failure-duplicate:%'
                ) = 1
                or (
                    r.credit_settlement = 'pending'
                    and r.result_type = 'technical_failure'
                )
                or (
                    r.credit_settlement = 'pending'
                    and r.result_type in ('review_candidate', 'source_only_clue')
                    and count(*) filter (
                        where lr.id = r.receipt_id
                          and lr.verdict in ('pass', 'partial')
                    ) = 1
                )
            )
        ) as decode_failure_pair
    from legacy_receipts lr
    join workflow_runs r on r.id = lr.run_id
    group by lr.run_id, lr.receipt_type, r.result_type, r.credit_settlement, r.receipt_id
), legacy_ranked_receipts as (
    select
        lr.id,
        row_number() over (
            partition by lr.run_id, lr.receipt_type
            order by
                case
                    when lg.decode_failure_pair and lr.verdict in ('pass', 'partial') then 0
                    when lg.decode_failure_pair then 1
                    else 0
                end,
                lr.created_at desc,
                lr.id desc
        ) as receipt_rank
    from legacy_receipts lr
    join legacy_groups lg on lg.run_id = lr.run_id and lg.receipt_type = lr.receipt_type
)
update workflow_receipts wr
set is_current = legacy_ranked_receipts.receipt_rank = 1
from legacy_ranked_receipts
where wr.id = legacy_ranked_receipts.id;

with repaired_analysis as (
    select wr.run_id, wr.id, wr.evidence_refs, wr.candidate_refs
    from workflow_receipts wr
    join workflow_runs r on r.id = wr.run_id
    where wr.receipt_type = 'analysis'
      and wr.is_current = true
      and wr.idempotency_key like 'legacy:%'
      and wr.verdict in ('pass', 'partial')
      and r.result_type = 'technical_failure'
      and r.credit_settlement = 'pending'
      and (
          select count(*)
          from workflow_receipts pair
          where pair.run_id = wr.run_id
            and pair.receipt_type = 'analysis'
            and pair.idempotency_key like 'legacy:%'
      ) = 2
      and not exists (
          select 1
          from workflow_receipts current_generation
          where current_generation.run_id = wr.run_id
            and current_generation.receipt_type = 'analysis'
            and current_generation.idempotency_key not like 'legacy:%'
      )
      and exists (
          select 1
          from workflow_receipts failed
          where failed.run_id = wr.run_id
            and failed.receipt_type = 'analysis'
            and failed.id <> wr.id
            and failed.idempotency_key like 'legacy:%'
            and failed.verdict in ('fail', 'refund')
            and failed.created_at > wr.created_at
      )
), repaired_runs as (
    update workflow_runs r
    set status = 'needs_review',
        result_type = case
            when cardinality(repaired_analysis.candidate_refs) > 0 then 'review_candidate'
            else 'source_only_clue'
        end,
        evidence_tier = case when r.evidence_tier = 'none' then 'weak' else r.evidence_tier end,
        result_evidence_refs = repaired_analysis.evidence_refs,
        result_candidate_refs = repaired_analysis.candidate_refs,
        receipt_id = repaired_analysis.id,
        completed_at = null
    from repaired_analysis
    where r.id = repaired_analysis.run_id
    returning r.work_order_id, r.user_id
)
update work_orders wo
set status = 'needs_review'
from repaired_runs
where wo.id = repaired_runs.work_order_id and wo.user_id = repaired_runs.user_id;

create unique index if not exists idx_workflow_receipts_hash on workflow_receipts(receipt_hash);
create index if not exists idx_workflow_receipts_run_id on workflow_receipts(run_id, created_at desc);
create unique index if not exists idx_workflow_receipts_idempotency on workflow_receipts(run_id, receipt_type, idempotency_key);
create unique index if not exists idx_workflow_receipts_current_analysis on workflow_receipts(run_id, attempt_no)
where receipt_type = 'analysis' and is_current;
create unique index if not exists idx_workflow_receipts_decision_id on workflow_receipts(decision_id)
where decision_id is not null;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'workflow_receipts_attempt_check'
          and conrelid = 'workflow_receipts'::regclass
    ) then
        alter table workflow_receipts add constraint workflow_receipts_attempt_check check (
            attempt_no > 0 and result_revision > 0
        );
    end if;
    if not exists (select 1 from pg_constraint where conname = 'workflow_receipts_failure_code_check') then
        alter table workflow_receipts add constraint workflow_receipts_failure_code_check check (
            failure_code is null or failure_code in (
                'invalid_source', 'unsupported_source', 'source_fetch_failed', 'source_auth_blocked',
                'source_rate_limited', 'source_content_unavailable', 'extractor_failed',
                'model_provider_failed', 'model_timeout', 'model_invalid_output', 'map_lookup_failed',
                'candidate_persistence_failed', 'receipt_persistence_failed', 'configuration_missing',
                'internal_error'
            )
        );
    end if;
    if not exists (select 1 from pg_constraint where conname = 'workflow_receipts_failed_step_check') then
        alter table workflow_receipts add constraint workflow_receipts_failed_step_check check (
            failed_step is null or failed_step in (
                'validate_input', 'fetch_source', 'extract_source', 'classify_source',
                'recover_candidate', 'resolve_map_identity', 'persist_candidate',
                'write_receipt', 'settle_credit'
            )
        );
    end if;
end $$;

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
    attempt_no integer not null default 1,
    decision_id uuid references user_decisions(id) on delete set null,
    settlement_key text not null,
    delta numeric(12, 4) not null,
    reason text not null,
    settlement text not null default 'pending',
    created_at timestamptz not null default now(),
    constraint credit_ledger_settlement_check check (settlement in ('pending', 'consumed', 'refunded', 'partial'))
);

create index if not exists idx_credit_ledger_user_id on credit_ledger(user_id, created_at desc);
create index if not exists idx_credit_ledger_run_id on credit_ledger(run_id);
alter table credit_ledger alter column delta type numeric(12, 4) using delta::numeric;
alter table credit_ledger add column if not exists attempt_no integer not null default 1;
alter table credit_ledger add column if not exists decision_id uuid references user_decisions(id) on delete set null;
alter table credit_ledger add column if not exists settlement_key text;
update credit_ledger set settlement_key = 'legacy:' || id::text where settlement_key is null;
alter table credit_ledger alter column settlement_key set not null;
create unique index if not exists idx_credit_ledger_settlement_key on credit_ledger(run_id, settlement_key)
where run_id is not null;

insert into credit_ledger (
    run_id, user_id, attempt_no, settlement_key, delta, reason, settlement
)
select
    r.id,
    r.user_id,
    r.current_attempt_no,
    'legacy_technical_failure:' || r.current_attempt_no::text,
    r.credit_reserved,
    'legacy_technical_failure',
    'refunded'
from workflow_runs r
join workflow_receipts wr on wr.run_id = r.id
where r.result_type = 'technical_failure'
  and r.credit_settlement = 'pending'
  and wr.receipt_type = 'analysis'
  and wr.is_current = true
  and wr.idempotency_key like 'legacy:%'
  and wr.verdict in ('fail', 'refund')
on conflict (run_id, settlement_key) where run_id is not null do nothing;

with refunded_runs as (
    update workflow_runs r
    set status = 'failed',
        credit_settlement = 'refunded',
        completed_at = coalesce(r.completed_at, now())
    where r.result_type = 'technical_failure'
      and r.credit_settlement = 'pending'
      and exists (
          select 1
          from workflow_receipts wr
          where wr.run_id = r.id
            and wr.receipt_type = 'analysis'
            and wr.is_current = true
            and wr.idempotency_key like 'legacy:%'
            and wr.verdict in ('fail', 'refund')
      )
    returning r.work_order_id, r.user_id
)
update work_orders wo
set status = 'failed'
from refunded_runs
where wo.id = refunded_runs.work_order_id and wo.user_id = refunded_runs.user_id;

create table if not exists workflow_reputation_snapshots (
    id uuid primary key default gen_random_uuid(),
    requester_id text references profiles(id) on delete cascade,
    listing_id text not null,
    workflow_id text not null,
    workflow_version text not null default 'v0',
    source_type text not null default 'unknown',
    operator_id text not null default 'unknown',
    model_provenance_bucket text not null default 'unknown',
    policy_version text not null default 'v0',
    is_current boolean not null default true,
    run_count integer not null default 0,
    operational_success_count integer not null default 0,
    technical_failure_count integer not null default 0,
    confirmed_count integer not null default 0,
    edited_count integer not null default 0,
    rejected_count integer not null default 0,
    source_only_count integer not null default 0,
    median_latency_ms double precision,
    user_decision_coverage double precision not null default 0,
    operational_success_rate double precision not null default 0,
    confirmation_rate double precision not null default 0,
    edit_rate double precision not null default 0,
    rejection_rate double precision not null default 0,
    technical_failure_rate double precision not null default 0,
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
alter table workflow_reputation_snapshots add column if not exists requester_id text references profiles(id) on delete cascade;
alter table workflow_reputation_snapshots add column if not exists workflow_version text not null default 'v0';
alter table workflow_reputation_snapshots add column if not exists source_type text not null default 'unknown';
alter table workflow_reputation_snapshots add column if not exists operator_id text not null default 'unknown';
alter table workflow_reputation_snapshots add column if not exists model_provenance_bucket text not null default 'unknown';
alter table workflow_reputation_snapshots add column if not exists policy_version text not null default 'v0';
alter table workflow_reputation_snapshots add column if not exists is_current boolean not null default true;
alter table workflow_reputation_snapshots add column if not exists operational_success_count integer not null default 0;
alter table workflow_reputation_snapshots add column if not exists technical_failure_count integer not null default 0;
alter table workflow_reputation_snapshots add column if not exists confirmed_count integer not null default 0;
alter table workflow_reputation_snapshots add column if not exists edited_count integer not null default 0;
alter table workflow_reputation_snapshots add column if not exists rejected_count integer not null default 0;
alter table workflow_reputation_snapshots add column if not exists source_only_count integer not null default 0;
alter table workflow_reputation_snapshots add column if not exists median_latency_ms double precision;
alter table workflow_reputation_snapshots add column if not exists user_decision_coverage double precision not null default 0;
alter table workflow_reputation_snapshots add column if not exists operational_success_rate double precision not null default 0;
alter table workflow_reputation_snapshots add column if not exists confirmation_rate double precision not null default 0;
alter table workflow_reputation_snapshots add column if not exists edit_rate double precision not null default 0;
alter table workflow_reputation_snapshots add column if not exists rejection_rate double precision not null default 0;
alter table workflow_reputation_snapshots add column if not exists technical_failure_rate double precision not null default 0;
create unique index if not exists idx_workflow_reputation_current_subject
on workflow_reputation_snapshots (
    requester_id, workflow_id, workflow_version, source_type,
    operator_id, model_provenance_bucket, policy_version
)
where is_current and requester_id is not null;

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
    ),
    (
        'SLR.cafe.place_order',
        'SLR',
        'cafe',
        'place_order',
        'Place a cafe/food order via SLL-R from buyer intent + location, charge (card-on-file or pay link), and return a receipt.',
        'purchase',
        '{"type":"object","required":["query"],"properties":{"query":{"type":"string"},"location":{"type":"object","properties":{"lat":{"type":"number"},"lng":{"type":"number"}}}}}'::jsonb,
        '{"type":"object","required":["order_id","status"],"properties":{"order_id":{"type":"string"},"status":{"type":"string"},"receipt_url":{"type":"string"}}}'::jsonb
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
