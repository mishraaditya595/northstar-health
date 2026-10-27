-- P2-07c: read-only authorization gate for the destructive server-only
-- delete-account Edge Function. A refreshed JWT is NOT fresh proof: require
-- a genuinely NEW Auth session created by email-code verification.
--
-- The function cannot delete anything. It exposes no user/session metadata.
-- auth.sessions is not exposed through PostgREST and must stay private.
create or replace function public.authorize_account_deletion()
returns boolean
language plpgsql
security definer
set search_path = ''
as $gate$
declare
  v_owner uuid := auth.uid();
  v_claims jsonb := auth.jwt();
  v_session_id uuid;
  v_created_at timestamptz;
begin
  if v_owner is null
     or v_claims->>'role' is distinct from 'authenticated'
     or coalesce((v_claims->>'is_anonymous')::boolean, true)
  then
    raise exception 'verified account required' using errcode = '28000';
  end if;

  if (v_claims->>'session_id') is null or
     (v_claims->>'session_id') !~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  then
    raise exception 'fresh session required' using errcode = '28000';
  end if;
  v_session_id := (v_claims->>'session_id')::uuid;

  -- The session ID is bound to the caller's JWT and the actual Auth user.
  -- A token refresh does not change auth.sessions.created_at. A signed-out
  -- or already-deleted session fails even if an old JWT has not expired.
  select s.created_at into v_created_at
    from auth.sessions as s
    join auth.users as u on u.id = s.user_id
    where s.id = v_session_id
      and s.user_id = v_owner
      and u.email_confirmed_at is not null;

  if v_created_at is null
     or v_created_at < now() - interval '5 minutes'
     or v_created_at > now() + interval '30 seconds'
  then
    raise exception 'recent email verification required' using errcode = '28000';
  end if;
  return true;
end;
$gate$;

revoke all on function public.authorize_account_deletion()
  from public, anon, authenticated;
grant execute on function public.authorize_account_deletion()
  to authenticated;
comment on function public.authorize_account_deletion() is
  'P2-07c: checks current Auth session created within five minutes. Read-only, no personal data returned. Server-only delete-account function performs privileged deletion.';
