-- Existing installs: separately authorized apply through the single-transaction
-- SQL helper. Idempotent; no user rows, ownership or status are rewritten.
-- Re-run after installing any optional source-owned tables to enable their RLS.
-- Backend-owned table privacy boundary
-- Explicit source-owned allowlist: never blanket-revoke existing public tables.
-- Apply in the intended schema as its backend table creator/owner. Browser
-- table grants inherited from a global default ACL or through role membership
-- (including SET-able NOINHERIT memberships) need separate authorization.
-- Implicit predefined privileges (pg_read_all_data, pg_write_all_data,
-- pg_maintain) and SUPERUSER/BYPASSRLS memberships also need separate
-- authorization; they do not appear in table ACLs.
-- Table REVOKE does not remove sequence privileges. Current-creator default
-- sequence grants to PUBLIC/anon/authenticated are revoked globally and in
-- this schema; owned serial/identity sequences of managed tables are revoked
-- the same way. Inherited sequence grants need separate authorization.
-- Direct PUBLIC/anon/authenticated revokes do not remove privileges granted
-- to a parent role that those browser roles can inherit or SET ROLE to.
-- Schema CREATE granted to PUBLIC/anon/authenticated is revoked so a browser
-- role cannot pre-create an absent runtime table. Inherited or foreign-grantor
-- schema CREATE needs separate authorization.
do $backend_data_privacy$
declare
    target_schema text := current_schema();
    managed_table text;
    browser_role text;
    seq_name text;
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
    -- MEMBER covers INHERIT (USAGE) and SET-able NOINHERIT memberships.
    -- SET ROLE parent can then use parent grants, including TRUNCATE, which
    -- RLS does not govern. Implicit predefined data/maintenance roles and
    -- SUPERUSER/BYPASSRLS also survive REVOKE and ordinary RLS; name lookup
    -- is a no-op on servers where pg_maintain does not exist.
    if exists (
        select 1 from pg_roles browser
        where browser.rolname in ('anon', 'authenticated')
          and (
              pg_has_role(browser.oid, current_user::regrole, 'MEMBER')
              or exists (
                  select 1 from pg_roles privileged
                  where (
                      privileged.rolsuper
                      or privileged.rolbypassrls
                      or privileged.rolname in ('pg_read_all_data', 'pg_write_all_data', 'pg_maintain')
                  )
                    and pg_has_role(browser.oid, privileged.oid, 'MEMBER')
              )
          )
    ) then
        raise exception 'Browser role membership reaches a backend owner or privileged role; separate authorized remediation required';
    end if;

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
                    and pg_has_role(browser.oid, granted.oid, 'MEMBER')
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
          and pg_has_role(browser.oid, granted.oid, 'MEMBER')
    ) or exists (
        select 1
        from unnest(managed_tables) as t(name)
        join pg_class c on c.oid = to_regclass(format('%I.%I', target_schema, t.name))
        cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
        join pg_roles granted on granted.oid = a.grantee
        join pg_roles browser on browser.rolname in ('anon', 'authenticated')
        where granted.rolname not in ('anon', 'authenticated')
          and pg_has_role(browser.oid, granted.oid, 'MEMBER')
    ) or exists (
        select 1
        from unnest(managed_tables) as t(name)
        join pg_class c on c.oid = to_regclass(format('%I.%I', target_schema, t.name))
        join pg_roles owner on owner.oid = c.relowner
        join pg_roles browser on browser.rolname in ('anon', 'authenticated')
        where browser.oid <> owner.oid
          and pg_has_role(browser.oid, owner.oid, 'MEMBER')
    ) then
        raise exception 'Browser-role table grants inherited through role membership require separate authorized remediation';
    end if;

    -- Table owners keep implicit privileges that REVOKE cannot remove, and
    -- RLS without FORCE does not apply to the owner. Direct browser-role
    -- ownership is therefore an incompatible state.
    if exists (
        select 1
        from unnest(managed_tables) as t(name)
        join pg_class c on c.oid = to_regclass(format('%I.%I', target_schema, t.name))
        join pg_roles owner on owner.oid = c.relowner
        where owner.rolname in ('anon', 'authenticated')
    ) then
        raise exception 'Managed table ownership by a browser role requires separate authorized remediation';
    end if;

    -- Table-level REVOKE leaves pg_attribute.attacl intact. Column SELECT/
    -- UPDATE/REFERENCES grants can still expose or mutate data under an
    -- existing policy or through foreign-key checks.
    if exists (
        select 1
        from unnest(managed_tables) as t(name)
        join pg_class c on c.oid = to_regclass(format('%I.%I', target_schema, t.name))
        join pg_attribute col on col.attrelid = c.oid
        cross join lateral aclexplode(col.attacl) a
        where col.attnum > 0 and not col.attisdropped
          and col.attacl is not null
          and (
              a.grantee = 0
              or exists (
                  select 1 from pg_roles browser
                  join pg_roles granted on granted.oid = a.grantee
                  where browser.rolname in ('anon', 'authenticated')
                    and pg_has_role(browser.oid, granted.oid, 'MEMBER')
              )
          )
    ) then
        raise exception 'Browser-role column grants require separate authorized remediation';
    end if;

    -- Owner REVOKE cannot remove privileges granted by another role. A
    -- delegated GRANT OPTION holder can grant TRUNCATE to PUBLIC/anon/
    -- authenticated; those entries survive and bypass RLS.
    if exists (
        select 1
        from unnest(managed_tables) as t(name)
        join pg_class c on c.oid = to_regclass(format('%I.%I', target_schema, t.name))
        cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
        where a.grantor <> current_user::regrole
          and (
              a.grantee = 0
              or exists (
                  select 1 from pg_roles browser
                  where browser.rolname in ('anon', 'authenticated')
                    and browser.oid = a.grantee
              )
          )
    ) then
        raise exception 'Browser-role table grants issued by another grantor require separate authorized remediation';
    end if;

    -- Sequence defaults and owned serial/identity sequences are not covered by
    -- table REVOKE. Direct PUBLIC/anon/authenticated grants are revoked below.
    -- MEMBER-reachable parent grants are not removed and must be refused.
    if exists (
        select 1 from pg_default_acl d
        cross join lateral aclexplode(d.defaclacl) a
        join pg_roles granted on granted.oid = a.grantee
        join pg_roles browser on browser.rolname in ('anon', 'authenticated')
        where d.defaclrole = current_user::regrole
          and d.defaclobjtype = 'S'
          and (d.defaclnamespace = 0 or d.defaclnamespace = target_schema::regnamespace)
          and granted.rolname not in ('anon', 'authenticated')
          and pg_has_role(browser.oid, granted.oid, 'MEMBER')
    ) or exists (
        select 1
        from unnest(managed_tables) as t(name)
        join pg_class c on c.oid = to_regclass(format('%I.%I', target_schema, t.name))
        join pg_depend dep on dep.refobjid = c.oid
          and dep.classid = 'pg_class'::regclass
          and dep.refclassid = 'pg_class'::regclass
          and dep.deptype in ('a', 'i')
        join pg_class s on s.oid = dep.objid and s.relkind = 'S'
        cross join lateral aclexplode(s.relacl) a
        join pg_roles granted on granted.oid = a.grantee
        join pg_roles browser on browser.rolname in ('anon', 'authenticated')
        where s.relacl is not null
          and granted.rolname not in ('anon', 'authenticated')
          and pg_has_role(browser.oid, granted.oid, 'MEMBER')
    ) then
        raise exception 'Browser-role sequence grants inherited through role membership require separate authorized remediation';
    end if;

    -- Owner REVOKE cannot remove sequence privileges granted by another role.
    -- A delegated GRANT OPTION holder can grant UPDATE/SELECT/USAGE to
    -- PUBLIC/anon/authenticated; those entries survive and allow setval.
    if exists (
        select 1
        from unnest(managed_tables) as t(name)
        join pg_class c on c.oid = to_regclass(format('%I.%I', target_schema, t.name))
        join pg_depend dep on dep.refobjid = c.oid
          and dep.classid = 'pg_class'::regclass
          and dep.refclassid = 'pg_class'::regclass
          and dep.deptype in ('a', 'i')
        join pg_class s on s.oid = dep.objid and s.relkind = 'S'
        cross join lateral aclexplode(coalesce(s.relacl, acldefault('S', s.relowner))) a
        where a.grantor <> current_user::regrole
          and (
              a.grantee = 0
              or exists (
                  select 1 from pg_roles browser
                  where browser.rolname in ('anon', 'authenticated')
                    and browser.oid = a.grantee
              )
          )
    ) then
        raise exception 'Browser-role sequence grants issued by another grantor require separate authorized remediation';
    end if;

    -- Schema CREATE is not covered by default table ACLs. PUBLIC still has
    -- CREATE on `public` in PostgreSQL 14 and upgraded databases. A browser
    -- role can pre-create an absent allowlisted runtime table; the startup
    -- create-if-not-exists path then accepts that owner, who bypasses RLS. Direct
    -- PUBLIC/anon/authenticated CREATE is revoked below. MEMBER-reachable
    -- parent CREATE and foreign-grantor CREATE need separate authorization.
    if exists (
        select 1
        from pg_namespace n
        cross join lateral aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
        join pg_roles granted on granted.oid = a.grantee
        join pg_roles browser on browser.rolname in ('anon', 'authenticated')
        where n.oid = target_schema::regnamespace
          and a.privilege_type = 'CREATE'
          and granted.rolname not in ('anon', 'authenticated')
          and pg_has_role(browser.oid, granted.oid, 'MEMBER')
    ) then
        raise exception 'Browser-role schema CREATE grants inherited through role membership require separate authorized remediation';
    end if;

    if exists (
        select 1
        from pg_namespace n
        cross join lateral aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
        where n.oid = target_schema::regnamespace
          and a.privilege_type = 'CREATE'
          and a.grantor <> current_user::regrole
          and (
              a.grantee = 0
              or exists (
                  select 1 from pg_roles browser
                  where browser.rolname in ('anon', 'authenticated')
                    and browser.oid = a.grantee
              )
          )
    ) then
        raise exception 'Browser-role schema CREATE grants issued by another grantor require separate authorized remediation';
    end if;

    -- Schema CREATE is revoked before default table ACLs. Defaults only
    -- protect objects created by current_user; leftover PUBLIC CREATE lets
    -- a browser role plant an absent runtime table and keep ownership
    -- through the startup create-if-not-exists path.
    execute format('revoke create on schema %I from public', target_schema);
    for browser_role in select rolname from pg_roles where rolname in ('anon', 'authenticated') loop
        execute format('revoke create on schema %I from %I', target_schema, browser_role);
    end loop;

    -- Only this creator/schema. Keep service_role grants, all other creators'
    -- defaults, current-creator global TABLE defaults, and every unrelated
    -- existing table unchanged. Later optional/runtime tables start private
    -- even before RLS is enabled. Sequence defaults for this creator are
    -- revoked globally and in this schema so later serial columns start
    -- without browser USAGE/SELECT/UPDATE.
    execute format('alter default privileges for role %I in schema %I revoke all privileges on tables from public', current_user, target_schema);
    execute format('alter default privileges for role %I revoke all privileges on sequences from public', current_user);
    execute format('alter default privileges for role %I in schema %I revoke all privileges on sequences from public', current_user, target_schema);
    for browser_role in select rolname from pg_roles where rolname in ('anon', 'authenticated') loop
        execute format('alter default privileges for role %I in schema %I revoke all privileges on tables from %I', current_user, target_schema, browser_role);
        execute format('alter default privileges for role %I revoke all privileges on sequences from %I', current_user, browser_role);
        execute format('alter default privileges for role %I in schema %I revoke all privileges on sequences from %I', current_user, target_schema, browser_role);
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
        -- serial/identity sequences keep a separate ACL. Owner implicit
        -- privileges and existing service_role grants are retained so
        -- backend inserts can still nextval.
        for seq_name in
            select distinct s.relname
            from pg_depend dep
            join pg_class s on s.oid = dep.objid and s.relkind = 'S'
            where dep.refobjid = to_regclass(format('%I.%I', target_schema, managed_table))
              and dep.classid = 'pg_class'::regclass
              and dep.refclassid = 'pg_class'::regclass
              and dep.deptype in ('a', 'i')
        loop
            execute format('revoke all privileges on sequence %I.%I from public', target_schema, seq_name);
            for browser_role in select rolname from pg_roles where rolname in ('anon', 'authenticated') loop
                execute format('revoke all privileges on sequence %I.%I from %I', target_schema, seq_name, browser_role);
            end loop;
        end loop;
    end loop;
end $backend_data_privacy$;
