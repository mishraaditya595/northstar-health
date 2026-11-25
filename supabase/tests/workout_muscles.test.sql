-- Training library stage 3: exercise muscle arrays on synced workouts.
-- Synthetic, rolled-back pgTAP. Run: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(20);

insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-0000000000a1','northstar-muscles@example.invalid');

create function pg_temp.doc(wid uuid, extra jsonb) returns jsonb language sql as $$
 select jsonb_build_object(
  'schema_version',1,
  'workout_id',wid,
  'origin','northstar_phone','status','completed','name','Muscles',
  'started_at_utc','2026-11-26T05:00:00Z',
  'completed_at_utc','2026-11-26T06:00:00Z',
  'original_offset_minutes',0,
  'exercises', jsonb_build_array(jsonb_build_object(
    'id','00000000-0000-4000-8000-000000000201','name','Romanian deadlift',
    'position',0,
    'sets', jsonb_build_array(jsonb_build_object(
      'id','00000000-0000-4000-8000-000000000301','position',0,
      'kind','working','status','completed','input_unit','kg','reps',8,
      'load_grams',60000,'completed_at_utc','2026-11-26T05:08:00Z'))) || extra))
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
 '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","is_anonymous":false}',true);

-- Each accepted case has its own workout so it is applied, never a revision
-- conflict on a reused workout. Rejected cases share one unused workout id.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000011',
 '00000000-0000-4000-8000-000000000101',
 pg_temp.doc('00000000-0000-4000-8000-000000000101',
  '{"primary_muscles":["hamstrings","glutes"],"secondary_muscles":["lowerBack"]}')),
 'applied','valid muscle arrays are applied');
select is((select payload->'exercises'->0->'primary_muscles' from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'),
 '["hamstrings","glutes"]'::jsonb,'stored payload keeps primary muscles');
select is((select payload->'exercises'->0->'secondary_muscles' from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'),
 '["lowerBack"]'::jsonb,'stored payload keeps secondary muscles');

select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000012',
 '00000000-0000-4000-8000-000000000102',
 pg_temp.doc('00000000-0000-4000-8000-000000000102','{}'::jsonb)),
 'applied','payload without muscle keys is applied');
select is((select (payload->'exercises'->0) ? 'primary_muscles'
   or (payload->'exercises'->0) ? 'secondary_muscles'
 from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000102'),
 false,'stored payload without keys has neither array');

select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000013',
 '00000000-0000-4000-8000-000000000103',
 pg_temp.doc('00000000-0000-4000-8000-000000000103','{"primary_muscles":["hamstrings"]}')),
 'applied','primary only is applied');
select is((select (payload->'exercises'->0) ? 'primary_muscles'
   and not ((payload->'exercises'->0) ? 'secondary_muscles')
 from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000103'),
 true,'primary-only payload stores just the primary array');

select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000021',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  '{"primary_muscles":["biceps","wings"]}')),'22023','unknown muscle rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000022',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  '{"primary_muscles":["quads","quads"]}')),'22023','duplicate rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000023',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  '{"primary_muscles":["quads"],"secondary_muscles":["quads"]}')),'22023','muscle in both lists rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000024',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  '{"primary_muscles":"quads"}')),'22023','non-array rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000025',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  '{"primary_muscles":[1]}')),'22023','non-string element rejected');
-- The vocabulary has exactly 14 names, so any 15-entry array necessarily
-- repeats one; this case therefore cannot isolate the length limit from the
-- duplicate check. Both rules reject it, which is all it asserts.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000026',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  jsonb_build_object('primary_muscles',
  '["chest","shoulders","biceps","forearms","abs","obliques","quads","calves","traps","lats","lowerBack","triceps","glutes","hamstrings","chest"]'::jsonb))),
 '22023','15 entries rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000027',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  '{"secondary_muscles":["quads"]}')),'22023','secondary without primary rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000028',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  '{"primary_muscles":[],"secondary_muscles":["quads"]}')),'22023','secondary with empty primary rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000029',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  '{"primary_muscles":["Quads"]}')),'22023','vocabulary is case sensitive');
select is(pg_temp.try_sync('00000000-0000-4000-8000-00000000002a',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  '{"secondary_muscles":[]}')),'22023','empty secondary key without primary key rejected');

select is(has_function_privilege('authenticated','northstar_private.validate_workout_v1(uuid,jsonb)','EXECUTE'),
 false,'authenticated cannot execute the private validator');
select is(has_function_privilege('anon','northstar_private.validate_workout_v1(uuid,jsonb)','EXECUTE'),
 false,'anon cannot execute the private validator');
select is(has_function_privilege('public','northstar_private.validate_workout_v1(uuid,jsonb)','EXECUTE'),
 false,'public cannot execute the private validator');

select * from finish();
rollback;
