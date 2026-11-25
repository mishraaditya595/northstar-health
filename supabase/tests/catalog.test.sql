-- Training catalogue: synthetic, rolled-back pgTAP. The catalogue holds shared
-- reference content only; clients read it through two RPCs and never touch the
-- tables, the pointer or the publish functions.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(40);

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

-- Release 1 (the 18 starter exercises) is live after the migrations run.
set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated","is_anonymous":false}', true);
select is((public.catalog_manifest()->>'release')::int, 1,
  'release 1 is live after migrations');
select is(public.catalog_manifest()->>'sha256',
  'a35713cc3e84253bacb0791cf6b04f05b80ff3ebf6f0e6e610958635588708f2',
  'release 1 checksum matches catalog/releases.lock.json');
select is(jsonb_array_length(public.catalog_snapshot(1)->'exercises'), 18,
  'release 1 carries the 18 starter exercises');
reset role;

-- Publish two synthetic releases through the private function.
select lives_ok($$select northstar_private.publish_catalog_release(
  900, 1, 1,
  '{"release": 900, "schemaVersion": 1, "exercises": [], "templates": [], "programs": []}'::jsonb,
  repeat('a', 64), 90, '2026-11-26T00:00:00Z')$$,
  'publishing release 900 succeeds');
select lives_ok($$select northstar_private.publish_catalog_release(
  901, 1, 1,
  '{"release": 901, "schemaVersion": 1, "exercises": [], "templates": [], "programs": []}'::jsonb,
  repeat('b', 64), 90, '2026-11-26T00:00:00Z')$$,
  'publishing release 901 succeeds');

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"00000000-0000-4000-8000-0000000000c1","role":"authenticated","is_anonymous":false}', true);
select is((public.catalog_manifest()->>'release')::int, 901,
  'manifest points at the newest published release');
select is(public.catalog_manifest()->>'url', '/rest/v1/rpc/catalog_snapshot',
  'manifest url is the snapshot RPC path');
select is(public.catalog_manifest()->>'sha256', repeat('b', 64),
  'manifest carries the release checksum');
select is((public.catalog_manifest()->>'sizeBytes')::int, 90,
  'manifest carries the release size');
select is((public.catalog_snapshot(901)->>'release')::int, 901,
  'the live release can be downloaded');
select throws_ok($$select public.catalog_snapshot(900)$$, 'P0002',
  'catalog release not live', 'a release that is not live cannot be downloaded');
select throws_ok($$select public.catalog_snapshot(12345)$$, 'P0002',
  'catalog release not live', 'an unknown release cannot be downloaded');
select throws_ok($$select * from public.catalog_releases$$, '42501', null,
  'signed-in clients cannot read the release table');
select throws_ok($$select * from public.catalog_live$$, '42501', null,
  'signed-in clients cannot read the live pointer');
select throws_ok($$update public.catalog_live set release = 900$$, '42501', null,
  'signed-in clients cannot move the live pointer');
select throws_ok($$select northstar_private.set_live_catalog_release(900)$$, '42501', null,
  'signed-in clients cannot call the rollback function');
reset role;

-- Anonymous clients are rejected at the function boundary.
set local role anon;
select throws_ok($$select public.catalog_manifest()$$, '42501', null,
  'anonymous manifest call is rejected');
select throws_ok($$select public.catalog_snapshot(901)$$, '42501', null,
  'anonymous snapshot call is rejected');
reset role;

-- Publish rules.
select throws_ok($$select northstar_private.publish_catalog_release(
  900, 1, 1,
  '{"release": 900, "schemaVersion": 1, "exercises": [], "templates": [], "programs": []}'::jsonb,
  repeat('a', 64), 90, '2026-11-26T00:00:00Z')$$, 'P0001',
  'catalog release must exceed existing releases', 'a release number cannot be reused');
select throws_ok($$select northstar_private.publish_catalog_release(
  899, 1, 1,
  '{"release": 899, "schemaVersion": 1, "exercises": [], "templates": [], "programs": []}'::jsonb,
  repeat('a', 64), 90, '2026-11-26T00:00:00Z')$$, 'P0001',
  'catalog release must exceed existing releases', 'an older release cannot be published');
select throws_ok($$select northstar_private.publish_catalog_release(
  902, 1, 1,
  '{"release": 905, "schemaVersion": 1, "exercises": [], "templates": [], "programs": []}'::jsonb,
  repeat('a', 64), 90, '2026-11-26T00:00:00Z')$$, 'P0001',
  'catalog content does not match release', 'content release must match the number');
select throws_ok($$select northstar_private.publish_catalog_release(
  902, 1, 1,
  '{"release": 902, "schemaVersion": 2, "exercises": [], "templates": [], "programs": []}'::jsonb,
  repeat('a', 64), 90, '2026-11-26T00:00:00Z')$$, 'P0001',
  'catalog content does not match release', 'content schema version must match');
select is((select release from public.catalog_live), 901,
  'rejected publishes leave the live release untouched');

-- Immutability.
select throws_ok($$update public.catalog_releases set sha256 = repeat('c', 64)
  where release = 900$$, 'P0001', 'catalog releases are immutable',
  'a published release cannot be edited');
select throws_ok($$delete from public.catalog_releases where release = 900$$,
  'P0001', 'catalog releases are immutable', 'a published release cannot be deleted');

-- Rollback.
select lives_ok($$select northstar_private.set_live_catalog_release(900)$$,
  'rolling back to a published release succeeds');
select is((select release from public.catalog_live), 900,
  'the live pointer moved to the rollback target');
select throws_ok($$select northstar_private.set_live_catalog_release(12345)$$,
  'P0001', 'catalog release does not exist', 'rollback to an unpublished release fails');
set local role authenticated;
select is((public.catalog_manifest()->>'release')::int, 900,
  'manifest follows the rollback');
select throws_ok($$select public.catalog_snapshot(901)$$, 'P0002',
  'catalog release not live', 'a rolled-back release can no longer be downloaded');
reset role;

select * from finish();
rollback;
