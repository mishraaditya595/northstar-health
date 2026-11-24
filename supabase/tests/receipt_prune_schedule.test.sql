-- P2-08: synthetic, rolled-back pgTAP for the scheduled receipt purge.
-- Covers the job definition, client isolation and what the purge removes.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(12);

select is(
  (select count(*) from cron.job
    where jobname = 'northstar-prune-expired-workout-receipts'),
  1::bigint, 'exactly one receipt purge job is scheduled'
);
select is(
  (select schedule from cron.job
    where jobname = 'northstar-prune-expired-workout-receipts'),
  '17 3 * * *', 'purge runs daily at 03:17 UTC'
);
select is(
  (select command from cron.job
    where jobname = 'northstar-prune-expired-workout-receipts'),
  'select northstar_private.prune_expired_workout_receipts()',
  'purge job calls only the receipt prune function'
);
select ok(
  (select active from cron.job
    where jobname = 'northstar-prune-expired-workout-receipts'),
  'purge job is active'
);
select is(
  has_schema_privilege('anon', 'cron', 'USAGE'), false,
  'anonymous clients cannot reach scheduled jobs'
);
select is(
  has_schema_privilege('authenticated', 'cron', 'USAGE'), false,
  'signed-in clients cannot reach scheduled jobs'
);
select is(
  has_function_privilege('authenticated',
    'northstar_private.prune_expired_workout_receipts(timestamptz)', 'EXECUTE'),
  false, 'signed-in clients cannot run the full purge'
);

insert into auth.users(id, email) values
 ('00000000-0000-4000-8000-0000000000a1', 'p2-prune-a@example.invalid'),
 ('00000000-0000-4000-8000-0000000000b2', 'p2-prune-b@example.invalid');

-- A is inactive with one expired and one live receipt; B has one expired.
insert into public.workout_sync_operations(
  user_id, operation_id, workout_id, expected_revision, action,
  request_sha256, applied_revision, applied_change_seq, committed_at, expires_at
) values
 ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000a01',
  '00000000-0000-4000-8000-000000000101', 0, 'upsert',
  sha256('a-old'::bytea), 1, 1, now() - interval '100 days', now() - interval '10 days'),
 ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000a02',
  '00000000-0000-4000-8000-000000000101', 1, 'upsert',
  sha256('a-new'::bytea), 2, 2, now() - interval '1 day', now() + interval '89 days'),
 ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-000000000b01',
  '00000000-0000-4000-8000-000000000102', 0, 'upsert',
  sha256('b-old'::bytea), 1, 1, now() - interval '91 days', now() - interval '1 day');

insert into public.workout_records(
  user_id, workout_id, server_revision, schema_version, status, payload,
  server_change_seq
) values
 ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000101',
  2, 1, 'completed',
  '{"completed_at_utc":"2026-10-25T06:00:00Z","original_offset_minutes":0}'::jsonb, 2);

-- Run exactly what the scheduler runs.
select is(
  northstar_private.prune_expired_workout_receipts(), 2::bigint,
  'purge removes every expired receipt across accounts'
);
select is(
  (select count(*) from public.workout_sync_operations where expires_at <= now()),
  0::bigint, 'no expired receipts remain'
);
select is(
  (select operation_id from public.workout_sync_operations
    where user_id = '00000000-0000-4000-8000-0000000000a1'),
  '00000000-0000-4000-8000-000000000a02'::uuid, 'unexpired receipt is kept'
);
select is(
  (select count(*) from public.workout_records
    where user_id = '00000000-0000-4000-8000-0000000000a1'),
  1::bigint, 'workout records are never purged'
);
select is(
  northstar_private.prune_expired_workout_receipts(), 0::bigint,
  'a second run is a no-op'
);

select * from finish();
rollback;
