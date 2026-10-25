-- Reviewed P2-01 cleanup applied to development Supabase.
-- Hosted Supabase may create this helper; local/clean databases do not.
-- Guard without defining or depending on provider-owned functionality.
do $northstar_optional_rls_helper$
begin
  if pg_catalog.to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable()
      from public, anon, authenticated;
  end if;
end;
$northstar_optional_rls_helper$;
drop index if exists public.workout_records_owner_changes_idx;
create index if not exists workout_operations_expiry_idx on public.workout_sync_operations(expires_at);
CREATE OR REPLACE FUNCTION northstar_private.sync_workout_internal(p_operation_id uuid, p_workout_id uuid, p_expected_revision bigint, p_action text, p_payload jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_owner uuid := auth.uid();
 v_hash bytea;
 v_receipt public.workout_sync_operations%rowtype;
 v_existing public.workout_records%rowtype;
 v_stats jsonb;
 v_next bigint;
 v_cursor bigint;
 v_affected integer;
 v_status text;
 v_deleted timestamptz;
 v_working integer;
 v_loaded integer;
 v_volume bigint;
begin
 if v_owner is null
   or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
   raise exception 'verified account required' using errcode='28000';
 end if;
 if p_operation_id is null or p_workout_id is null
   or p_expected_revision is null or p_expected_revision < 0
   or p_action is null or p_action not in ('upsert','delete') then
   raise exception 'invalid sync arguments' using errcode='22023';
 end if;
 if p_action = 'upsert' then
   v_stats := northstar_private.validate_workout_v1(p_workout_id,p_payload);
   v_status := v_stats->>'status';
   v_working := (v_stats->>'working')::integer;
   v_loaded := (v_stats->>'loaded')::integer;
   v_volume := (v_stats->>'volume')::bigint;
   v_deleted := null;
 else
   if p_payload is not null then
     raise exception 'delete payload must be null' using errcode='22023';
   end if;
   v_deleted := now();
 end if;
 v_hash := pg_catalog.sha256(pg_catalog.convert_to(
    pg_catalog.jsonb_build_array(p_workout_id,p_expected_revision,p_action,p_payload)::text,'UTF8'
 ));
 -- Lock only one account after validation; high-cost parsing never blocks others.
 perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_owner::text,913751)
 );
 -- Opportunistic owner-specific receipt pruning. Global expiry still needs
 -- external scheduled maintenance for accounts that stop synchronizing.
 delete from public.workout_sync_operations
   where user_id=v_owner and expires_at <= now();
 select * into v_receipt from public.workout_sync_operations
   where user_id=v_owner and operation_id=p_operation_id;
 if found then
   if v_receipt.request_sha256 <> v_hash then
     raise exception 'operation ID reused with different content' using errcode='22023';
   end if;
   return pg_catalog.jsonb_build_object(
     'result','applied','revision',v_receipt.applied_revision,
     'change_seq',v_receipt.applied_change_seq,'replay',true,'processing','processed'
   );
 end if;
 select * into v_existing from public.workout_records
    where user_id=v_owner and workout_id=p_workout_id for update;
 if not found then
   if p_expected_revision <> 0 or p_action='delete' then
     return pg_catalog.jsonb_build_object(
       'result','conflict','revision',0,'change_seq',null,
       'replay',false,'processing','not_applied'
     );
   end if;
   v_next := 1;
 else
   if v_existing.server_revision <> p_expected_revision then
     return pg_catalog.jsonb_build_object(
       'result','conflict','revision',v_existing.server_revision,
       'change_seq',v_existing.server_change_seq,
       'replay',false,'processing','not_applied'
     );
   end if;
   v_next := v_existing.server_revision + 1;
 end if;
 insert into northstar_private.workout_owner_cursors(user_id,last_change_seq)
   values(v_owner,1)
   on conflict(user_id) do update
     set last_change_seq=northstar_private.workout_owner_cursors.last_change_seq+1
   returning last_change_seq into v_cursor;

 if v_existing.workout_id is null then
   insert into public.workout_records(
      user_id,workout_id,server_revision,schema_version,status,payload,
      deleted_at,server_change_seq,completed_working_sets,
      loaded_working_sets,loaded_volume_gram_reps
   ) values (
      v_owner,p_workout_id,v_next,1,v_status,p_payload,
      null,v_cursor,v_working,v_loaded,v_volume
   );
 else
   update public.workout_records set
     server_revision=v_next,
     status=coalesce(v_status,status),
     payload=p_payload,
     deleted_at=v_deleted,
     server_change_seq=v_cursor,
     completed_working_sets=v_working,
     loaded_working_sets=v_loaded,
     loaded_volume_gram_reps=v_volume,
     processed_at=now(),updated_at=now()
   where user_id=v_owner and workout_id=p_workout_id
     and server_revision=p_expected_revision;
   get diagnostics v_affected = row_count;
   if v_affected <> 1 then
     raise exception 'concurrent revision changed during update' using errcode='40001';
   end if;
 end if;

 insert into public.workout_sync_operations(
   user_id,operation_id,workout_id,expected_revision,action,request_sha256,
   applied_revision,applied_change_seq
 ) values(v_owner,p_operation_id,p_workout_id,p_expected_revision,p_action,v_hash,
          v_next,v_cursor);
 return pg_catalog.jsonb_build_object(
    'result','applied','revision',v_next,'change_seq',v_cursor,
    'replay',false,'processing','processed'
 );
end;
$function$
;
