-- P2-06 per-workout resolution lookup; synthetic roles, rollback-only.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(18);
insert into auth.users(id,email) values
('00000000-0000-4000-8000-0000000000e1','lookup-a@example.invalid'),
('00000000-0000-4000-8000-0000000000e2','lookup-b@example.invalid');
select is(has_function_privilege('anon','public.get_workout_for_resolution(uuid)','EXECUTE'),false,
 'anon cannot read a workout');
select is(has_function_privilege('authenticated','public.get_workout_for_resolution(uuid)','EXECUTE'),true,
 'authenticated may use owner-bound lookup');
select is(has_table_privilege('authenticated','northstar_private.workout_owner_cursors','SELECT'),false,
 'private owner cursor stays inaccessible');
select is(has_table_privilege('authenticated','northstar_private.workout_restore_epoch','SELECT'),false,
 'private restore epoch stays inaccessible');
select is(has_table_privilege('authenticated','public.workout_records','UPDATE'),false,
 'lookup does not grant mutation');
create function pg_temp.try_lookup(workout uuid) returns text
language plpgsql security invoker as $test$
begin
 perform public.get_workout_for_resolution(workout);
 return 'ok';
exception when others then return sqlstate;
end;
$test$;
set local role authenticated;
select is(pg_temp.try_lookup('00000000-0000-4000-8000-0000000000f1'),'28000',
 'missing claim denied');
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000e1","is_anonymous":true}',true);
select is(pg_temp.try_lookup('00000000-0000-4000-8000-0000000000f1'),'28000',
 'anonymous identity denied');
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000e1","is_anonymous":false}',true);
select is(pg_temp.try_lookup(null),'22023','null workout ID rejected');
select is((public.get_workout_for_resolution(
 '00000000-0000-4000-8000-0000000000f1')->>'schema_version')::int,1,
 'versioned result');
select is((public.get_workout_for_resolution(
 '00000000-0000-4000-8000-0000000000f1')->'change')::text,'null',
 'missing workout has no data');
select ok((public.get_workout_for_resolution(
 '00000000-0000-4000-8000-0000000000f1')->>'cursor_epoch')::uuid is not null,
 'lookup includes epoch');
select set_config('northstar.lookup_fixture',
 '{"schema_version":1,"workout_id":"00000000-0000-4000-8000-0000000000f1","origin":"northstar_phone","status":"completed","name":"Private","started_at_utc":"2026-10-26T08:00:00Z","completed_at_utc":"2026-10-26T09:00:00Z","original_offset_minutes":330,"exercises":[]}',true);
select is((public.sync_workout('00000000-0000-4000-8000-0000000000a1',
 '00000000-0000-4000-8000-0000000000f1',0,'upsert',
 current_setting('northstar.lookup_fixture')::jsonb)->>'result'),'applied',
 'seed completed workout through real RPC');
select is((public.get_workout_for_resolution(
 '00000000-0000-4000-8000-0000000000f1')->'change'->>'server_revision')::bigint,1::bigint,
 'lookup returns current server revision');
select is((public.get_workout_for_resolution(
 '00000000-0000-4000-8000-0000000000f1')->'change'->'payload'->>'name'),
 'Private','lookup returns completed DTO to the owner');
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000e2","is_anonymous":false}',true);
select is((public.get_workout_for_resolution(
 '00000000-0000-4000-8000-0000000000f1')->'change')::text,'null',
 'second owner cannot read first owner workout');
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000e1","is_anonymous":false}',true);
select is((public.sync_workout('00000000-0000-4000-8000-0000000000a2',
 '00000000-0000-4000-8000-0000000000f1',1,'delete',null)->>'result'),'applied',
 'owner deletes existing workout');
select is((public.get_workout_for_resolution(
 '00000000-0000-4000-8000-0000000000f1')->'change'->>'deleted')::boolean,true,
 'lookup exposes deletion marker');
select is((public.get_workout_for_resolution(
 '00000000-0000-4000-8000-0000000000f1')->'change'->'payload')::text,'null',
 'deleted workout payload redacted');
select is((public.get_workout_for_resolution(
 '00000000-0000-4000-8000-0000000000f1')->'change'->>'server_revision')::bigint,2::bigint,
 'latest CAS revision available for reviewed resolution');
select * from finish();
rollback;
