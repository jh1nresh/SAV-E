-- Restricted, revocable Share Extension sessions and bounded analysis replay control.
-- Apply after analysis-usage.sql. Additive and never applied automatically by the app.
create table if not exists share_extension_sessions (
    id uuid primary key default gen_random_uuid(),
    owner_id text not null references profiles(id) on delete cascade,
    owner_subject text not null,
    installation_id uuid not null,
    token_hash text not null unique,
    expires_at timestamptz not null,
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    constraint share_extension_sessions_token_hash_check check (token_hash ~ '^[0-9a-f]{64}$')
);

create unique index if not exists share_extension_sessions_active_install
    on share_extension_sessions(owner_id, installation_id) where revoked_at is null;
create index if not exists share_extension_sessions_expiry
    on share_extension_sessions(expires_at) where revoked_at is null;

create table if not exists share_extension_analyses (
    analysis_id uuid primary key,
    session_id uuid not null references share_extension_sessions(id) on delete cascade,
    request_hash text not null,
    status text not null,
    response jsonb,
    created_at timestamptz not null default now(),
    finished_at timestamptz,
    constraint share_extension_analyses_request_hash_check check (request_hash ~ '^[0-9a-f]{64}$'),
    constraint share_extension_analyses_status_check check (status in ('pending', 'completed', 'failed')),
    constraint share_extension_analyses_response_check check (
        (status = 'completed' and response is not null and jsonb_typeof(response) = 'object')
        or (status <> 'completed' and response is null)
    )
);

create index if not exists share_extension_analyses_session_created
    on share_extension_analyses(session_id, created_at desc);
