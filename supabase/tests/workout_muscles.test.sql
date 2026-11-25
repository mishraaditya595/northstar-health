-- Training library stage 3: exercise muscle arrays on synced workouts.
-- Synthetic, rolled-back pgTAP. Run: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);

insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-0000000000a1','northstar-muscles@example.invalid');

create function pg_temp.doc(extra jsonb) returns jsonb language sql as $$
 select jsonb_build_object(
  'schema_version',1,
  'workout_id','00000000-0000-4000-8000-000000000101',
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

create function pg_temp.try_sync(op uuid, doc jsonb) returns text
language plpgsql security invoker as $$
begin
 perform public.sync_workout(op,'00000000-0000-4000-8000-000000000101',0,'upsert',doc);
 return 'ok';
exception when others then
 return sqlstate;
end $$;

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","is_anonymous":false}',true);

select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000011',
 pg_temp.doc('{"primary_muscles":["hamstrings","glutes"],"secondary_muscles":["lowerBack"]}')),
 'ok','valid muscle arrays sync');
select is((select payload->'exercises'->0->'primary_muscles' from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'),
 '["hamstrings","glutes"]'::jsonb,'stored payload keeps primary muscles');
select is((select payload->'exercises'->0->'secondary_muscles' from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'),
 '["lowerBack"]'::jsonb,'stored payload keeps secondary muscles');

select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000012',
 pg_temp.doc('{}'::jsonb)),'ok','payload without muscle keys still syncs');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000013',
 pg_temp.doc('{"primary_muscles":["hamstrings"]}')),'ok','primary only syncs');

select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000021',
 pg_temp.doc('{"primary_muscles":["biceps","wings"]}')),'22023','unknown muscle rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000022',
 pg_temp.doc('{"primary_muscles":["quads","quads"]}')),'22023','duplicate rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000023',
 pg_temp.doc('{"primary_muscles":["quads"],"secondary_muscles":["quads"]}')),'22023',
 'muscle in both lists rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000024',
 pg_temp.doc('{"primary_muscles":"quads"}')),'22023','non-array rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000025',
 pg_temp.doc('{"primary_muscles":[1]}')),'22023','non-string element rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000026',
 pg_temp.doc(jsonb_build_object('primary_muscles',
  '["chest","shoulders","biceps","forearms","abs","obliques","quads","calves","traps","lats","lowerBack","triceps","glutes","hamstrings","chest"]'::jsonb))),
 '22023','15 entries rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000027',
 pg_temp.doc('{"secondary_muscles":["quads"]}')),'22023','secondary without primary rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000028',
 pg_temp.doc('{"primary_muscles":[],"secondary_muscles":["quads"]}')),'22023',
 'secondary with empty primary rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000029',
 pg_temp.doc('{"primary_muscles":["Quads"]}')),'22023','vocabulary is case sensitive');

select * from finish();
rollback;
