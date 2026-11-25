-- Training catalogue backbone (issue #63, stage 1, ADR-0010).
-- Shared, non-personal reference content published as immutable releases.
-- Clients read the live release through two RPCs only; tables, the live
-- pointer and the publish/rollback functions are not reachable by clients.

create table public.catalog_releases (
  release integer primary key check (release > 0),
  schema_version integer not null,
  min_app_schema integer not null,
  content jsonb not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes integer not null check (size_bytes > 0),
  published_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.catalog_live (
  singleton boolean primary key default true check (singleton),
  release integer not null references public.catalog_releases (release),
  updated_at timestamptz not null default now()
);

alter table public.catalog_releases enable row level security;
alter table public.catalog_live enable row level security;
revoke all on public.catalog_releases from public, anon, authenticated;
revoke all on public.catalog_live from public, anon, authenticated;

-- A published release never changes and is never deleted; withdraw it by
-- moving the live pointer to an earlier release instead.
create function northstar_private.reject_catalog_release_change()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'catalog releases are immutable';
end;
$function$;

revoke all on function northstar_private.reject_catalog_release_change()
  from public, anon, authenticated;

create trigger catalog_releases_immutable
before update or delete on public.catalog_releases
for each row execute function northstar_private.reject_catalog_release_change();

create trigger catalog_releases_no_truncate
before truncate on public.catalog_releases
for each statement execute function northstar_private.reject_catalog_release_change();

-- Publish a release and make it live, in the caller's transaction.
create function northstar_private.publish_catalog_release(
  p_release integer,
  p_schema_version integer,
  p_min_app_schema integer,
  p_content jsonb,
  p_sha256 text,
  p_size_bytes integer,
  p_published_at timestamptz
) returns void
language plpgsql
set search_path = ''
as $function$
begin
  if exists (
    select 1 from public.catalog_releases r where r.release >= p_release
  ) then
    raise exception 'catalog release must exceed existing releases';
  end if;
  if p_content->>'release' is distinct from p_release::text
      or p_content->>'schemaVersion' is distinct from p_schema_version::text
      or p_content->>'minAppCatalogSchema' is distinct from p_min_app_schema::text
      or (p_content->>'publishedAt')::timestamptz
         is distinct from p_published_at then
    raise exception 'catalog content does not match release';
  end if;
  insert into public.catalog_releases
    (release, schema_version, min_app_schema, content, sha256, size_bytes, published_at)
  values
    (p_release, p_schema_version, p_min_app_schema, p_content, p_sha256,
     p_size_bytes, p_published_at);
  insert into public.catalog_live (singleton, release)
  values (true, p_release)
  on conflict (singleton)
  do update set release = excluded.release, updated_at = now();
end;
$function$;

-- Roll the live pointer to an already published release.
create function northstar_private.set_live_catalog_release(p_release integer)
returns void
language plpgsql
set search_path = ''
as $function$
begin
  if not exists (
    select 1 from public.catalog_releases r where r.release = p_release
  ) then
    raise exception 'catalog release does not exist';
  end if;
  insert into public.catalog_live (singleton, release)
  values (true, p_release)
  on conflict (singleton)
  do update set release = excluded.release, updated_at = now();
end;
$function$;

revoke all on function northstar_private.publish_catalog_release(
  integer, integer, integer, jsonb, text, integer, timestamptz
) from public, anon, authenticated;
revoke all on function northstar_private.set_live_catalog_release(integer)
  from public, anon, authenticated;

-- Same session rule as the other public RPCs: a verified, non-anonymous user.
create function public.catalog_manifest()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_manifest jsonb;
begin
  if auth.uid() is null
      or (auth.jwt()->>'is_anonymous') is distinct from 'false' then
    raise exception 'verified account required' using errcode = '28000';
  end if;
  select pg_catalog.jsonb_build_object(
    'release', r.release,
    'schemaVersion', r.schema_version,
    'minAppCatalogSchema', r.min_app_schema,
    -- The exact string inside the checksummed content, not a re-rendering.
    'publishedAt', r.content->'publishedAt',
    'sha256', r.sha256,
    'sizeBytes', r.size_bytes,
    'url', '/rest/v1/rpc/catalog_snapshot'
  ) into v_manifest
  from public.catalog_live l
  join public.catalog_releases r on r.release = l.release;
  return v_manifest;
end;
$function$;

create function public.catalog_snapshot(p_release integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_content jsonb;
begin
  if auth.uid() is null
      or (auth.jwt()->>'is_anonymous') is distinct from 'false' then
    raise exception 'verified account required' using errcode = '28000';
  end if;
  select r.content into v_content
  from public.catalog_live l
  join public.catalog_releases r on r.release = l.release
  where l.release = p_release;
  if v_content is null then
    raise exception 'catalog release not live' using errcode = 'P0002';
  end if;
  return v_content;
end;
$function$;

revoke all on function public.catalog_manifest() from public, anon, authenticated;
revoke all on function public.catalog_snapshot(integer) from public, anon, authenticated;
grant execute on function public.catalog_manifest() to authenticated;
grant execute on function public.catalog_snapshot(integer) to authenticated;
