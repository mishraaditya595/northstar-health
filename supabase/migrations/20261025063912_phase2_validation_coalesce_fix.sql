-- Follow-up to the applied phase2_workout_sync_hardening migration.
-- Fix invalid pg_catalog qualification of SQL COALESCE special form.
CREATE OR REPLACE FUNCTION northstar_private.validate_workout_v1(p_workout_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 v_e jsonb;
 v_s jsonb;
 v_key text;
 v_start timestamptz;
 v_finish timestamptz;
 v_at timestamptz;
 v_working integer := null;
 v_loaded integer := null;
 v_volume bigint := null;
 v_status text;
 v_allowed_workout text[] := array[
  'schema_version','workout_id','origin','status','name','started_at_utc',
  'completed_at_utc','original_offset_minutes','exercises'
 ];
 v_allowed_exercise text[] := array['id','name','position','muscle','equipment','sets'];
 v_allowed_set text[] := array[
  'id','position','kind','status','reps','load_grams','input_unit','rpe','completed_at_utc'
 ];
 v_required_workout text[] := array[
  'schema_version','workout_id','origin','status','name','started_at_utc',
  'original_offset_minutes','exercises'
 ];
 v_required_exercise text[] := array['id','name','position','sets'];
 v_required_set text[] := array['id','position','kind','status','input_unit'];
begin
 if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or pg_catalog.octet_length(p_payload::text) > 65536 then
   raise exception 'invalid workout object or size' using errcode = '22023';
 end if;
 if not (p_payload ?& v_required_workout)
   or exists(select 1 from pg_catalog.jsonb_object_keys(p_payload) as k
     where k <> all(v_allowed_workout))
 then
   raise exception 'missing or unsupported workout fields' using errcode = '22023';
 end if;
 if pg_catalog.jsonb_typeof(p_payload->'schema_version') <> 'number'
    or p_payload->'schema_version' <> '1'::jsonb
    or pg_catalog.jsonb_typeof(p_payload->'workout_id') <> 'string'
    or p_payload->>'workout_id' is distinct from p_workout_id::text
    or pg_catalog.jsonb_typeof(p_payload->'origin') <> 'string'
    or p_payload->>'origin' is distinct from 'northstar_phone'
    or pg_catalog.jsonb_typeof(p_payload->'status') <> 'string'
    or p_payload->>'status' not in ('inProgress','paused','completed','discarded')
    or pg_catalog.jsonb_typeof(p_payload->'name') <> 'string'
    or pg_catalog.length(p_payload->>'name') not between 1 and 160
    or pg_catalog.jsonb_typeof(p_payload->'started_at_utc') <> 'string'
    or pg_catalog.jsonb_typeof(p_payload->'original_offset_minutes') <> 'number'
    or pg_catalog.length(p_payload->>'original_offset_minutes') > 5
    or (p_payload->>'original_offset_minutes') !~ '^-?[0-9]+$'
    or (p_payload->>'original_offset_minutes')::integer not between -840 and 840
    or pg_catalog.jsonb_typeof(p_payload->'exercises') <> 'array'
    or pg_catalog.jsonb_array_length(p_payload->'exercises') > 120
 then
   raise exception 'invalid workout values' using errcode = '22023';
 end if;
 if (p_payload->>'started_at_utc') !~
  '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$'
 then
   raise exception 'invalid start timestamp format' using errcode = '22023';
 end if;
 v_start := (p_payload->>'started_at_utc')::timestamptz;
 v_status := p_payload->>'status';
 if v_status = 'completed' then
   if not (p_payload ? 'completed_at_utc')
      or pg_catalog.jsonb_typeof(p_payload->'completed_at_utc') <> 'string'
   then
     raise exception 'completed workout requires completion time' using errcode = '22023';
   end if;
   v_working := 0; v_loaded := 0;
 end if;
 if p_payload ? 'completed_at_utc' then
   if pg_catalog.jsonb_typeof(p_payload->'completed_at_utc') not in ('null','string') then
      raise exception 'invalid completion time type' using errcode='22023';
   end if;
   if pg_catalog.jsonb_typeof(p_payload->'completed_at_utc') = 'string' then
     if (p_payload->>'completed_at_utc') !~
       '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$'
     then
       raise exception 'invalid completion timestamp format' using errcode='22023';
     end if;
     v_finish := (p_payload->>'completed_at_utc')::timestamptz;
     if v_finish < v_start then
       raise exception 'completion before start' using errcode='22023';
     end if;
   end if;
 end if;
 for v_e in select value from pg_catalog.jsonb_array_elements(p_payload->'exercises') loop
   if pg_catalog.jsonb_typeof(v_e) <> 'object'
      or not(v_e ?& v_required_exercise)
      or exists(select 1 from pg_catalog.jsonb_object_keys(v_e) as k
        where k <> all(v_allowed_exercise)) then
     raise exception 'missing or unsupported exercise fields' using errcode='22023';
   end if;
   if pg_catalog.jsonb_typeof(v_e->'id') <> 'string'
      or pg_catalog.jsonb_typeof(v_e->'name') <> 'string'
      or pg_catalog.length(v_e->>'name') not between 1 and 160
      or pg_catalog.jsonb_typeof(v_e->'position') <> 'number'
      or pg_catalog.length(v_e->>'position') > 5
      or (v_e->>'position') !~ '^[0-9]+$'
      or (v_e->>'position')::integer > 10000
      or pg_catalog.jsonb_typeof(v_e->'sets') <> 'array'
      or pg_catalog.jsonb_array_length(v_e->'sets') > 300
   then
     raise exception 'invalid exercise values' using errcode='22023';
   end if;
   perform (v_e->>'id')::uuid;
   if (v_e ? 'muscle' and
        (pg_catalog.jsonb_typeof(v_e->'muscle') <> 'string'
        or pg_catalog.length(v_e->>'muscle') > 160))
      or (v_e ? 'equipment' and
        (pg_catalog.jsonb_typeof(v_e->'equipment') <> 'string'
        or pg_catalog.length(v_e->>'equipment') > 160))
   then
      raise exception 'invalid exercise metadata' using errcode='22023';
   end if;

   for v_s in select value from pg_catalog.jsonb_array_elements(v_e->'sets') loop
     if pg_catalog.jsonb_typeof(v_s) <> 'object'
        or not(v_s ?& v_required_set)
        or exists(select 1 from pg_catalog.jsonb_object_keys(v_s) as k
          where k <> all(v_allowed_set))
     then
       raise exception 'missing or unsupported set fields' using errcode='22023';
     end if;
     if pg_catalog.jsonb_typeof(v_s->'id') <> 'string'
       or pg_catalog.jsonb_typeof(v_s->'position') <> 'number'
       or pg_catalog.length(v_s->>'position') > 5
       or (v_s->>'position') !~ '^[0-9]+$'
       or (v_s->>'position')::integer > 10000
       or pg_catalog.jsonb_typeof(v_s->'kind') <> 'string'
       or v_s->>'kind' not in ('working','warmup')
       or pg_catalog.jsonb_typeof(v_s->'status') <> 'string'
       or v_s->>'status' not in ('planned','completed','skipped')
       or pg_catalog.jsonb_typeof(v_s->'input_unit') <> 'string'
       or v_s->>'input_unit' not in ('kg','lb')
     then
       raise exception 'invalid set values' using errcode='22023';
     end if;
     perform (v_s->>'id')::uuid;
     if v_s ? 'reps' and pg_catalog.jsonb_typeof(v_s->'reps') <> 'null' then
       if pg_catalog.jsonb_typeof(v_s->'reps') <> 'number'
         or pg_catalog.length(v_s->>'reps') > 5
         or (v_s->>'reps') !~ '^[0-9]+$'
         or (v_s->>'reps')::integer > 10000 then
         raise exception 'invalid repetitions' using errcode='22023';
       end if;
     end if;
     if v_s ? 'load_grams' and pg_catalog.jsonb_typeof(v_s->'load_grams') <> 'null' then
       if pg_catalog.jsonb_typeof(v_s->'load_grams') <> 'number'
         or pg_catalog.length(v_s->>'load_grams') > 9
         or (v_s->>'load_grams') !~ '^[0-9]+$'
         or (v_s->>'load_grams')::bigint > 100000000 then
         raise exception 'invalid load grams' using errcode='22023';
       end if;
     end if;
     if v_s ? 'rpe' and pg_catalog.jsonb_typeof(v_s->'rpe') <> 'null' then
       if pg_catalog.jsonb_typeof(v_s->'rpe') <> 'number'
         or pg_catalog.length(v_s->>'rpe') > 5
         or (v_s->>'rpe') !~ '^(0|[1-9]|10)(\.0|\.5)?$' then
         raise exception 'invalid RPE' using errcode='22023';
       end if;
     end if;
     if v_s->>'status' = 'completed' then
       if not (v_s ?& array['reps','completed_at_utc'])
          or pg_catalog.jsonb_typeof(v_s->'reps') <> 'number'
          or pg_catalog.jsonb_typeof(v_s->'completed_at_utc') <> 'string'
       then
         raise exception 'completed set needs reps and time' using errcode='22023';
       end if;
     end if;
     if v_s ? 'completed_at_utc' and pg_catalog.jsonb_typeof(v_s->'completed_at_utc') <> 'null' then
       if pg_catalog.jsonb_typeof(v_s->'completed_at_utc') <> 'string'
          or (v_s->>'completed_at_utc') !~
           '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
         raise exception 'invalid set timestamp format' using errcode='22023';
       end if;
       v_at := (v_s->>'completed_at_utc')::timestamptz;
       if v_at < v_start then
         raise exception 'set before workout started' using errcode='22023';
       end if;
     end if;
     if v_working is not null and v_s->>'kind' = 'working'
        and v_s->>'status' = 'completed' then
       v_working := v_working + 1;
       if pg_catalog.jsonb_typeof(v_s->'load_grams') = 'number'
          and (v_s->>'load_grams')::bigint > 0 then
         v_loaded := v_loaded + 1;
         v_volume := coalesce(v_volume,0)
                       + (v_s->>'load_grams')::bigint * (v_s->>'reps')::bigint;
       end if;
     end if;
   end loop;
 end loop;
 if (select pg_catalog.count(*) <> pg_catalog.count(distinct e->>'id')
     from pg_catalog.jsonb_array_elements(p_payload->'exercises') as e) then
    raise exception 'duplicate exercise ID' using errcode='22023';
 end if;
 if (select pg_catalog.count(*) <> pg_catalog.count(distinct s->>'id')
     from pg_catalog.jsonb_array_elements(p_payload->'exercises') as e
     cross join lateral pg_catalog.jsonb_array_elements(e->'sets') as s) then
    raise exception 'duplicate set ID' using errcode='22023';
 end if;
 return pg_catalog.jsonb_build_object(
   'status',v_status,'working',v_working,'loaded',v_loaded,'volume',v_volume
 );
exception
 when invalid_text_representation or numeric_value_out_of_range
      or invalid_datetime_format or datetime_field_overflow
 then
   raise exception 'invalid numeric, UUID or timestamp value' using errcode='22023';
end;
$function$
;
