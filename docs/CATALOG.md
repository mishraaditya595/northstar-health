# Training catalogue

Shared, read-only exercise (and later template and program) content. Decision: [ADR-0010](adr/0010-shared-training-catalogue.md). Stage 1 is in source and **not deployed**: the backend, the validator and release 1 (the 18 existing exercises) exist; the phone client is stage 2.

## Source format

`catalog/exercises/*.json`, `catalog/templates/*.json` and `catalog/programs/*.json` are JSON arrays. `scripts/catalog_build.py` merges them, sorts each list by `id` and adds the release metadata and provenance to form one snapshot described by `catalog/schema/catalog.schema.json`.

- IDs: exercises `builtin.v1.<slug>`, templates `tpl.<slug>`, programs `prog.<slug>`; slug `^[a-z0-9]+(-[a-z0-9]+)*$`. IDs are never renamed, reused or removed; retire an exercise with `"status": "retired"`.
- Muscles (exactly the app's `Muscle` enum): `chest, shoulders, biceps, forearms, abs, obliques, quads, calves, traps, lats, lowerBack, triceps, glutes, hamstrings`. Each exercise has at least one primary muscle.
- `muscleGroup`: `Chest, Back, Legs, Shoulders, Arms, Core`.
- Modes: `reps_load`, `reps`, `duration`, `duration_load`.
- Equipment and category are fixed vocabularies in the schema.
- Text limits: name 80, alias 60 (max 10), cue 160 (max 6), description 1000, note 300. Integers only, no control characters in strings. `publishedAt` is RFC 3339 UTC ending in `Z`. A muscle cannot be both primary and secondary for one exercise. A snapshot over 2 MiB (canonical bytes) is rejected.

## Access rules

`catalog_manifest()` and `catalog_snapshot(release)` run for signed-in, verified (non-anonymous) accounts only, like the other public RPCs: an anonymous-user session or a missing JWT gets SQLSTATE `28000` (`verified account required`), and the `anon` role has no EXECUTE. The manifest's `publishedAt` is the exact string inside the checksummed content. The private publish function rejects content whose `release`, `schemaVersion`, `minAppCatalogSchema` or `publishedAt` differ from its arguments.

## Validation

`scripts/catalog_validate.py` runs the schema, then rejects: duplicate IDs across kinds, unknown references, templates using retired exercises, weeks without 7 entries or without a training day, `daysPerWeek` mismatches, out-of-range sets/reps/rest/duration, prescriptions that do not fit the exercise mode, and (against `catalog/releases.lock.json`) a removed ID, a changed kind, a changed exercise mode, a reused retired slug, or a release number that does not exceed every locked release.

## Canonical bytes and checksum

`json.dumps(snapshot, sort_keys=True, separators=(",", ":"), ensure_ascii=False)` encoded as UTF-8, no trailing newline. `sha256` is the hex SHA-256 of those bytes and `size_bytes` their length. The phone (`lib/features/catalog/domain/canonical_json.dart`) reproduces this form to verify a download; a test checks it against release 1 and `catalog/releases.lock.json`.

## Commands (from the repository root)

```sh
python3 scripts/catalog_build.py check        # validate the next release; prints sha256 and size
python3 scripts/catalog_build.py publish --timestamp YYYYMMDDHHMMSS --published-at 2026-12-01T00:00:00Z
python3 scripts/catalog_build.py rollback --to N --timestamp YYYYMMDDHHMMSS
```

`check` uses a placeholder publish date (it says so in its output), so its sha256 differs from the published one. `publish` and `rollback` refuse an existing target file and a `--timestamp` that is not later than the newest migration, write the migration before the lock and leave nothing behind if a step fails. `publish` writes `supabase/migrations/<ts>_catalog_release_<n>.sql`, appends the release to `catalog/releases.lock.json` and records it in `catalog/CHANGELOG.md`. `rollback` writes `<ts>_catalog_rollback_to_<n>.sql` and refuses a release that was never published. Never edit a generated migration.

## Deploying

Open a pull request with the generated migration, the lock and the changelog. CI replays every migration and runs the pgTAP tests (`supabase/tests/catalog.test.sql`). After merge, the owner runs the `supabase-database` Codemagic job (preview, then deploy), see [SUPABASE_CODEMAGIC_DEPLOY.md](SUPABASE_CODEMAGIC_DEPLOY.md). Nothing is deployed from a branch.

## Phone client (stage 2, in source, not released)

Code lives in `apps/mobile/lib/features/catalog/`. The app is read-only against the catalogue: it never writes to Supabase and the refresh never writes to ObjectBox.

- **Cache:** `<app store directory>/northstar_catalog/<backend host>/` holds `snapshot.json` (the canonical snapshot bytes, which name their own `release`) and `meta.json` (`{"lastCheckedAtMs": n}`). It is shared by every account on that backend host and holds no account, health or workout data. Writes go to a `.tmp` file and are renamed over the target, so a kill mid-write can only leave a stale `.tmp`, which the next start deletes.
- **Refresh:** on start, on app resume and when cloud backup becomes ready, at most once per 24 hours (a last-checked time in the future counts as stale). It needs a verified, non-anonymous, unexpired session for the bound account and calls `catalog_manifest` (10 s timeout), then `catalog_snapshot(release)` (20 s) only if the release or checksum differs. Pull to refresh on the Exercises page and the Retry buttons force a check.
- **Verification before activation:** SHA-256 over the canonical bytes must equal the manifest, `release` must match, the schema must be supported, and references, ranges and modes are re-validated (the same rules as the validator). Anything else is rejected and the old cache stays.
- **Outcomes:** `updated`, `upToDate`, `skippedFresh`, `noLiveRelease`, `outdatedApp` (manifest `minAppCatalogSchema` above the app's supported schema 1: keeps the cache and shows "Update BeyondRep to get the latest exercises."), `unauthorized`, `notLive` (the named release was rolled back mid-check), `invalid` and `failed`. `updated`, `upToDate`, `noLiveRelease` and `outdatedApp` record the last-checked time; `skippedFresh`, `unauthorized`, `notLive`, `invalid` and `failed` change nothing on disk.
- **Failure behaviour:** a failed refresh with a cache is silent (pull to refresh shows "Couldn't update the exercise library. Showing the saved copy."). With no cache, pickers and the Exercises page show "The exercise library hasn't downloaded yet. Your own exercises and the basics still work." with Retry. A corrupt or unparsable cache file is deleted and treated as no cache. Logs and failure kinds never contain response bodies.
- **Use:** picking a catalogue exercise copies it into the account's ObjectBox store (`materializeCatalogExercise`: insert, or refresh display fields when the stored copy is from an older release; the input mode is never changed). Nothing references the cache live.

## Provenance and licence

All text is original BeyondRep writing under MPL-2.0 (`catalog/PROVENANCE.md`). No third-party text or media. A checklist source may be used for coverage only after its licence is recorded there.

## Release gate

`scripts/p2_08_hosted_rls.py` includes `run_catalog_audit` (anonymous denied, authenticated manifest and live snapshot, stale release refused, tables unreachable, `northstar_private` schema not exposed through the API). It **requires the catalogue migrations to be applied** to the project under test, and responses are capped at 2 MiB. The live hosted run is a manual release gate and has not been run; see [p2-08-hosted-release-plan.md](implementation/phase-2/p2-08-hosted-release-plan.md).
