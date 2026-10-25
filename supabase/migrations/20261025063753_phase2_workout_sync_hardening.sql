-- P2-01 security corrections. Apply after 20261025060300_phase2_workout_sync_foundation.sql.
-- No secrets. Preserve the initial migration for databases where it was applied.
create schema if not exists northstar_private;
revoke all on schema northstar_private from public, anon;
grant usage on schema northstar_private to authenticated;

-- A transactional, per-owner cursor. No globally enumerable sequence.
create table northstar_private.workout_owner_cursors (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_change_seq bigint not null check(last_change_seq >= 0)
);
alter table northstar_private.workout_owner_cursors enable row level security;
revoke all on northstar_private.workout_owner_cursors from public, anon, authenticated;

-- Historic receipt rows are migrated to hashes before dropping their raw payloads.
alter table public.workout_sync_operations add column request_sha256 bytea;
update public.workout_sync_operations set request_sha256 =
  pg_catalog.sha256(pg_catalog.convert_to(
    pg_catalog.jsonb_build_array(workout_id, expected_revision, action, request_payload)::text,
    'UTF8'
  ));
alter table public.workout_sync_operations alter column request_sha256 set not null;
alter table public.workout_sync_operations
  add constraint receipt_hash_length check(pg_catalog.octet_length(request_sha256) = 32);
alter table public.workout_sync_operations
  add column expires_at timestamptz not null default (now() + interval '90 days');
update public.workout_sync_operations set expires_at = committed_at + interval '90 days';
alter table public.workout_sync_operations drop column request_payload;

-- Replace global uniqueness with owner-local ordering; earlier rows retain cursor values.
alter table public.workout_records
  drop constraint if exists workout_records_server_change_seq_key;
alter table public.workout_records
  add constraint workout_records_owner_change_unique unique (user_id, server_change_seq);
insert into northstar_private.workout_owner_cursors(user_id,last_change_seq)
select user_id, max(change_seq) from (
  select user_id,server_change_seq as change_seq from public.workout_records
  union all
  select user_id,applied_change_seq from public.workout_sync_operations
) historical group by user_id
on conflict(user_id) do update set last_change_seq =
  greatest(northstar_private.workout_owner_cursors.last_change_seq,excluded.last_change_seq);

drop policy if exists workout_records_read_own on public.workout_records;
create policy workout_records_read_own on public.workout_records
 for select to authenticated using(
  user_id = (select auth.uid())
  and coalesce(((select auth.jwt())->>'is_anonymous')::boolean,false) = false
);

-- Strict, allowlisted DTO validator. All expensive work runs before the owner lock.
create or replace function northstar_private.validate_workout_v1(
 p_workout_id uuid, p_payload jsonb
) returns jsonb
language plpgsql security invoker
set search_path = ''
as $validate$
declare
 v_e jsonb;
 v_s jsonb;
 v_key text;
 v_start timestamptz;
 v_finish timestamptz;
 v_at timestamptz;
 v_working integer := null;
 v_loaded integer := null;
 v_volume bigint := null;
 v_status text;
 v_allowed_workout text[] := array[
  'schema_version','workout_id','origin','status','name','started_at_utc',
  'completed_at_utc','original_offset_minutes','exercises'
 ];
 v_allowed_exercise text[] := array['id','name','position','muscle','equipment','sets'];
 v_allowed_set text[] := array[
  'id','position','kind','status','reps','load_grams','input_unit','rpe','completed_at_utc'
 ];
 v_required_workout text[] := array[
  'schema_version','workout_id','origin','status','name','started_at_utc',
  'original_offset_minutes','exercises'
 ];
 v_required_exercise text[] := array['id','name','position','sets'];
 v_required_set text[] := array['id','position','kind','status','input_unit'];
begin
 if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or pg_catalog.octet_length(p_payload::text) > 65536 then
   raise exception 'invalid workout object or size' using errcode = '22023';
 end if;
 if not (p_payload ?& v_required_workout)
   or exists(select 1 from pg_catalog.jsonb_object_keys(p_payload) as k
     where k <> all(v_allowed_workout))
 then
   raise exception 'missing or unsupported workout fields' using errcode = '22023';
 end if;
 if pg_catalog.jsonb_typeof(p_payload->'schema_version') <> 'number'
    or p_payload->'schema_version' <> '1'::jsonb
    or pg_catalog.jsonb_typeof(p_payload->'workout_id') <> 'string'
    or p_payload->>'workout_id' is distinct from p_workout_id::text
    or pg_catalog.jsonb_typeof(p_payload->'origin') <> 'string'
    or p_payload->>'origin' is distinct from 'northstar_phone'
    or pg_catalog.jsonb_typeof(p_payload->'status') <> 'string'
    or p_payload->>'status' not in ('inProgress','paused','completed','discarded')
    or pg_catalog.jsonb_typeof(p_payload->'name') <> 'string'
    or pg_catalog.length(p_payload->>'name') not between 1 and 160
    or pg_catalog.jsonb_typeof(p_payload->'started_at_utc') <> 'string'
    or pg_catalog.jsonb_typeof(p_payload->'original_offset_minutes') <> 'number'
    or pg_catalog.length(p_payload->>'original_offset_minutes') > 5
    or (p_payload->>'original_offset_minutes') !~ '^-?[0-9]+$'
    or (p_payload->>'original_offset_minutes')::integer not between -840 and 840
    or pg_catalog.jsonb_typeof(p_payload->'exercises') <> 'array'
    or pg_catalog.jsonb_array_length(p_payload->'exercises') > 120
 then
   raise exception 'invalid workout values' using errcode = '22023';
 end if;
 if (p_payload->>'started_at_utc') !~
  '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$'
 then
   raise exception 'invalid start timestamp format' using errcode = '22023';
 end if;
 v_start := (p_payload->>'started_at_utc')::timestamptz;
 v_status := p_payload->>'status';
 if v_status = 'completed' then
   if not (p_payload ? 'completed_at_utc')
      or pg_catalog.jsonb_typeof(p_payload->'completed_at_utc') <> 'string'
   then
     raise exception 'completed workout requires completion time' using errcode = '22023';
   end if;
   v_working := 0; v_loaded := 0;
 end if;
 if p_payload ? 'completed_at_utc' then
   if pg_catalog.jsonb_typeof(p_payload->'completed_at_utc') not in ('null','string') then
      raise exception 'invalid completion time type' using errcode='22023';
   end if;
   if pg_catalog.jsonb_typeof(p_payload->'completed_at_utc') = 'string' then
     if (p_payload->>'completed_at_utc') !~
       '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$'
     then
       raise exception 'invalid completion timestamp format' using errcode='22023';
     end if;
     v_finish := (p_payload->>'completed_at_utc')::timestamptz;
     if v_finish < v_start then
       raise exception 'completion before start' using errcode='22023';
     end if;
   end if;
 end if;
 for v_e in select value from pg_catalog.jsonb_array_elements(p_payload->'exercises') loop
   if pg_catalog.jsonb_typeof(v_e) <> 'object'
      or not(v_e ?& v_required_exercise)
      or exists(select 1 from pg_catalog.jsonb_object_keys(v_e) as k
        where k <> all(v_allowed_exercise)) then
     raise exception 'missing or unsupported exercise fields' using errcode='22023';
   end if;
   if pg_catalog.jsonb_typeof(v_e->'id') <> 'string'
      or pg_catalog.jsonb_typeof(v_e->'name') <> 'string'
      or pg_catalog.length(v_e->>'name') not between 1 and 160
      or pg_catalog.jsonb_typeof(v_e->'position') <> 'number'
      or pg_catalog.length(v_e->>'position') > 5
      or (v_e->>'position') !~ '^[0-9]+$'
      or (v_e->>'position')::integer > 10000
      or pg_catalog.jsonb_typeof(v_e->'sets') <> 'array'
      or pg_catalog.jsonb_array_length(v_e->'sets') > 300
   then
     raise exception 'invalid exercise values' using errcode='22023';
   end if;
   perform (v_e->>'id')::uuid;
   if (v_e ? 'muscle' and
        (pg_catalog.jsonb_typeof(v_e->'muscle') <> 'string'
        or pg_catalog.length(v_e->>'muscle') > 160))
      or (v_e ? 'equipment' and
        (pg_catalog.jsonb_typeof(v_e->'equipment') <> 'string'
        or pg_catalog.length(v_e->>'equipment') > 160))
   then
      raise exception 'invalid exercise metadata' using errcode='22023';
   end if;

   for v_s in select value from pg_catalog.jsonb_array_elements(v_e->'sets') loop
     if pg_catalog.jsonb_typeof(v_s) <> 'object'
        or not(v_s ?& v_required_set)
        or exists(select 1 from pg_catalog.jsonb_object_keys(v_s) as k
          where k <> all(v_allowed_set))
     then
       raise exception 'missing or unsupported set fields' using errcode='22023';
     end if;
     if pg_catalog.jsonb_typeof(v_s->'id') <> 'string'
       or pg_catalog.jsonb_typeof(v_s->'position') <> 'number'
       or pg_catalog.length(v_s->>'position') > 5
       or (v_s->>'position') !~ '^[0-9]+$'
       or (v_s->>'position')::integer > 10000
       or pg_catalog.jsonb_typeof(v_s->'kind') <> 'string'
       or v_s->>'kind' not in ('working','warmup')
       or pg_catalog.jsonb_typeof(v_s->'status') <> 'string'
       or v_s->>'status' not in ('planned','completed','skipped')
       or pg_catalog.jsonb_typeof(v_s->'input_unit') <> 'string'
       or v_s->>'input_unit' not in ('kg','lb')
     then
       raise exception 'invalid set values' using errcode='22023';
     end if;
     perform (v_s->>'id')::uuid;
     if v_s ? 'reps' and pg_catalog.jsonb_typeof(v_s->'reps') <> 'null' then
       if pg_catalog.jsonb_typeof(v_s->'reps') <> 'number'
         or pg_catalog.length(v_s->>'reps') > 5
         or (v_s->>'reps') !~ '^[0-9]+$'
         or (v_s->>'reps')::integer > 10000 then
         raise exception 'invalid repetitions' using errcode='22023';
       end if;
     end if;
     if v_s ? 'load_grams' and pg_catalog.jsonb_typeof(v_s->'load_grams') <> 'null' then
       if pg_catalog.jsonb_typeof(v_s->'load_grams') <> 'number'
         or pg_catalog.length(v_s->>'load_grams') > 9
         or (v_s->>'load_grams') !~ '^[0-9]+$'
         or (v_s->>'load_grams')::bigint > 100000000 then
         raise exception 'invalid load grams' using errcode='22023';
       end if;
     end if;
     if v_s ? 'rpe' and pg_catalog.jsonb_typeof(v_s->'rpe') <> 'null' then
       if pg_catalog.jsonb_typeof(v_s->'rpe') <> 'number'
         or pg_catalog.length(v_s->>'rpe') > 5
         or (v_s->>'rpe') !~ '^(0|[1-9]|10)(\.0|\.5)?$' then
         raise exception 'invalid RPE' using errcode='22023';
       end if;
     end if;
     if v_s->>'status' = 'completed' then
       if not (v_s ?& array['reps','completed_at_utc'])
          or pg_catalog.jsonb_typeof(v_s->'reps') <> 'number'
          or pg_catalog.jsonb_typeof(v_s->'completed_at_utc') <> 'string'
       then
         raise exception 'completed set needs reps and time' using errcode='22023';
       end if;
     end if;
     if v_s ? 'completed_at_utc' and pg_catalog.jsonb_typeof(v_s->'completed_at_utc') <> 'null' then
       if pg_catalog.jsonb_typeof(v_s->'completed_at_utc') <> 'string'
          or (v_s->>'completed_at_utc') !~
           '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
         raise exception 'invalid set timestamp format' using errcode='22023';
       end if;
       v_at := (v_s->>'completed_at_utc')::timestamptz;
       if v_at < v_start then
         raise exception 'set before workout started' using errcode='22023';
       end if;
     end if;
     if v_working is not null and v_s->>'kind' = 'working'
        and v_s->>'status' = 'completed' then
       v_working := v_working + 1;
       if pg_catalog.jsonb_typeof(v_s->'load_grams') = 'number'
          and (v_s->>'load_grams')::bigint > 0 then
         v_loaded := v_loaded + 1;
         v_volume := pg_catalog.coalesce(v_volume,0)
                       + (v_s->>'load_grams')::bigint * (v_s->>'reps')::bigint;
       end if;
     end if;
   end loop;
 end loop;
 if (select pg_catalog.count(*) <> pg_catalog.count(distinct e->>'id')
     from pg_catalog.jsonb_array_elements(p_payload->'exercises') as e) then
    raise exception 'duplicate exercise ID' using errcode='22023';
 end if;
 if (select pg_catalog.count(*) <> pg_catalog.count(distinct s->>'id')
     from pg_catalog.jsonb_array_elements(p_payload->'exercises') as e
     cross join lateral pg_catalog.jsonb_array_elements(e->'sets') as s) then
    raise exception 'duplicate set ID' using errcode='22023';
 end if;
 return pg_catalog.jsonb_build_object(
   'status',v_status,'working',v_working,'loaded',v_loaded,'volume',v_volume
 );
exception
 when invalid_text_representation or numeric_value_out_of_range
      or invalid_datetime_format or datetime_field_overflow
 then
   raise exception 'invalid numeric, UUID or timestamp value' using errcode='22023';
end;
$validate$;

create or replace function northstar_private.sync_workout_internal(
 p_operation_id uuid, p_workout_id uuid, p_expected_revision bigint,
 p_action text, p_payload jsonb default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $sync$
declare
 v_owner uuid := auth.uid();
 v_hash bytea;
 v_receipt public.workout_sync_operations%rowtype;
 v_existing public.workout_records%rowtype;
 v_stats jsonb;
 v_next bigint;
 v_cursor bigint;
 v_affected integer;
 v_status text;
 v_deleted timestamptz;
 v_working integer;
 v_loaded integer;
 v_volume bigint;
begin
 if v_owner is null
   or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
   raise exception 'verified account required' using errcode='28000';
 end if;
 if p_operation_id is null or p_workout_id is null
   or p_expected_revision is null or p_expected_revision < 0
   or p_action is null or p_action not in ('upsert','delete') then
   raise exception 'invalid sync arguments' using errcode='22023';
 end if;
 if p_action = 'upsert' then
   v_stats := northstar_private.validate_workout_v1(p_workout_id,p_payload);
   v_status := v_stats->>'status';
   v_working := (v_stats->>'working')::integer;
   v_loaded := (v_stats->>'loaded')::integer;
   v_volume := (v_stats->>'volume')::bigint;
   v_deleted := null;
 else
   if p_payload is not null then
     raise exception 'delete payload must be null' using errcode='22023';
   end if;
   v_deleted := now();
 end if;
 v_hash := pg_catalog.sha256(pg_catalog.convert_to(
    pg_catalog.jsonb_build_array(p_workout_id,p_expected_revision,p_action,p_payload)::text,'UTF8'
 ));
 -- Lock only one account after validation; high-cost parsing never blocks others.
 perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_owner::text,913751)
 );
 select * into v_receipt from public.workout_sync_operations
   where user_id=v_owner and operation_id=p_operation_id;
 if found then
   if v_receipt.request_sha256 <> v_hash then
     raise exception 'operation ID reused with different content' using errcode='22023';
   end if;
   return pg_catalog.jsonb_build_object(
     'result','applied','revision',v_receipt.applied_revision,
     'change_seq',v_receipt.applied_change_seq,'replay',true,'processing','processed'
   );
 end if;
 select * into v_existing from public.workout_records
    where user_id=v_owner and workout_id=p_workout_id for update;
 if not found then
   if p_expected_revision <> 0 or p_action='delete' then
     return pg_catalog.jsonb_build_object(
       'result','conflict','revision',0,'change_seq',null,
       'replay',false,'processing','not_applied'
     );
   end if;
   v_next := 1;
 else
   if v_existing.server_revision <> p_expected_revision then
     return pg_catalog.jsonb_build_object(
       'result','conflict','revision',v_existing.server_revision,
       'change_seq',v_existing.server_change_seq,
       'replay',false,'processing','not_applied'
     );
   end if;
   v_next := v_existing.server_revision + 1;
 end if;
 insert into northstar_private.workout_owner_cursors(user_id,last_change_seq)
   values(v_owner,1)
   on conflict(user_id) do update
     set last_change_seq=northstar_private.workout_owner_cursors.last_change_seq+1
   returning last_change_seq into v_cursor;

 if v_existing.workout_id is null then
   insert into public.workout_records(
      user_id,workout_id,server_revision,schema_version,status,payload,
      deleted_at,server_change_seq,completed_working_sets,
      loaded_working_sets,loaded_volume_gram_reps
   ) values (
      v_owner,p_workout_id,v_next,1,v_status,p_payload,
      null,v_cursor,v_working,v_loaded,v_volume
   );
 else
   update public.workout_records set
     server_revision=v_next,
     status=coalesce(v_status,status),
     payload=p_payload,
     deleted_at=v_deleted,
     server_change_seq=v_cursor,
     completed_working_sets=v_working,
     loaded_working_sets=v_loaded,
     loaded_volume_gram_reps=v_volume,
     processed_at=now(),updated_at=now()
   where user_id=v_owner and workout_id=p_workout_id
     and server_revision=p_expected_revision;
   get diagnostics v_affected = row_count;
   if v_affected <> 1 then
     raise exception 'concurrent revision changed during update' using errcode='40001';
   end if;
 end if;

 insert into public.workout_sync_operations(
   user_id,operation_id,workout_id,expected_revision,action,request_sha256,
   applied_revision,applied_change_seq
 ) values(v_owner,p_operation_id,p_workout_id,p_expected_revision,p_action,v_hash,
          v_next,v_cursor);
 return pg_catalog.jsonb_build_object(
    'result','applied','revision',v_next,'change_seq',v_cursor,
    'replay',false,'processing','processed'
 );
end;
$sync$;

revoke all on function northstar_private.validate_workout_v1(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function northstar_private.sync_workout_internal(uuid,uuid,bigint,text,jsonb)
  from public,anon,authenticated;
grant execute on function northstar_private.sync_workout_internal(uuid,uuid,bigint,text,jsonb)
  to authenticated;

-- Public Data API endpoint is invoker-only; its single capability calls
-- a private, audited definer function. No direct client write grants.
create or replace function public.sync_workout(
 p_operation_id uuid, p_workout_id uuid, p_expected_revision bigint,
 p_action text, p_payload jsonb default null
) returns jsonb language sql security invoker set search_path = ''
as $rpc$
 select northstar_private.sync_workout_internal($1,$2,$3,$4,$5);
$rpc$;
revoke all on function public.sync_workout(uuid,uuid,bigint,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.sync_workout(uuid,uuid,bigint,text,jsonb)
  to authenticated;

-- Privileged maintenance only. The 90-day retention is a policy; scheduler
-- setup and deletion recovery checks must be verified before production.
create or replace function northstar_private.prune_expired_workout_receipts(
 p_now timestamptz default now()
) returns bigint language plpgsql security invoker set search_path = ''
as $prune$
declare v_count bigint;
begin
 delete from public.workout_sync_operations
  where expires_at <= p_now;
 get diagnostics v_count = row_count;
 return v_count;
end;
$prune$;
revoke all on function northstar_private.prune_expired_workout_receipts(timestamptz)
 from public,anon,authenticated;

-- No global server sequence is used by the new function.
drop sequence if exists public.workout_change_seq;
