# Training library stage 3: specific muscles drive recovery, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exercises carry primary and secondary muscles from the catalogue; each logged workout keeps a snapshot of them that syncs and restores; muscle recovery, "Better fit today" and the body map use them (secondary at half weight), while older workouts and custom exercises keep today's coarse-group behaviour.

**Architecture:** Server first: `validate_workout_v1` accepts two optional arrays on each exercise. Phone: additive ObjectBox list properties on exercise definitions and session exercises; the catalogue fills definitions (including a backfill for the 18 seeded built-ins); session start copies them; the outbox sends them only when non-empty; restore reads them; recovery computes per drawn muscle for exercises that have them and falls back to the group mapping otherwise. A new exercise detail screen shows the muscles on the existing body map.

**Tech Stack:** PostgreSQL/pgTAP (Supabase CLI 2.81.3), Flutter 3.47.7, ObjectBox 5 codegen, Riverpod 3.

**Spec:** `docs/superpowers/specs/2026-11-25-training-library-design.md` sections 4.2, 5.4 (exercise half), 6.4, 6.7 (exercise detail), 8 stage 3. Also `docs/CATALOG.md`, `docs/OBJECTBOX.md`, `docs/CLOUD_SYNC.md`. Executors read them.

## Decisions this plan makes

- **Payload fields** on each exercise: `primary_muscles` and `secondary_muscles`, arrays of the 14 muscle names. Sent **only when the snapshot has at least one primary muscle**, so workouts of custom or legacy exercises keep exactly today's payload. `schema_version` stays 1.
- **Deploy order:** the migration must be deployed (owner runs the `supabase-database` job) **before** any app build containing Task 5 is uploaded. Older app builds reject unknown fields when restoring, so every TestFlight install should be updated after this ships (no real users yet; the owner accepted this).
- **Seeded built-ins get muscles** through a backfill whenever the catalogue snapshot is ready, not only when picked, so existing plans of the 18 built-ins benefit immediately.
- **Custom exercises stay coarse** (no muscle picker for custom exercises in this stage).
- **Recovery weights:** primary 1.0, secondary 0.5 (`secondaryMuscleWeight`). Small-muscle window 48 h for `shoulders, biceps, triceps, forearms, abs, obliques, calves`; others 72 h. Same stimulus formula as today.

## Running checks

From `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`. ObjectBox codegen: `dart run build_runner build --delete-conflicting-outputs`; commit `lib/objectbox.g.dart` and `lib/objectbox-model.json`. SQL: `supabase db reset && supabase test db` (CLI 2.81.3, Docker). If Flutter or the Supabase stack cannot run in the environment, follow the same fallback as stages 1 and 2 and say so in the PR; the `mobile` and `database` GitHub jobs are then the first runs.

## Global Constraints

- Muscle vocabulary (exact strings, the Dart `Muscle` enum names): `chest, shoulders, biceps, forearms, abs, obliques, quads, calves, traps, lats, lowerBack, triceps, glutes, hamstrings`.
- Display names: Chest, Shoulders, Biceps, Forearms, Abs, Obliques, Quads, Calves, Traps, Lats, Lower back, Triceps, Glutes, Hamstrings.
- Arrays: each at most 14 entries, no duplicates, no muscle in both lists, `primary` non-empty whenever `secondary` is non-empty.
- ObjectBox: additive properties only, stable UIDs kept, generated files committed, old-database migration test added (follow `test/workouts/fixtures/objectbox_pre_*.g.dart` pattern).
- Durable write contract unchanged: session exercise rows and outbox entries still commit atomically as today.
- AGENTS.md design kit rules; no raw dialogs, sheets, snackbars or chips in features.
- Public repo: synthetic data only in tests and fixtures.

## Review Focus

1. **A workout logged before this change** (empty muscle snapshots) must upload with no new keys, restore unchanged, and keep coarse recovery (Tasks 4 to 6).
2. **A malformed array from the server or a tampered payload** (unknown muscle, duplicates, overlap, wrong type, 15 entries) is rejected by the server and by the restore parser, never partially imported (Tasks 1 and 5).
3. **Mixed session** with a catalogue exercise and a custom "Legs" exercise: both contribute, a drawn muscle takes the larger of its fine and coarse values, no double counting within the fine path (Task 6).
4. **Backfill must not overwrite custom rows or change modes**, and must be idempotent across launches (Task 3).
5. **Plan fit with a plan of built-ins whose definitions were backfilled**: "recovering" names specific muscles (for example "Hamstrings") instead of "Legs" and suggestion logic still works when nothing is recovering (Task 6).

---

### Task 1: Server accepts muscle arrays

**Files:**
- Create: `supabase/migrations/20261126010000_workout_exercise_muscles.sql`
- Modify: `supabase/tests/workout_sync.test.sql` (or create `supabase/tests/workout_muscles.test.sql`; prefer a new file to keep plan counts simple)

**Interfaces:**
- Produces: `northstar_private.validate_workout_v1(uuid, jsonb)` redefined with `create or replace`, starting from its **latest** body (in `20261025090000_phase2_completed_only_scope.sql`; confirm no later migration redefines it), with `v_allowed_exercise` extended by `'primary_muscles','secondary_muscles'` and these checks when the keys are present: JSON array; ≤ 14 elements; every element a string in the vocabulary; no duplicates; no element in both arrays; `secondary_muscles` present and non-empty only if `primary_muscles` is non-empty. Error: `raise exception 'invalid exercise muscles' using errcode = '22023'`. Keep the function's existing grants/revokes exactly (re-issue them after `create or replace` as the original migration does).

- [ ] **Step 1: Write failing pgTAP** following `workout_sync.test.sql` style (synthetic users, `sync_workout` calls as `authenticated`): a payload with valid arrays syncs and the stored `payload` contains them; a payload without them still syncs; one case each for unknown muscle, duplicate, overlap, non-array, non-string element, 15 elements, secondary without primary → `22023`.
- [ ] **Step 2: Run** `supabase db reset && supabase test db`. Expected: the new valid-arrays case FAILS (unknown key rejected).
- [ ] **Step 3: Write the migration.**
- [ ] **Step 4: Run** again. Expected: all test files PASS.
- [ ] **Step 5: Commit** `feat(supabase): accept primary and secondary muscles on synced exercises`

### Task 2: Muscle fields in the local model

**Files:**
- Create: `apps/mobile/lib/features/workouts/domain/muscles.dart`
- Modify: `lib/features/workouts/data/workout_entities.dart` (`ExerciseDefinitionEntity`: `List<String> primaryMuscles`, `List<String> secondaryMuscles`; `WorkoutExerciseEntity`: `List<String> primaryMusclesSnapshot`, `List<String> secondaryMusclesSnapshot`; all default empty), `lib/features/workouts/domain/workout_library_models.dart` (`ExerciseRecord.primaryMuscles`, `.secondaryMuscles`, default `const []`), `lib/features/workouts/domain/workout_models.dart` (`WorkoutExerciseRecord.primaryMusclesSnapshot`, `.secondaryMusclesSnapshot`, default `const []`), the entity/record mappers in `objectbox_workout_library_repository.dart`, `objectbox_workout_repository.dart`, `progress/data/objectbox_workout_history_repository.dart`, generated `lib/objectbox.g.dart`, `lib/objectbox-model.json`
- Test: `test/workouts/muscles_test.dart`, `test/workouts/objectbox_muscle_migration_test.dart`

**Interfaces:**
- Produces in `muscles.dart`: `const muscleVocabulary = <String>{...}` (the 14 names); `String muscleDisplayName(String name)`; `({List<String> primary, List<String> secondary})? validMuscles(List<String> primary, List<String> secondary)` returning `null` when invalid by the Global Constraints rules, else the lists in their given order.
- `Muscle` enum (progress) stays the drawing enum; add `Muscle? muscleFromName(String name)` next to it.

- [ ] **Step 1: Write failing tests**: `validMuscles` accepts a valid pair, rejects each invalid rule; `muscleDisplayName('lowerBack') == 'Lower back'`; every vocabulary name maps to a `Muscle` value; migration test: open a store created with the current committed model fixture (copy `lib/objectbox.g.dart` before the change into `test/workouts/fixtures/objectbox_pre_muscles.g.dart`, same pattern as the existing pre-* fixtures), write a definition and a session exercise, reopen with the new model, read empty muscle lists, write lists, read them back.
- [ ] **Step 2: Run** `flutter test test/workouts/muscles_test.dart test/workouts/objectbox_muscle_migration_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the fields, mappers and helpers; run codegen.
- [ ] **Step 4: Run** those tests and `flutter test test/workouts test/progress test/sync`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(workouts): store primary and secondary muscles on definitions and session exercises`

### Task 3: Catalogue fills muscles on local definitions (including a backfill)

**Files:**
- Modify: `lib/features/workouts/domain/workout_library_repository.dart`, `.../data/objectbox_workout_library_repository.dart`, `lib/features/train/exercise_picker_sheet.dart`, `lib/features/catalog/application/catalog_refresh_host.dart` (or a new small `catalog_definition_sync.dart` in the same folder)
- Test: `test/workouts/objectbox_workout_library_repository_test.dart`, `test/catalog/catalog_definition_sync_test.dart`

**Interfaces:**
- `materializeCatalogExercise` gains `required List<String> primaryMuscles, required List<String> secondaryMuscles`. Rule change: an existing built-in row is updated when `catalogVersion < release` **or** its `primaryMuscles` is empty; mode rules unchanged.
- New: `int syncCatalogDefinitions(List<CatalogDefinitionInput> items, int release)` on the library repository, where `CatalogDefinitionInput` is a record typedef in `workout_library_models.dart`: `({String id, String name, String muscleGroup, String equipment, String category, String mode, List<String> primaryMuscles, List<String> secondaryMuscles})`. In one write transaction it updates only **existing** `builtin.v1.` rows whose id is in `items` and which need it by the rule above; it never inserts, never touches custom rows, never changes mode (skips a row whose mode differs). Returns the number updated.
- Wiring: whenever `catalogStateProvider` has a snapshot (on load and after `updated`), call `syncCatalogDefinitions` with its active exercises (labels via `equipmentLabel`/`categoryLabel`), then `ref.invalidate(trainLibraryProvider)` if the count is > 0. Runs inside the account scope only.
- Picker passes the choice's muscles.

- [ ] **Step 1: Write failing tests**: materialize fills muscles on a seeded squat at release 1; materialize same release with muscles already set writes nothing; `syncCatalogDefinitions` updates seeded rows, ignores ids not present locally (no insert), ignores custom rows, skips a mode mismatch, is idempotent (second call returns 0); widget/provider test: a ready snapshot triggers the sync once and the library shows muscles.
- [ ] **Step 2: Run** `flutter test test/workouts/objectbox_workout_library_repository_test.dart test/catalog/catalog_definition_sync_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** plus `flutter test test/train test/catalog`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(catalog): fill specific muscles on local built-in exercises`

### Task 4: Session snapshots copy muscles

**Files:**
- Modify: `lib/features/workouts/data/objectbox_live_workout_engine.dart` (~line 172), `lib/features/train/active_workout_state.dart` (~line 133), any other `WorkoutExerciseRecord(`/`WorkoutExerciseEntity(` construction from a definition (grep)
- Test: `test/workouts/objectbox_live_workout_engine_test.dart`, `test/train/active_workout_widget_test.dart`

- [ ] **Step 1: Write failing tests**: starting a plan whose exercise definition has muscles snapshots them on the session exercise; adding an exercise mid-workout does the same; a custom exercise snapshots empty lists; later editing the definition's muscles does not change an existing session's snapshot.
- [ ] **Step 2: Run** those files. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(workouts): snapshot muscles when an exercise joins a workout`

### Task 5: Upload, restore and export carry muscles

**Files:**
- Modify: `lib/features/workouts/data/objectbox_workout_outbox.dart` (payload builder ~line 383 and local validation ~line 333), `lib/features/sync/workout_restore_feed.dart` (`_exerciseFields`, parse ~line 384), `lib/features/sync/objectbox_workout_restore_importer.dart` (~line 1009), `docs/SYNC_PROTOCOL.md` (new "Cloud workout payload" section listing every exercise and set field, including the two new optional arrays and the omission rule), `docs/CLOUD_SYNC.md` (short pointer)
- Test: `test/workouts/objectbox_workout_outbox_test.dart`, `test/sync/` restore feed and importer tests, `test/account/` export test if it asserts payload keys

**Interfaces:**
- Outbox adds `'primary_muscles'` and `'secondary_muscles'` only when `primaryMusclesSnapshot` is non-empty; local validation uses `validMuscles` and throws `StateError('Invalid exercise for cloud backup')` when invalid.
- Restore accepts the two optional keys, validates with `validMuscles` (invalid → the parser's existing invalid path with code `invalid_exercise_muscles`), and maps them to the snapshot fields; absent → empty lists.
- Export passes the server payload through; confirm with a test that the arrays survive.

- [ ] **Step 1: Write failing tests**: payload includes arrays for a catalogue exercise and omits both keys for a custom/legacy one (assert exact key set); invalid local snapshot blocks upload with the existing error; restore round-trip (payload → parse → import → `WorkoutExerciseRecord` has the lists); restore rejects unknown muscle, duplicate, overlap, wrong type; legacy payload without keys restores with empty lists; export keeps the arrays.
- [ ] **Step 2: Run** the affected test files. Expected: FAIL.
- [ ] **Step 3: Implement** and write the docs.
- [ ] **Step 4: Run** `flutter test test/workouts test/sync test/account`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(sync): upload and restore exercise muscle snapshots`

### Task 6: Recovery and plan fit use specific muscles

**Files:**
- Modify: `lib/features/progress/muscle_recovery.dart`, `lib/features/train/plan_fit.dart`
- Test: `test/progress/` recovery tests, `test/train/plan_fit_test.dart`, `test/train/train_plan_fit_test.dart`

**Interfaces:**
- `MuscleRecovery.fromWorkouts` keeps its signature. New constant `const secondaryMuscleWeight = 0.5;` and small-muscle set as in Decisions.
- Algorithm per finished session within 72 h:
  - Fine path (exercise with non-empty `primaryMusclesSnapshot`): for each completed working set, add `_stimulus(set)` to each primary muscle and `secondaryMuscleWeight * _stimulus(set)` to each secondary muscle. Per muscle: `value = min(1, Σ / 10) * fade(muscle window)`. Across sessions sum and cap at 1 into `fine[muscle]`. Display entry in `groups` under `muscleDisplayName`.
  - Coarse path (empty snapshot): unchanged from today, producing `groups[groupName]` and the max-mapped muscle loads.
  - Final `load[muscle] = max(fine[muscle], coarseMapped[muscle])`.
- `planRecoveryOf`: for an exercise whose `ExerciseRecord.primaryMuscles` is non-empty, use those muscles (named with `muscleDisplayName`) instead of `muscleGroup`; secondary muscles are ignored for "recovering"; otherwise today's group logic.

- [ ] **Step 1: Write failing tests**:
  - RDL session (primary hamstrings, glutes; secondary lowerBack) loads hamstrings and glutes fully and lower back at half; quads stay 0.
  - Calves via a catalogue calf raise fade over 48 h; a legacy "Legs" session keeps calves on 72 h.
  - Legacy-only history gives exactly today's numbers (copy one existing expectation as a regression).
  - Mixed session (Review Focus 3).
  - Plan fit: a plan of backfilled built-ins reports "Hamstrings"/"Glutes" as recovering after an RDL day, "Chest" rested; legacy custom "Legs" exercise still reports "Legs".
  - Body map widget test: after an RDL session the hamstrings paint as worked and quads do not.
- [ ] **Step 2: Run** `flutter test test/progress test/train`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(progress): recovery from primary and secondary muscles`

### Task 7: Exercise detail screen

**Files:**
- Create: `lib/features/train/exercise_detail_page.dart`
- Modify: `lib/features/train/exercise_catalog_page.dart` (tapping a row opens the detail), `lib/app/beyondrep_app.dart` (route `/train/exercises/:id`, following existing route style)
- Test: `test/train/exercise_detail_page_test.dart`

**Interfaces:**
- Consumes: `exerciseChoicesProvider`, `MuscleMap` and `MuscleRecovery` (build a `MuscleRecovery` with primary muscles at 1.0 and secondary at 0.5 purely for drawing), `muscleDisplayName`, kit widgets.
- Shows: name, aliases, "Primary" and "Secondary" muscle lists, front and back body maps, equipment, category, mode ("Reps and weight" for `reps_load`, "Time" for `duration`), technique cues as a list. Custom exercises show group and equipment with the text `Custom exercise. Muscles aren't mapped yet.` Unknown id shows `This exercise isn't available.`

- [ ] **Step 1: Write failing widget tests**: catalogue exercise shows both muscle lists and cues; custom shows the custom text; unknown id; light and dark at 390×844 and text scale 2.0 without overflow; the Exercises page navigates to it.
- [ ] **Step 2: Run** `flutter test test/train/exercise_detail_page_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** plus `flutter test test/train test/design_kit_guard_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): exercise detail with muscles on the body map`

### Task 8: Docs and full checks

**Files:**
- Modify: `docs/ROADMAP.md` (stage 3 in source, not deployed), `docs/RELEASE.md` (rows: deploy migration before the build; update all TestFlight installs; recovery after an RDL day on device; restore on a second device keeps muscles), `docs/CATALOG.md` (definitions backfill), `docs/superpowers/specs/2026-11-25-training-library-design.md` 5.4 (payload omission rule)

- [ ] **Step 1: Run the full checks**: from `apps/mobile/` format, analyze, `flutter test`; from the root `python3 -m unittest discover -s tool -p 'test_*.py'`; `supabase db reset && supabase test db`. Expected: all pass.
- [ ] **Step 2: Commit** `docs: stage 3 muscles, deploy order and device checks`

## Out of scope

Muscle selection for custom exercises, timed sets (stage 4), more catalogue content (stage 5), recovery weighting by exercise category, and any change to server progress aggregation.
