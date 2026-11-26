-- Training catalogue: synthetic, rolled-back pgTAP. The catalogue holds shared
-- reference content only; clients read it through two RPCs and never touch the
-- tables, the pointer or the publish functions.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(63);

-- Synthetic release helper: content mirrors a real snapshot's header fields.
create function pg_temp.pub(p_release integer, p_over jsonb default '{}',
  p_sha text default repeat('a', 64), p_min integer default 1,
  p_at timestamptz default '2026-11-26T00:00:00Z') returns void
language sql as $$
  select northstar_private.publish_catalog_release(
    p_release, 1, p_min,
    pg_catalog.jsonb_build_object('release', p_release, 'schemaVersion', 1,
      'minAppCatalogSchema', 1, 'publishedAt', '2026-11-26T00:00:00Z',
      'exercises', '[]'::jsonb, 'templates', '[]'::jsonb,
      'programs', '[]'::jsonb) || p_over,
    p_sha, 90, p_at)
$$;

-- Access surface.
select is(has_function_privilege('anon', 'public.catalog_manifest()', 'EXECUTE'),
  false, 'anonymous clients cannot read the catalogue manifest');
select is(has_function_privilege('anon', 'public.catalog_snapshot(integer)', 'EXECUTE'),
  false, 'anonymous clients cannot read a catalogue snapshot');
select is(has_function_privilege('authenticated', 'public.catalog_manifest()', 'EXECUTE'),
  true, 'signed-in clients can read the catalogue manifest');
select is(has_function_privilege('authenticated', 'public.catalog_snapshot(integer)', 'EXECUTE'),
  true, 'signed-in clients can read a catalogue snapshot');
select is(
  (select bool_or(has_table_privilege(r, 'public.catalog_releases', p))
     from unnest(array['anon','authenticated']) r,
          unnest(array['SELECT','INSERT','UPDATE','DELETE']) p),
  false, 'clients have no direct privileges on catalog_releases');
select is(
  (select bool_or(has_table_privilege(r, 'public.catalog_live', p))
     from unnest(array['anon','authenticated']) r,
          unnest(array['SELECT','INSERT','UPDATE','DELETE']) p),
  false, 'clients have no direct privileges on catalog_live');
select is(
  (select relrowsecurity from pg_class where oid = 'public.catalog_releases'::regclass),
  true, 'catalog_releases has row level security enabled');
select is(
  (select relrowsecurity from pg_class where oid = 'public.catalog_live'::regclass),
  true, 'catalog_live has row level security enabled');
select is(
  (select bool_or(has_function_privilege(r,
     'northstar_private.publish_catalog_release(integer,integer,integer,jsonb,text,integer,timestamptz)',
     'EXECUTE'))
     from unnest(array['anon','authenticated','public']) r),
  false, 'clients and PUBLIC cannot publish a catalogue release');
select is(
  (select bool_or(has_function_privilege(r,
     'northstar_private.set_live_catalog_release(integer)', 'EXECUTE'))
     from unnest(array['anon','authenticated','public']) r),
  false, 'clients and PUBLIC cannot move the live catalogue pointer');

-- Existing owner-scoped workout storage is unaffected.
select is(
  (select relrowsecurity from pg_class where oid = 'public.workout_records'::regclass),
  true, 'workout_records still has row level security enabled');
select is(has_table_privilege('authenticated', 'public.workout_records', 'SELECT'),
  true, 'signed-in clients still read their workout records');
select is(
  (select bool_or(has_table_privilege(r, 'public.workout_records', p))
     from (values ('anon','SELECT'), ('anon','INSERT'), ('authenticated','INSERT'),
                  ('authenticated','UPDATE'), ('authenticated','DELETE')) v(r, p)),
  false, 'workout_records grants are unchanged (no anon, no client writes)');

-- The migrations leave the newest release live; release 1 is the starter set.
select is((select release from public.catalog_live),
  (select max(release) from public.catalog_releases),
  'the live release is the newest published release');
select set_config('catalog.livesha', (select r.sha256 from public.catalog_releases r
  join public.catalog_live l using (release)), true);
set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated","is_anonymous":false}', true);
select is(public.catalog_manifest()->>'sha256', current_setting('catalog.livesha'),
  'the manifest checksum is the live release row checksum');
reset role;
select is((select sha256 from public.catalog_releases where release = 1),
  '97c93550a7ef47e61ef5395b612863c56ca246f906b54d146eac45f9e6b5f8eb',
  'release 1 checksum matches catalog/releases.lock.json');
select is((select jsonb_array_length(content->'exercises')
            from public.catalog_releases where release = 1), 18,
  'release 1 carries the 18 starter exercises');

select set_config('catalog.base',
  ((select max(release) from public.catalog_releases) + 1000)::text, true);

-- Publish two synthetic releases through the private function.
select lives_ok($$select pg_temp.pub(current_setting('catalog.base')::int,
  '{}', repeat('a', 64))$$, 'publishing the first synthetic release succeeds');
select lives_ok($$select pg_temp.pub(current_setting('catalog.base')::int + 1,
  '{"publishedAt": "2026-11-27T01:02:03Z"}', repeat('b', 64), 1,
  '2026-11-27T01:02:03Z')$$, 'publishing the second synthetic release succeeds');

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated","is_anonymous":false}', true);
select is((public.catalog_manifest()->>'release')::int,
  current_setting('catalog.base')::int + 1,
  'manifest points at the newest published release');
select is(public.catalog_manifest()->>'url', '/rest/v1/rpc/catalog_snapshot',
  'manifest url is the snapshot RPC path');
select is(public.catalog_manifest()->>'sha256', repeat('b', 64),
  'manifest carries the release checksum');
select is((public.catalog_manifest()->>'sizeBytes')::int, 90,
  'manifest carries the release size');
select is(public.catalog_manifest()->>'publishedAt', '2026-11-27T01:02:03Z',
  'manifest publishedAt is the exact string inside the signed content');
select is((public.catalog_snapshot(current_setting('catalog.base')::int + 1)->>'release')::int,
  current_setting('catalog.base')::int + 1,
  'the live release can be downloaded');
select throws_ok($$select public.catalog_snapshot(current_setting('catalog.base')::int)$$,
  'P0002', 'catalog release not live',
  'a release that is not live cannot be downloaded');
select throws_ok($$select public.catalog_snapshot(2147483000)$$, 'P0002',
  'catalog release not live', 'an unknown release cannot be downloaded');
select throws_ok($$select * from public.catalog_releases$$, '42501', null,
  'signed-in clients cannot read the release table');
select throws_ok($$select * from public.catalog_live$$, '42501', null,
  'signed-in clients cannot read the live pointer');
select throws_ok($$update public.catalog_live set release = 1$$, '42501', null,
  'signed-in clients cannot move the live pointer');
select throws_ok($$select northstar_private.set_live_catalog_release(1)$$, '42501', null,
  'signed-in clients cannot call the rollback function');

-- Anonymous sessions and missing JWTs are refused like the other public RPCs.
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000c2","role":"authenticated","is_anonymous":true}', true);
select throws_ok($$select public.catalog_manifest()$$, '28000', 'verified account required',
  'an anonymous-user session cannot read the manifest');
select throws_ok($$select public.catalog_snapshot(1)$$, '28000', 'verified account required',
  'an anonymous-user session cannot read a snapshot');
select set_config('request.jwt.claims', '', true);
select throws_ok($$select public.catalog_manifest()$$, '28000', 'verified account required',
  'a session without a JWT cannot read the manifest');
reset role;

-- Anonymous clients are rejected at the function boundary.
set local role anon;
select throws_ok($$select public.catalog_manifest()$$, '42501', null,
  'anonymous manifest call is rejected');
select throws_ok($$select public.catalog_snapshot(1)$$, '42501', null,
  'anonymous snapshot call is rejected');
reset role;

-- Publish rules.
select throws_ok($$select pg_temp.pub(current_setting('catalog.base')::int)$$, 'P0001',
  'catalog release must exceed existing releases', 'a release number cannot be reused');
select throws_ok($$select pg_temp.pub(current_setting('catalog.base')::int - 1)$$, 'P0001',
  'catalog release must exceed existing releases', 'an older release cannot be published');
select throws_ok($$select northstar_private.publish_catalog_release(
  current_setting('catalog.base')::int + 2, 1, 1,
  '{"release": 1, "schemaVersion": 1, "minAppCatalogSchema": 1, "publishedAt": "2026-11-26T00:00:00Z"}'::jsonb,
  repeat('a', 64), 90, '2026-11-26T00:00:00Z')$$, 'P0001',
  'catalog content does not match release', 'content release must match the number');
select throws_ok($$select pg_temp.pub(current_setting('catalog.base')::int + 2,
  '{"schemaVersion": 2}')$$, 'P0001',
  'catalog content does not match release', 'content schema version must match');
select throws_ok($$select pg_temp.pub(current_setting('catalog.base')::int + 2,
  '{"minAppCatalogSchema": 2}')$$, 'P0001',
  'catalog content does not match release', 'content minimum app schema must match');
select throws_ok($$select pg_temp.pub(current_setting('catalog.base')::int + 2,
  '{}', repeat('a', 64), 1, '2026-12-01T00:00:00Z')$$, 'P0001',
  'catalog content does not match release', 'content publish time must match');
select is((select release from public.catalog_live),
  current_setting('catalog.base')::int + 1,
  'rejected publishes leave the live release untouched');

-- Immutability.
select throws_ok($$update public.catalog_releases set sha256 = repeat('c', 64)
  where release = 1$$, 'P0001', 'catalog releases are immutable',
  'a published release cannot be edited');
select throws_ok($$delete from public.catalog_releases where release = 1$$,
  'P0001', 'catalog releases are immutable', 'a published release cannot be deleted');

-- Rollback.
select lives_ok($$select northstar_private.set_live_catalog_release(
  current_setting('catalog.base')::int)$$,
  'rolling back to a published release succeeds');
select is((select release from public.catalog_live),
  current_setting('catalog.base')::int, 'the live pointer moved to the rollback target');
select throws_ok($$select northstar_private.set_live_catalog_release(2147483000)$$,
  'P0001', 'catalog release does not exist', 'rollback to an unpublished release fails');
set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated","is_anonymous":false}', true);
select is((public.catalog_manifest()->>'release')::int,
  current_setting('catalog.base')::int, 'manifest follows the rollback');
select throws_ok($$select public.catalog_snapshot(current_setting('catalog.base')::int + 1)$$,
  'P0002', 'catalog release not live', 'a rolled-back release can no longer be downloaded');
reset role;

-- Hardening (stage 9 security review).
select is(
  (select bool_or(has_table_privilege('service_role', t, p))
     from unnest(array['public.catalog_releases','public.catalog_live']) t,
          unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p),
  false, 'the service key has no direct privileges on the catalogue tables');
select is(
  (select bool_or(has_table_privilege(r, t, p))
     from unnest(array['anon','authenticated']) r,
          unnest(array['public.catalog_releases','public.catalog_live']) t,
          unnest(array['TRUNCATE','REFERENCES','TRIGGER']) p),
  false, 'clients cannot truncate, reference or add triggers to catalogue tables');
select is(
  (select bool_and(prosecdef and proconfig = array['search_path=""'])
     from pg_proc where oid in ('public.catalog_manifest()'::regprocedure,
                                'public.catalog_snapshot(integer)'::regprocedure)),
  true, 'catalogue RPCs are security definer with an empty search_path');
select is(
  (select bool_or(prosecdef or proconfig is distinct from array['search_path=""'])
     from pg_proc where oid in (
       'northstar_private.publish_catalog_release(integer,integer,integer,jsonb,text,integer,timestamptz)'::regprocedure,
       'northstar_private.set_live_catalog_release(integer)'::regprocedure,
       'northstar_private.reject_catalog_release_change()'::regprocedure)),
  false, 'private catalogue functions are not security definer and pin search_path');
select is(
  (select coalesce(string_agg(p.oid::regprocedure::text, ', '), '')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'northstar_private'
      and p.proname not in ('sync_workout_internal', 'current_workout_restore_state')
      and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
           or has_function_privilege('anon', p.oid, 'EXECUTE'))),
  '', 'no other private function is executable by clients');
select throws_ok($$select northstar_private.publish_catalog_release(
  current_setting('catalog.base')::int + 2, 1, 1,
  pg_catalog.jsonb_build_object('release', current_setting('catalog.base')::int + 2,
    'schemaVersion', 1, 'minAppCatalogSchema', 1,
    'publishedAt', '2026-11-26T00:00:00Z'),
  repeat('a', 64), 2097153, '2026-11-26T00:00:00Z')$$, '23514', null,
  'a release over 2 MiB is refused');
select throws_ok($$truncate public.catalog_live, public.catalog_releases$$,
  'P0001', 'catalog releases are immutable', 'catalogue releases cannot be truncated');

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated","is_anonymous":false}', true);
select throws_ok($$select public.catalog_snapshot(null)$$, 'P0002',
  'catalog release not live', 'a null release cannot be downloaded');
select throws_ok($$insert into public.catalog_live (singleton, release) values (true, 1)$$,
  '42501', null, 'signed-in clients cannot insert a live pointer');
select throws_ok($$delete from public.catalog_live$$, '42501', null,
  'signed-in clients cannot delete the live pointer');
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);
select throws_ok($$select public.catalog_manifest()$$, '28000', 'verified account required',
  'a JWT without the is_anonymous claim cannot read the manifest');
select set_config('request.jwt.claims', '', true);
select throws_ok($$select public.catalog_snapshot(1)$$, '28000', 'verified account required',
  'a session without a JWT cannot read a snapshot');
reset role;

-- With nothing live, the manifest is empty rather than an error.
delete from public.catalog_live;
set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated","is_anonymous":false}', true);
select is(public.catalog_manifest(), null, 'the manifest is null when no release is live');
reset role;

select * from finish();
rollback;
