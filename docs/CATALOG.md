# Training catalogue

Shared, read-only exercise (and later template and program) content. Decision: [ADR-0010](adr/0010-shared-training-catalogue.md). Stage 1 is in source and **not deployed**: the backend, the validator and release 1 (the 18 existing exercises) exist; the phone client is stage 2.

## Source format

`catalog/exercises/*.json`, `catalog/templates/*.json` and `catalog/programs/*.json` are JSON arrays. `scripts/catalog_build.py` merges them, sorts each list by `id` and adds the release metadata and provenance to form one snapshot described by `catalog/schema/catalog.schema.json`.

- IDs: exercises `builtin.v1.<slug>`, templates `tpl.<slug>`, programs `prog.<slug>`; slug `^[a-z0-9]+(-[a-z0-9]+)*$`. IDs are never renamed, reused or removed; retire an exercise with `"status": "retired"`.
- Muscles (exactly the app's `Muscle` enum): `chest, shoulders, biceps, forearms, abs, obliques, quads, calves, traps, lats, lowerBack, triceps, glutes, hamstrings`. Each exercise has at least one primary muscle.
- `muscleGroup`: `Chest, Back, Legs, Shoulders, Arms, Core`.
- Modes: `reps_load`, `reps`, `duration`, `duration_load`.
- Equipment and category are fixed vocabularies in the schema.
- Text limits: name 80, alias 60 (max 10), cue 160 (max 6), description 1000, note 300. Integers only.

## Validation

`scripts/catalog_validate.py` runs the schema, then rejects: duplicate IDs across kinds, unknown references, templates using retired exercises, weeks without 7 entries or without a training day, `daysPerWeek` mismatches, out-of-range sets/reps/rest/duration, prescriptions that do not fit the exercise mode, and (against `catalog/releases.lock.json`) a removed ID, a changed kind, a changed exercise mode, a reused retired slug, or a release number that does not exceed every locked release.

## Canonical bytes and checksum

`json.dumps(snapshot, sort_keys=True, separators=(",", ":"), ensure_ascii=False)` encoded as UTF-8, no trailing newline. `sha256` is the hex SHA-256 of those bytes and `size_bytes` their length. The phone (stage 2) reproduces this form to verify a download.

## Commands (from the repository root)

```sh
python3 scripts/catalog_build.py check        # validate the next release; prints sha256 and size
python3 scripts/catalog_build.py publish --timestamp YYYYMMDDHHMMSS --published-at 2026-12-01T00:00:00Z
python3 scripts/catalog_build.py rollback --to N --timestamp YYYYMMDDHHMMSS
```

`check` uses a placeholder publish date, so its sha256 differs from the published one. `publish` writes `supabase/migrations/<ts>_catalog_release_<n>.sql`, appends the release to `catalog/releases.lock.json` and records it in `catalog/CHANGELOG.md`. `rollback` writes `<ts>_catalog_rollback_to_<n>.sql` and refuses a release that was never published. Never edit a generated migration.

## Deploying

Open a pull request with the generated migration, the lock and the changelog. CI replays every migration and runs the pgTAP tests (`supabase/tests/catalog.test.sql`). After merge, the owner runs the `supabase-database` Codemagic job (preview, then deploy), see [SUPABASE_CODEMAGIC_DEPLOY.md](SUPABASE_CODEMAGIC_DEPLOY.md). Nothing is deployed from a branch.

## Provenance and licence

All text is original BeyondRep writing under MPL-2.0 (`catalog/PROVENANCE.md`). No third-party text or media. A checklist source may be used for coverage only after its licence is recorded there.

## Release gate

`scripts/p2_08_hosted_rls.py` includes `run_catalog_audit` (anonymous denied, authenticated manifest and live snapshot, stale release refused, tables and publish function unreachable). The live hosted run is a manual release gate and has not been run.
