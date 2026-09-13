-- Apply after schema.sql. Additive, idempotent; never applied automatically by the app.
-- Internal operational metadata only. No prompts, source URLs, queries or place notes.
create table if not exists analysis_sessions (
 id uuid primary key, user_id text not null references profiles(id) on delete cascade,
 started_at timestamptz not null default now(), finished_at timestamptz,
 events_truncated boolean not null default false,
 client_events_expected boolean not null default true, client_events_received boolean not null default false,
 outcome text check(outcome in ('review_candidate','source_only','failed','cancelled')),
 unique(id,user_id)
);
alter table analysis_sessions add column if not exists client_events_expected boolean not null default true;
alter table analysis_sessions add column if not exists client_events_received boolean not null default false;
create index if not exists analysis_sessions_owner_day on analysis_sessions(user_id,started_at);
create table if not exists analysis_usage_events (
 id uuid primary key, analysis_id uuid not null, user_id text not null,
 operation text not null check(operation in ('google_places','gemini','metadata','public_search','media_download','rubric','local_ocr','local_asr','apple_maps','china_places')),
 model text, origin text not null check(origin in ('server','client')),
 outcome text not null check(outcome in ('pending','success','failure','cancelled')),
 reserved_micros bigint check(reserved_micros>=0), estimated_micros bigint check(estimated_micros>=0),
 duration_ms integer check(duration_ms>=0), input_tokens bigint check(input_tokens>=0),output_tokens bigint check(output_tokens>=0),
 thinking_tokens bigint check(thinking_tokens>=0),cached_tokens bigint check(cached_tokens>=0),total_tokens bigint check(total_tokens>=0),
 price_version text, created_at timestamptz not null default now(),
 foreign key(analysis_id,user_id) references analysis_sessions(id,user_id) on delete cascade
);
create index if not exists analysis_events_day on analysis_usage_events(created_at) where origin='server';
create index if not exists analysis_events_owner on analysis_usage_events(user_id,analysis_id);
create table if not exists analysis_captures (
 analysis_id uuid not null, capture_id uuid not null references captures(id) on delete cascade,
 user_id text not null, primary key(analysis_id,capture_id),
 foreign key(analysis_id,user_id) references analysis_sessions(id,user_id) on delete cascade
);
-- Cache is private recovery output, separately scoped from operational usage records.
create table if not exists analysis_recovery_runs (
 key text primary key, user_id text not null references profiles(id) on delete cascade,
 capture_id uuid not null references captures(id) on delete cascade,
 state text not null check(state in ('running','completed','failed')),
 lease_token uuid not null,lease_expires_at timestamptz not null,result jsonb,updated_at timestamptz not null
);
create index if not exists analysis_recovery_expiry on analysis_recovery_runs(lease_expires_at);
