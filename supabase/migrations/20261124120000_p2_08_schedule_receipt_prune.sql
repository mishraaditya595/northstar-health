-- P2-08: schedule the daily full purge of expired hash-only sync receipts.
-- No secrets. Each authenticated sync already prunes its own owner's expired
-- receipts; this job covers inactive accounts so the documented 90-day
-- retention holds for everyone. Workout records and tombstones are untouched.
--
-- pg_cron is available on every Supabase plan and in the local CLI stack.
-- The job runs as the migration role (postgres), which owns the receipts table
-- and is the only role with EXECUTE on the prune function.
create extension if not exists pg_cron with schema pg_catalog;

-- Clients never see or manage scheduled jobs.
revoke all on schema cron from public, anon, authenticated;

-- cron.schedule upserts by job name, so a replay keeps a single job.
select cron.schedule(
  'northstar-prune-expired-workout-receipts',
  '17 3 * * *',
  $$select northstar_private.prune_expired_workout_receipts()$$
);
