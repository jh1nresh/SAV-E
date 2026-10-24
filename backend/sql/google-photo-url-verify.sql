-- Read-only G5 verify. Expect 0|0.
-- Founder-owned. Do not apply cleanup from this file.

select
  (
    select count(*)
    from public.places
    where coalesce(cardinality(business_photo_urls), 0) > 0
  ) as leftover_business_photo_urls,
  (
    select count(*)
    from public.places
    where source_image_url is not null
      and (
        source_image_url ilike '%maps.googleapis.com/maps/api/place/photo%'
        or source_image_url ilike '%places.googleapis.com%/%/media%'
        or source_image_url ilike '%photo_reference=%'
        or source_image_url ~* '^places/.+/photos/'
        or source_image_url ilike '%googleusercontent.com%/places/%'
        or source_image_url ilike '%googleusercontent.com%/place-photos/%'
        or source_image_url ilike '%googleusercontent.com%/p/%'
        or source_image_url ilike '%googleusercontent.com%/gps-cs-s/%'
        or source_image_url ilike '%googleusercontent.com%/gps-proxy/%'
      )
  ) as leftover_google_source_image_urls;
