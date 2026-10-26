-- P2-05: server-derived progress from validated completed phone workouts.
-- These are summary metadata columns only; no raw platform health measurements.
-- All writes continue through the existing P2-01 authenticated sync RPC.
-- Interpret legacy zone-less timestamps in UTC during any required cast.
-- This migration is run inside the normal Supabase migration transaction.
set local timezone = 'UTC';

alter table public.workout_records
  add column progress_completed_at timestamptz,
  add column progress_local_day date;

-- Derive the original recorded local calendar day from the already validated
-- workout completion time and UTC offset, not the viewer's device timezone.
create or replace function northstar_private.assign_workout_progress_day()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_completed timestamptz;
  v_offset integer;
begin
  new.progress_completed_at := null;
  new.progress_local_day := null;
  if new.deleted_at is not null
      or new.payload is null
      or new.status <> 'completed' then
    return new;
  end if;
  -- Called after the P2-01 validator on insert/update; never trust an
  -- arbitrary completion date or original offset supplied through a read RPC.
  v_completed := (new.payload->>'completed_at_utc')::timestamptz;
  v_offset := (new.payload->>'original_offset_minutes')::integer;
  new.progress_completed_at := v_completed;
  new.progress_local_day := (
    (v_completed at time zone 'UTC') +
    pg_catalog.make_interval(mins => v_offset)
  )::date;
  return new;
end;
$function$;

revoke all on function northstar_private.assign_workout_progress_day()
  from public, anon, authenticated;

create trigger workout_progress_day_before_write
before insert or update of payload, deleted_at, status
on public.workout_records
for each row execute function northstar_private.assign_workout_progress_day();

-- A pre-existing completed workout must be included immediately after
-- migration, without replaying its operation or changing its server revision.
-- DEPLOYMENT LOCK NOTE: This UPDATE rewrites matching rows and can hold row
-- locks / grow WAL on a populated database. The non-CONCURRENT CREATE INDEX
-- below can block table writes. Before production deployment assess row counts,
-- schedule a maintenance window, or split into audited batched backfill and
-- non-transactional CREATE INDEX CONCURRENTLY migrations. Do not pretend this
-- one-transaction migration is zero-downtime on a large table.
update public.workout_records
set progress_completed_at = (payload->>'completed_at_utc')::timestamptz,
    progress_local_day = (
      ((payload->>'completed_at_utc')::timestamptz at time zone 'UTC') +
      pg_catalog.make_interval(
        mins => (payload->>'original_offset_minutes')::integer
      )
    )::date
where deleted_at is null and payload is not null;

create index workout_progress_owner_day_idx
  on public.workout_records(user_id, progress_local_day, progress_completed_at)
  where deleted_at is null;

comment on column public.workout_records.progress_local_day is
  'Completed date with original workout UTC offset; derived from validated payload.';
comment on column public.workout_records.progress_completed_at is
  'Validated completed workout timestamp for server-owned aggregation.';

-- Read-only user-facing API. SECURITY INVOKER + the existing RLS SELECT
-- policy + explicit owner filter: no cross-account metrics are exposed.
-- Limit the date range and recent-workout page to bound response size.
create or replace function public.get_workout_progress(
  p_start_day date,
  p_end_day date,
  p_recent_limit integer default 100
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_owner uuid := auth.uid();
  v_result jsonb;
begin
  if v_owner is null or
    coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then
    raise exception 'verified account required' using errcode = '28000';
  end if;
  -- Reject infinity/null *before* subtracting, to avoid 22008 and integer
  -- overflow from adding intervals near PostgreSQL's maximum DATE.
  if p_start_day is null or p_end_day is null
      or not pg_catalog.isfinite(p_start_day)
      or not pg_catalog.isfinite(p_end_day) then
    raise exception 'invalid progress range or limit' using errcode = '22023';
  end if;
  if p_end_day < p_start_day
      or p_end_day - p_start_day > 365
      or p_recent_limit is null or p_recent_limit not between 1 and 200 then
    raise exception 'invalid progress range or limit' using errcode = '22023';
  end if;

  with selected as materialized (
    select r.workout_id,
           r.progress_local_day as local_day,
           r.progress_completed_at as completed_at,
           r.server_revision,
           r.completed_working_sets,
           r.loaded_working_sets,
           r.loaded_volume_gram_reps
      from public.workout_records r
     where r.user_id = v_owner
       and r.deleted_at is null
       and r.progress_local_day between p_start_day and p_end_day
  ),
  totals as (
    select count(*)::bigint as workouts,
           case when count(*) filter (where completed_working_sets is null) > 0
                then null else coalesce(sum(completed_working_sets),0) end
             as completed_working_sets,
           case when count(*) filter (where loaded_working_sets is null) > 0
                then null else coalesce(sum(loaded_working_sets),0) end
             as loaded_working_sets,
           case when count(*) filter (where completed_working_sets is null
                                     or loaded_working_sets is null
                                     or (loaded_working_sets > 0 and
                                         loaded_volume_gram_reps is null)) > 0
                     or coalesce(sum(loaded_working_sets),0) = 0
                then null else sum(loaded_volume_gram_reps) end
             as loaded_volume_gram_reps
      from selected
  ),
  per_day as (
    select local_day,
           count(*)::bigint as workouts,
           case when count(*) filter (where completed_working_sets is null) > 0
                then null else coalesce(sum(completed_working_sets),0) end
             as completed_working_sets,
           case when count(*) filter (where loaded_working_sets is null) > 0
                then null else coalesce(sum(loaded_working_sets),0) end
             as loaded_working_sets,
           case when count(*) filter (where completed_working_sets is null
                                     or loaded_working_sets is null
                                     or (loaded_working_sets > 0 and
                                         loaded_volume_gram_reps is null)) > 0
                     or coalesce(sum(loaded_working_sets),0) = 0
                then null else sum(loaded_volume_gram_reps) end
             as loaded_volume_gram_reps
      from selected group by local_day
  )
  select pg_catalog.jsonb_build_object(
    'schema_version', 1,
    'start_day', p_start_day,
    'end_day', p_end_day,
    'totals', (select pg_catalog.to_jsonb(t) from totals t),
    'days', (select coalesce(
       pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) order by d.local_day),
       '[]'::jsonb
     ) from per_day d),
    'recent_workouts', (select coalesce(
       pg_catalog.jsonb_agg(
         pg_catalog.jsonb_build_object(
           'workout_id', w.workout_id,
           'local_day', w.local_day,
           'completed_at',
             pg_catalog.to_char(
               w.completed_at at time zone 'UTC',
               'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
             ),
           'server_revision', w.server_revision,
           'completed_working_sets', w.completed_working_sets,
           'loaded_working_sets', w.loaded_working_sets,
           'loaded_volume_gram_reps', w.loaded_volume_gram_reps
         ) order by w.local_day desc, w.completed_at desc, w.workout_id),
       '[]'::jsonb
     ) from (
       select workout_id, local_day, completed_at, server_revision,
              completed_working_sets, loaded_working_sets,
              loaded_volume_gram_reps
         from selected
        order by local_day desc, completed_at desc, workout_id
        limit p_recent_limit
     ) w),
    'recent_truncated', (select workouts > p_recent_limit from totals)
  ) into v_result;
  return v_result;
end;
$function$;

revoke all on function public.get_workout_progress(date,date,integer)
  from public, anon, authenticated;
grant execute on function public.get_workout_progress(date,date,integer)
  to authenticated;
comment on function public.get_workout_progress(date,date,integer) is
  'RLS-protected completed phone workout progress; null volume means no loaded sets or incomplete stats.';
