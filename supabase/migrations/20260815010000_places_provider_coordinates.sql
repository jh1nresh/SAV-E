alter table public.places
    add column if not exists coordinate_system text not null default 'WGS84',
    add column if not exists location_provider text,
    add column if not exists provider_place_id text,
    add column if not exists provider_map_url text;

alter table public.places
    drop constraint if exists places_coordinate_system_check,
    add constraint places_coordinate_system_check
        check (coordinate_system in ('WGS84', 'GCJ-02', 'BD-09')),
    drop constraint if exists places_location_provider_check,
    add constraint places_location_provider_check
        check (location_provider is null or location_provider in ('apple_maps', 'google_places', 'amap', 'baidu'));
