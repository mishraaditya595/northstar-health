-- P2-06 slice 1: owner-scoped, cursor-paginated current-state restore.
-- A database rollback can reuse sequence numbers. Numeric cursor checks alone
-- cannot detect it once new writes overtake a client's stale cursor.
--
-- The epoch is deliberately persisted in the database and must be ROTATED
-- by a privileged operator IMMEDIATELY AFTER EVERY RESTORE, BEFORE reopening
-- app traffic. A database-only function cannot automatically identify whether
-- it has been restored from a backup of itself. See the restore runbook.
create table northstar_private.workout_restore_epoch (
  singleton boolean primary key default true check (singleton),
  epoch uuid not null default pg_catalog.gen_random_uuid(),
  rotated_at timestamptz not null default pg_catalog.now()
);
insert into northstar_private.workout_restore_epoch (singleton) values (true);
alter table northstar_private.workout_restore_epoch enable row level security;
revoke all on northstar_private.workout_restore_epoch from public, anon, authenticated;

-- Deliberately not executable by mobile roles. During a restore, the
-- operator must keep application access disabled, finish restoring data,
-- rotate this epoch in a committed transaction, then resume traffic.
create function northstar_private.rotate_workout_restore_epoch()
returns uuid
language plpgsql security invoker set search_path = ''
as $rotate$
declare
  v_epoch uuid;
begin
  update northstar_private.workout_restore_epoch
     set epoch = pg_catalog.gen_random_uuid(), rotated_at = pg_catalog.now()
   where singleton = true
   returning epoch into v_epoch;
  if v_epoch is null then
    raise exception 'restore epoch row missing' using errcode = '55000';
  end if;
  return v_epoch;
end;
$rotate$;
revoke all on function northstar_private.rotate_workout_restore_epoch()
  from public, anon, authenticated;

-- Only this audited definer may read the private owner counter and global
-- epoch. Both are read in ONE statement snapshot. No caller-supplied owner,
-- and clients get no SELECT on either private table.
create function northstar_private.current_workout_restore_state()
returns jsonb
language plpgsql security definer set search_path = ''
as $state$
declare
  v_owner uuid := auth.uid();
  v_epoch uuid;
  v_last bigint;
begin
  if v_owner is null
     or (auth.jwt()->>'is_anonymous') is distinct from 'false' then
    raise exception 'verified account required' using errcode = '28000';
  end if;
  select e.epoch, coalesce(c.last_change_seq, 0)
    into v_epoch, v_last
    from northstar_private.workout_restore_epoch e
    left join northstar_private.workout_owner_cursors c on c.user_id = v_owner
   where e.singleton = true;
  if v_epoch is null then
    raise exception 'restore epoch unavailable' using errcode = '55000';
  end if;
  return pg_catalog.jsonb_build_object(
    'cursor_epoch', v_epoch,
    'last_change_seq', v_last
  );
end;
$state$;
revoke all on function northstar_private.current_workout_restore_state()
  from public, anon, authenticated;
grant execute on function northstar_private.current_workout_restore_state()
  to authenticated;

-- p_cursor_epoch is optional ONLY for the first request at cursor zero.
-- All subsequent client requests must echo cursor_epoch from the prior page.
-- Old/unknown epochs always return a reset response, even when new writes
-- have already pushed the server cursor above the stale client cursor.
create function public.get_workout_changes(
  p_after_seq bigint default 0,
  p_limit integer default 100,
  p_cursor_epoch uuid default null
) returns jsonb
language plpgsql security invoker set search_path = ''
as $changes$
declare
  v_owner uuid := auth.uid();
  v_state jsonb;
  v_epoch uuid;
  v_server_cursor bigint;
  v_changes jsonb;
  v_next bigint;
  v_more boolean;
begin
  if v_owner is null
     or (auth.jwt()->>'is_anonymous') is distinct from 'false' then
    raise exception 'verified account required' using errcode = '28000';
  end if;
  if p_after_seq is null or p_after_seq < 0
     or p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'invalid change feed arguments' using errcode = '22023';
  end if;

  v_state := northstar_private.current_workout_restore_state();
  v_epoch := (v_state->>'cursor_epoch')::uuid;
  v_server_cursor := (v_state->>'last_change_seq')::bigint;

  -- A new device can bootstrap with (0, NULL). A previously synced device
  -- MUST provide its epoch; no-epoch nonzero cursors cannot be trusted.
  if (p_cursor_epoch is null and p_after_seq <> 0)
     or (p_cursor_epoch is not null and p_cursor_epoch <> v_epoch)
     or p_after_seq > v_server_cursor then
    return pg_catalog.jsonb_build_object(
      'schema_version', 1,
      'cursor_epoch', v_epoch,
      'cursor_reset', true,
      'next_cursor', 0,
      'has_more', false,
      'changes', '[]'::jsonb
    );
  end if;

  -- Return each workout's CURRENT state, not a history of older revisions.
  -- Account-scoped sequence numbers are allocated under a per-owner
  -- transaction lock, making cursor order safe across concurrent writers.
  with fetched as materialized (
    select r.workout_id, r.server_revision, r.server_change_seq,
           r.deleted_at, r.payload
      from public.workout_records r
     where r.user_id = v_owner and r.server_change_seq > p_after_seq
     order by r.server_change_seq asc
     limit p_limit + 1
  ), page as (
    select * from fetched order by server_change_seq asc limit p_limit
  )
  select coalesce(
           pg_catalog.jsonb_agg(
             pg_catalog.jsonb_build_object(
               'workout_id', workout_id,
               'server_revision', server_revision,
               'change_seq', server_change_seq,
               'deleted', deleted_at is not null,
               'payload', case when deleted_at is not null
                              then null else payload end
             ) order by server_change_seq
           ), '[]'::jsonb),
         coalesce(pg_catalog.max(server_change_seq), p_after_seq),
         (select pg_catalog.count(*) > p_limit from fetched)
    into v_changes, v_next, v_more
    from page;

  return pg_catalog.jsonb_build_object(
    'schema_version', 1,
    'cursor_epoch', v_epoch,
    'cursor_reset', false,
    'next_cursor', v_next,
    'has_more', v_more,
    'changes', v_changes
  );
end;
$changes$;

revoke all on function public.get_workout_changes(bigint, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.get_workout_changes(bigint, integer, uuid)
  to authenticated;
comment on function public.get_workout_changes(bigint, integer, uuid) is
  'Owner-scoped completed workout changes with restore epoch check and payload-free tombstones';
comment on function northstar_private.rotate_workout_restore_epoch() is
  'Operator-only: rotate after every database restore before reopening traffic; epoch changes cause stale client cursors to reset';
comment on function northstar_private.current_workout_restore_state() is
  'Read only the authenticated current owner counter and database restore epoch without direct private-table grants';
