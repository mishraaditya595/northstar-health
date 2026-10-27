-- P2-01: synthetic, rolled-back pgTAP suite. Run: supabase test db
-- Requires completed phase2 migrations, exercises RPC as authenticated/anon.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(66);

insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-0000000000a1','northstar-p2-a@example.invalid'),
 ('00000000-0000-4000-8000-0000000000b2','northstar-p2-b@example.invalid');

select ok((select relrowsecurity from pg_class where oid='public.workout_records'::regclass),
 'workout records RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.workout_sync_operations'::regclass),
 'receipts RLS enabled');
select is(has_function_privilege('anon','public.sync_workout(uuid,uuid,bigint,text,jsonb)','EXECUTE'),
 false,'anonymous cannot invoke sync endpoint');

create function pg_temp.try_sync(op uuid,wid uuid,rev bigint,action text,doc jsonb)
returns text language plpgsql security invoker as $$
begin
 perform public.sync_workout(op,wid,rev,action,doc);
 return 'ok';
exception when others then
 return sqlstate;
end $$;
create function pg_temp.try_dml(query text)
returns text language plpgsql security invoker as $$
begin
 execute query;
 return 'ok';
exception when others then
 return sqlstate;
end $$;

select set_config('northstar.fixture',
 '{"schema_version":1,"workout_id":"00000000-0000-4000-8000-000000000101","origin":"northstar_phone","status":"completed","name":"Rows","started_at_utc":"2026-10-25T05:00:00Z","completed_at_utc":"2026-10-25T06:00:00Z","original_offset_minutes":330,"exercises":[{"id":"00000000-0000-4000-8000-000000000201","name":"Seated row","position":0,"sets":[{"id":"00000000-0000-4000-8000-000000000301","position":0,"kind":"working","status":"completed","input_unit":"kg","reps":8,"load_grams":60000,"completed_at_utc":"2026-10-25T05:08:00Z"},{"id":"00000000-0000-4000-8000-000000000302","position":1,"kind":"warmup","status":"completed","input_unit":"kg","reps":12,"load_grams":20000,"completed_at_utc":"2026-10-25T05:09:00Z"},{"id":"00000000-0000-4000-8000-000000000303","position":2,"kind":"working","status":"completed","input_unit":"kg","reps":10,"load_grams":null,"completed_at_utc":"2026-10-25T05:10:00Z"},{"id":"00000000-0000-4000-8000-000000000304","position":3,"kind":"working","status":"completed","input_unit":"kg","reps":5,"load_grams":0,"completed_at_utc":"2026-10-25T05:11:00Z"}]}]}',
 true);

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","is_anonymous":false}',true);

-- The mobile outbox must not queue a cloud delete with no tracked upload:
-- the RPC rejects an absent workout instead of inventing a tombstone.
select is((public.sync_workout('00000000-0000-4000-8000-0000000000de',
 '00000000-0000-4000-8000-0000000000dd',0,'delete',null::jsonb)->>'result'),
 'conflict','deleting an unknown server workout is not an applied operation');
select is((select count(*)::int from public.workout_records
 where workout_id='00000000-0000-4000-8000-0000000000dd'),0,
 'missing-record delete cannot create a phantom cloud row');

select is((public.sync_workout('00000000-0000-4000-8000-000000000011',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb)->>'result'),
 'applied','first version inserted');
select is((select server_revision::text from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'), '1','server revision 1');
select is((select completed_working_sets::text from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'), '3','completed working sets exclude warmup');
select is((select loaded_working_sets::text from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'), '1','missing and zero load excluded');
select is((select loaded_volume_gram_reps::text from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'), '480000','volume computed on server');
reset role;
select is((select pg_catalog.octet_length(request_sha256)::text from
 public.workout_sync_operations limit 1),'32','receipt contains SHA-256 hash');
set local role authenticated;
select is((public.sync_workout('00000000-0000-4000-8000-000000000011',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb)->>'replay'),
 'true','exact replay recognized');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000011',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{name}','"changed"'::jsonb)),
 '22023','same operation ID with altered content rejected');
select is((public.sync_workout('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb)->>'result'),
 'conflict','stale update returns conflict');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'origin'),
 '22023','invalid stale payload fails validation before conflict');


-- Validate the remaining required keys individually, not only the shortest payload.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'schema_version'),
 '22023','missing workout schema_version rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'name'),
 '22023','missing workout name rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'original_offset_minutes'),
 '22023','missing workout original_offset_minutes rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'exercises'),
 '22023','missing workout exercises rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{exercises,0}',
 (current_setting('northstar.fixture')::jsonb #> '{exercises,0}') - 'position')),
 '22023','missing exercise position rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{exercises,0,sets,0}',
 (current_setting('northstar.fixture')::jsonb #> '{exercises,0,sets,0}') - 'position')),
 '22023','missing set position rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{exercises,0,sets,0}',
 (current_setting('northstar.fixture')::jsonb #> '{exercises,0,sets,0}') - 'input_unit')),
 '22023','missing set input_unit rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{completed_at_utc}',
 '"2026-10-25T04:00:00Z"'::jsonb)),
 '22023','finish earlier than start rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{exercises,0,sets,0,completed_at_utc}',
 '"2026-02-30T25:00:00Z"'::jsonb)),
 '22023','malformed set timestamp rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{exercises}',
 (current_setting('northstar.fixture')::jsonb->'exercises') ||
 (current_setting('northstar.fixture')::jsonb->'exercises'->0))),
 '22023','duplicate exercise IDs rejected');

-- Explicit missing-field negative tests: workout, exercise and set fields.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 '{"status":"completed"}'::jsonb),
 '22023','only status rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'origin'),
 '22023','missing origin rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'workout_id'),
 '22023','missing workout id rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'status'),
 '22023','missing status rejected');
-- ADR-0005: only workouts the user finished are synchronized.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{status}','"inProgress"'::jsonb)),
 '22023','in-progress workout rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{status}','"paused"'::jsonb)),
 '22023','paused workout rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{status}','"discarded"'::jsonb)),
 '22023','discarded workout rejected');
reset role;
select is((select pg_get_constraintdef(oid) from pg_constraint
 where conname='workout_records_status_check'),
 'CHECK ((status = ''completed''::text))','table accepts only completed status');
set local role authenticated;
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'started_at_utc'),
 '22023','missing start rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb - 'completed_at_utc'),
 '22023','completed without completion time rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0}',(current_setting('northstar.fixture')::jsonb #> '{exercises,0}') - 'name')),
 '22023','missing exercise name rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0}',(current_setting('northstar.fixture')::jsonb #> '{exercises,0}') - 'id')),
 '22023','missing exercise id rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0}',(current_setting('northstar.fixture')::jsonb #> '{exercises,0}') - 'sets')),
 '22023','missing exercise sets rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0}',(current_setting('northstar.fixture')::jsonb #> '{exercises,0,sets,0}') - 'id')),
 '22023','missing set id rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0}',(current_setting('northstar.fixture')::jsonb #> '{exercises,0,sets,0}') - 'kind')),
 '22023','missing set kind rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0}',(current_setting('northstar.fixture')::jsonb #> '{exercises,0,sets,0}') - 'status')),
 '22023','missing set status rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0}',(current_setting('northstar.fixture')::jsonb #> '{exercises,0,sets,0}') - 'reps')),
 '22023','completed set missing reps rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0}',(current_setting('northstar.fixture')::jsonb #> '{exercises,0,sets,0}') - 'completed_at_utc')),
 '22023','completed set missing timestamp rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0,reps}','"8"'::jsonb)),
 '22023','string repetitions rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0,load_grams}','"60000"'::jsonb)),
 '22023','string grams rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0,load_grams}','999999999999999999999999'::jsonb)),
 '22023','overflow grams returns 22023');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{started_at_utc}','"2026-16-99T99:99:99Z"'::jsonb)),
 '22023','malformed timestamp rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,'{origin}','"external_platform"'::jsonb)),
 '22023','external workouts rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 current_setting('northstar.fixture')::jsonb || '{"heart_rate":70}'::jsonb),
 '22023','unapproved health field rejected');
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,1,id}','"00000000-0000-4000-8000-000000000301"'::jsonb)),
 '22023','duplicate set ids rejected');
select is(pg_temp.try_dml($$update public.workout_records set status='discarded'$$),
 '42501','authenticated user cannot write records directly');
select is(pg_temp.try_dml($$insert into public.workout_sync_operations(user_id) values (null)$$),
 '42501','authenticated user cannot insert receipt directly');

select is((public.sync_workout('00000000-0000-4000-8000-000000000012',
 '00000000-0000-4000-8000-000000000101',1,'delete',null)->>'result'),
 'applied','delete produces tombstone');
select is((select payload is null from public.workout_records
 where workout_id='00000000-0000-4000-8000-000000000101'),true,
 'deleted record contains no payload');
reset role;
select is((select count(*)::text from public.workout_sync_operations
 where request_sha256 is not null),'2','delete receipts retain hashes only');
select is((select count(*)::text from public.workout_sync_operations
 where expires_at > now()),'2','receipt retention has future expiry');
set local role authenticated;

-- The 90-day receipt policy is enforced opportunistically on the owner's
-- next mutation. Only hash receipts expire, not tombstones or change cursors.
reset role;
update public.workout_sync_operations
 set expires_at=now() - interval '1 second'
 where operation_id='00000000-0000-4000-8000-000000000011';
set local role authenticated;
select is(
 (public.sync_workout('00000000-0000-4000-8000-000000000013',
 '00000000-0000-4000-8000-000000000101',2,'delete',null)->>'result'),
 'applied','owner next write succeeds with expired receipt');
reset role;
select is(
 (select count(*)::text from public.workout_sync_operations
  where operation_id='00000000-0000-4000-8000-000000000011'),
 '0','expired hash receipt is purged on owner sync');
set local role authenticated;


-- RPE 10.5 is outside the allowed 0..10 range even though it ends in .5.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0,rpe}','10.5'::jsonb)),
 '22023','RPE 10.5 rejected');
-- UUIDs are case-insensitive; don't compare a second uppercase spelling as a distinct identity.
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000099',
 '00000000-0000-4000-8000-000000000101',0,'upsert',
 jsonb_set(jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{exercises,0,sets,0,id}','"00000000-0000-4000-8000-0000000003ab"'::jsonb),
 '{exercises,0,sets,1,id}','"00000000-0000-4000-8000-0000000003AB"'::jsonb)),
 '22023','case variants of same UUID are duplicate set IDs');

select is((public.sync_workout('00000000-0000-4000-8000-000000000014',
 '00000000-0000-4000-8000-000000000101',3,'upsert',
 current_setting('northstar.fixture')::jsonb)->>'result'),
 'conflict','tombstoned workout cannot be silently resurrected');

-- Account B sees none of A's records; writer identity is derived from JWT.
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000b2","role":"authenticated","is_anonymous":false}',true);
select is((select count(*)::text from public.workout_records),'0','other user cannot select A workout');
select is((public.sync_workout('00000000-0000-4000-8000-000000000021',
 '00000000-0000-4000-8000-000000000102',0,'upsert',
 jsonb_set(current_setting('northstar.fixture')::jsonb,
 '{workout_id}','"00000000-0000-4000-8000-000000000102"'::jsonb))->>'change_seq'),
 '1','independent owner cursor starts at 1');
select is((select count(*)::text from public.workout_records),'1','B sees only B');
select is(pg_temp.try_dml($$delete from public.workout_records$$),
 '42501','B cannot delete A or B rows directly');

-- Signed-in Supabase anonymous accounts are not valid NorthStar accounts.
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000b2","role":"authenticated","is_anonymous":true}',true);
select is(pg_temp.try_sync('00000000-0000-4000-8000-000000000022',
 '00000000-0000-4000-8000-000000000102',1,'delete',null),
 '28000','anonymous Supabase auth sessions rejected');

reset role;
select * from finish();
rollback;
