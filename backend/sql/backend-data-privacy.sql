-- Existing installs: separately authorized apply through the single-transaction
-- SQL helper. Idempotent; no user rows, ownership or status are rewritten.
-- Re-run after installing any optional source-owned tables to enable their RLS.
-- Backend-owned table privacy boundary
-- Explicit source-owned allowlist: never blanket-revoke existing public tables.
-- Apply in the intended schema as its backend table creator/owner. Browser
-- table grants inherited from a global default ACL or through role membership
-- need separate authorization. Direct PUBLIC/anon/authenticated revokes do not
-- remove privileges granted to a parent role that those browser roles inherit.
do $backend_data_privacy$
declare
    target_schema text := current_schema();
    managed_table text;
    browser_role text;
    managed_tables text[] := array[
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
    ];
begin
    -- USAGE follows INHERIT membership, the path that yields effective table
    -- privileges (including TRUNCATE, which RLS does not govern).
    if exists (
        select 1 from pg_default_acl d
        cross join lateral aclexplode(d.defaclacl) a
        where d.defaclrole = current_user::regrole
          and d.defaclnamespace = 0 and d.defaclobjtype = 'r'
          and (
              a.grantee = 0
              or exists (
                  select 1 from pg_roles browser
                  join pg_roles granted on granted.oid = a.grantee
                  where browser.rolname in ('anon', 'authenticated')
                    and pg_has_role(browser.oid, granted.oid, 'USAGE')
              )
          )
    ) then
        raise exception 'Global default table grants to browser roles require separate authorized remediation';
    end if;

    -- Parent-role schema defaults and existing table/owner grants are not
    -- removed by the PUBLIC/anon/authenticated revokes below. Refuse before
    -- changing any ACL so a membership hole cannot remain after a "successful"
    -- apply, and so refusal stays atomic.
    if exists (
        select 1 from pg_default_acl d
        cross join lateral aclexplode(d.defaclacl) a
        join pg_roles granted on granted.oid = a.grantee
        join pg_roles browser on browser.rolname in ('anon', 'authenticated')
        where d.defaclrole = current_user::regrole
          and d.defaclnamespace = target_schema::regnamespace
          and d.defaclobjtype = 'r'
          and granted.rolname not in ('anon', 'authenticated')
          and pg_has_role(browser.oid, granted.oid, 'USAGE')
    ) or exists (
        select 1
        from unnest(managed_tables) as t(name)
        join pg_class c on c.oid = to_regclass(format('%I.%I', target_schema, t.name))
        cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
        join pg_roles granted on granted.oid = a.grantee
        join pg_roles browser on browser.rolname in ('anon', 'authenticated')
        where granted.rolname not in ('anon', 'authenticated')
          and pg_has_role(browser.oid, granted.oid, 'USAGE')
    ) or exists (
        select 1
        from unnest(managed_tables) as t(name)
        join pg_class c on c.oid = to_regclass(format('%I.%I', target_schema, t.name))
        join pg_roles owner on owner.oid = c.relowner
        join pg_roles browser on browser.rolname in ('anon', 'authenticated')
        where browser.oid <> owner.oid
          and pg_has_role(browser.oid, owner.oid, 'USAGE')
    ) then
        raise exception 'Browser-role table grants inherited through role membership require separate authorized remediation';
    end if;

    -- Only this creator/schema. Keep service_role grants, all other creators'
    -- defaults, global defaults, and every unrelated existing table unchanged.
    -- Later optional/runtime tables start private even before RLS is enabled.
    execute format('alter default privileges for role %I in schema %I revoke all privileges on tables from public', current_user, target_schema);
    for browser_role in select rolname from pg_roles where rolname in ('anon', 'authenticated') loop
        execute format('alter default privileges for role %I in schema %I revoke all privileges on tables from %I', current_user, target_schema, browser_role);
    end loop;

    foreach managed_table in array managed_tables loop
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
