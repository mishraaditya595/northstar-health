-- Training library stage 4: timed sets (duration_seconds) on synced workouts.
-- Synthetic, rolled-back pgTAP. Run: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(19);

insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-0000000000a1','northstar-timed@example.invalid');

-- One exercise per workout; p_sets is the complete jsonb array of sets.
create function pg_temp.doc(wid uuid, p_sets jsonb) returns jsonb language sql as $$
 select jsonb_build_object(
  'schema_version',1,
  'workout_id',wid,
  'origin','northstar_phone','status','completed','name','Timed',
  'started_at_utc','2026-11-26T05:00:00Z',
  'completed_at_utc','2026-11-26T06:00:00Z',
  'original_offset_minutes',0,
  'exercises', jsonb_build_array(jsonb_build_object(
    'id','00000000-0000-4000-8000-000000000201','name','Plank',
    'position',0,'sets',p_sets)))
$$;

-- A completed working set; p_extra is merged over the defaults.
create function pg_temp.wset(n int, p_extra jsonb) returns jsonb language sql as $$
 select jsonb_build_object(
  'id',('00000000-0000-4000-8000-0000000003' || lpad(n::text,2,'0')),
  'position',n,'kind','working','status','completed','input_unit','kg',
  'completed_at_utc','2026-11-26T05:08:00Z') || p_extra
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

-- Accepted cases each use their own workout id; rejected cases share one.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000011',
 '00000000-0000-4000-8000-000000000101',
 pg_temp.doc('00000000-0000-4000-8000-000000000101',
  jsonb_build_array(pg_temp.wset(1,'{"duration_seconds":45}')))),
 'applied','completed timed set without reps is applied');
select is((select payload->'exercises'->0->'sets'->0->'duration_seconds'
 from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'),
 '45'::jsonb,'stored payload keeps duration_seconds');

select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000012',
 '00000000-0000-4000-8000-000000000102',
 pg_temp.doc('00000000-0000-4000-8000-000000000102',
  jsonb_build_array(pg_temp.wset(1,'{"duration_seconds":1}'),
                    pg_temp.wset(2,'{"duration_seconds":86400}')))),
 'applied','boundary durations 1 and 86400 are applied');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000013',
 '00000000-0000-4000-8000-000000000103',
 pg_temp.doc('00000000-0000-4000-8000-000000000103',
  jsonb_build_array(pg_temp.wset(1,'{"reps":8,"load_grams":60000}')))),
 'applied','rep set without duration_seconds is applied');
select is((select (payload->'exercises'->0->'sets'->0) ? 'duration_seconds'
 from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000103'),
 false,'rep set payload has no duration_seconds key');

select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000021',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  jsonb_build_array(pg_temp.wset(1,'{"duration_seconds":0}')))),
 '22023','zero seconds rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000022',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  jsonb_build_array(pg_temp.wset(1,'{"duration_seconds":86401}')))),
 '22023','86401 seconds rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000023',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  jsonb_build_array(pg_temp.wset(1,'{"duration_seconds":"45"}')))),
 '22023','string seconds rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000024',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  jsonb_build_array(pg_temp.wset(1,'{"duration_seconds":45.5}')))),
 '22023','fractional seconds rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000025',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  jsonb_build_array(pg_temp.wset(1,'{"duration_seconds":-5}')))),
 '22023','negative seconds rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000026',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  jsonb_build_array(pg_temp.wset(1,'{"reps":5,"duration_seconds":45}')))),
 '22023','reps and seconds together rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000027',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  jsonb_build_array(pg_temp.wset(1,'{}')))),
 '22023','completed set with neither reps nor seconds rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000028',
 '00000000-0000-4000-8000-000000000199',
 pg_temp.doc('00000000-0000-4000-8000-000000000199',
  jsonb_build_array(pg_temp.wset(1,'{"reps":null,"duration_seconds":null}')))),
 '22023','completed set with both null rejected');

-- Progress: one timed working set and one loaded rep working set.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000014',
 '00000000-0000-4000-8000-000000000104',
 pg_temp.doc('00000000-0000-4000-8000-000000000104',
  jsonb_build_array(pg_temp.wset(1,'{"duration_seconds":45}'),
                    pg_temp.wset(2,'{"reps":5,"load_grams":100000}')))),
 'applied','mixed timed and rep workout is applied');
select is((select completed_working_sets from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000104'),
 2,'timed set counts as a completed working set');
select is((select loaded_volume_gram_reps from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000104'),
 500000::bigint,'volume is only the rep set load times reps');

-- A timed set may carry a load (later duration_load); it adds no volume.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000015',
 '00000000-0000-4000-8000-000000000105',
 pg_temp.doc('00000000-0000-4000-8000-000000000105',
  jsonb_build_array(pg_temp.wset(1,'{"duration_seconds":30,"load_grams":20000}'),
                    pg_temp.wset(2,'{"reps":5,"load_grams":100000}')))),
 'applied','timed set with a load is applied');
select is((select loaded_volume_gram_reps from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000105'),
 500000::bigint,'timed set load adds no volume');

select is(has_function_privilege('authenticated','northstar_private.validate_workout_v1(uuid,jsonb)','EXECUTE'),
 false,'authenticated cannot execute the private validator');

select * from finish();
rollback;
