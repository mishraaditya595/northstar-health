-- P2-05 server progress. Synthetic JWTs/workouts only; transaction rolled back.
-- supabase test db on a clean stack runs this alongside workout_sync.test.sql.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(65);

insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-0000000000a1','northstar-p5-a@example.invalid'),
 ('00000000-0000-4000-8000-0000000000b2','northstar-p5-b@example.invalid');

select ok((select relrowsecurity from pg_catalog.pg_class
  where oid='public.workout_records'::regclass), 'RLS protects progress source');
select is(has_function_privilege('anon',
  'public.get_workout_progress(date,date,integer)','EXECUTE'),
 false, 'anonymous role has no progress RPC execution grant');
select is(has_function_privilege('authenticated',
  'public.get_workout_progress(date,date,integer)','EXECUTE'),
 true, 'verified JWT role can execute progress RPC');
select is(has_table_privilege('authenticated','public.workout_records','UPDATE'),
 false, 'client cannot alter derived progress columns');
select is(has_table_privilege('authenticated','public.workout_records','INSERT'),
 false, 'client cannot insert workout records directly');
select is(has_table_privilege('authenticated','public.workout_records','DELETE'),
 false, 'client cannot delete workout records directly');

create function pg_temp.progress_state(a date,b date,c integer)
returns text language plpgsql security invoker as $body$
begin
 perform public.get_workout_progress(a,b,c);
 return 'ok';
exception when others then
 return sqlstate;
end $body$;
create function pg_temp.progress_try_write(p_command text)
returns text language plpgsql security invoker as $body$
begin
 execute p_command;
 return 'ok';
exception when others then
 return sqlstate;
end $body$;

set local role authenticated;
select is(pg_temp.progress_state('2026-10-25','2026-10-26',100),
 '28000','missing auth JWT rejected');
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","is_anonymous":false}',true);
select is(pg_temp.progress_try_write(
 'insert into public.workout_records
   (user_id,workout_id,server_revision,schema_version,status,server_change_seq)
   values (''00000000-0000-4000-8000-0000000000a1'',
           ''00000000-0000-4000-8000-0000000001c1'',1,1,''completed'',12345)'
 ),'42501','authenticated user cannot INSERT workout progress source');
select is(pg_temp.progress_try_write(
 'update public.workout_records set completed_working_sets = 999'
 ),'42501','authenticated user cannot UPDATE processed counters');
select is(pg_temp.progress_try_write(
 'delete from public.workout_records'
 ),'42501','authenticated user cannot DELETE workout source');

select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'workouts')::integer,
 0,'empty account yields zero workouts');
select is(pg_catalog.jsonb_array_length(public.get_workout_progress('2026-10-25','2026-10-26')->'days'),
 0,'empty progress has no fake days');
select is(pg_catalog.jsonb_array_length(public.get_workout_progress('2026-10-25','2026-10-26')->'recent_workouts'),
 0,'empty account has no recent sessions');
select is(pg_catalog.jsonb_typeof(public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->'loaded_volume_gram_reps'),
 'null','no loaded sets is unknown volume, not zero');
select is(pg_temp.progress_state('2026-10-26','2026-10-25',100),
 '22023','backwards range rejected');
select is(pg_temp.progress_state('2026-01-01','2027-01-03',100),
 '22023','oversized range rejected');
select is(pg_temp.progress_state('2026-10-25','2026-10-26',0),
 '22023','zero page size rejected');
select is(pg_temp.progress_state('2026-10-25','2026-10-26',201),
 '22023','unbounded recent page rejected');
select is(pg_temp.progress_state('2026-01-01','2027-01-01',100),
 'ok','366 inclusive calendar dates accepted');
select is(pg_temp.progress_state('infinity'::date,'infinity'::date,100),
 '22023','infinite upper and lower bounds are rejected');
select is(pg_temp.progress_state('-infinity'::date,'2026-10-26',100),
 '22023','negative-infinite lower bound is rejected');
select is(pg_temp.progress_state('2026-10-25','infinity'::date,100),
 '22023','infinite upper bound is rejected');
select is(pg_temp.progress_state('5874897-01-01'::date,'5874897-01-02'::date,100),
 'ok','near-maximum valid dates do not overflow interval validation');

-- P2-01 authoritative processing excludes warmups and weightless sets.
select set_config('northstar.progress_fixture', $json$
{"schema_version":1,
 "workout_id":"00000000-0000-4000-8000-000000000101",
 "origin":"northstar_phone","status":"completed","name":"Rows",
 "started_at_utc":"2026-10-25T09:00:00Z",
 "completed_at_utc":"2026-10-25T20:00:00Z",
 "original_offset_minutes":330,
 "exercises":[{"id":"00000000-0000-4000-8000-000000000201",
  "name":"Seated row","position":0,"sets":[
  {"id":"00000000-0000-4000-8000-000000000301",
   "position":0,"kind":"working","status":"completed","input_unit":"kg",
   "reps":8,"load_grams":60000,"completed_at_utc":"2026-10-25T10:00:00Z"},
  {"id":"00000000-0000-4000-8000-000000000302",
   "position":1,"kind":"warmup","status":"completed","input_unit":"kg",
   "reps":12,"load_grams":20000,"completed_at_utc":"2026-10-25T10:01:00Z"},
  {"id":"00000000-0000-4000-8000-000000000303",
   "position":2,"kind":"working","status":"completed","input_unit":"kg",
   "reps":10,"load_grams":null,"completed_at_utc":"2026-10-25T10:02:00Z"}]}]}
$json$,true);

select is(public.sync_workout(
  '00000000-0000-4000-8000-000000000011',
  '00000000-0000-4000-8000-000000000101',
  0,'upsert',current_setting('northstar.progress_fixture')::jsonb)->>'result',
 'applied','completed NorthStar workout stored via authenticated RPC');
select is((select progress_local_day::text from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'),
 '2026-10-26','UTC 20:00 with +330 minutes belongs to next local day');
select is((select progress_completed_at at time zone 'UTC' from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101')::text,
 '2026-10-25 20:00:00','server persists validated UTC completion instant');

select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'workouts')::integer,
 1,'one completed session counted');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'completed_working_sets')::integer,
 2,'warmup excluded from completed working count');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'loaded_working_sets')::integer,
 1,'missing load excluded from loaded set count');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'loaded_volume_gram_reps')::bigint,
 480000::bigint,'loaded volume uses server-validated gram-reps');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'days'->0->>'local_day'),
 '2026-10-26','daily progress uses original timezone offset');
set local timezone = 'America/Los_Angeles';
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'recent_workouts'->0->>'completed_at'),
 '2026-10-25T20:00:00.000000Z',
 'recent completion timestamp emits the same UTC Z value under non-UTC session');
set local timezone = 'UTC';
select is((public.get_workout_progress('2026-10-25','2026-10-25')->'totals'->>'workouts')::integer,
 0,'range bounds are based on original calendar day');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'recent_workouts'->0->>'server_revision')::integer,
 1,'recent list includes validated server revision');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->>'recent_truncated')::boolean,
 false,'recent list truthfully reports not truncated');

-- Simulate an older partially processed server row. This is privileged
-- synthetic migration-test setup, never a client-write path.
reset role;
update public.workout_records set completed_working_sets = null
 where workout_id = '00000000-0000-4000-8000-000000000101';
set local role authenticated;
select is(pg_catalog.jsonb_typeof(
 public.get_workout_progress('2026-10-25','2026-10-26')
   ->'totals'->'completed_working_sets'), 'null',
 'missing completed counter propagates to total instead of fake zero');
select is(pg_catalog.jsonb_typeof(
 public.get_workout_progress('2026-10-25','2026-10-26')
   ->'days'->0->'completed_working_sets'), 'null',
 'missing completed counter propagates to daily summary');
select is(pg_catalog.jsonb_typeof(
 public.get_workout_progress('2026-10-25','2026-10-26')
   ->'totals'->'loaded_volume_gram_reps'), 'null',
 'missing completed counter invalidates weighted volume');
reset role;
update public.workout_records
 set completed_working_sets = 2, loaded_working_sets = null
 where workout_id = '00000000-0000-4000-8000-000000000101';
set local role authenticated;
select is(pg_catalog.jsonb_typeof(
 public.get_workout_progress('2026-10-25','2026-10-26')
   ->'totals'->'loaded_working_sets'), 'null',
 'missing loaded counter propagates to total');
select is(pg_catalog.jsonb_typeof(
 public.get_workout_progress('2026-10-25','2026-10-26')
   ->'days'->0->'loaded_working_sets'), 'null',
 'missing loaded counter propagates to daily summary');
select is(pg_catalog.jsonb_typeof(
 public.get_workout_progress('2026-10-25','2026-10-26')
   ->'totals'->'loaded_volume_gram_reps'), 'null',
 'missing loaded counter invalidates weighted volume');
reset role;
update public.workout_records
 set completed_working_sets = 2, loaded_working_sets = 1
 where workout_id = '00000000-0000-4000-8000-000000000101';
set local role authenticated;

-- Add one completed bodyweight-only workout on the previous local day.
select set_config('northstar.weightless', pg_catalog.jsonb_set(
 pg_catalog.jsonb_set(
 pg_catalog.jsonb_set(current_setting('northstar.progress_fixture')::jsonb,
 '{workout_id}','"00000000-0000-4000-8000-000000000102"'::jsonb),
 '{completed_at_utc}','"2026-10-25T11:00:00Z"'::jsonb),
 '{exercises,0,sets}',
 '[{"id":"00000000-0000-4000-8000-000000000311",
 "position":0,"kind":"working","status":"completed","input_unit":"kg",
 "reps":10,"load_grams":null,"completed_at_utc":"2026-10-25T10:03:00Z"}]'::jsonb
 )::text,true);
select is(public.sync_workout(
 '00000000-0000-4000-8000-000000000012',
 '00000000-0000-4000-8000-000000000102',
 0,'upsert',current_setting('northstar.weightless')::jsonb)->>'result',
 'applied','bodyweight workout synced with null loaded weight');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'workouts')::integer,
 2,'owner aggregate combines two sessions');
select is(pg_catalog.jsonb_array_length(public.get_workout_progress('2026-10-25','2026-10-26')->'days'),
 2,'two distinct original local days are present');
select is(pg_catalog.jsonb_typeof(public.get_workout_progress('2026-10-25','2026-10-25')->'totals'->'loaded_volume_gram_reps'),
 'null','bodyweight day has NULL volume instead of fabricated zero');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'loaded_volume_gram_reps')::bigint,
 480000::bigint,'missing weight elsewhere does not dilute valid volume');
select is(pg_catalog.jsonb_array_length(public.get_workout_progress('2026-10-25','2026-10-26',1)->'recent_workouts'),
 1,'recent page limit bounds response');
select is((public.get_workout_progress('2026-10-25','2026-10-26',1)->>'recent_truncated')::boolean,
 true,'truncated recent list explicitly disclosed');
select is((public.get_workout_progress('2026-10-25','2026-10-26',1)->'recent_workouts'->0->>'workout_id'),
 '00000000-0000-4000-8000-000000000101','recent page sorts latest local-day workout first');

-- Update the original workout: no duplicate row and changed progress day.
select set_config('northstar.progress_edit', pg_catalog.jsonb_set(
 pg_catalog.jsonb_set(current_setting('northstar.progress_fixture')::jsonb,
 '{completed_at_utc}','"2026-10-25T14:00:00Z"'::jsonb),
 '{exercises,0,sets,0,load_grams}','30000'::jsonb
 )::text,true);
select is(public.sync_workout(
 '00000000-0000-4000-8000-000000000013',
 '00000000-0000-4000-8000-000000000101',
 1,'upsert',current_setting('northstar.progress_edit')::jsonb)->>'result',
 'applied','CAS workout correction accepted');
select is((select progress_local_day::text from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'),
 '2026-10-25','correction moves workout to earlier local calendar day');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'loaded_volume_gram_reps')::bigint,
 240000::bigint,'server-derived corrected volume replaces old value');
select is(pg_catalog.jsonb_array_length(public.get_workout_progress('2026-10-25','2026-10-26')->'days'),
 1,'corrected local day removes stale aggregate bucket');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'recent_workouts'->0->>'server_revision')::integer,
 2,'progress reflects latest server revision');
select is((public.sync_workout(
 '00000000-0000-4000-8000-000000000013',
 '00000000-0000-4000-8000-000000000101',
 1,'upsert',current_setting('northstar.progress_edit')::jsonb)->>'replay')::boolean,
 true,'replayed operation is idempotent');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'workouts')::integer,
 2,'replay never duplicates account progress');

-- Tombstones remove the workout from progress without destroying its cursor.
select is(public.sync_workout(
 '00000000-0000-4000-8000-000000000014',
 '00000000-0000-4000-8000-000000000101',
 2,'delete',null)->>'result',
 'applied','delete tombstone committed');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'workouts')::integer,
 1,'deleted completed workout disappears from aggregate');
select is(pg_catalog.jsonb_typeof(public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->'loaded_volume_gram_reps'),
 'null','remaining weightless workout has no weighted volume');
select is((select count(*)::text from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'
   and progress_local_day is null and progress_completed_at is null),
 '1','tombstone clears derived calendar metadata');

-- Other account's workouts never appear even with identical date ranges.
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000b2","role":"authenticated","is_anonymous":false}',true);
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'workouts')::integer,
 0,'account B cannot read account A progress');
select is(public.sync_workout(
 '00000000-0000-4000-8000-000000000021',
 '00000000-0000-4000-8000-000000000103',
 0,'upsert',pg_catalog.jsonb_set(current_setting('northstar.weightless')::jsonb,
 '{workout_id}','"00000000-0000-4000-8000-000000000103"'::jsonb))->>'result',
 'applied','account B writes its own finished workout');
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'workouts')::integer,
 1,'account B sees its own workout only');
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","is_anonymous":false}',true);
select is((public.get_workout_progress('2026-10-25','2026-10-26')->'totals'->>'workouts')::integer,
 1,'switching to account A restores only its separate summary');

select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","is_anonymous":true}',true);
select is(pg_temp.progress_state('2026-10-25','2026-10-26',100),
 '28000','Supabase anonymous Auth accounts cannot read progress');
reset role;
select * from finish();
rollback;
