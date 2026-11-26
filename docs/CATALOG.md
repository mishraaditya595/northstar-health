# Training catalogue

Shared, read-only exercise (and later template and program) content. Decision: [ADR-0010](adr/0010-shared-training-catalogue.md). Stage 1 is in source and **not deployed**: the backend, the validator and release 1 (the 18 existing exercises) exist; the phone client is stage 2.

## Source format

`catalog/exercises/*.json`, `catalog/templates/*.json` and `catalog/programs/*.json` are JSON arrays. `scripts/catalog_build.py` merges them, sorts each list by `id` and adds the release metadata and provenance to form one snapshot described by `catalog/schema/catalog.schema.json`.

- IDs: exercises `builtin.v1.<slug>`, templates `tpl.<slug>`, programs `prog.<slug>`; slug `^[a-z0-9]+(-[a-z0-9]+)*$`. IDs are never renamed, reused or removed; retire an exercise, template or program with `"status": "retired"` (see "Changing content after launch").
- Muscles (exactly the app's `Muscle` enum): `chest, shoulders, biceps, forearms, abs, obliques, quads, calves, traps, lats, lowerBack, triceps, glutes, hamstrings`. Each exercise has at least one primary muscle.
- `muscleGroup`: `Chest, Back, Legs, Shoulders, Arms, Core`.
- Modes: `reps_load`, `reps`, `duration`, `duration_load`.
- Equipment and category are fixed vocabularies in the schema.
- Text limits: name 80, alias 60 (max 10), cue 160 (max 6), description 1000, note 300. Integers only, no control characters in strings. `publishedAt` is RFC 3339 UTC ending in `Z`. A muscle cannot be both primary and secondary for one exercise. A snapshot over 2 MiB (canonical bytes) is rejected.

## Access rules

`catalog_manifest()` and `catalog_snapshot(release)` run for signed-in, verified (non-anonymous) accounts only, like the other public RPCs: an anonymous-user session or a missing JWT gets SQLSTATE `28000` (`verified account required`), and the `anon` role has no EXECUTE. The manifest's `publishedAt` is the exact string inside the checksummed content. The private publish function rejects content whose `release`, `schemaVersion`, `minAppCatalogSchema` or `publishedAt` differ from its arguments.

## Validation

`scripts/catalog_validate.py` runs the schema, then rejects: duplicate IDs across kinds, unknown references, templates using retired exercises, an active program using a retired template, weeks without 7 entries or without a training day, `daysPerWeek` mismatches, out-of-range sets/reps/rest/duration, prescriptions that do not fit the exercise mode, and (against `catalog/releases.lock.json`) a removed ID, a changed kind, a changed exercise mode, a reused retired slug, or a release number that does not exceed every locked release.

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

## Changing content after launch

Exercises, workout templates and programs live on the server, not in the app binary. Adding or editing content never needs an App Store or Play Store update.

1. Edit the JSON under `catalog/` to add or change content: sets, reps, rest, notes and descriptions.
2. Run `python3 scripts/catalog_build.py check`, then `publish` to write the next release migration, the lock and the changelog. Open a pull request. CI and the content tests check it, and the owner reviews a sheet of every changed entry.
3. Merge the pull request and run the `supabase-database` Codemagic job (see [Deploying](#deploying)). The live pointer moves to the new release.
4. Phones pick it up on their next check. That happens at most once every 24 hours, on start or resume, or at once with pull to refresh or Retry (see [Phone client](#phone-client-stage-2-in-source-not-released)).

Rules that hold for every release:

- **User copies never change.** A copied template or an added program is the user's own local data, with fresh IDs. A later release, retirement or rollback does not touch it, or any past workout. Edits reach only new copies and new adds. A user who wants the new version adds it again.
- **IDs are permanent.** An ID's contents may change in a later release, but the ID is never deleted, renamed or reused, and the validator rejects a removed ID. To take an exercise out of browse and "add exercise", set `"status": "retired"`. Its local copies keep working.
- **An exercise's mode is fixed forever.** `reps_load` stays `reps_load`, and `duration` stays `duration`, so past sessions never change meaning. For a different mode, add a new exercise ID. The validator and `releases.lock.json` enforce this.
- **Mistakes are undone by rollback.** `python3 scripts/catalog_build.py rollback --to N --timestamp YYYYMMDDHHMMSS` writes a migration that points the live release back to N, deployed by the same job. Releases themselves are immutable.
- **Only new features need an app update.** A breaking format change, such as a new tracking mode like load plus seconds, or a removed or re-typed field, must raise `minAppCatalogSchema` (see [Phone client](#phone-client-stage-2-in-source-not-released)). Older apps then keep their last good catalogue and show "Update the app to get the latest workouts". Additive changes keep `minAppCatalogSchema` as it is.
- **Templates and programs can be retired.** Add `"status": "retired"` (optional, defaults to `"active"`) to a template or program. The phone hides a retired item from Workouts and Programs, and its detail route says "no longer available". Copies, added programs and past sessions are never touched. The validator rejects an active program that uses a retired template (a retired program may keep its retired templates), and a retired template must still use only active exercises, because app builds from before stage 8 ignore `status` and still check that. `status` is additive, so `minAppCatalogSchema` stays 1.
- **Known limit of retiring.** Builds from before stage 8 ignore `status` on templates and programs, so they keep listing a retired item until the user updates the app. Hiding it on those builds would need a `minAppCatalogSchema` bump, which would also freeze their catalogue. Retire for housekeeping, and do not rely on it to withdraw content from older builds.

## Phone client (stage 2, in source, not released)

Code lives in `apps/mobile/lib/features/catalog/`. The app is read-only against the catalogue: it never writes to Supabase and the refresh never writes to ObjectBox.

- **Cache:** `<app store directory>/northstar_catalog/<backend host>/` holds `snapshot.json` (the canonical snapshot bytes, which name their own `release`) and `meta.json` (`{"lastCheckedAtMs": n}`). It is shared by every account on that backend host and holds no account, health or workout data. Each write goes to a uniquely named `.tmp` file that is renamed over the target, so a kill mid-write can only leave a stale `.tmp`; the next start deletes temp files older than 10 minutes. The new snapshot is active in memory as soon as the rename succeeds, even if the metadata write then fails.
- **Refresh:** on start, on app resume and when cloud backup becomes ready, at most once per 24 hours (a last-checked time in the future counts as stale). It needs a verified, non-anonymous, unexpired session for the bound account and calls `catalog_manifest` (10 s timeout), then `catalog_snapshot(release)` (20 s) only if the release or checksum differs. Pull to refresh on the Exercises page and the Retry buttons force a check.
- **Verification before activation:** the client repeats the cheap structural checks, not every validator rule: SHA-256 over the canonical bytes equals the manifest, canonical size equals the manifest `sizeBytes` and is at most 2 MiB, `release` matches, the snapshot shape (required fields and types, no doubles), unique IDs across kinds, references (unknown or retired exercises, unknown templates in a week), ranges, week length and mode/prescription fit. Anything else is rejected and the old cache stays. A release rejected this way is not downloaded again for 24 hours (in memory, the manifest is still checked); pull to refresh and Retry ignore that.
- **Compatibility:** `minAppCatalogSchema` is the only gate. The app supports catalogue schema 1 and accepts any snapshot whose `minAppCatalogSchema` is at most that, even if `schemaVersion` is higher, ignoring unknown keys at every level. **Publishers must raise `minAppCatalogSchema` for any breaking change** (a removed or re-typed field, a changed meaning); additive changes keep it. Only a higher `minAppCatalogSchema` shows the update notice, which is remembered across restarts in `meta.json` and cleared by the next successful check or by an app update.
- **Outcomes:** `updated`, `upToDate`, `skippedFresh`, `noLiveRelease`, `outdatedApp` (manifest `minAppCatalogSchema` above the supported schema 1: keeps the cache and shows "Update BeyondRep to get the latest exercises."), `unauthorized`, `notLive` (the named release was rolled back mid-check), `invalid` and `failed`. `updated`, `upToDate`, `noLiveRelease` and `outdatedApp` record the last-checked time; `skippedFresh`, `unauthorized`, `notLive`, `invalid` and `failed` change nothing on disk.
- **Failure behaviour:** a failed refresh with a cache is silent (pull to refresh shows "Couldn't update the exercise library. Showing the saved copy.", or "Couldn't download the exercise library. Check your connection and try again." with no cache). With no cache, pickers and the Exercises page show "The exercise library hasn't downloaded yet. Your own exercises and the basics still work." with Retry. A corrupt or unparsable cache file is deleted and treated as no cache. Logs and failure kinds never contain response bodies.
- **Use:** pickers offer only exercises the logger can record today (modes `reps_load` and `duration`; `reps` and `duration_load` stay hidden until timed sets and bodyweight logging exist, unless the account already has the exercise). Picking a catalogue exercise copies it into the account's ObjectBox store (`materializeCatalogExercise`: insert, or refresh display fields when the stored copy is from an older release; the input mode is never changed). Nothing references the cache live.
- **Timed sets (stage 4):** an exercise's `mode` (`duration`) decides that its sets are logged in seconds and its plan rows target seconds; no mode is stored on logged sets. Stage 4 makes no catalogue schema bump: templates and programs first reach the app in stage 6, and every build that reads them already logs seconds, so no older build can receive a timed prescription. Only `duration` is loggable as seconds; `duration_load` (weighted carries) and bodyweight `reps` stay unloggable. Plank sets logged as reps before stage 4 are left as they are, nothing is migrated.
- **Definitions backfill (stage 3):** the catalogue's `primaryMuscles` and `secondaryMuscles` are stored on the account's local exercise definitions. Picking an exercise copies them; in addition, whenever a catalogue snapshot is available (on load and after an update) `syncCatalogDefinitions` fills them on the **already stored** built-in rows (the 18 seeded exercises), in one transaction. It updates only existing `builtin.v1.` rows that are older than the release or have no muscles yet, never inserts, never touches custom rows, never changes the input mode (a row whose mode differs is skipped) and is idempotent. Starting a workout copies a snapshot of the muscles onto each session exercise, so later catalogue changes never rewrite logged workouts. Custom exercises have no muscles (empty snapshots) and keep the coarse group behaviour. The phone validates catalogue muscles against its own vocabulary before storing them: an entry the app does not know (an unknown name, a duplicate, an overlap) is stored as empty lists, so such an exercise keeps the coarse path and uploads are never blocked. Adding a muscle to the vocabulary therefore needs an app update first (and a server migration, because `validate_workout_v1` holds the same list); publish catalogue content using it only afterwards.

## Content rules (release 2, stage 5)

Release 2 grows the library from 18 to 240 exercises in `catalog/exercises/` (one file per equipment family; `legacy.json` is never edited). Rules, enforced by `tool/test_catalog_content.py` where a test can check them:

- **Modes are permanent per ID.** `catalog_validate.py` (run in CI and by `publish`) rejects a release that changes the mode recorded for an ID in `releases.lock.json`, the server keeps every published release row immutable, and the phone never changes the mode of a stored exercise. The server does not compare modes across releases itself: the CI check and the generated-migration workflow are the guard. A wrong mode is fixed by retiring the ID and publishing a new one.
- **Loggable modes only.** Rep exercises use `reps_load` (bodyweight ones too, where load is optional added weight) and holds use `duration`. No `reps` or `duration_load` exercise is added, because a mode is fixed per ID forever and the app cannot log those modes yet. Carries and bodyweight `reps` come with the stage that makes them loggable.
- **Categories.** `mobility` and `conditioning` are left out: their reps or seconds are not meaningful training data for recovery.
- **Writing.** 2 to 4 cues in plain imperative English with no trailing full stop; each covers setup, the movement or a safety point. No outcome or medical claims. Aliases are only other names for the same movement (a chin-up is not an alias of a pull-up). Names follow "Equipment + movement" and are unique ignoring case; no alias equals another exercise's name.
- **Muscles.** 1 to 3 primary muscles (main movers only); secondary muscles are only real assisting muscles. The 14-muscle vocabulary has no rhomboids or adductors, so rows use `traps` for the mid-back and there is no hip adduction exercise. Each muscle is primary in at least 5 exercises. Primary means a main muscle the described execution trains, not every force contributor or stabiliser: hinges done with a neutral spine (good mornings, 45-degree back extensions, reverse hypers) list the lower back as secondary, and the lower back is primary only where the spine itself extends or holds the load. These are heuristics for the recovery model, not measured fatigue. Adductors, hip flexors, rhomboids and serratus anterior are future vocabulary candidates; adding a muscle needs an app update and a server migration first.
- **Unilateral exercises.** Reps or seconds are per side, and one logged set covers both sides.
- **Equipment.** The vocabulary has no preacher bench, landmine, rack, dip station or Nordic anchor. Exercises that need one also list `other`, and their first cue names the setup, so the equipment filter never implies a plain barbell or dumbbell is enough.
- **Muscle group** is the coarse group a lifter would file the exercise under: Chest, Back, Legs, Shoulders, Arms or Core.
- **Owner review gate.** The owner reads a review sheet of every entry before the pull request is merged; merging and running the `supabase-database` job is what publishes release 2. Rollback: `python3 scripts/catalog_build.py rollback --to 1`.
- **Picker.** The Exercises page and the picker sheet have muscle group chips and an equipment select that combine with search. Search also matches the primary muscle names, so "hamstrings" finds Romanian deadlifts. Both lists build rows lazily. No snapshot schema change: `minAppCatalogSchema` stays 1.

Release 2 is in source as `supabase/migrations/20261126030000_catalog_release_2.sql`, **not deployed**.

## Templates (release 3, stage 6)

Release 3 adds 16 standalone templates in `catalog/templates/standalone.json` (IDs `tpl.<slug>`, never reused). Rules, enforced by `TemplateContentTest` in `tool/test_catalog_content.py` where a test can check them:

- **Content.** 4 to 7 exercises, each active and in a loggable mode (`reps_load` or `duration`), no exercise twice. Compounds are 3 to 5 sets of 5 to 10 reps with 120 to 180 s rest, accessories 2 to 4 sets of 8 to 15 reps with 60 to 90 s rest, holds 2 to 3 sets of 20 to 60 s. At most 18 working sets for beginner templates and 24 otherwise, and at least 60 s rest on any row of 8 reps or fewer. Unilateral exercises are counted per side (the row note says so) and one logged set covers both sides.
- **Writing.** Each description is one or two plain sentences saying who it suits and what it covers, with no outcome claims. All text is original.
- **Tags.** `tags.equipment` is the union of the exercises' equipment, without `bodyweight` when other equipment is present. Goal filters, equipment filters and programs come in later stages; `standalone: false` hides a template from the Workouts list (program-only templates arrive with their programs).
- **Owner review gate.** As release 2: the owner reads a review sheet of every template before merging, and merging plus the `supabase-database` job publishes release 3. Rollback: `python3 scripts/catalog_build.py rollback --to 2`.

Phone behaviour (in source, not released): a template is shown only if every exercise is active in the cached snapshot and has a loggable mode. **Copy to My Plans** (`copyCatalogTemplate`) materializes the exercises and writes the plan and its rows in one ObjectBox transaction; the screen's request UUID is the plan UUID, so a repeated tap returns the same plan, and a deliberate second copy gets " (2)", " (3)" in the name while an active plan has it. Any failure leaves no plan, rows or new exercises. The copy has no link back to the template, so later catalogue releases never change it. **Start now** (`startTemplateWorkout`) materializes the exercises, then creates the session and its planned sets in one transaction with no saved plan; an unfinished workout blocks it with the usual message. Targets are not shown inside the logger. No catalogue schema bump: `minAppCatalogSchema` stays 1 and older builds ignore the templates.

Release 3 is in source as `supabase/migrations/20261126040000_catalog_release_3.sql`, **not deployed**.

## Programs (release 4, stage 7)

Release 4 adds 17 programs in `catalog/programs/programs.json` (IDs `prog.<slug>`, never reused) and 22 program-only templates in `catalog/templates/program_sessions.json` (`"standalone": false`, so the Workouts list never shows them and the template routes never open them). Programs also reuse the standalone templates. Rules, enforced by `ProgramContentTest` in `tool/test_catalog_content.py` where a test can check them:

- **Week.** Seven entries, index 0 is the program's first day (the user picks its weekday when adding it), `null` is a rest day, `daysPerWeek` is the number of training days (2 to 6). A template may appear on several days.
- **Level and time.** The program level is at least as hard as its hardest template (beginner < intermediate < advanced), and `estimatedMinutes` is within 5 of the average of its training days.
- **Equipment.** The union of its templates' equipment, without `bodyweight` when other equipment is present.
- **Spacing.** A program with 4 or fewer training days never has 3 training days in a row, counting Sunday to Monday as consecutive. 5 and 6 day splits are exempt.
- **Text.** One to five sentences for programs (two for templates), no outcome claims. A week that uses its templates unevenly says "twice" and "once", and a program states its equipment setup (rack and safeties, bench safeties, anchors, assisted variations). Every program-only template is used by at least one program.
- **Content.** The same conservative rules as templates. The 5x5 sessions use fixed sets of five with 3 minute rests on the main lifts. The low volume sessions use one or two hard sets per exercise with long rests. The calisthenics pull-up and chin-up rows carry the assisted-variation note.

Phone behaviour (in source, not released): a program is shown only if every template its week uses is active and loggable in the cached snapshot (program-only templates count). **Add program** (`importProgram`) asks for the weekday of day 1 and whether to make the program active, then in one ObjectBox transaction materializes the exercises, creates one plan per distinct template (hidden from Your plans, edited in the normal plan editor, archived only with the program), the program and its seven days, and deactivates any other active program. The request UUID is the program UUID, so a repeated tap returns the same program and a deliberate second add is named " (2)". Any failure leaves nothing behind. Programs, their days, `programUuid` on plans and the session program fields are local only and never reach the sync payload, snapshot, export or restore. Starting today's workout from **Your program** records `programUuid` and `programDayLocalDate` on the session; stage 8 adds the Today card and the done and missed days, computed fresh from finished sessions and never stored. No catalogue schema bump: `minAppCatalogSchema` stays 1.

Release 4 is in source as `supabase/migrations/20261126050000_catalog_release_4.sql`, **not deployed**. Owner review gate as for release 3: the owner reads a review sheet of every program and every new template before merging, and merging plus the `supabase-database` job publishes it. Rollback: `python3 scripts/catalog_build.py rollback --to 3`.

## Provenance and licence

All text is original BeyondRep writing under MPL-2.0 (`catalog/PROVENANCE.md`). No third-party text or media. A checklist source may be used for coverage only after its licence is recorded there. Release 2 used the public-domain Free Exercise DB (github.com/yuhonas/free-exercise-db, Unlicense) only as a checklist of which movements exist; no text, wording or muscle tags were copied.

## Release gate

`scripts/p2_08_hosted_rls.py` includes `run_catalog_audit` (anonymous denied, authenticated manifest and live snapshot, stale release refused, tables unreachable, `northstar_private` schema not exposed through the API). It **requires the catalogue migrations to be applied** to the project under test, and responses are capped at 2 MiB. The live hosted run is a manual release gate and has not been run; see [p2-08-hosted-release-plan.md](implementation/phase-2/p2-08-hosted-release-plan.md).
