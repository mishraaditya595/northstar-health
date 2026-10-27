-- P2-07c: synthetic, rolled-back pgTAP. No real accounts are deleted.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(25);

select is(
  has_function_privilege('anon','public.authorize_account_deletion()','EXECUTE'),
  false, 'anon cannot execute the fresh-session gate'
);
select is(
  has_function_privilege('authenticated','public.authorize_account_deletion()','EXECUTE'),
  true, 'authenticated role may request fresh-session check'
);
select is(
  has_table_privilege('authenticated','auth.sessions','SELECT'),
  false, 'app clients cannot query Auth session records'
);

insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-4000-8000-0000000000a1','p2-delete-a@example.invalid',now()),
 ('00000000-0000-4000-8000-0000000000b2','p2-delete-b@example.invalid',now()),
 ('00000000-0000-4000-8000-0000000000c3','p2-delete-unverified@example.invalid',null);

insert into auth.sessions(id,user_id,created_at,updated_at) values
 ('00000000-0000-4000-8000-0000000000d1','00000000-0000-4000-8000-0000000000a1',now(),now()),
 ('00000000-0000-4000-8000-0000000000d2','00000000-0000-4000-8000-0000000000a1',now()-interval '20 minutes',now()),
 ('00000000-0000-4000-8000-0000000000d3','00000000-0000-4000-8000-0000000000b2',now(),now()),
 ('00000000-0000-4000-8000-0000000000d4','00000000-0000-4000-8000-0000000000c3',now(),now());

-- Two real synthetic owners have entries in every user-data table. The
-- gate test must not trivially pass by counting zero pre-existing rows.
insert into public.workout_records
 (user_id,workout_id,server_revision,schema_version,status,server_change_seq)
values
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-000000000111',1,1,'completed',1),
 ('00000000-0000-4000-8000-0000000000b2','00000000-0000-4000-8000-000000000222',1,1,'completed',1);

-- Real deleted workout tombstone: no payload or completed/loaded statistics.
insert into public.workout_records
 (user_id,workout_id,server_revision,schema_version,status,server_change_seq,
  deleted_at,payload,completed_working_sets,loaded_working_sets,loaded_volume_gram_reps)
values
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-000000000112',
  2,1,'completed',2,now(),null,null,null,null);

insert into public.workout_sync_operations
 (user_id,operation_id,workout_id,expected_revision,action,applied_revision,
  applied_change_seq,request_sha256)
values
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-000000000113','00000000-0000-4000-8000-000000000111',0,'upsert',1,1,decode(repeat('11',32),'hex')),
 ('00000000-0000-4000-8000-0000000000b2','00000000-0000-4000-8000-000000000223','00000000-0000-4000-8000-000000000222',0,'upsert',1,1,decode(repeat('22',32),'hex'));
insert into northstar_private.workout_owner_cursors(user_id,last_change_seq)
values
 ('00000000-0000-4000-8000-0000000000a1',2),
 ('00000000-0000-4000-8000-0000000000b2',1);

create function pg_temp.try_deletion_gate() returns text
language plpgsql security invoker as $$
begin
  if public.authorize_account_deletion() then return 'ok'; end if;
  return 'false';
exception when others then return sqlstate;
end
$$;

set local role authenticated;

select set_config('request.jwt.claims','{}',true);
select is(pg_temp.try_deletion_gate(),'28000','no caller is denied');

select set_config('request.jwt.claims',
 '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1","is_anonymous":true,"session_id":"00000000-0000-4000-8000-0000000000d1"}',true);
select is(pg_temp.try_deletion_gate(),'28000','anonymous auth cannot delete');

select set_config('request.jwt.claims',
 '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1","is_anonymous":false}',true);
select is(pg_temp.try_deletion_gate(),'28000','missing session ID is denied');

select set_config('request.jwt.claims',
 '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1","is_anonymous":false,"session_id":"junk"}',true);
select is(pg_temp.try_deletion_gate(),'28000','malformed session ID is denied');

select set_config('request.jwt.claims',
 '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1","is_anonymous":false,"session_id":"00000000-0000-4000-8000-0000000000d9"}',true);
select is(pg_temp.try_deletion_gate(),'28000','revoked/nonexistent session fails');

select set_config('request.jwt.claims',
 '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1","is_anonymous":false,"session_id":"00000000-0000-4000-8000-0000000000d3"}',true);
select is(pg_temp.try_deletion_gate(),'28000','a different owner session fails');

select set_config('request.jwt.claims',
 '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1","is_anonymous":false,"session_id":"00000000-0000-4000-8000-0000000000d2","iat":9999999999}',true);
select is(pg_temp.try_deletion_gate(),'28000','a refreshed JWT cannot make old session fresh');

select set_config('request.jwt.claims',
 '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1","is_anonymous":false,"session_id":"00000000-0000-4000-8000-0000000000d1"}',true);
select is(pg_temp.try_deletion_gate(),'ok','fresh verified owner session authorized');

select set_config('request.jwt.claims',
 '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000c3","is_anonymous":false,"session_id":"00000000-0000-4000-8000-0000000000d4"}',true);
select is(pg_temp.try_deletion_gate(),'28000','unverified email is denied');

reset role;
update auth.sessions set created_at=now()+interval '1 minute'
 where id='00000000-0000-4000-8000-0000000000d1';
set local role authenticated;
select set_config('request.jwt.claims',
 '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1","is_anonymous":false,"session_id":"00000000-0000-4000-8000-0000000000d1"}',true);
select is(pg_temp.try_deletion_gate(),'28000','sessions dated in the future are rejected');

reset role;
select is((select count(*) from public.workout_records where user_id in
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-0000000000b2')),
 3::bigint, 'gate cannot alter seeded owner workout rows');
select is(
 (select count(*) from public.workout_records
  where user_id='00000000-0000-4000-8000-0000000000a1'
    and deleted_at is not null and payload is null
    and completed_working_sets is null and loaded_working_sets is null
    and loaded_volume_gram_reps is null),
 1::bigint, 'synthetic deleted-workout tombstone really exists before cascade');
select is((select count(*) from public.workout_sync_operations where user_id in
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-0000000000b2')),
 2::bigint, 'gate cannot alter seeded owner receipt rows');

-- Dynamic regression guard: EVERY app-owned FK into auth.users must cascade,
-- so adding a table without ON DELETE CASCADE fails the test suite.
select ok(
 (select count(*) >= 3 and bool_and(c.confdeltype = 'c')
  from pg_constraint c
  join pg_class relation on relation.oid = c.conrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where c.contype = 'f'
    and c.confrelid = 'auth.users'::regclass
    and namespace.nspname in ('public','northstar_private')),
 'all NorthStar tables referencing auth.users use ON DELETE CASCADE'
);

delete from auth.users where id='00000000-0000-4000-8000-0000000000a1';
select is((select count(*) from auth.users where id='00000000-0000-4000-8000-0000000000a1'),
 0::bigint, 'synthetic owner A deleted');
select is((select count(*) from auth.users where id='00000000-0000-4000-8000-0000000000b2'),
 1::bigint, 'synthetic owner B remains');
select is((select count(*) from public.workout_records where user_id='00000000-0000-4000-8000-0000000000a1'),
 0::bigint, 'deleting A cascades workout history and tombstones');
select is((select count(*) from public.workout_sync_operations where user_id='00000000-0000-4000-8000-0000000000a1'),
 0::bigint, 'deleting A cascades idempotency receipts');
select is((select count(*) from northstar_private.workout_owner_cursors where user_id='00000000-0000-4000-8000-0000000000a1'),
 0::bigint, 'deleting A cascades owner cursor');
select is((select count(*) from public.workout_records where user_id='00000000-0000-4000-8000-0000000000b2'),
 1::bigint, 'B workout rows remain intact');
select is((select count(*) from public.workout_sync_operations where user_id='00000000-0000-4000-8000-0000000000b2'),
 1::bigint, 'B receipt rows remain intact');
select is((select count(*) from northstar_private.workout_owner_cursors where user_id='00000000-0000-4000-8000-0000000000b2'),
 1::bigint, 'B cursor remains intact');
select * from finish();
rollback;
