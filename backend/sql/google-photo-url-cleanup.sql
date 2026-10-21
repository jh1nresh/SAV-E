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
update public.places
set source_image_url = null
where source_image_url is not null
  and (
    source_image_url ilike '%maps.googleapis.com/maps/api/place/photo%'
    or source_image_url ilike '%places.googleapis.com%/%/media%'
    or source_image_url ilike '%photo_reference=%'
    or source_image_url ~* '^places/.+/photos/'
  );

commit;
