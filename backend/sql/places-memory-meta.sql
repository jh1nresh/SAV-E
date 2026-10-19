-- Additive, idempotent. Owner-private structured stamp memory (extra source
-- evidence, highlights, vibe, access, priced recommended items). Never store
-- this in places.note — that column is the user's plain memory.
alter table places add column if not exists memory_meta jsonb;
alter table places drop constraint if exists places_memory_meta_object;
alter table places add constraint places_memory_meta_object
    check (memory_meta is null or jsonb_typeof(memory_meta) = 'object');
