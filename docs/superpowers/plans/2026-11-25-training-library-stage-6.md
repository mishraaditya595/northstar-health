# Training library stage 6: workout templates, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** About 16 owner-reviewed workout templates (push, pull, legs, upper, lower, full body, core, home, band, kettlebell and more) are published in catalogue release 3. Users can browse them on Train, open one to see every exercise with its sets, reps or seconds, and rest, and then either start a workout from it right away or copy it into My Plans as an editable plan.

**Architecture:** Templates already fit catalogue schema 1, and older builds ignore them. The phone parses them into typed models. Two new local-write paths reuse the existing ones:
- **Copy:** a library-repository method materializes the referenced exercises and creates the plan and its rows in **one** ObjectBox transaction. It is idempotent per request UUID.
- **Start:** a live-workout-engine method starts a session from in-memory plan rows, after the exercises have been materialized. It creates no saved plan.

The UI adds a "Workouts" entry on Train, a template list and a template detail screen built from existing kit components.

**Tech Stack:** JSON plus the Python validator and build, Flutter 3.47.7, ObjectBox 5, Riverpod 3, go_router.

**Spec:** `docs/superpowers/specs/2026-11-25-training-library-design.md` sections 4.4, 4.5, 6.2 (exercise materialization, copy template, start from template), 6.7 (template detail), 7, 8 (stage 6) and 9 (materialization and copies). Also read `docs/CATALOG.md`. Executors read them.

## Decisions this plan makes

- **No Library segmented screen yet.** The kit has no segmented control, and AGENTS.md forbids inventing one inside a feature. Train's "More ways to move" section gets a "Workouts" card next to "Exercise library". Stage 7 adds a "Programs" card the same way. A combined Library screen can come later if a kit segment control is added first in its own change.
- **Template list:** a search field and level chips (All, Beginner, Intermediate, Advanced). Goal, equipment and frequency filters stay in stage 8, as the spec orders. Templates with `standalone: false` are hidden.
- **Hide what the app can't log.** A template is hidden on the phone if any of its exercises has a mode outside `loggableModes`, or is missing or retired in the cached snapshot. The parser already rejects such references; this guard is for future modes.
- **Copy is one transaction, idempotent per request:**
  - `copyCatalogTemplate` materializes every exercise (the same rules as `materializeCatalogExercise`) and creates the plan and its rows in a single transaction.
  - The template screen creates a request UUID once per visit and uses it as the new plan's UUID. A second tap with the same UUID returns the existing plan.
  - After a copy finishes, the screen makes a new request UUID, so a deliberate second copy creates another plan. Its name gets " (2)", " (3)" and so on when an active plan already has the name.
  - The copied plan has no link back to the template (spec 6.2: copies are independent).
- **Prescription mapping:** `repsMin`/`repsMax` become `targetRepsMin`/`targetRepsMax`. `durationSeconds` becomes `targetDurationSeconds`. `restSeconds` stays `restSeconds`, `note` becomes `notes`, and `sets` becomes `targetSets`. The template description becomes the plan description, truncated to the plan field's limit if needed.
- **Start now:**
  - The exercises are materialized first (each call is idempotent, in its own transaction).
  - Then `startTemplateWorkout` creates the session in one transaction. It uses the template name and `planUuid` null, and adds planned sets with no values. As in `startWorkout`, targets are not performed values.
  - An existing unfinished workout blocks the start with the same message the Train page already shows.
  - Plan targets are not shown inside the logger in this stage; the logger never showed them.
- **Content: about 16 standalone templates**, conservative and owner-reviewed. Each has 4 to 7 exercises and takes 30 to 60 minutes:
  - Compound lifts: 3 to 5 sets of 5 to 10 reps, 120 to 180 s rest.
  - Accessories: 2 to 4 sets of 8 to 15 reps, 60 to 90 s rest.
  - Holds: 2 to 3 sets of 20 to 60 s.
  - Beginner templates use less volume.
  - Each description is one or two plain sentences: who it suits and what it covers, with no outcome claims.
  - Suggested set: Push, Pull, Legs, Upper A, Upper B, Lower A, Lower B, Full body A, Full body B, Full body dumbbell, Bodyweight full body, Hotel room, Resistance band full body, Kettlebell full body, Core and holds, Glute focus. Adjust the names; keep the coverage.
- **Program-only templates are not added here.** They come with their programs in stage 7.
- **Owner review gate, same as stage 5.** After the agent finishes, a readable review sheet of every template is generated outside the repo. Merging and running the `supabase-database` job publishes release 3.

## Running checks

From the repo root, run `python3 -m unittest discover -s tool -p 'test_*.py'` and `python3 scripts/catalog_build.py check`. From `apps/mobile/`, run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze` and `flutter test`. Flutter is at `/opt/sdk/flutter/bin`.

## Global Constraints

- Template IDs follow `tpl.<slug>`. Never reuse an ID from `catalog/releases.lock.json`.
- Prescription ranges (validator): sets 1 to 30; reps 1 to 1000 with min ≤ max; rest 0 to 3600 s; duration 1 to 3600 s. Reps only on rep exercises, seconds only on `duration` exercises, never both.
- Text limits: name 80, description 1000, note 300. The plan name limit is 160 and the notes limit is 1000, so they always fit.
- Durable write contract: the plan and its rows are written in one transaction, as are the session and its planned sets. Nothing is synced (plans are local-only under ADR-0005).
- Design kit only: `NsListCard`, `NsChip`, `NsTextField`, `NsTag`, `NsDialog`/`showNsDialog`, snackbars from the kit, and `FilledButton` as used elsewhere. Support light and dark, text scale 2.0 at 390 × 844, and screen-reader labels.
- Synthetic data in tests. Original text only.

## Review Focus

1. **A double tap on Copy** creates one plan, and a deliberate second copy creates "<name> (2)" (Tasks 2 and 6).
2. **A failure in the middle of a copy** must leave no plan, no rows and no newly materialized exercises. The materialization is inside the same transaction (Task 2).
3. **Start now while a workout is already running** must show the existing "finish or discard" message and change nothing. A timed template exercise must start as a timed exercise in the logger (Tasks 3 and 6).
4. **A catalogue refresh or rollback after a copy** leaves the copied plan unchanged. A template whose exercise was retired disappears from the list but never breaks existing plans (Tasks 1, 2 and 5).
5. **Text scale 2.0** on the template detail screen with a 7-exercise template: no overflow, and both buttons are reachable (Task 6).

---

### Task 1: Typed templates on the phone

**Files:**
- Modify: `apps/mobile/lib/features/catalog/domain/catalog_models.dart`, `lib/features/catalog/domain/catalog_parser.dart`
- Create: `lib/features/catalog/domain/catalog_templates.dart`
- Test: `test/catalog/catalog_parser_test.dart`, `test/catalog/catalog_templates_test.dart` (new), fixtures in `test/catalog/catalog_fixtures.dart`

**Interfaces:**
- `class CatalogPrescription { String exerciseId; int sets; int? repsMin; int? repsMax; int? durationSeconds; int restSeconds; String note; }`
- `class CatalogTemplate { String id; String name; String description; List<String> goals; String level; List<String> equipment; int estimatedMinutes; bool standalone; List<CatalogPrescription> exercises; }`, with `standalone` defaulting to true.
- `CatalogSnapshot.templates` becomes `List<CatalogTemplate>`. Programs stay raw maps until stage 7. Unknown keys are ignored.
- `catalog_templates.dart` provides:
  - `List<CatalogTemplate> browsableTemplates(CatalogSnapshot s)`: standalone templates whose every exercise is active in `s` and has a mode in `loggableModes`, sorted by name.
  - `String prescriptionLabel(CatalogPrescription p)`, for example "4 × 6–8 reps", "3 × 10 reps" (when min equals max) or "3 × 45 s" (via `formatDurationSeconds`).
  - `String restLabel(int seconds)`, for example "Rest 90 s" or "Rest 2 min 30 s".

- [ ] **Step 1: Write failing tests**:
  - A snapshot with one template parses into typed fields, and a missing `standalone` reads as true.
  - Release 1 and 2 fixtures still parse. Their checksums are unchanged, because parsing changes nothing that is hashed.
  - `browsableTemplates` hides non-standalone templates, templates with a retired exercise, and templates with a `duration_load` exercise.
  - The label cases above.
- [ ] **Step 2: Run** `flutter test test/catalog`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/catalog`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(catalog): parse workout templates into typed models`

### Task 2: Copy a template into My Plans, atomically

**Files:**
- Modify: `lib/features/workouts/domain/workout_library_repository.dart`, `lib/features/workouts/domain/workout_library_models.dart`, `lib/features/workouts/data/objectbox_workout_library_repository.dart`
- Test: `test/workouts/objectbox_workout_library_repository_test.dart`

**Interfaces:**
- `typedef TemplateRowInput = ({CatalogDefinitionInput exercise, int sets, int? repsMin, int? repsMax, int? durationSeconds, int restSeconds, String note});`
- `WorkoutPlanRecord copyCatalogTemplate({required String requestUuid, required String name, required String description, required List<TemplateRowInput> rows, required int release})`:
  - If a plan with UUID `requestUuid` exists, return it unchanged.
  - Otherwise, in **one** transaction: materialize each exercise with the same rules as `materializeCatalogExercise` (refactor its body into a private helper both methods call inside the transaction). Pick a unique name, then create the plan (UUID = `requestUuid`) and its rows with fresh UUIDs, positions 0..n-1 and the mode rules from stage 4.
  - Any throw rolls everything back.
- Add a test-only seam to inject a failure after step k (for example, an optional `@visibleForTesting void Function(String step)? debugCopyHook` on the repository). The hook is called after materializing all exercises, after putting the plan, and after putting the rows.

- [ ] **Step 1: Write failing tests**:
  - A copy creates a plan with the right rows and targets, including a timed row, and materializes missing exercises with their muscles.
  - Repeating the same `requestUuid` returns the same plan with no second plan.
  - A new `requestUuid` with the same name gives "<name> (2)", and a third gives "<name> (3)". An archived plan's name does not count.
  - For each injected failure point: there is no plan, no rows, and no newly materialized definition. A definition that already existed before the copy is left unchanged.
  - Editing the copied plan, and then calling `syncCatalogDefinitions` with a newer release, leaves the plan's rows unchanged.
- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/workouts`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(workouts): copy a catalogue template into an editable plan atomically`

### Task 3: Start a workout straight from a template

**Files:**
- Modify: `lib/features/workouts/domain/live_workout_engine.dart`, `lib/features/workouts/data/objectbox_live_workout_engine.dart`, `lib/features/train/active_workout_state.dart` (`WorkoutActions.startTemplate`)
- Test: `test/workouts/objectbox_live_workout_engine_test.dart`, `test/train/active_workout_widget_test.dart` (timed exercise from a template)

**Interfaces:**
- `WorkoutSessionRecord startTemplateWorkout({required String sessionUuid, required String name, required List<PlanExerciseRecord> rows, required DateTime startedAtUtc, required int originalOffsetMinutes})`:
  - It runs in one transaction with the same checks as `startWorkout`: an unfinished workout throws the same `StateError`; a missing definition throws; the name must be 1 to 160 characters.
  - A replay with the same `sessionUuid`, name and start time returns the committed session.
  - Session exercises snapshot names and muscles exactly as `startWorkout` does, and get `targetSets` planned sets with no values.
  - Extract the shared session-building code into a private helper rather than duplicating it.
- `WorkoutActions.startTemplate(CatalogTemplate t, int release)` materializes each exercise, then calls the engine with rows built from the prescriptions.

- [ ] **Step 1: Write failing tests**:
  - Starting from rows creates a session with `planUuid` null, the template name, ordered exercises, muscle snapshots and empty planned sets.
  - A replay is idempotent.
  - A second start while one is active throws, and nothing is written.
  - The logger shows a template's plank with the SEC column.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/workouts test/train`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(workouts): start a workout from a template without saving a plan`

### Task 4: Template content

**Files:**
- Create: `catalog/templates/standalone.json`
- Modify: `tool/test_catalog_content.py`

**Interfaces (content tests):**
- `test_templates_reference_loggable_active_exercises`: every exercise is active and has a mode of `reps_load` or `duration`.
- `test_template_shape`: 4 to 7 exercises; `estimatedMinutes` from 20 to 75; no exercise twice in one template; a non-empty description of at most 2 sentences; no outcome-claim words (reuse `OUTCOME_CLAIM`).
- `test_template_prescriptions_are_conservative`: beginner templates have at most 18 working sets; every template has at most 24; rest is at least 60 s on any row whose `repsMax` is 8 or less.
- `test_template_equipment_tag_matches_exercises`: `tags.equipment` equals the union of the referenced exercises' equipment, minus `bodyweight` when other equipment is present.

- [ ] **Step 1: Write the tests.** Run them against an empty templates file, where they pass vacuously. Then add one deliberately bad template per rule and watch each test fail. Remove it.
- [ ] **Step 2: Write the templates** following the Decisions and using only exercise IDs from the published catalogue (`catalog/exercises/*.json`).
- [ ] **Step 3: Run** `python3 -m unittest tool.test_catalog_content` and `python3 scripts/catalog_build.py check`. Expected: PASS.
- [ ] **Step 4: Commit** `feat(catalog): standalone workout templates`

### Task 5: Workouts list and template detail screens

**Files:**
- Create: `lib/features/train/workout_templates_page.dart`, `lib/features/train/template_detail_page.dart`, `lib/features/catalog/application/templates_provider.dart`
- Modify: `lib/features/train/train_page.dart` (a "Workouts" `NsListCard` under "More ways to move", subtitle "Ready-made sessions to start or copy"), `lib/app/beyondrep_app.dart` (routes `/train/workouts` and `/train/workouts/:id`)
- Test: `test/train/workout_templates_page_test.dart`, `test/train/template_detail_page_test.dart` (new)

**Interfaces:**
- `templatesProvider` is `browsableTemplates` of the current cached snapshot, or empty while there is no snapshot. The list shows the same unavailable/Retry and outdated-app states as the Exercises page, reusing its copy constants.
- **List page:** a search field (matching name and description), level chips, and `NsListCard` rows showing name, "Level · N min · M exercises", and the equipment labels.
- **Detail page:**
  - Header: name, description, level, minutes and equipment tags.
  - One row per exercise: name, `prescriptionLabel`, `restLabel` and the note if present. Tapping a row opens `/train/exercises/:id`.
  - Two buttons: "Start now" (calls `startTemplate`, then goes to `/train/workout`) and "Copy to My Plans".
  - Copy calls `copyCatalogTemplate` with the screen's request UUID. On success it shows a kit snackbar "Saved to My Plans as <name>" with an "Edit" action that opens the plan editor, then rotates the request UUID.
  - The buttons are disabled while an action is running.
  - Errors use the existing kit snackbar copy.

- [ ] **Step 1: Write failing widget tests**:
  - The list filters by search and level, and hides a non-standalone template.
  - The detail page shows "4 × 6–8 reps" and "3 × 45 s" rows.
  - Copy twice quickly gives one plan. A copy after the first finished gives "(2)".
  - Start now opens the logger. Start now with an active workout shows the message and does not navigate.
  - The unavailable state shows Retry.
  - Text scale 2.0 at 390 × 844, light and dark: no overflow, and both buttons are reachable by scrolling.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/train test/catalog test/design_kit_guard_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): browse, start and copy workout templates`

### Task 6: Publish release 3 and document it

**Files:**
- Generated: `supabase/migrations/<ts>_catalog_release_3.sql`, the lock file and the changelog
- Modify: `docs/CATALOG.md` (template rules, copy and start behaviour), `docs/ROADMAP.md`, `docs/RELEASE.md` (device rows: browse, start a template with a plank, copy twice, copy offline with the cached catalogue, text scale 2.0)

- [ ] **Step 1: Run** `python3 scripts/catalog_build.py check`. Expected: PASS.
- [ ] **Step 2: Publish** with `--timestamp 20261126040000 --published-at 2026-11-26T04:00:00Z`, unless a newer migration exists; in that case use a later matching pair. Never hand-edit the output.
- [ ] **Step 3: Write the docs.** Run the full Running checks. Expected: all PASS.
- [ ] **Step 4: Commit** `feat(catalog): publish release 3 with workout templates`
