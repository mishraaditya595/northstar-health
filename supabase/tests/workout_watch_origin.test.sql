-- Phase 4 stage 4a: the beyondrep_watch workout origin.
-- Synthetic, rolled-back pgTAP. Run: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);

insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-0000000000b1','northstar-watch-origin@example.invalid');

-- One completed rep set; p_origin is the complete jsonb value of the origin
-- key, or null (SQL null) to omit the key.
create function pg_temp.doc(wid uuid, p_origin jsonb) returns jsonb language sql as $$
 select (jsonb_build_object(
  'schema_version',1,
  'workout_id',wid,
  'status','completed','name','Watch origin',
  'started_at_utc','2026-11-27T05:00:00Z',
  'completed_at_utc','2026-11-27T06:00:00Z',
  'original_offset_minutes',0,
  'exercises', jsonb_build_array(jsonb_build_object(
    'id','00000000-0000-4000-8000-000000000201','name','Squat',
    'position',0,'sets',jsonb_build_array(jsonb_build_object(
      'id',md5(wid::text || 'set')::uuid,
      'position',0,'kind','working','status','completed','input_unit','kg',
      'reps',5,'load_grams',100000,
      'completed_at_utc','2026-11-27T05:08:00Z'))))))
  || case when p_origin is null then '{}'::jsonb
          else jsonb_build_object('origin',p_origin) end
$$;

create function pg_temp.try_sync(op uuid, wid uuid, doc jsonb) returns text
language plpgsql security invoker as $$
begin
 return public.sync_workout(op,wid,0,'upsert',doc)->>'result';
exception when others then
 return sqlstate;
end $$;

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","is_anonymous":false}',true);

select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000011',
 '00000000-0000-4000-8000-000000000101',
 pg_temp.doc('00000000-0000-4000-8000-000000000101','"beyondrep_watch"')),
 'applied','origin beyondrep_watch is applied');
select is((select payload->>'origin' from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'),
 'beyondrep_watch','stored payload keeps origin beyondrep_watch');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000012',
 '00000000-0000-4000-8000-000000000102',
 pg_temp.doc('00000000-0000-4000-8000-000000000102','"northstar_phone"')),
 'applied','origin northstar_phone is still applied');

-- Rejected cases share one workout id.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000021',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199','"beyondrep_wear"')),
 '22023','unknown origin rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000022',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199','"BEYONDREP_WATCH"')),
 '22023','origin is case sensitive');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000023',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199','""')),
 '22023','empty origin rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000024',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199','1')),
 '22023','numeric origin rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000025',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199','null'::jsonb)),
 '22023','JSON null origin rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000026',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',null)),
 '22023','missing origin rejected');

-- Restore feed and progress read the watch workout.
select is((select c->'payload'->>'origin'
 from jsonb_array_elements(public.get_workout_changes()->'changes') c
 where c->>'workout_id'='00000000-0000-4000-8000-000000000101'),
 'beyondrep_watch','restore feed returns the watch workout with its origin');
select is(pg_catalog.jsonb_array_length(public.get_workout_changes()->'changes'),2,
 'restore feed holds the phone and the watch workout');
select is((public.get_workout_progress('2026-11-27','2026-11-27')
 ->'totals'->>'workouts')::integer,2,
 'progress counts one phone and one watch workout');

select is(has_function_privilege('authenticated','northstar_private.validate_workout_v1(uuid,jsonb)','EXECUTE'),
 false,'authenticated cannot execute the private validator');
select is(has_function_privilege('anon','northstar_private.validate_workout_v1(uuid,jsonb)','EXECUTE'),
 false,'anon cannot execute the private validator');

select * from finish();
rollback;
