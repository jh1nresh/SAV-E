-- Apply after schema.sql, separately authorized. Never run on boot.
-- Atomic and additive; no historical backfill or client access policies.
begin;
create unique index if not exists idx_captures_id_user_id on captures(id,user_id);
create table if not exists extraction_cache_epochs (
 user_id text primary key references profiles(id) on delete cascade,
 epoch bigint not null default 0
);
alter table extraction_cache_epochs enable row level security;
create table if not exists semantic_extraction_cache (
 user_id text not null references profiles(id) on delete cascade,
 input_key text not null check(input_key ~ '^[a-f0-9]{64}$'),
 extracted jsonb not null check(octet_length(extracted::text)<=65536),
 expires_at timestamptz not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key(user_id,input_key)
);
alter table semantic_extraction_cache enable row level security;
create table if not exists candidate_extraction_inputs (
 candidate_id uuid primary key references place_candidates(id) on delete cascade,
 capture_id uuid not null,
 user_id text not null,
 source_key text not null check(source_key ~ '^[a-f0-9]{64}$'),
 input_key text not null check(input_key ~ '^[a-f0-9]{64}$'),
 content_stamp text not null,
 foreign key(capture_id,user_id) references captures(id,user_id) on delete cascade
);
alter table candidate_extraction_inputs enable row level security;
create table if not exists place_identity_feedback (
 decision_id uuid primary key references user_decisions(id) on delete cascade,
 user_id text not null,
 capture_id uuid not null,
 candidate_id uuid not null references candidate_extraction_inputs(candidate_id) on delete cascade,
 final_place_id uuid not null,
 source_key text not null,
 input_key text not null,
 rejected_id text,
 selected_id text not null,
 foreign key(capture_id,user_id) references captures(id,user_id) on delete cascade,
 foreign key(final_place_id,user_id) references places(id,user_id) on delete cascade
);
alter table place_identity_feedback enable row level security;
create index if not exists place_identity_feedback_source on place_identity_feedback(user_id,source_key,input_key);

-- One bounded state row per place. No fabricated historical backfill.
create table if not exists place_signal_state (
 place_id uuid primary key,
 user_id text not null,
 google_place_id text not null,
 saved_at timestamptz,
 first_visited_at timestamptz,
 foreign key(place_id,user_id) references places(id,user_id) on delete cascade
);
alter table place_signal_state enable row level security;
create index if not exists place_signal_state_venue on place_signal_state(google_place_id,user_id);

create or replace function track_place_signal_state() returns trigger language plpgsql as $$
begin
 if new.google_place_id is null or btrim(new.google_place_id)='' then
   delete from place_signal_state where place_id=new.id;
   return new;
 end if;
 if TG_OP='INSERT' then
   insert into place_signal_state(place_id,user_id,google_place_id,saved_at,first_visited_at)
   values(new.id,new.user_id,new.google_place_id,
     case when new.status in ('wantToGo','visited') then clock_timestamp() end,
     case when new.status='visited' then clock_timestamp() end);
 elsif old.google_place_id is distinct from new.google_place_id or old.user_id is distinct from new.user_id then
   -- Identity correction does not prove a new save or visit to the new venue.
   delete from place_signal_state where place_id=new.id;
   insert into place_signal_state(place_id,user_id,google_place_id) values(new.id,new.user_id,new.google_place_id);
 elsif old.status is distinct from new.status then
   insert into place_signal_state(place_id,user_id,google_place_id,first_visited_at)
   values(new.id,new.user_id,new.google_place_id,case when new.status='visited' then clock_timestamp() end)
   on conflict(place_id) do update set first_visited_at=coalesce(place_signal_state.first_visited_at,excluded.first_visited_at);
 end if;
 return new;
end $$;
drop trigger if exists place_signal_state_changed on places;
create trigger place_signal_state_changed after insert or update of status,google_place_id,user_id on places
 for each row execute function track_place_signal_state();


create or replace function record_place_identity_feedback() returns trigger language plpgsql as $$
begin
 if new.action in ('confirm','edit','wrong_place','wrong_city','wrong_branch','merge_existing') and new.final_place_id is not null then
   insert into place_identity_feedback(decision_id,user_id,capture_id,candidate_id,final_place_id,source_key,input_key,rejected_id,selected_id)
   select new.id,new.user_id,c.id,pc.id,p.id,ce.source_key,ce.input_key,
     (select value->>'google_place_id' from jsonb_array_elements(pc.evidence) where value ? 'google_place_id' limit 1),p.google_place_id
   from place_candidates pc join captures c on c.id=pc.capture_id and c.user_id=new.user_id
   join candidate_extraction_inputs ce on ce.candidate_id=pc.id and ce.capture_id=c.id and ce.user_id=c.user_id
   join places p on p.id=new.final_place_id and p.user_id=c.user_id
   where pc.id=new.candidate_id and nullif(btrim(p.google_place_id),'') is not null
     and ce.content_stamp=md5(jsonb_build_array(c.source_url,c.raw_text,c.source_resolution->'captured_text_v1')::text);
 end if;
 return new;
end $$;
drop trigger if exists identity_feedback_decision on user_decisions;
create trigger identity_feedback_decision after insert on user_decisions
 for each row execute function record_place_identity_feedback();

create or replace function clear_owner_extraction_cache() returns trigger language plpgsql as $$
begin
 -- Serialize invalidation against pending writes. An old provider response
 -- cannot repopulate deleted content after this epoch changes.
 insert into extraction_cache_epochs(user_id,epoch) select id,1 from profiles where id=old.user_id
 on conflict(user_id) do update set epoch=extraction_cache_epochs.epoch+1;
 delete from semantic_extraction_cache where user_id=old.user_id;
 return old;
end $$;
drop trigger if exists deleted_capture_extraction_cache on captures;
create trigger deleted_capture_extraction_cache after delete on captures for each row execute function clear_owner_extraction_cache();
drop trigger if exists deleted_place_extraction_cache on places;
create trigger deleted_place_extraction_cache after delete on places for each row execute function clear_owner_extraction_cache();

create or replace function invalidate_candidate_extraction() returns trigger language plpgsql as $$
begin
 if old.source_url is distinct from new.source_url or old.raw_text is distinct from new.raw_text
   or (old.source_resolution->'captured_text_v1') is distinct from (new.source_resolution->'captured_text_v1') then
   delete from candidate_extraction_inputs where capture_id=new.id;
 end if;
 return new;
end $$;
drop trigger if exists candidate_extraction_changed on captures;
create trigger candidate_extraction_changed after update of source_url,raw_text,source_resolution on captures
 for each row execute function invalidate_candidate_extraction();
commit;
