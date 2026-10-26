-- Founder-owned G5 cleanup. NOT a migration. Merge / boot / agents must not apply this.
-- Apply only after #306 is the binary you will submit, and only after the BACKUP step
-- in docs/operations/google-photo-url-cleanup.md.
-- Single transaction. Leaves the column in place.

begin;

-- Retired Places photo URL array. The #306 app no longer reads this column.
update public.places
set business_photo_urls = '{}'
where business_photo_urls is distinct from '{}';

-- source_image_url remains a live user/social field. Clear Google Places leftovers only.
-- BEGIN shared Google photo classifier
-- Keep this CTE identical in cleanup and verify (checked by the offline SQL test).
-- Decode percent escapes until stable, including stacked %25 escapes. This is
-- deliberately stricter than the write guard's eight-layer cap: a deeply encoded
-- Google identity must not produce a false-zero verification. Invalid UTF-8 or
-- NUL escapes, or non-ASCII hosts needing WHATWG/IDNA normalization, abort the
-- statement/transaction instead of reporting a false PASS;
-- inspect those malformed rows separately before authorizing cleanup.
-- Only the comparison value is normalized; retained source bytes are never rewritten.
with recursive decoded(id, value) as (
  select id, source_image_url collate "C" from public.places where source_image_url is not null
  union all
  select d.id, next.value
  from decoded d
  cross join lateral (
    select string_agg(
      case when token[1] ~* '^(%[0-9a-f]{2})+$'
        then convert_from(decode(replace(token[1], '%', ''), 'hex'), 'UTF8')
        else token[1] end, '' order by ordinal) as value
    from regexp_matches(d.value, '((?:%[0-9a-f]{2})+|.)', 'gi') with ordinality as parts(token, ordinal)
  ) next
  where d.value ~* '%[0-9a-f]{2}'
), normalized as (
  select id, lower(btrim(regexp_replace(
    replace(replace(replace(value, chr(9), ''), chr(10), ''), chr(13), ''),
    '^[[:space:][:cntrl:]]+|[[:space:][:cntrl:]]+$', '', 'g'),
    U&'\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF')) as value
  from decoded where value !~* '%[0-9a-f]{2}'
), urls as (
  select id, value,
    case when value ~ '^(https?|ftp|wss?|file):'
      then regexp_replace(replace(value, chr(92), '/'), '^([^:]+:)[/]*', '\1//')
      else value end as url
  from normalized
), authorities as (
  select id, value,
    substring(url from '^[a-z][a-z0-9+.-]*://([^/?#]*)') as authority,
    coalesce(substring(regexp_replace(url, '^[a-z][a-z0-9+.-]*://[^/?#]*', '') from '^[^?#]*'), '') as path
  from urls
), host_candidates as (
  select id, value,
    case when authority ~ ':[0-9]+$' and
      case when substring(authority from ':0*([0-9]{1,5})$') is not null
        then substring(authority from ':0*([0-9]{1,5})$')::integer > 65535 else true end
      then null else regexp_replace(regexp_replace(authority, '^.*@', ''), ':[0-9]*$', '') end as host,
    string_to_array(path, '/') as parts
  from authorities
), paths as (
  select id, value, parts,
    -- SQL has no WHATWG IDNA parser. Fail closed rather than overlooking a
    -- Unicode hostname that the app would normalize to a Google hostname.
    case when host ~ U&'[^\0001-\007F]'
      then convert_from(convert_to(host, 'UTF8') || decode('ff', 'hex'), 'UTF8')
      else host end as host
  from host_candidates
), path_walk(id, value, host, parts, position, stack) as (
  select id, value, host, parts, 1, array[]::text[] collate "C" from paths
  union all
  select id, value, host, parts, position + 1,
    case when parts[position] = '..' then stack[1:greatest(cardinality(stack) - 1, 0)]
      when parts[position] = '.' then stack
      else array_append(stack, parts[position]) end
  from path_walk where position <= cardinality(parts)
), google_photo_rows as (
  select id from path_walk
  where position > cardinality(parts) and (
    value ~ '^places/[^/]+/photos(/|$)'
    -- Preserve the existing write guard's legacy parameter-name contract.
    or value like '%photo_reference=%'
    or (host = 'maps.googleapis.com' and array_to_string(stack, '/') like '%/maps/api/place/photo%')
    or (host = 'places.googleapis.com' and (
      array_to_string(stack, '/') like '%/photos/%' or array_to_string(stack, '/') like '%/media%'))
    or ((host = 'googleusercontent.com' or host like '%.googleusercontent.com')
      and stack && array['places', 'place-photos', 'p', 'gps-cs-s', 'gps-proxy'])
  )
)
-- END shared Google photo classifier
update public.places
set source_image_url = null
where id in (select id from google_photo_rows);

commit;
