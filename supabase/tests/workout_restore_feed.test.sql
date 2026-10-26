-- P2-06. Synthetic users, rolled-back pgTAP. Run after all nine migrations.
-- This pgTAP suite uses ONE connection: it cannot verify inter-session
-- commit ordering. Reviewer separately verified with two concurrent sessions
-- that readers never skip an uncommitted lower owner sequence; keep that
-- explicit two-session check as a pre-release integration gate.
-- Simulated restore is the operator's privileged epoch rotation while the
-- authoritative counter is already higher than the client's stale cursor.
-- A DB backup includes its old epoch: production operators MUST rotate the
-- epoch after restoring, before allowing client traffic. PostgreSQL cannot
-- infer this event from restored state alone.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(76);
insert into auth.users(id,email) values
('00000000-0000-4000-8000-0000000000c1','restore-a@example.invalid'),
('00000000-0000-4000-8000-0000000000d2','restore-b@example.invalid');
select ok((select relrowsecurity from pg_class where oid='public.workout_records'::regclass),'RLS enabled');
select is(has_function_privilege('anon','public.get_workout_changes(bigint,integer,uuid)','EXECUTE'),false,'anon denied');
select is(has_function_privilege('authenticated','public.get_workout_changes(bigint,integer,uuid)','EXECUTE'),true,'auth granted');
select is(has_table_privilege('authenticated','public.workout_records','INSERT'),false,'no direct insert');
select is(has_table_privilege('authenticated','public.workout_records','UPDATE'),false,'no direct update');
select is(has_table_privilege('authenticated','public.workout_records','DELETE'),false,'no direct delete');
select is(has_table_privilege('authenticated','northstar_private.workout_owner_cursors','SELECT'),
false,'no client read grant on the private owner counter');
select is(has_function_privilege('anon','northstar_private.current_workout_restore_state()','EXECUTE'),
false,'anon cannot read the private owner state');
select is(has_function_privilege('authenticated','northstar_private.rotate_workout_restore_epoch()','EXECUTE'),
false,'authenticated user cannot rotate restore epoch');
select is(has_function_privilege('anon','northstar_private.rotate_workout_restore_epoch()','EXECUTE'),
false,'anon cannot rotate restore epoch');
select is(has_table_privilege('authenticated','northstar_private.workout_restore_epoch','SELECT'),
false,'authenticated user has no epoch table SELECT grant');
select is(has_table_privilege('authenticated','northstar_private.workout_restore_epoch','UPDATE'),
false,'authenticated user cannot rotate epoch using direct UPDATE');
create function pg_temp.read_state(c bigint,n integer)
returns text language plpgsql security invoker as $check$
begin perform public.get_workout_changes(c,n);return 'ok';
exception when others then return sqlstate;end $check$;
set local role authenticated;
select is(pg_temp.read_state(0,100),'28000','missing user denied');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-0000000000c1","is_anonymous":true}',true);
select is(pg_temp.read_state(0,100),'28000','anonymous session denied');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-0000000000c1","is_anonymous":"yes"}',true);
select is(pg_temp.read_state(0,100),'28000','malformed is_anonymous claim rejected with auth error, not 22P02');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-0000000000c1"}',true);
select is(pg_temp.read_state(0,100),'28000','missing is_anonymous claim rejected');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-0000000000c1","is_anonymous":false}',true);
select is(pg_temp.read_state(-1,1),'22023','negative cursor denied');
select is(pg_temp.read_state(0,0),'22023','zero limit denied');
select is(pg_temp.read_state(0,201),'22023','oversized limit denied');
select is(pg_temp.read_state(0,null),'22023','null page limit denied');
select is(pg_temp.read_state(null,10),'22023','null cursor denied');
select is(pg_temp.read_state(0,200),'ok','max bounded page allowed');
select is((public.get_workout_changes()->>'next_cursor')::bigint,0::bigint,'empty cursor');
select ok((public.get_workout_changes()->>'cursor_epoch')::uuid is not null,
'initial bootstrap at zero returns a server epoch');
select set_config('northstar.restore_epoch',public.get_workout_changes()->>'cursor_epoch',true);
select is((public.get_workout_changes(0,100,current_setting('northstar.restore_epoch')::uuid)
  ->>'cursor_reset')::boolean,false,'same-epoch bootstrap does not reset');
select is(pg_catalog.jsonb_array_length(public.get_workout_changes()->'changes'),0,'empty feed');
select is((public.get_workout_changes()->>'cursor_reset')::boolean,false,'fresh zero cursor needs no reset');
select is((public.get_workout_changes(1,100,current_setting('northstar.restore_epoch')::uuid)->>'cursor_reset')::boolean,true,'positive cursor ahead of empty server requests reset');
select is((public.get_workout_changes(1,100,current_setting('northstar.restore_epoch')::uuid)
  ->>'cursor_reset')::boolean,true,'valid epoch cannot override a cursor ahead of the server');
select is((public.get_workout_changes(1,100,current_setting('northstar.restore_epoch')::uuid)->>'next_cursor')::bigint,0::bigint,'reset response directs restart at zero');
select set_config('northstar.restore_fixture','{"schema_version":1,"workout_id":"00000000-0000-4000-8000-000000000401","origin":"northstar_phone","status":"completed","name":"Rows","started_at_utc":"2026-10-25T05:00:00Z","completed_at_utc":"2026-10-25T06:00:00Z","original_offset_minutes":330,"exercises":[]}',true);
select is(public.sync_workout('00000000-0000-4000-8000-000000000411',
'00000000-0000-4000-8000-000000000401',0,'upsert',current_setting('northstar.restore_fixture')::jsonb)->>'result','applied','first workout');
select is(public.sync_workout('00000000-0000-4000-8000-000000000412',
'00000000-0000-4000-8000-000000000402',0,'upsert',
jsonb_set(current_setting('northstar.restore_fixture')::jsonb,'{workout_id}','"00000000-0000-4000-8000-000000000402"'::jsonb))->>'result','applied','second workout');
select is(pg_catalog.jsonb_array_length(public.get_workout_changes(0,1,current_setting('northstar.restore_epoch')::uuid)->'changes'),1,'page limit respected');
select is((public.get_workout_changes(0,1,current_setting('northstar.restore_epoch')::uuid)->>'has_more')::boolean,true,'next page exists');
select is((public.get_workout_changes(1,1,current_setting('northstar.restore_epoch')::uuid)->>'next_cursor')::bigint,2::bigint,'cursor advances');
select is((public.get_workout_changes(1,1,current_setting('northstar.restore_epoch')::uuid)->'changes'->0->>'workout_id'),
'00000000-0000-4000-8000-000000000402','second page returns second workout');
select is((public.get_workout_changes(1,1,current_setting('northstar.restore_epoch')::uuid)->>'has_more')::boolean,false,'second page is final');
select is(pg_catalog.jsonb_array_length(public.get_workout_changes(0,2,current_setting('northstar.restore_epoch')::uuid)->'changes'),2,'exactly-limit page returns both changes');
select is((public.get_workout_changes(0,2,current_setting('northstar.restore_epoch')::uuid)->>'has_more')::boolean,false,'exactly-limit page has no next page');
select is((public.get_workout_changes(0,2,current_setting('northstar.restore_epoch')::uuid)->>'next_cursor')::bigint,
(public.get_workout_changes(0,2,current_setting('northstar.restore_epoch')::uuid)->'changes'->1->>'change_seq')::bigint,
'full-page next_cursor equals its last emitted change_seq');
select is((public.get_workout_changes(0,1,current_setting('northstar.restore_epoch')::uuid)->>'next_cursor')::bigint,
(public.get_workout_changes(0,1,current_setting('northstar.restore_epoch')::uuid)->'changes'->0->>'change_seq')::bigint,
'truncated-page next_cursor equals its last emitted change_seq');
select is((public.get_workout_changes(2,1,current_setting('northstar.restore_epoch')::uuid)->>'next_cursor')::bigint,2::bigint,'empty page retains cursor');
select is((public.get_workout_changes(1,1)->>'cursor_reset')::boolean,true,
'nonzero cursor without an epoch cannot silently skip existing changes');
select is((public.get_workout_changes(0,1,current_setting('northstar.restore_epoch')::uuid)->'changes'->0 ? 'user_id'),false,'no owner field');
select is(public.sync_workout('00000000-0000-4000-8000-000000000414',
'00000000-0000-4000-8000-000000000401',1,'upsert',
jsonb_set(current_setting('northstar.restore_fixture')::jsonb,'{name}','"Edited Rows"'::jsonb))->>'result',
'applied','corrected workout accepted');
select is((public.get_workout_changes(2,1,current_setting('northstar.restore_epoch')::uuid)->'changes'->0->>'server_revision')::bigint,
2::bigint,'updated revision appears in feed');
select is((public.get_workout_changes(2,1,current_setting('northstar.restore_epoch')::uuid)->'changes'->0->'payload'->>'name'),
'Edited Rows','latest payload after correction');
select is((public.sync_workout('00000000-0000-4000-8000-000000000414',
'00000000-0000-4000-8000-000000000401',1,'upsert',
jsonb_set(current_setting('northstar.restore_fixture')::jsonb,'{name}','"Edited Rows"'::jsonb))->>'replay')::boolean,true,'repeated operation is idempotent');
select is((public.get_workout_changes(3,1,current_setting('northstar.restore_epoch')::uuid)->>'next_cursor')::bigint,
3::bigint,'exact replay does not allocate a cursor');
select is(public.sync_workout('00000000-0000-4000-8000-000000000413',
'00000000-0000-4000-8000-000000000401',2,'delete',null)->>'result','applied','delete');
select is((public.get_workout_changes(2,1,current_setting('northstar.restore_epoch')::uuid)->'changes'->0->>'deleted')::boolean,true,'tombstone emitted');
select is(pg_catalog.jsonb_typeof(public.get_workout_changes(2,1,current_setting('northstar.restore_epoch')::uuid)->'changes'->0->'payload'),'null','tombstone has no payload');
select is((northstar_private.current_workout_restore_state()->>'last_change_seq')::bigint,4::bigint,
'authoritative owner cursor advances through delete');
select is((public.get_workout_changes(999,100,current_setting('northstar.restore_epoch')::uuid)->>'cursor_reset')::boolean,true,
'cursor greater than authoritative owner head detects restored-server regression');
select is((public.get_workout_changes(999,100,current_setting('northstar.restore_epoch')::uuid)->>'next_cursor')::bigint,0::bigint,
'regressed-server cursor returns restart position zero, never 999');
select is((public.get_workout_changes(999,100,current_setting('northstar.restore_epoch')::uuid)->>'has_more')::boolean,false,
'reset response is not a normal pagination page');
select is(pg_catalog.jsonb_array_length(public.get_workout_changes(999,100,current_setting('northstar.restore_epoch')::uuid)->'changes'),0,
'reset response contains no workout data');
select is((public.get_workout_changes(0,100,current_setting('northstar.restore_epoch')::uuid)->>'cursor_reset')::boolean,false,
're-reading from zero after reset is allowed');
select is(pg_catalog.jsonb_array_length(public.get_workout_changes(0,100,current_setting('northstar.restore_epoch')::uuid)->'changes'),2,
're-reading from zero includes the latest active snapshot and tombstone');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-0000000000d2","is_anonymous":false}',true);
select is(pg_catalog.jsonb_array_length(public.get_workout_changes(0,100,current_setting('northstar.restore_epoch')::uuid)->'changes'),0,'B cannot see A feed');
select is(public.sync_workout('00000000-0000-4000-8000-000000000421',
'00000000-0000-4000-8000-000000000401',0,'upsert',
current_setting('northstar.restore_fixture')::jsonb)->>'result','applied','B owns same UUID independently');
select is((public.get_workout_changes(0,100,current_setting('northstar.restore_epoch')::uuid)->'changes'->0->>'deleted')::boolean,
false,'B sees its own live workout, not A tombstone');
select is((public.get_workout_changes(0,100,current_setting('northstar.restore_epoch')::uuid)->>'next_cursor')::bigint,
1::bigint,'independent B cursor');
select is((public.get_workout_changes(2,100,current_setting('northstar.restore_epoch')::uuid)->>'cursor_reset')::boolean,true,
'B detects its own high cursor regardless of account A sequence');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-0000000000c1","is_anonymous":false}',true);
select is((public.get_workout_changes(3,100,current_setting('northstar.restore_epoch')::uuid)->'changes'->0->>'deleted')::boolean,
true,'A tombstone remains isolated after account switch');

-- Privileged fixture: a cursor may exceed the maximum live row sequence.
-- Comparing only MAX(workout_records.server_change_seq) would report a false
-- reset here; the private authoritative owner counter must decide instead.
reset role;
update northstar_private.workout_owner_cursors
  set last_change_seq=10
  where user_id='00000000-0000-4000-8000-0000000000c1';
set local role authenticated;
select is((northstar_private.current_workout_restore_state()->>'last_change_seq')::bigint,10::bigint,
'current owner counter is authoritative even when no row has seq 10');
select is((public.get_workout_changes(8,100,current_setting('northstar.restore_epoch')::uuid)->>'cursor_reset')::boolean,false,
'cursor below authoritative owner counter does not spuriously reset');
select is((public.get_workout_changes(8,100,current_setting('northstar.restore_epoch')::uuid)->>'next_cursor')::bigint,8::bigint,
'non-reset empty result retains the requested cursor');

-- Overtaken stale cursor: server has newer writes through seq 10, but a
-- device still has seq 8 from an epoch that was invalidated by restore.
-- Numeric comparison alone sees 8 <= 10 and misses this rollback.
reset role;
select set_config('northstar.new_restore_epoch',
 northstar_private.rotate_workout_restore_epoch()::text,true);
set local role authenticated;
select isnt(current_setting('northstar.restore_epoch'),
 current_setting('northstar.new_restore_epoch'),
 'operator rotation generates a new restore epoch');
select is((public.get_workout_changes(8,100,current_setting('northstar.restore_epoch')::uuid)
 ->>'cursor_reset')::boolean,true,
 'old epoch detects rollback even after new writes overtake stale cursor');
select is((public.get_workout_changes(8,100,current_setting('northstar.restore_epoch')::uuid)
 ->>'next_cursor')::bigint,0::bigint,
 'old epoch tells stale client to reconcile and restart at zero');
select is((public.get_workout_changes(8,100,current_setting('northstar.restore_epoch')::uuid)
 ->>'cursor_epoch'),current_setting('northstar.new_restore_epoch'),
 'reset response supplies the new authoritative epoch');
select is((public.get_workout_changes(0,100,current_setting('northstar.restore_epoch')::uuid)
 ->>'cursor_reset')::boolean,true,
 'stale epoch is rejected even if numeric cursor is zero');
select is((public.get_workout_changes(8,100,current_setting('northstar.new_restore_epoch')::uuid)
 ->>'cursor_reset')::boolean,false,
 'new epoch is accepted with valid nonzero cursor');
select is((public.get_workout_changes(8,100,current_setting('northstar.new_restore_epoch')::uuid)
 ->>'next_cursor')::bigint,8::bigint,
 'new-epoch empty page preserves cursor');
select is((public.get_workout_changes(0,100)->>'cursor_epoch'),
 current_setting('northstar.new_restore_epoch'),
 'bootstrap without epoch returns new authoritative epoch');
select * from finish();
rollback;
