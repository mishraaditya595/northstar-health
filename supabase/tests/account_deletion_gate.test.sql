-- P2-07c: synthetic, rolled-back pgTAP. No real accounts are deleted.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);

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
select is(
 (select count(*) from public.workout_records
  where user_id in ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-0000000000b2')),
  0::bigint,'gate does not mutate workout records'
);
select * from finish();
rollback;
