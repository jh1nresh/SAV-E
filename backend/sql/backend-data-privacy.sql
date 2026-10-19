-- Existing installs: separately authorized apply through the single-transaction
-- SQL helper. Idempotent; no user rows, ownership or status are rewritten.
-- Re-run after installing any optional source-owned tables to enable their RLS.
-- Backend-owned table privacy boundary
-- Explicit source-owned allowlist: never blanket-revoke existing public tables.
-- Apply in the intended schema as its backend table creator/owner. Browser
-- table grants inherited from a global default ACL need separate authorization.
do $backend_data_privacy$
declare
    target_schema text := current_schema();
    managed_table text;
    browser_role text;
begin
    if exists (
        select 1 from pg_default_acl d
        cross join lateral aclexplode(d.defaclacl) a
        left join pg_roles r on r.oid = a.grantee
        where d.defaclrole = current_user::regrole
          and d.defaclnamespace = 0 and d.defaclobjtype = 'r'
          and (a.grantee = 0 or r.rolname in ('anon', 'authenticated'))
    ) then
        raise exception 'Global default table grants to browser roles require separate authorized remediation';
    end if;

    -- Only this creator/schema. Keep service_role grants, all other creators'
    -- defaults, global defaults, and every unrelated existing table unchanged.
    -- Later optional/runtime tables start private even before RLS is enabled.
    execute format('alter default privileges for role %I in schema %I revoke all privileges on tables from public', current_user, target_schema);
    for browser_role in select rolname from pg_roles where rolname in ('anon', 'authenticated') loop
        execute format('alter default privileges for role %I in schema %I revoke all privileges on tables from %I', current_user, target_schema, browser_role);
    end loop;

    foreach managed_table in array array[
        'agent_capabilities',
        'agent_decisions',
        'agent_tool_calls',
        'ai_usage_events',
        'analysis_captures',
        'analysis_recovery_runs',
        'analysis_sessions',
        'analysis_usage_events',
        'candidate_extraction_inputs',
        'captures',
        'claim_usage_receipts',
        'clearing_block_items',
        'clearing_blocks',
        'collection_places',
        'collections',
        'credit_ledger',
        'evidence_items',
        'extraction_cache_epochs',
        'follows',
        'friend_rating_saves',
        'friend_restaurant_ratings',
        'friend_share_events',
        'ig_bot_links',
        'list_items',
        'list_members',
        'list_share_codes',
        'lists',
        'memory_preferences',
        'pending_subscription_notifications',
        'place_candidates',
        'place_claims',
        'place_identity_feedback',
        'place_signal_state',
        'place_social_signals',
        'place_visibility',
        'places',
        'profiles',
        'recommendation_analysis_receipts',
        'recommendation_items',
        'recommendation_outcomes',
        'recommendation_sets',
        'related_place_source_packs',
        'semantic_extraction_cache',
        'sendblue_conversation_state',
        'sendblue_reviews',
        'sendblue_saved_places',
        'sendblue_sllr_buyers',
        'sendblue_sllr_notified_runs',
        'sendblue_user_locations',
        'sendblue_verified_visits',
        'share_extension_analyses',
        'share_extension_sessions',
        'shared_place_links',
        'source_artifacts',
        'subscription_entitlements',
        'trip_stops',
        'trips',
        'user_channels',
        'user_decisions',
        'work_orders',
        'workflow_receipts',
        'workflow_reputation_snapshots',
        'workflow_runs',
        'workflow_steps'
    ] loop
        if to_regclass(format('%I.%I', target_schema, managed_table)) is null then
            continue; -- Optional installations are not created by this migration.
        end if;
        execute format('alter table %I.%I enable row level security', target_schema, managed_table);
        -- TRUNCATE/REFERENCES/TRIGGER (and newer server privileges) also need
        -- revocation: RLS alone does not govern every table operation.
        execute format('revoke all privileges on table %I.%I from public', target_schema, managed_table);
        for browser_role in select rolname from pg_roles where rolname in ('anon', 'authenticated') loop
            execute format('revoke all privileges on table %I.%I from %I', target_schema, managed_table, browser_role);
        end loop;
    end loop;
end $backend_data_privacy$;
