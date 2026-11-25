# Training library stage 4: timed sets, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Timed exercises (plank, side plank, holds) are logged as seconds end to end: the logger shows a seconds field with a start/stop timer and never a reps field, plans can target seconds ("3 × 45 s"), and the seconds survive sync, restore, export, history, progress and recovery.

**Architecture:** Server first: `validate_workout_v1` accepts an optional `duration_seconds` on each set, a completed set needs reps or seconds, and only rep sets add loaded volume. Phone: additive ObjectBox fields on sets and plan rows. The exercise definition's `inputMode` (fixed per ID forever, spec 4.4) decides whether an exercise is timed, so no mode snapshot is added. The repository enforces the mode, the outbox sends the new key only when it is set, restore reads it back, and the UI renders seconds wherever it rendered reps.

**Tech Stack:** PostgreSQL/pgTAP (Supabase CLI 2.81.3), Flutter 3.47.7, ObjectBox 5 codegen, Riverpod 3.

**Spec:** `docs/superpowers/specs/2026-11-25-training-library-design.md` sections 4.3, 5.4 (set half), 6.4 (`durationSeconds`, `targetDurationSeconds`), 6.6, 8 stage 4, 9 (timed sets). Also `docs/OBJECTBOX.md`, `docs/CLOUD_SYNC.md`, `docs/SYNC_PROTOCOL.md`. Executors read them.

## Decisions this plan makes

- **Scope is the `duration` mode only.** `duration_load` (weighted carries) and bodyweight `reps` stay unloggable and hidden by `loggableModes`, as today. The server still accepts `load_grams` beside `duration_seconds`, so `duration_load` later needs no migration, but no load is counted as volume without reps.
- **A set carries reps or seconds, never both.** The server, the restore parser and `WorkoutSetRecord.validate` reject both. A completed set needs one of them plus its completion time.
- **Payload omission rule:** `duration_seconds` is sent only when non-null, so every rep set keeps exactly today's payload and request hash. `schema_version` stays 1.
- **Mode source:** the session exercise's definition (`definitionUuid` → `inputMode`). If the definition is missing locally (a restored workout from another device), a set that already has seconds is shown as timed.
- **The stopwatch is a draft, like typed values.** It is not checkpointed. Leaving the screen or a process death loses a running timer, and the user can still type the seconds. Recording a set saves the field's value through the normal durable path.
- **No catalogue schema bump in this stage.** Templates and programs reach the app first in stage 6, and every build that reads them will already log seconds, so older builds can never receive a timed prescription. `docs/CATALOG.md` records this. (The spec listed a bump under stage 4. It is not needed because no shipped build reads templates.)
- **Old plank sets stored as reps stay as they are** (owner's decision, 2026-11-25). Nothing is migrated.
- **Deploy order:** the migration goes to hosted Supabase (owner runs `supabase-database`) **before** any TestFlight build with Task 4. Older builds reject the unknown `duration_seconds` key when restoring (same as stage 3, owner accepted), so every TestFlight install is updated after this ships.

## Running checks

These are the same as stage 3. From `apps/mobile/`, run `dart format --output=none --set-exit-if-changed lib test`, then `flutter analyze`, then `flutter test`. For ObjectBox codegen, run `dart run build_runner build --delete-conflicting-outputs`, then commit `lib/objectbox.g.dart` and `lib/objectbox-model.json`. For SQL, run `supabase db reset && supabase test db`. If Docker is unavailable, use the Postgres 16 stand-in from stages 1 to 3 and say so in the PR. The `database` GitHub job is then the first real run.

## Global Constraints

- `duration_seconds` / `durationSeconds` on a set: integer 1 to 86,400.
- `targetDurationSeconds` on a plan row: integer 1 to 3600 (the catalogue's prescription range).
- Seconds display, through one helper: under 60 shows "45 s". 60 and over shows "1 min", or "1 min 30 s" when there are leftover seconds.
- ObjectBox: additive properties only, stable UIDs kept, generated files committed, and an old-database migration test (pattern: `test/workouts/fixtures/objectbox_pre_muscles.g.dart`).
- Durable write contract unchanged: the set, session revision and checkpoint still commit in one transaction; the outbox payload is built once at enqueue.
- AGENTS.md design-kit rules (no raw dialogs, sheets, snackbars, chips or text fields in features). Light and dark, text scale 2.0 at 390 × 844, screen-reader labels, reduced motion.
- Public repo: synthetic data only.

## Review Focus

1. **A rep workout logged before or after this change** uploads with no `duration_seconds` key and an unchanged request hash, and restores unchanged (Task 4).
2. **Reps typed for a timed exercise, or seconds for a rep exercise** (a stale widget, a tampered payload, a restored row) are rejected by the repository, server or restore parser. They are never stored half-converted (Tasks 1, 3 and 4).
3. **A timed set with a load** (the server allows it for later `duration_load`) must not make server or phone volume null or wrong. Volume counts only sets with reps (Tasks 1 and 5).
4. **Stopwatch edge cases:** stop after under 1 second records 1 s, never 0. A running timer on one set does not block saving other sets. A set saved while its timer runs saves the elapsed value shown (Task 6).
5. **Mixed plan:** squats and a plank in one plan editor and one session. Each row shows its own fields and targets, and "Use previous" fills the right field (Tasks 6 and 7).

---

### Task 1: Server accepts timed sets

**Files:**
- Create: `supabase/migrations/20261126020000_workout_set_duration.sql`, `supabase/tests/workout_timed_sets.test.sql`

**Interfaces:**
- Produces: `northstar_private.validate_workout_v1(uuid, jsonb)` redefined with `create or replace` from its **latest** body (`20261126010000_workout_exercise_muscles.sql`, confirm nothing later redefines it). Changes:
  - Add `'duration_seconds'` to `v_allowed_set`. When present and not null, it must be a JSON number matching `^[0-9]+$`, between 1 and 86400; otherwise `raise exception 'invalid set duration' using errcode='22023'`.
  - A set with non-null `reps` and non-null `duration_seconds` raises `'set has both reps and duration'` (22023).
  - The completed rule becomes: `completed_at_utc` is a string, and either `reps` or `duration_seconds` is a number. Otherwise raise `'completed set needs reps or duration and time'` (22023).
  - Working-set counting: every completed working set increments `v_working` (timed sets included). `v_loaded` and `v_volume` change only when `reps` is a number and `load_grams` > 0.
  - Re-issue the function's grants exactly as the previous migration does.

- [ ] **Step 1: Write failing pgTAP** in the style of `workout_muscles.test.sql`:
  - A completed set with `duration_seconds: 45` and no reps syncs, and the stored payload keeps it.
  - Rejected with 22023: 0, 86401, `"45"` (a string), 45.5, both reps and seconds, and a completed set with neither.
  - `get_workout_progress` for a workout with one timed and one loaded rep working set reports `completed_working_sets` = 2 and volume equal to the rep set's load × reps.
  - A timed set with `load_grams: 20000` syncs, and the volume is still only the rep set's.
- [ ] **Step 2: Run** `supabase db reset && supabase test db`. Expected: the timed cases FAIL (unknown key).
- [ ] **Step 3: Write the migration.**
- [ ] **Step 4: Run** again. Expected: every test file PASSES, including `workout_sync`, `workout_progress` and `workout_muscles`.
- [ ] **Step 5: Commit** `feat(supabase): accept timed sets with duration_seconds`

### Task 2: Seconds in the local model

**Files:**
- Modify: `apps/mobile/lib/features/workouts/data/workout_entities.dart` (`WorkoutSetEntity.durationSeconds` int?, `PlanExerciseEntity.targetDurationSeconds` int?), `lib/features/workouts/domain/workout_models.dart` (`WorkoutSetRecord.durationSeconds`), `lib/features/workouts/domain/workout_library_models.dart` (`PlanExerciseRecord.targetDurationSeconds`, kept by `withPosition`), the entity/record mappers in `objectbox_workout_repository.dart`, `objectbox_workout_library_repository.dart` and `progress/data/objectbox_workout_history_repository.dart`, plus the generated files
- Create: `lib/features/workouts/domain/durations.dart`, `test/workouts/fixtures/objectbox_pre_duration.g.dart` (copy of the current `lib/objectbox.g.dart`), `test/workouts/objectbox_duration_migration_test.dart`
- Test: `test/workouts/workout_domain_test.dart`

**Interfaces:**
- Produces `String formatDurationSeconds(int seconds)` in `durations.dart`. Global Constraints define the output.
- `WorkoutSetRecord.validate()` additions:
  - `durationSeconds` outside 1 to 86400 throws `ArgumentError.value(durationSeconds, 'durationSeconds')`.
  - Both reps and seconds present throws.
  - A completed set needs `completedAtUtc` and one of reps or seconds. This replaces "requires reps".
- `PlanExerciseRecord.validate()` additions: `targetDurationSeconds` outside 1 to 3600 throws, and so does a seconds target together with any reps target.

- [ ] **Step 1: Write failing tests**:
  - `formatDurationSeconds`: 1 → "1 s", 45 → "45 s", 60 → "1 min", 90 → "1 min 30 s", 3600 → "60 min".
  - Validate accepts a completed set with seconds only, and rejects each new rule.
  - Plan row validation, both cases.
  - Migration test: open a store with the pre-duration fixture, write a set and a plan row, reopen with the new model, read null fields, write values and read them back.
- [ ] **Step 2: Run** `flutter test test/workouts/workout_domain_test.dart test/workouts/objectbox_duration_migration_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the fields, the mappers and the helper, then run codegen.
- [ ] **Step 4: Run** those tests, then `flutter test test/workouts test/progress test/sync`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(workouts): store set seconds and plan seconds targets`

### Task 3: The repository enforces the mode

**Files:**
- Modify: `lib/features/workouts/data/objectbox_workout_repository.dart` (`saveSet`), `lib/features/workouts/data/objectbox_workout_library_repository.dart` (`savePlan`)
- Test: `test/workouts/objectbox_workout_repository_test.dart`, `test/workouts/objectbox_workout_library_repository_test.dart`

**Interfaces:**
- `saveSet` rule: inside its transaction, read the session exercise's definition (by `definitionUuid`).
  - If its `inputMode` is `duration`, a set with reps throws `ArgumentError('Timed exercise takes seconds, not reps')`.
  - If the mode is anything else, a set with seconds throws `ArgumentError('Rep exercise takes reps, not seconds')`.
  - A missing definition allows either. Nothing is written on a throw.
- `savePlan` rule: a row whose definition is `duration` may not carry reps targets, and a row of any other mode may not carry `targetDurationSeconds`. A violation throws `ArgumentError` before anything is written.

- [ ] **Step 1: Write failing tests** with the seeded `builtin.v1.plank` (mode `duration`) and a squat:
  - A plank set with 45 seconds saves, and reading it back gives 45.
  - A plank set with reps throws, and the session revision is unchanged.
  - A squat set with seconds throws.
  - A custom exercise (`reps_load`) set with seconds throws.
  - `savePlan` with a plank row targeting 45 s saves.
  - A plank row with reps targets throws, and so does a squat row with seconds.
- [ ] **Step 2: Run** those files. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/workouts`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(workouts): enforce seconds for timed exercises and reps for the rest`

### Task 4: Sync, restore and export carry seconds

**Files:**
- Modify: `lib/features/workouts/data/objectbox_workout_outbox.dart`, `lib/features/sync/workout_restore_feed.dart`, `lib/features/sync/objectbox_workout_restore_importer.dart`
- Test: `test/workouts/objectbox_workout_outbox_test.dart`, `test/sync/workout_restore_feed_test.dart`, `test/sync/objectbox_workout_restore_importer_test.dart`, `test/account/workout_history_export_test.dart`

**Interfaces:**
- The outbox mirrors the server rules in its local check, and adds `'duration_seconds': set.durationSeconds` to a set row **only when non-null**.
- The restore feed adds `duration_seconds` to `_setFields` and parses it with `_integer(..., max: 86400)`. Below 1, a non-integer, or a value next to reps fails with code `invalid_set_duration`. The completion check becomes reps or seconds. The importer writes `durationSeconds`.
- Export passes server payloads through unchanged (verify only; change nothing unless the test fails).

- [ ] **Step 1: Write failing tests**:
  - The outbox payload for a completed plank set has `duration_seconds: 45` and no `reps` value.
  - The payload and request hash of an all-rep workout are byte-identical to a fixture captured from today's code. Capture it first.
  - Restore round-trips a timed set, and conflict review then shows the cloud copy's set count.
  - Restore rejects 0, 86401, `45.5`, `"45"` and reps-plus-seconds with `invalid_set_duration`, and imports nothing from that page.
  - The export of a stored payload with `duration_seconds` contains it.
- [ ] **Step 2: Run** those files. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/workouts test/sync test/account`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(sync): send, restore and export set seconds`

### Task 5: History, progress and recovery count timed sets

**Files:**
- Modify: `lib/features/progress/domain/workout_history_models.dart` (summary), `lib/features/progress/workout_history_detail_page.dart` (set line), `lib/features/progress/muscle_recovery.dart` (comment only, if the test passes unchanged)
- Test: `test/progress/workout_history_models_test.dart`, `test/progress/muscle_recovery_test.dart`, the history detail widget test that covers set lines

**Interfaces:**
- Summary:
  - A completed working set with seconds counts in `completedWorkingSets`.
  - It counts in none of `loaded`, `unloaded` or `zeroLoad`, and adds no volume or strength-trend point.
  - Volume and trends use only sets with reps, which is unchanged.
- History detail line for a timed set: `formatDurationSeconds(s)` plus the existing effort suffix, for example "45 s · RPE 8". No "reps" and no load.
- Recovery: a completed timed working set counts as one set with a reps factor of 1.0 at its RPE effort (today's code already does this when reps is null, so the test pins it).

- [ ] **Step 1: Write failing tests**:
  - A session with one plank set (45 s) and one squat set (100 kg × 5) gives 2 working sets, 1 loaded set, volume 500,000 gram-reps and one trend (squat).
  - The detail page shows "45 s".
  - Recovery from one plank set equals recovery from one set with reps null at the same RPE.
- [ ] **Step 2: Run** them. Expected: the summary and detail tests FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/progress`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(progress): count timed sets and show their seconds`

### Task 6: The logger records seconds with a timer

**Files:**
- Create: `lib/features/train/timed_sets.dart`
- Modify: `lib/features/train/active_workout_page.dart` (`_ExerciseCard`, `SetEditorTile`)
- Test: `test/train/timed_set_logging_test.dart` (new), `test/train/active_workout_widget_test.dart`, `test/train/set_editor_safety_widget_test.dart`

**Interfaces:**
- Produces, in `timed_sets.dart`: `bool isTimedExercise(WorkoutExerciseRecord exercise, List<WorkoutSetRecord> sets, Map<String, ExerciseRecord> definitions)`. It returns true when the definition's `inputMode == 'duration'`, or when the definition is missing and any set has `durationSeconds`.
- `_ExerciseCard` reads definitions from `trainLibraryProvider` and passes `timed` to each `SetEditorTile`. A timed card's headers are SET, PREVIOUS, TIMER and SEC. The load column holds a start/stop icon button, and the reps column holds the seconds field (key `seconds-<setUuid>`).
- Stopwatch: record a wall-clock start; a 1 s `Timer.periodic` writes the elapsed whole seconds into the seconds field while running. Stop keeps the value (minimum 1). Tooltips: "Start timer for set N" and "Stop timer for set N". The timer is cancelled on dispose. There is no animation, so reduced motion needs nothing extra.
- Recording a timed set saves `durationSeconds` from the field (1 to 86400; otherwise the existing "check the values" error) with reps and load null. "Use previous" fills seconds. The previous hint text is `formatDurationSeconds`.

- [ ] **Step 1: Write failing widget tests** with a fake clock or `tester.pump(Duration)`:
  - A plank card shows TIMER and SEC, has no reps field, and has no load field.
  - Typing 45 and recording saves a set with `durationSeconds` 45 and reps null.
  - Start, pump 3 s, then stop fills "3".
  - Starting and stopping within the same second records 1.
  - Recording while the timer runs saves the shown value and stops it.
  - "Use previous" from a 45 s set fills 45.
  - A squat card in the same session is unchanged.
  - Text scale 2.0 at 390 × 844 in light and dark gives no overflow.
- [ ] **Step 2: Run** `flutter test test/train/timed_set_logging_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/train test/design_kit_guard_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): log timed sets with a seconds field and stopwatch`

### Task 7: Plans target seconds

**Files:**
- Modify: `lib/features/train/plan_editor_page.dart` (`_addExercise`, `_editTargets`, target label)
- Test: `test/train/plan_builder_widget_test.dart`

**Interfaces:**
- Adding a `duration` exercise sets `targetDurationSeconds: 30` with no rep targets.
- Its target dialog shows one "Seconds per set" `NsTextField` (1 to 3600) in place of the min and max reps fields. Sets, rest and notes are unchanged.
- The row label reads " · 45 s" through `formatDurationSeconds`, so the row shows "3 × 45 s" style text.
- Rep exercises are unchanged.

- [ ] **Step 1: Write failing tests**:
  - Adding a plank gives a row reading "45 s" after editing seconds to 45.
  - Saving persists `targetDurationSeconds` 45.
  - An empty or 0 value shows the existing validation error.
  - A squat row still edits reps.
- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/train`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): plan targets in seconds for timed exercises`

### Task 8: Docs and release rows

**Files:**
- Modify: `docs/SYNC_PROTOCOL.md` (cloud payload section: `duration_seconds`, its range, the reps-or-seconds rule and the omission rule), `docs/CATALOG.md` (the no-schema-bump decision above), `docs/RELEASE.md` (device rows: log a plank with the timer on iOS and Android, background the app with a timer running, restore a timed workout on a second device, update every TestFlight install), `docs/ROADMAP.md` (stage 4 implemented in source, not released or device-verified), `CLAUDE.md` project-state line for the training library if one exists (check, then update the stage list only)

- [ ] **Step 1:** Write the doc changes.
- [ ] **Step 2: Run** the full set: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, and from the repo root `python3 -m unittest discover -s tool -p 'test_*.py'`. Expected: all PASS.
- [ ] **Step 3: Commit** `docs: timed sets in the sync protocol, catalogue and release checklist`
