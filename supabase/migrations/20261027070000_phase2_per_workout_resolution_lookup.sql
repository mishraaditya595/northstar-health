-- P2-06: independently review one authoritative workout without rewinding a
-- shared restore cursor. This endpoint is READ ONLY and owner-scoped by RLS.
-- The restore epoch is returned for device-side reconciliation/CAS evidence.
create function public.get_workout_for_resolution(p_workout_id uuid)
returns jsonb language plpgsql security invoker set search_path = ''
as $lookup$
declare
  v_owner uuid := auth.uid();
  v_state jsonb;
  v_row public.workout_records%rowtype;
  v_change jsonb;
begin
  if v_owner is null or (auth.jwt()->>'is_anonymous') is distinct from 'false' then
    raise exception 'verified account required' using errcode = '28000';
  end if;
  if p_workout_id is null then
    raise exception 'workout ID required' using errcode = '22023';
  end if;
  -- Snapshot semantics: under PostgreSQL READ COMMITTED, the helper read
  -- below and the following SELECT of workout_records can observe separate
  -- statement snapshots. This is a read-only *review*, not an atomic epoch
  -- + row snapshot or a lock on the server revision. In particular, an epoch
  -- rotation or concurrent write between these reads must not be treated as
  -- a reserved CAS baseline. The client validates the epoch against its
  -- local cursor and uses revision compare-and-swap for every subsequent
  -- mutation; a conflict requires another fresh review. Do not advance the
  -- shared restore cursor based on this lookup alone.
  -- This private helper derives auth.uid(); the caller cannot supply owner.
  v_state := northstar_private.current_workout_restore_state();
  select * into v_row from public.workout_records
   where user_id = v_owner and workout_id = p_workout_id;
  if found then
    v_change := pg_catalog.jsonb_build_object(
      'workout_id', v_row.workout_id,
      'server_revision', v_row.server_revision,
      'change_seq', v_row.server_change_seq,
      'deleted', v_row.deleted_at is not null,
      'payload', case when v_row.deleted_at is not null
                      then null else v_row.payload end
    );
  end if;
  return pg_catalog.jsonb_build_object(
    'schema_version', 1,
    'cursor_epoch', v_state->>'cursor_epoch',
    'change', v_change
  );
end;
$lookup$;
revoke all on function public.get_workout_for_resolution(uuid)
  from public, anon, authenticated;
grant execute on function public.get_workout_for_resolution(uuid)
  to authenticated;
comment on function public.get_workout_for_resolution(uuid) is
  'Read current owner-scoped workout for explicit conflict review; never advances restore cursor';
