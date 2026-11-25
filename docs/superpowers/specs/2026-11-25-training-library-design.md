# Training library, workout templates and programs: design

Issue: [#63](https://github.com/mishraaditya595/BeyondRep-Health/issues/63). Status: draft for owner approval, 2026-11-25.

## 1. Intent

BeyondRep today ships 18 hard-coded exercises and nothing else: every plan is built by hand. Before the public launch, new users need a ready library (exercises, standalone workouts and multi-day programs) so they can start training on day one. The owner also wants to run these programs himself, so the content has to be good enough for someone with years of training, not filler.

The library is shared reference content published from Supabase and cached on the phone. Anything a user takes from it becomes their own local, editable copy. Workout logging, history and sync keep working exactly as now.

### Goals

- A remote, versioned catalogue (exercises, workout templates, programs) published from version-controlled JSON, read-only for clients, cached on the phone, usable offline after one download.
- About 200 to 300 exercises with specific primary and secondary muscles, equipment, movement category, tracking mode, aliases and short technique cues.
- Muscle recovery driven by those specific muscles, with secondary muscles counting for less.
- Timed sets (planks, holds, carries) logged as seconds end to end: phone, sync contract, server, export and restore.
- Standalone workout templates that can be previewed, started directly or copied into My Plans.
- Programs with a repeating 7-day schedule, imported atomically as editable local data, one active at a time, shown on Today with a "missed" line.

### Non-goals (this issue)

Listed in the issue's section 6 and not built here: exercise alternatives, readiness-driven suggestions, progressive overload, media (images, animations), program sharing or community submissions, cloud backup of plans or programs, flexible (non-weekday) rotations.

### Anti-goals (failure even if it "works")

- A catalogue refresh, retirement or rollback changes a past workout, a user's plan or a user's program.
- A half-downloaded or invalid catalogue becomes live.
- The app blocks on the catalogue: logging, custom plans and history must work with no catalogue at all.
- An unrelated workout ticks off a scheduled program day.
- Seconds stored as reps, or a timed exercise silently logged as reps.
- Health data, user data or account identifiers in the shared catalogue.
- Copied, unlicensed exercise text or media.

## 2. Decisions made with the owner

| Topic | Decision |
| --- | --- |
| Why | Public launch content and the owner's own training. |
| Order | The issue's sequence: backend catalogue and publishing first, Train/Today screens last (section 8). |
| Timed sets | In scope. Needs an additive sync-contract and server change; owner approved extending scope for it. |
| Muscles | Specific primary and secondary muscles drive recovery; secondary counts for less. Old coarse-group workouts keep the coarse mapping. |
| Content format | Plain JSON in the repo, validated in CI. |
| Content review | The owner reviews every workout template and program prescription before it is published. |
| Schedule | Today shows today's scheduled workout or rest day, plus a "Missed <day>: <workout>" line. A day counts as done only when a workout started from that program day is finished. |
| Old plank sets | Left as logged (reps). No migration or backfill; TestFlight data may be wiped instead. |
| Server storage | Approach A: one immutable snapshot row per release plus a live pointer (section 3). |
| Phone cache | Approach A: a validated snapshot file swapped in atomically, searched in memory (section 3). |

## 3. Approaches considered

### Server: how a release is stored

- **A. One snapshot row per release plus a live pointer (chosen).** A release is one immutable row holding the whole catalogue as JSON with schema version, release number, checksum and size. A single pointer row names the live release. Publishing inserts the row and flips the pointer in one transaction; rollback flips it back. Smallest build, coherent by construction, fits the existing migration, RLS and pgTAP setup.
- **B. Normalized tables per release** (exercises, templates, programs keyed by release). Queryable, but the phone always needs the whole set, and keeping a release consistent across tables is extra work for no benefit at this size.
- **C. Snapshot file in Supabase Storage.** Adds bucket policies and a second kind of infrastructure. Kept as an escape hatch: the manifest returns a download URL, so a release can later move to Storage or a CDN without an app update.

Sizing behind the choice: about 300 exercises at roughly 600 bytes, plus about 60 templates and 16 programs, is roughly 300 KB of JSON (around 50 KB compressed). Revisit past roughly 5,000 exercises or several MB.

### Phone: how the cache is kept

- **A. Validated snapshot file, swapped atomically, held in memory (chosen).** Download to a temp file, verify checksum and schema, parse, validate references, then rename over the live file. Parsing a few hundred KB off the UI thread takes tens of milliseconds; in-memory search over a few hundred items is instant. No ObjectBox model churn, and a partial download can never be live.
- **B. ObjectBox entities.** Matches the issue's "preferably ObjectBox", but adds model changes and makes "switch the whole release at once" harder. Not worth it below tens of thousands of rows.

### Muscles

- **1. Specific muscles drive recovery (chosen).**
- **2. Specific muscles for browsing only, recovery stays coarse.** Less work, but the coarse groups get visibly wrong with 200+ exercises.

### Build order

- **A. Issue order, layer by layer (chosen).**
- **B. Thin end-to-end slice first, then widen.** Gets the owner training sooner; not chosen.

## 4. Data model

### 4.1 Identifiers

- Exercises keep the existing namespace: `builtin.v1.<slug>`. The 18 current IDs (for example `builtin.v1.squat`) appear in the catalogue unchanged. New exercises get new slugs. A slug is never renamed or reused; removed exercises are marked `retired`, never deleted from the source.
- Templates: `tpl.<slug>`. Programs: `prog.<slug>`. Same never-reuse rule.
- Every user copy (plan, plan exercise, program, program day) gets a fresh UUID. The copy records the catalogue ID and release it came from (`sourceId`, `sourceRelease`) for display only; nothing depends on it later.

### 4.2 Muscle taxonomy

The fixed muscle list is the body map's `Muscle` enum (chest, shoulders, biceps, triceps, forearms, abs, obliques, quads, hamstrings, glutes, calves, traps, lats, lowerBack). Catalogue exercises list `primaryMuscles` (at least one) and `secondaryMuscles` (zero or more) from that list only. Each exercise also keeps a coarse `muscleGroup` (Chest, Back, Legs, Shoulders, Arms, Core) for display, filters and old code paths.

Recovery: a primary muscle receives the set's full load contribution; a secondary muscle receives a fraction (builder's call, start at 0.5 and expose as a named constant). Sessions recorded before this change, or custom exercises without specific muscles, fall back to today's coarse-group mapping, so no history changes meaning.

### 4.3 Tracking modes

| Mode | Logged fields | Example |
| --- | --- | --- |
| `reps_load` | reps, optional load | Squat |
| `reps` | reps (bodyweight) | Push-up |
| `duration` | seconds | Plank |
| `duration_load` | seconds, load | Farmer carry |

Today's code has `reps_load` and `duration`. Bodyweight rep exercises can keep using `reps_load` with no load if the builder prefers; `duration_load` is included only if the timed-set stage supports load with seconds cleanly. A template or program never contains an exercise whose mode the app version cannot log; the manifest's compatibility field (4.5) enforces this.

### 4.4 Catalogue JSON (source and snapshot)

Source lives in `catalog/` at the repo root (new top-level directory; update `docs/REPOSITORY_LAYOUT.md` and `tool/test_repository_layout.py`):

```
catalog/
  schema/catalog.schema.json      # JSON Schema for one snapshot
  exercises/*.json                # one file per exercise, or per equipment group (builder's call)
  templates/*.json
  programs/*.json
  PROVENANCE.md                   # source, licence, attribution, modifications
  CHANGELOG.md                    # one entry per published release
```

A build script assembles the source into one snapshot:

```json
{
  "schemaVersion": 1,
  "release": 3,
  "publishedAt": "2026-12-01T00:00:00Z",
  "provenance": { "source": "BeyondRep original", "license": "MPL-2.0", "attribution": "" },
  "exercises": [
    {
      "id": "builtin.v1.rdl",
      "name": "Romanian deadlift",
      "aliases": ["RDL", "stiff-leg deadlift"],
      "muscleGroup": "Legs",
      "primaryMuscles": ["hamstrings", "glutes"],
      "secondaryMuscles": ["lowerBack"],
      "equipment": ["barbell"],
      "category": "hinge",
      "mode": "reps_load",
      "cues": ["Soft knees, push hips back", "Bar close to legs", "Stop when hips stop moving back"],
      "status": "active"
    }
  ],
  "templates": [
    {
      "id": "tpl.push-a",
      "name": "Push A",
      "description": "...",
      "tags": { "goal": ["hypertrophy"], "level": "intermediate", "equipment": ["barbell", "dumbbell", "cable"] },
      "estimatedMinutes": 60,
      "exercises": [
        { "exerciseId": "builtin.v1.bench-press", "sets": 4, "repsMin": 6, "repsMax": 8, "restSeconds": 150, "note": "" },
        { "exerciseId": "builtin.v1.plank", "sets": 3, "durationSeconds": 45, "restSeconds": 60 }
      ]
    }
  ],
  "programs": [
    {
      "id": "prog.ppl-3",
      "name": "Push/Pull/Legs",
      "description": "...",
      "goals": ["hypertrophy"],
      "level": "intermediate",
      "daysPerWeek": 3,
      "estimatedMinutes": 60,
      "equipment": ["barbell", "dumbbell", "cable"],
      "week": ["tpl.push-a", null, "tpl.pull-a", null, "tpl.legs-a", null, null]
    }
  ]
}
```

- `week` has exactly 7 entries: a template ID or `null` for rest. Index 0 is the program's first day, not Monday; the user chooses which weekday it lands on at import (6.2). The same template may appear on several days.
- A program's templates live in `templates` like any standalone template; a `standalone: false` flag (builder's call on naming) hides program-only templates from the standalone browse list.
- Equipment and category are fixed vocabularies defined in the schema, so filters cannot drift.

### 4.5 Validation (one validator, used in CI, before publish, and mirrored on the phone)

A Python validator in `tool/` (with `tool/test_catalog_*.py` unit tests, run by the existing unittest discovery) rejects:

- duplicate IDs across exercises, templates or programs; an ID that appears in an earlier release with a different kind; reuse of a retired slug for a new exercise; removal of an ID present in any earlier release (it must be `retired` instead);
- unknown exercise or template references; a published template or program referencing a retired exercise;
- an exercise whose `mode` differs from the mode recorded for its ID in any earlier release (tracking mode is fixed per ID forever; a different mode needs a new ID), so past sessions never change meaning and no mode snapshot is needed;
- weeks without exactly 7 entries, programs with no training day, `daysPerWeek` not matching the non-rest count;
- sets outside 1 to 30, reps outside 1 to 1000 or min greater than max, rest outside 0 to 3600, duration outside 1 to 3600;
- a prescription that does not match the exercise mode: reps on a `duration` exercise, seconds on a `reps_load` exercise, or both;
- muscles or equipment outside the fixed vocabularies, an exercise with no primary muscle, text fields over their limits;
- snapshot size over a limit (builder's call, for example 2 MB) as an early warning.

"Earlier releases" come from a committed `catalog/releases.lock.json` listing every published release's IDs (with each exercise's mode) and checksum, updated by the publish job's PR (section 5.3). The phone repeats the cheap structural checks (schema version, checksum, references, ranges) before activating a snapshot; it never trusts the server blindly.

Compatibility: the manifest carries `minAppCatalogSchema`. The app knows the highest catalogue schema it understands. If the live release needs a newer schema, the phone keeps its last good cache and shows "Update the app to get the latest workouts" in the library, without blocking anything else. Adding timed sets to templates is a schema bump, so older builds never receive timed prescriptions they cannot log.

## 5. Backend

### 5.1 Schema (new migration)

- `catalog_releases(release int primary key, schema_version int, min_app_schema int, content jsonb, sha256 text, size_bytes int, published_at timestamptz, created_at timestamptz)`. There is no `notes` column (release notes live in `catalog/CHANGELOG.md`). Rows are immutable: an update, delete or truncate trigger raises.
- `catalog_live(singleton bool primary key default true check (singleton), release int references catalog_releases)`. One row.
- No column holds user or health data.

### 5.2 Read API and access

- `catalog_manifest()` (SQL, `security definer`, `stable`, fixed `search_path`): returns `{release, schemaVersion, minAppCatalogSchema, publishedAt, sha256, sizeBytes, url}` for the live release. `url` is the RPC endpoint path for the snapshot today and can later point to Storage or a CDN.
- `catalog_snapshot(p_release int)`: returns `content` only when `p_release` is the live release; otherwise it raises a "not live" error. A phone that read the manifest just before a publish or rollback gets that error, keeps its cache and tries again at the next check. This keeps rollback a real withdrawal: a release rolled back for bad content can no longer be downloaded. (Planner's call, from the builder check.) Drafts never exist in these tables; staging is a separate local step (5.3).
- Session rule: both functions require a verified, non-anonymous user (`auth.uid()` not null and `is_anonymous` claim `false`, SQLSTATE `28000` otherwise), like the other public RPCs. `catalog_manifest().publishedAt` is the exact string inside the checksummed content.
- Grants: `execute` on both functions to `authenticated` only. Revoke all on both tables from `anon` and `authenticated`; RLS enabled with no client policies. No client insert, update, delete or publish path.
- pgTAP tests (new `supabase/tests/catalog.test.sql`): anonymous cannot call either function or read tables; authenticated can read manifest and the live snapshot; authenticated cannot read tables directly, insert, update, delete or flip the pointer; immutability trigger fires; existing owner-scoped workout tables are unaffected. Extend `tool/test_p2_08_hosted_rls.py` with the same checks for the hosted harness.

### 5.3 Publishing, staging, rollback

Publishing uses generated migrations instead of a new Codemagic job (decided by the owner with the stage 1 plan): no `codemagic.yaml` change or new credential path, every release is reviewed in a PR, and CI replays it against a clean database.

- **Build:** `python3 scripts/catalog_build.py check` assembles `catalog/` deterministically (sorted keys, stable ordering, canonical bytes) and prints size and SHA-256.
- **Validate:** the validator runs in `check` and `publish`, and the content tests run in CI on every PR (`tool/test_catalog_*.py`).
- **Stage:** CI replays every migration, including the release, against a clean database and runs the pgTAP tests; locally, `supabase db reset` does the same. There is no draft row in the hosted database.
- **Publish:** `python3 scripts/catalog_build.py publish --timestamp ... --published-at ...` writes `supabase/migrations/<ts>_catalog_release_<n>.sql`, which calls `northstar_private.publish_catalog_release(...)` (no client access) to insert the release and flip `catalog_live` in one transaction. The owner deploys it with the existing manual `supabase-database` job.
- **Rollback:** `rollback --to <n>` writes a `<ts>_catalog_rollback_to_<n>.sql` migration that calls `northstar_private.set_live_catalog_release(n)`; only a published release is accepted. Releases are never deleted. Because user copies are independent (section 6), rollback cannot damage user data.
- **Record:** `publish` also updates `catalog/releases.lock.json` and `catalog/CHANGELOG.md` in the same PR.
- Documentation: `docs/CATALOG.md` (format, validation, publish, rollback, cache policy, licensing), plus updates to `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/SUPABASE_CODEMAGIC_DEPLOY.md`.

### 5.4 Sync payload changes (additive)

The phone-to-Supabase workout payload is not described in `contracts/` today: it is defined by the outbox builder (`objectbox_workout_outbox.dart`) and the server allow-lists in the latest sync migration (`20261025090000_phase2_completed_only_scope.sql`). `contracts/workout_sync/v1` is the watch-to-phone envelope only. These changes touch the cloud payload, server, restore, export and conflict review; the watch envelope is not changed, because watch recording is not implemented, and it gets its own review when it is. The payload's `schema_version` stays 1 because both additions are optional fields. `docs/SYNC_PROTOCOL.md` gains a section describing the cloud payload's set and exercise fields. (Planner's call, from the builder check.)

Two additions, each in its own stage (8), each deployed to the server before any app build sends it:

- **Set:** optional `duration_seconds` (integer 1 to 86,400). A completed set needs `reps` or `duration_seconds` (or both for `duration_load`, builder's call on whether reps are allowed alongside). Server validation, progress aggregation (`completed_working_sets` counts timed sets; `loaded_volume_gram_reps` stays reps times load only), restore feed, JSON export and the conflict review all carry the field.
- **Exercise:** optional `primary_muscles` and `secondary_muscles` (arrays of the fixed muscle vocabulary, each at most 14 entries). Needed so restoring history on a second device keeps specific-muscle recovery.
- Update the outbox builder and its tests, the restore and export parsers, `docs/SYNC_PROTOCOL.md` and pgTAP tests.
- Plank sets logged before timed sets (stored as reps) are left unchanged: no phone migration and no server backfill. There are no real users yet, only the owner's TestFlight data, which the owner is happy to wipe if it looks odd (owner's decision, 2026-11-25).
- Older internal builds: an older app restoring a workout that contains `duration_seconds` may reject it. Nothing is publicly released, so the release note for the stage says to update every TestFlight install; the builder checks the old restore parser's behaviour and records it.

## 6. App

### 6.1 Catalogue repository and cache

- `features/catalog/` (new feature module): `CatalogRepository` (domain interface), a Supabase transport, a file store and Riverpod providers. Widgets only read providers.
- Cache location: the app support directory, outside the account-partitioned ObjectBox store: `catalog/snapshot.json` plus `catalog/meta.json` (release, schema, SHA-256, fetchedAt, lastCheckedAt). Shared across accounts because it holds no personal data; documented in the new ADR.
- Load: on app start, read and parse the cached snapshot in a background isolate; the library is available as soon as parsing finishes. A corrupt cache file is discarded and treated as "no cache".
- Refresh: after sign-in and on app foreground, if `lastCheckedAt` is older than 24 hours, call `catalog_manifest()`. Same release and checksum: update `lastCheckedAt` only. New release: if its schema is supported, download, verify size and SHA-256, parse and validate, write to `snapshot.json.tmp`, flush, rename over `snapshot.json`, then write `meta.json`, then publish the new snapshot to providers. Any failure keeps the last good cache.
- One refresh at a time: concurrent triggers share the in-flight future. A pull-to-refresh or "Retry" in the library forces a check ignoring the 24-hour window.
- Timeouts (builder's call, around 15 seconds for the snapshot), offline, low storage (write failure) and process death mid-download all leave the old file untouched; a stale `.tmp` is deleted on next start.
- No cache and no network: the library shows an unavailable state with Retry. Everything else (custom plans, legacy 18 built-ins, logging, history) works.
- The legacy 18-exercise seed stays in the app unchanged as the offline compatibility path (`ensureCatalogSeeded`). Nothing new is bundled.

### 6.2 Copying catalogue content into the user's account

Catalogue records are never referenced live by user data. They are copied into the existing account-scoped ObjectBox store at the moment of use:

- **Exercise definition materialization:** adding a catalogue exercise to a plan, copying a template, importing a program or starting a template workout upserts an `ExerciseDefinitionEntity` with the catalogue ID as `uuid`, `isBuiltIn = true`, `catalogVersion = release`, and the new fields (6.4). If the local copy exists from an older release and is not referenced by history in a way that matters (definitions are not history; sessions snapshot names and muscles), it is refreshed to the newer release's name and muscles. Retired catalogue exercises stay as local definitions and keep working in existing plans; they are only hidden from browse and "add exercise".
- **Exercise picker:** shows the union of the cached catalogue and local definitions (custom plus materialized), de-duplicated by ID, with search by name and alias and filters for muscle, equipment and category.
- **Copy template to My Plans:** one ObjectBox transaction creates a new `WorkoutPlanEntity` and its `PlanExerciseEntity` rows with fresh UUIDs and materializes every referenced exercise. Double-tap protection: the copy action carries a client-generated request UUID; a second submission with the same request UUID within the same screen returns the first copy instead of creating another. A deliberate second copy (new tap after the first finished) creates a new plan, named "<name> (2)".
- **Start from template:** starts a session through the existing session-start path using an in-memory plan built from the template (exercises materialized first), without creating a saved plan.
- **Import program:** one ObjectBox transaction validates every referenced template and exercise against the cached snapshot, materializes exercises, creates one plan per distinct template, creates the program and its seven days, and optionally makes it active. Any failure throws before commit: no partial program, no orphan plans. Failure injection tests cover a throw after each step.

### 6.3 Local program model (new ObjectBox entities, additive, account-scoped, never synced)

- `TrainingProgramEntity`: uuid, name, description, sourceId, sourceRelease, firstDayWeekday (1 to 7, ISO Monday = 1), isActive, activatedLocalDate (`yyyy-MM-dd`, set each time it becomes active), createdAtMs, updatedAtMs, archivedAtMs.
- `ProgramDayEntity`: uuid, programUuid, dayIndex (0 to 6), planUuid (nullable means rest).
- `WorkoutPlanEntity` gains `programUuid` (nullable). Program plans show under their program, not in My Plans, and use the existing plan editor, stale-edit check and archive behaviour.
- At most one active program; activating one deactivates the other in the same transaction. Archiving a program archives its plans and never touches sessions.
- Schedule editing: the user can change the first weekday, move a workout to another day, set a day to rest, or point a day at another of the program's plans. Done days are durable because they come from sessions. Missed days are computed against the current schedule, so an edit can change which earlier days this week show as missed; that is acceptable because the missed window is at most six days. No schedule history is stored (6.5). (Planner's call, from the builder check.)

### 6.4 Additive changes to existing entities

- `ExerciseDefinitionEntity`: `primaryMuscles`, `secondaryMuscles` (string lists), `aliases`, `cues`, `catalogStatus`.
- `WorkoutExerciseEntity` (session snapshot): `primaryMusclesSnapshot`, `secondaryMusclesSnapshot`.
- `WorkoutSetEntity`: `durationSeconds` (nullable).
- `PlanExerciseEntity`: `targetDurationSeconds` (nullable). `PlanExerciseRecord.validate` rejects both reps and duration targets on one row, and a duration target on a rep-mode exercise.
- `WorkoutSessionEntity`: `programUuid` and `programDayLocalDate` (`yyyy-MM-dd`, nullable), set only when the session is started from a program day. Local only; not part of the sync payload.
- All additive with stable UIDs; regenerate and commit `objectbox.g.dart` and `objectbox-model.json`; add an old-database migration test per `docs/OBJECTBOX.md`.

### 6.5 Schedule rules

Let the local date be the device's current calendar date. The program's day for a date is `(isoWeekday(date) - firstDayWeekday) mod 7`.

- **Today card:** shows today's scheduled workout with "Start", or "Rest day". If an active-session recovery is pending, that keeps priority as today.
- **Done:** a program day on date D is done when a finished (completed, not discarded) session exists with `programUuid` = this program and `programDayLocalDate` = D. Starting the same day's workout again after finishing it is allowed and recorded the same way; the day is simply done.
- **Missed:** a day earlier in the current program week (from the most recent occurrence of `firstDayWeekday`, or `activatedLocalDate` if later, up to yesterday) whose scheduled workout is not done. Days before the program was activated are never missed. Today shows the most recent missed day as "Missed <weekday>: <workout>"; tapping it starts that workout with `programDayLocalDate` = the missed date, which marks it done. Older misses in the same week are reachable from the program screen. A new program week clears the line.
- **Outside the schedule:** a workout from My Plans, a template or Quick workout never marks a program day, even if it is the same exercises.
- **Day boundaries and time zones:** `programDayLocalDate` is captured once at session start from the local date. Travel or a time-zone change afterwards does not move it. A session started at 23:50 and finished after midnight counts for the start date.
- **Schedule edits:** do not rewrite `programDayLocalDate` on past sessions. A day becomes "done" only through its own sessions.

### 6.6 Timed sets in the logger

- The active workout screen shows a duration field (and a start/stop timer that fills it) for `duration` and `duration_load` exercises, and never a reps field for them. Plan targets show "3 × 45 s".
- Previous-set hints, history detail, progress and export show seconds for timed sets.
- Muscle recovery counts a completed timed set as one working set at the default effort; it contributes no load volume.

### 6.7 Screens (built on the existing component kit, no new tabs)

- **Train:** keeps "Start training", "Your plans" and recovery. Adds a "Library" entry leading to a library screen with three segments: Programs, Workouts, Exercises. Each has search and filters (goal, level, equipment, days per week where relevant) using kit chips and sheets.
- **Program detail:** description, level, days per week, session length, equipment, the 7-day week, and each day's exercises with sets, reps or seconds, and rest. Action: "Add program" (asks for the first weekday and whether to make it active).
- **Template detail:** same prescription list; actions "Start now" and "Copy to My Plans".
- **Exercise detail:** muscles (with the body map highlighting primary and secondary), equipment, cues.
- **Today:** active program card with today's workout or rest day, the missed line, and Start.
- **My program:** schedule view and editing, archive, switch active.
- All screens: light and dark, text scaling, narrow phones and tablet split view, reduced motion, screen-reader labels. Layout follows `prototypes/performance-v2/` and `docs/DESIGN_SYSTEM.md`; missing kit pieces are added to `core/design/` first in their own small change.

## 7. Content

- All text is written fresh for BeyondRep. A public-domain exercise list may be used only as a checklist of what to cover, after its licence is confirmed and recorded in `PROVENANCE.md`. No images, animations or copied cues.
- Exercises: about 200 to 300 across barbell, dumbbell, machine, cable, bodyweight, band, kettlebell and home equipment, added over stages.
- Programs: start from the issue's suggested list and drop or merge any that cannot be done well. Prescriptions follow conservative, widely accepted programming (for example beginner programs at moderate volume with clear rep ranges and longer rests for compound lifts). No outcome claims ("gain X kg").
- Owner review: every template and program change is a PR the owner reads and approves before the publish job runs. The validator enforces structure; only the owner signs off on training content.

## 8. Stages

Each stage is one or more small PRs, independently verifiable, in this order. Server-side changes deploy (manual Codemagic job) before an app build depends on them.

1. **Catalogue backbone.** ADR-0010 (shared reference content from Supabase, phone cache outside account storage), `catalog/` format and JSON Schema, validator, build script and CI, migration with tables, functions, grants and pgTAP tests, hosted RLS harness checks, publish and rollback job, `docs/CATALOG.md`. Starter content: the 18 existing exercises with specific muscles, aliases and cues; no templates or programs yet.
2. **Phone catalogue cache.** `features/catalog/`, manifest check, download, validation, atomic swap, freshness, coalescing, retry state, schema compatibility; exercise picker shows catalogue plus local; materialization on add.
3. **Specific muscles.** Additive ObjectBox fields, sync contract and server change for exercise muscles, session snapshots, recovery and "Better fit today" using primary and secondary muscles with legacy fallback, body map on exercise detail.
4. **Timed sets.** Sync contract and server change for `duration_seconds`, ObjectBox fields, logger UI, plan editor duration targets, progress, export, restore, conflict review. Catalogue schema bump for timed prescriptions.
5. **Exercise content.** Expand to about 200 to 300 exercises in reviewed batches; search and filter polish.
6. **Workout templates.** Template content (owner-reviewed), library Workouts segment, template detail, start now, copy to My Plans with double-submit protection.
7. **Programs.** Local program entities, atomic import, active program, schedule editing, Programs segment and detail, program content (owner-reviewed, may ship in batches).
8. **Today and scheduling.** Today card, missed line, done rules, day-boundary handling, remaining filters (goal, level, equipment, frequency).
9. **Release verification.** Security review of the catalogue API, performance measurements (first download size and time, cache load, search), physical iOS and Android devices, tablet, accessibility, process death. Rows added to `docs/RELEASE.md`.

## 9. Testing

- **Validator and build:** unit tests for each rejection rule; determinism (same input, same SHA-256).
- **Backend:** pgTAP for grants, RLS, immutability, pointer flip and rollback; contract fixtures for both sync additions; progress aggregation with timed sets; hosted harness checks.
- **Catalogue repository:** fake transport and temp directory tests for first download, no-op refresh on same release, new release swap, checksum mismatch, invalid references, unsupported schema, timeout, offline, interrupted write (stale `.tmp`), corrupt cache, concurrent refreshes sharing one request, forced retry, account switch keeping the shared cache.
- **Materialization and copies:** template copy and program import are atomic under injected failures at each step; double-submit returns one copy; deliberate second copy creates a new plan; catalogue refresh or rollback leaves plans, programs and sessions unchanged; retired exercise still works in an existing plan.
- **Schedule:** done, missed, rest day, repeated session, out-of-schedule workout, session across midnight, time-zone change, schedule edit after sessions, program switch.
- **Timed sets:** engine logs seconds, never reps; previous-set hints; export and restore round trip; recovery weight.
- **Recovery:** specific muscles with secondary fraction; legacy coarse sessions unchanged.
- **Regression:** existing workout, plan editor, recovery, progress, sync, restore and design-kit guard tests pass.
- **Widgets:** library segments, filters, empty, loading, unavailable and outdated-app states, detail screens, Today card, light and dark, large text.
- **ObjectBox:** old-database migration test for every additive field and entity.

## 10. Constraints

- AGENTS.md: feature-first Riverpod, repositories isolate ObjectBox and Supabase, component kit only, data ownership rules, durable write contract for the sync changes, public-repo secret rules (no project ref, keys or real data in `catalog/`, docs or tests).
- Supabase free plan: the project can pause; the phone treats that like offline. Bandwidth per release is roughly users times snapshot size; the manifest URL allows moving the file to Storage or a CDN later.
- Codemagic: one new manual workflow, existing credential group, no automatic trigger.
- No catalogue metadata or program ID becomes a dependency for restoring workout history.

## 11. Left to the builder

- File split inside `catalog/`, exact field names where marked, secondary-muscle fraction (start at 0.5), timeouts, snapshot size warning limit.
- Whether bodyweight exercises get a separate `reps` mode or use `reps_load` without load.
- Exact library layout within the existing Train patterns and design system.
