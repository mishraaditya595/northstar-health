-- NorthStar Health Phase 2 P2-01 - authenticated workout sync. No secrets.
create sequence public.workout_change_seq as bigint;
create table public.workout_records (
 user_id uuid not null references auth.users(id) on delete cascade,
 workout_id uuid not null, server_revision bigint not null check(server_revision>0),
 schema_version integer not null check(schema_version=1),
 status text not null check(status in ('inProgress','paused','completed','discarded')),
 payload jsonb, deleted_at timestamptz, server_change_seq bigint not null unique,
 completed_working_sets integer, loaded_working_sets integer, loaded_volume_gram_reps bigint,
 processed_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 primary key(user_id,workout_id),
 constraint deleted_has_no_payload check(deleted_at is null or payload is null),
 constraint deleted_has_no_stats check(deleted_at is null or (completed_working_sets is null and loaded_working_sets is null and loaded_volume_gram_reps is null))
);
create index workout_records_owner_changes_idx on public.workout_records(user_id,server_change_seq);
create table public.workout_sync_operations (
 user_id uuid not null references auth.users(id) on delete cascade,
 operation_id uuid not null, workout_id uuid not null,
 expected_revision bigint not null, action text not null check(action in ('upsert','delete')),
 request_payload jsonb, applied_revision bigint not null, applied_change_seq bigint not null,
 committed_at timestamptz not null default now(),
 primary key(user_id,operation_id)
);
create index workout_operations_owner_workout_idx on public.workout_sync_operations(user_id,workout_id);
alter table public.workout_records enable row level security;
alter table public.workout_sync_operations enable row level security;
revoke all on public.workout_records from public,anon,authenticated;
revoke all on public.workout_sync_operations from public,anon,authenticated;
revoke all on sequence public.workout_change_seq from public,anon,authenticated;
grant select on public.workout_records to authenticated;
create policy workout_records_read_own on public.workout_records for select to authenticated
 using(user_id=(select auth.uid()) and coalesce((select auth.jwt()->>'is_anonymous')::boolean,false)=false);

CREATE OR REPLACE FUNCTION public.sync_workout(p_operation_id uuid, p_workout_id uuid, p_expected_revision bigint, p_action text, p_payload jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := auth.uid();
  v_old public.workout_records%rowtype;
  v_receipt public.workout_sync_operations%rowtype;
  v_revision bigint;
  v_change bigint;
  v_status text;
  v_deleted timestamptz;
  v_working integer;
  v_loaded integer;
  v_volume bigint;
  v_exercise jsonb;
  v_set jsonb;
  v_key text;
  v_exercise_ids text[] := array[]::text[];
  v_set_ids text[] := array[]::text[];
begin
  if v_user is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
  then
    raise exception 'verified account required' using errcode = '28000';
  end if;
  if p_operation_id is null or p_workout_id is null or p_expected_revision is null
    or p_expected_revision < 0 or p_action is null or p_action not in ('upsert', 'delete')
  then
    raise exception 'invalid sync command' using errcode = '22023';
  end if;
  if (p_action = 'delete' and p_payload is not null)
    or (p_action = 'upsert' and (p_payload is null or jsonb_typeof(p_payload) <> 'object'))
  then
    raise exception 'invalid payload for action' using errcode = '22023';
  end if;
  if p_payload is not null and pg_catalog.octet_length(p_payload::text) > 65536 then
    raise exception 'workout payload exceeds 64 KiB' using errcode = '22023';
  end if;

  -- Serializes change sequence allocation through commit, so paginated
  -- cursors cannot skip an earlier transaction that commits later.
  perform pg_catalog.pg_advisory_xact_lock(913751, 2);

  select * into v_receipt
    from public.workout_sync_operations
   where user_id = v_user and operation_id = p_operation_id;
  if found then
    if v_receipt.workout_id <> p_workout_id
      or v_receipt.expected_revision <> p_expected_revision
      or v_receipt.action <> p_action
      or v_receipt.request_payload is distinct from p_payload
    then
      raise exception 'operation ID reused with different contents' using errcode = '22023';
    end if;
    return pg_catalog.jsonb_build_object(
      'result', 'applied',
      'revision', v_receipt.applied_revision,
      'change_seq', v_receipt.applied_change_seq,
      'replay', true
    );
  end if;

  select * into v_old from public.workout_records
    where user_id = v_user and workout_id = p_workout_id for update;
  if found then
    if v_old.server_revision <> p_expected_revision then
      return pg_catalog.jsonb_build_object(
        'result','conflict',
        'server_revision',v_old.server_revision,
        'change_seq',v_old.server_change_seq
      );
    end if;
    v_revision := v_old.server_revision + 1;
  else
    if p_expected_revision <> 0 or p_action = 'delete' then
      return pg_catalog.jsonb_build_object('result','conflict','server_revision',0);
    end if;
    v_revision := 1;
  end if;

  if p_action = 'upsert' then
    -- Strict DTO allowlists prevent uploading health samples, arbitrary
    -- annotations, account/user identifiers, or platform-imported workouts.
    for v_key in select pg_catalog.jsonb_object_keys(p_payload) loop
      if v_key not in ('schema_version','workout_id','status','origin','name',
                       'started_at_utc','completed_at_utc','original_offset_minutes','exercises') then
        raise exception 'unsupported workout field' using errcode = '22023';
      end if;
    end loop;
    if p_payload->>'schema_version' <> '1'
      or p_payload->>'workout_id' <> p_workout_id::text
      or p_payload->>'origin' <> 'northstar_phone'
      or p_payload->>'status' not in ('inProgress','paused','completed','discarded')
      or pg_catalog.jsonb_typeof(p_payload->'name') <> 'string'
      or pg_catalog.length(p_payload->>'name') not between 1 and 160
      or pg_catalog.jsonb_typeof(p_payload->'started_at_utc') <> 'string'
      or (p_payload->>'started_at_utc') !~ '^\d{4}-\d\d-\d\dT'
      or pg_catalog.jsonb_typeof(p_payload->'original_offset_minutes') <> 'number'
      or (p_payload->>'original_offset_minutes') !~ '^-?\d+$'
      or (p_payload->>'original_offset_minutes')::integer not between -840 and 840
      or pg_catalog.jsonb_typeof(p_payload->'exercises') <> 'array'
      or pg_catalog.jsonb_array_length(p_payload->'exercises') > 120
    then
      raise exception 'invalid workout fields' using errcode = '22023';
    end if;
    v_status := p_payload->>'status';
    if v_status = 'completed' and
      (pg_catalog.jsonb_typeof(p_payload->'completed_at_utc') <> 'string'
        or (p_payload->>'completed_at_utc') !~ '^\d{4}-\d\d-\d\dT')
    then
      raise exception 'completed workout needs a completion timestamp' using errcode = '22023';
    end if;
    if p_payload->'completed_at_utc' is not null
      and pg_catalog.jsonb_typeof(p_payload->'completed_at_utc') not in ('string','null')
    then
      raise exception 'invalid completion timestamp' using errcode = '22023';
    end if;
    v_working := null; v_loaded := null; v_volume := null;
    if v_status = 'completed' then
      v_working := 0; v_loaded := 0;
    end if;

    for v_exercise in
      select value from pg_catalog.jsonb_array_elements(p_payload->'exercises')
    loop
      if pg_catalog.jsonb_typeof(v_exercise) <> 'object' then
        raise exception 'invalid exercise' using errcode = '22023';
      end if;
      for v_key in select pg_catalog.jsonb_object_keys(v_exercise) loop
        if v_key not in ('id','name','muscle','equipment','position','sets') then
          raise exception 'unsupported exercise field' using errcode = '22023';
        end if;
      end loop;
      if pg_catalog.jsonb_typeof(v_exercise->'id') <> 'string'
         or pg_catalog.jsonb_typeof(v_exercise->'name') <> 'string'
         or pg_catalog.length(v_exercise->>'name') not between 1 and 160
         or pg_catalog.jsonb_typeof(v_exercise->'sets') <> 'array'
         or pg_catalog.jsonb_array_length(v_exercise->'sets') > 300
         or (v_exercise->>'position') !~ '^\d+$'
         or (v_exercise->>'position')::integer > 10000
      then
        raise exception 'invalid exercise fields' using errcode = '22023';
      end if;
      perform (v_exercise->>'id')::uuid;
      if (v_exercise->>'id') = any (v_exercise_ids) then
        raise exception 'duplicate exercise ID' using errcode = '22023';
      end if;
      v_exercise_ids := pg_catalog.array_append(v_exercise_ids, v_exercise->>'id');

      for v_set in
        select value from pg_catalog.jsonb_array_elements(v_exercise->'sets')
      loop
        if pg_catalog.jsonb_typeof(v_set) <> 'object' then
          raise exception 'invalid set' using errcode = '22023';
        end if;
        for v_key in select pg_catalog.jsonb_object_keys(v_set) loop
          if v_key not in ('id','position','kind','status','reps','load_grams',
                           'input_unit','rpe','completed_at_utc') then
            raise exception 'unsupported set field' using errcode = '22023';
          end if;
        end loop;
        if pg_catalog.jsonb_typeof(v_set->'id') <> 'string'
          or (v_set->>'position') !~ '^\d+$'
          or (v_set->>'position')::integer > 10000
          or v_set->>'kind' not in ('working','warmup')
          or v_set->>'status' not in ('planned','completed','skipped')
          or v_set->>'input_unit' not in ('kg','lb')
        then
          raise exception 'invalid set fields' using errcode = '22023';
        end if;
        perform (v_set->>'id')::uuid;
        if (v_set->>'id') = any (v_set_ids) then
          raise exception 'duplicate set ID' using errcode = '22023';
        end if;
        v_set_ids := pg_catalog.array_append(v_set_ids,v_set->>'id');
        if v_set->'reps' is not null and pg_catalog.jsonb_typeof(v_set->'reps') <> 'null'
          and ((v_set->>'reps') !~ '^\d+$' or (v_set->>'reps')::bigint > 10000)
        then
          raise exception 'invalid reps' using errcode = '22023';
        end if;
        if v_set->'load_grams' is not null and pg_catalog.jsonb_typeof(v_set->'load_grams') <> 'null'
          and ((v_set->>'load_grams') !~ '^\d+$' or (v_set->>'load_grams')::bigint > 100000000)
        then
          raise exception 'invalid load' using errcode = '22023';
        end if;
        if v_set->'rpe' is not null and pg_catalog.jsonb_typeof(v_set->'rpe') <> 'null'
          and (pg_catalog.jsonb_typeof(v_set->'rpe') <> 'number'
               or (v_set->>'rpe')::numeric not between 0 and 10
               or mod((v_set->>'rpe')::numeric * 2,1) <> 0)
        then
          raise exception 'invalid rpe' using errcode = '22023';
        end if;
        if v_set->>'status' = 'completed' and
          ((v_set->'reps' is null or pg_catalog.jsonb_typeof(v_set->'reps') = 'null')
          or pg_catalog.jsonb_typeof(v_set->'completed_at_utc') <> 'string')
        then
          raise exception 'completed set requires reps and timestamp' using errcode = '22023';
        end if;
        if v_working is not null and v_set->>'kind' = 'working'
          and v_set->>'status' = 'completed' then
          v_working := v_working + 1;
          if pg_catalog.jsonb_typeof(v_set->'load_grams') = 'number'
            and (v_set->>'load_grams')::bigint > 0 then
            v_loaded := v_loaded + 1;
            v_volume := coalesce(v_volume,0)
              + ((v_set->>'load_grams')::bigint * (v_set->>'reps')::bigint);
          end if;
        end if;
      end loop;
    end loop;
    v_deleted := null;
  else
    v_status := coalesce(v_old.status,'discarded');
    v_deleted := now();
    v_working := null; v_loaded := null; v_volume := null;
  end if;

  v_change := pg_catalog.nextval('public.workout_change_seq'::regclass);
  insert into public.workout_records as w
    (user_id,workout_id,server_revision,schema_version,status,payload,deleted_at,
     server_change_seq,completed_working_sets,loaded_working_sets,loaded_volume_gram_reps)
  values
    (v_user,p_workout_id,v_revision,1,v_status,p_payload,v_deleted,
     v_change,v_working,v_loaded,v_volume)
  on conflict (user_id,workout_id) do update set
    server_revision = excluded.server_revision,
    status = excluded.status,
    payload = excluded.payload,
    deleted_at = excluded.deleted_at,
    server_change_seq = excluded.server_change_seq,
    completed_working_sets = excluded.completed_working_sets,
    loaded_working_sets = excluded.loaded_working_sets,
    loaded_volume_gram_reps = excluded.loaded_volume_gram_reps,
    processed_at = now(), updated_at = now();

  insert into public.workout_sync_operations
    (user_id,operation_id,workout_id,expected_revision,action,request_payload,
     applied_revision,applied_change_seq)
  values (v_user,p_operation_id,p_workout_id,p_expected_revision,p_action,p_payload,
          v_revision,v_change);
  return pg_catalog.jsonb_build_object(
    'result','applied','revision',v_revision,'change_seq',v_change,'replay',false,
    'processing','processed'
  );
end;
$function$
;
revoke all on function public.sync_workout(uuid,uuid,bigint,text,jsonb) from public,anon,authenticated;
grant execute on function public.sync_workout(uuid,uuid,bigint,text,jsonb) to authenticated;
