-- Apply before deploying ordered entitlement persistence. Additive/idempotent;
-- no owner/status backfill: arrival time is not a signed event version.
-- Legacy rows retain existing ownership and revocation. The backend only seeds
-- signed versions without reducing known expiry; a legacy revoked row requires
-- revoked evidence or a new purchase period at/after its previous expiry.
alter table subscription_entitlements add column if not exists transaction_id text;
alter table subscription_entitlements add column if not exists purchase_date_ms bigint;
alter table subscription_entitlements add column if not exists signed_date_ms bigint;

-- One verified event state per unregistered subscription. No account owner is
-- assigned until authenticated registration supplies its signed account token.
-- Retain refund state until that registration atomically consumes it; no TTL may
-- remove denial evidence and make an old receipt eligible again.
create table if not exists pending_subscription_notifications (
    original_transaction_id text primary key,
    transaction_id text not null,
    app_account_token uuid,
    product_id text not null,
    status text not null check (status in ('active', 'expired', 'revoked', 'none')),
    environment text not null check (environment in ('Production', 'Sandbox', 'Xcode')),
    expires_at timestamptz not null,
    purchase_date_ms bigint not null,
    signed_date_ms bigint not null,
    revocation_reversed boolean not null default false
);

-- Entitlement state is backend-only, including on Supabase public schemas.
-- RLS is default-deny for non-owners; table revokes also block TRUNCATE, which
-- RLS does not cover. Remove copied default grants and any older direct grants.
alter table subscription_entitlements enable row level security;
alter table pending_subscription_notifications enable row level security;
revoke all privileges on table subscription_entitlements, pending_subscription_notifications from public;
do $$
declare browser_role text;
begin
    for browser_role in select rolname from pg_roles where rolname in ('anon', 'authenticated') loop
        execute format('revoke all privileges on table subscription_entitlements, pending_subscription_notifications from %I', browser_role);
    end loop;
end $$;
