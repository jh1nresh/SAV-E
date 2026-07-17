-- Preserve server-resolved source links so expiring short URLs do not erase
-- canonical IDs or the public metadata already recovered for a capture.

alter table public.captures
  add column if not exists source_resolution jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'captures_source_resolution_check'
      and conrelid = 'public.captures'::regclass
  ) then
    alter table public.captures
      add constraint captures_source_resolution_check check (
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
