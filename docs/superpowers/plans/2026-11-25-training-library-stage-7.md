# Training library stage 7: programs, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users can browse owner-reviewed multi-day programs, preview the whole 7-day week with every prescription, and add a program to their account. Adding a program creates editable plans and a schedule, and makes it active. Users can then:
- edit its workouts and schedule;
- switch or deactivate the active program;
- archive a program;
- start a scheduled day's workout. The session records which program day it was for, which stage 8 uses for Today, done and missed.

**Architecture:**
- **Storage:** two new local-only ObjectBox entities (`TrainingProgramEntity`, `ProgramDayEntity`) plus additive fields on plans and sessions, all in the account store and never synced.
- **Import:** one repository method imports a whole program atomically and idempotently. It materializes exercises, creates one plan per distinct template and the program with its 7 days, and optionally makes it active, all in one transaction.
- **Starting a day:** the session-start path gains an optional program-day context.
- **UI:** a "Programs" entry on Train, program list and detail screens, and a "Your program" screen, all from existing kit components.
- **Content:** programs ship as catalogue release 4.

**Tech Stack:** JSON plus the Python validator and build, Flutter 3.47.7, ObjectBox 5, Riverpod 3, go_router.

**Spec:** `docs/superpowers/specs/2026-11-25-training-library-design.md` sections 4.4 (programs), 4.5, 6.2 (import program), 6.3, 6.4 (session fields), 6.5 (only the rule for capturing `programDayLocalDate`), 6.7 (program detail, My program), 7 and 9. Also read `docs/CATALOG.md`, `docs/OBJECTBOX.md` and the stage 6 plan for the template patterns this stage reuses.

## Decisions this plan makes

- **Stage boundary with stage 8:**
  - **This stage:** stores `programUuid` and `programDayLocalDate` on a session when it is started from a program day. It also lets the user start **today's** scheduled workout from the Your program screen.
  - **Stage 8:** the Today card, the done and missed computations and the "Missed <day>" line, starting a missed day, and the remaining filters (goal, equipment, frequency).
  - Nothing in this stage computes done or missed.
- **No segmented Library screen.** As in stage 6, Train's "More ways to move" gains a "Programs" card. When a program is active, a "Your program" card is added above "Your plans". It shows the program name and "Today: <workout>" or "Today: Rest day" (a pure calculation, see Task 3), and opens the Your program screen.
- **Program plans:**
  - Each distinct template in a program becomes one plan, with `programUuid` set and fresh UUIDs for the plan and its rows. A template used on two days gives one plan referenced by two days.
  - Program plans are hidden from "Your plans" and edited with the existing plan editor, which keeps `programUuid` on save.
  - The plan editor's archive action is hidden for program plans. Plans are archived only by archiving their program.
- **Import:**
  - It is idempotent per request UUID, like stage 6's copy, and the request UUID becomes the program UUID.
  - A deliberate second import of the same program is named "<name> (2)".
  - "Add program" shows a kit sheet (`showNsSheet`) that asks which weekday day 1 falls on, defaulting to today's weekday, with seven `NsChip`s. It also has a "Make it my active program" `NsCheckButton`, on by default.
  - Making a program active deactivates any other in the same transaction and sets `activatedLocalDate` to today.
- **Schedule editing on the Your program screen:**
  - Change the first weekday (the seven chips again).
  - For any day, pick one of the program's plans or "Rest" (an `NsDropdown` in a kit sheet).
  - Activate or deactivate the program, and archive it (with `showNsConfirm`; this archives its plans and never touches sessions).
  - Each day row opens that plan in the editor.
  - A program with no training day left after an edit is allowed but shows "No training days".
- **Starting a program day:**
  - Only today's day can be started in this stage. The start sets `programUuid` and `programDayLocalDate` (today's local date, `yyyy-MM-dd`) once, at start.
  - The same plan started from Your plans or a template never sets them.
  - Starting on a rest day isn't offered.
- **Program-only templates** (`standalone: false`) are previewed inside the program detail. They are never listed under Workouts, and the template routes never open them.
- **Content: up to 16 programs from issue #63's table.** Any program that can't be done well is dropped or merged, and the reason goes in the review sheet.
  - Existing standalone templates are reused where they fit, for example Push/Pull/Legs 3 and 6 reuse Push, Pull and Legs day, and Upper/Lower reuses Upper A/B and Lower A/B.
  - New program-only templates are added where a program needs its own sessions, for example the 5×5 A/B, the bodybuilding split days, low-volume high-intensity sessions and calisthenics.
  - The same conservative rules and content tests as stage 6 apply. Program text makes no outcome claims, and `estimatedMinutes` is the average of its days.
- **Release 4** keeps `minAppCatalogSchema` at 1. Older builds already parse programs and only check their week structure, and they ignore `standalone: false` because they don't show templates, or hide them since stage 6.
- **Owner review gate as before:** a review sheet of every program and every new template. Merging and running the `supabase-database` job publishes it.

## Running checks

From the repo root, run `python3 -m unittest discover -s tool -p 'test_*.py'` and `python3 scripts/catalog_build.py check`. From `apps/mobile/`, run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze` and `flutter test`. Flutter is at `/opt/sdk/flutter/bin`.

## Global Constraints

- **ObjectBox:** additive only, with stable UIDs. Regenerate and commit `objectbox.g.dart` and `lib/objectbox-model.json`, and add an old-database migration test with a frozen `pre-*.g.dart` fixture, following `docs/OBJECTBOX.md` and the stage 6 rest field.
- **Local only:** programs, program days, `programUuid` on plans and sessions, and `programDayLocalDate` are never added to the sync outbox payload, cloud snapshot, export or restore mapping. `contracts/` and `supabase/` schema files are untouched; only the generated catalogue migration is new. A test asserts the upload payload has no program key.
- **Durable writes:** import, activation, schedule edits and archive are each one transaction. Failure injection tests cover the import.
- **Design kit only:** `NsListCard`, `NsChip`, `NsCheckButton`, `NsDropdown`, `showNsSheet`, `showNsConfirm`, `showNsMessage` and `SectionHeading`. Support light and dark, text scale 2.0 at 390 × 844, and screen-reader labels.
- **IDs:** programs use `prog.<slug>` and new templates use `tpl.<slug>`. Never reuse an ID from `catalog/releases.lock.json`.
- **Synthetic data in tests. Original text only.**

## Review Focus

1. **Import atomicity:** a throw after materializing, after the plans, after the rows, after the program or after the days leaves nothing new. A double tap gives one program, and a deliberate second import gives "(2)" (Task 4).
2. **One active program:** activating one deactivates the other in the same transaction, and `activatedLocalDate` is reset each time (Task 4).
3. **Weekday maths** at every `firstDayWeekday` from 1 to 7, including a week that wraps past Sunday (Task 3).
4. **Session program fields** are set only from the program-day start and never reach the sync payload. An old database opens with them null (Tasks 2 and 5).
5. **Program plans** are hidden from Your plans, and editing one in the plan editor keeps its `programUuid` (Tasks 4 and 6).
6. **Text scale 2.0** on the program detail with a 6-day program, and on the Your program screen (Task 6).

---

### Task 1: Typed programs on the phone

**Files:** `lib/features/catalog/domain/catalog_models.dart`, `catalog_parser.dart` and `catalog_templates.dart` (or a new `catalog_programs.dart`), with tests in `test/catalog/`.

**Interfaces:**
- `class CatalogProgram { String id; String name; String description; List<String> goals; String level; int daysPerWeek; int estimatedMinutes; List<String> equipment; List<String?> week; }`, where `week` has 7 entries and `null` means a rest day.
- `CatalogSnapshot.programs` becomes `List<CatalogProgram>`. The parser keeps today's week checks and adds: `daysPerWeek` equals the number of non-null days, and there is at least one training day.
- `List<CatalogProgram> browsablePrograms(CatalogSnapshot s)`: programs whose every referenced template is fully loggable and active (reusing the stage 6 rule, but **without** the `standalone` filter), sorted by days per week and then name.
- `CatalogTemplate? programTemplate(CatalogSnapshot s, String id)` looks up any template, including program-only ones, for the preview.

- [ ] **Step 1:** Write failing tests:
  - Parsing typed fields.
  - A `daysPerWeek` mismatch is rejected.
  - Release 1 to 3 fixtures still parse.
  - `browsablePrograms` hides a program whose template uses a retired exercise.
  - A program whose template is `standalone: false` is listed.
- [ ] **Step 2:** Run `flutter test test/catalog`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/catalog`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(catalog): parse programs into typed models`

### Task 2: Local program entities and fields

**Files:** `lib/features/workouts/data/workout_entities.dart`, the domain models (a new `lib/features/programs/domain/program_models.dart`), the generated ObjectBox files, `test/workouts/fixtures/objectbox_pre_programs.g.dart`, and a migration test.

**Interfaces:**
- `TrainingProgramEntity` and `ProgramDayEntity` exactly as spec 6.3. `uuid` is `@Unique()`, and there is an `@Index()` on `ProgramDayEntity.programUuid`.
- New fields: `WorkoutPlanEntity.programUuid` (`String?`, `@Index()`), `WorkoutSessionEntity.programUuid` (`String?`) and `WorkoutSessionEntity.programDayLocalDate` (`String?`).
- Domain records: `TrainingProgramRecord { uuid, name, description, sourceId, sourceRelease, firstDayWeekday, isActive, activatedLocalDate, updatedAtMs, archivedAtMs, days: List<ProgramDayRecord> }` and `ProgramDayRecord { uuid, dayIndex, planUuid? }`. `WorkoutPlanRecord` and `WorkoutSessionRecord` gain the matching nullable fields.

- [ ] **Step 1:** Write failing tests:
  - An old database built from the frozen fixture opens, and plans and sessions read the new fields as null.
  - The new entities round-trip.
  - The completed-workout upload payload of a session with program fields has no key containing "program".
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement, then run build_runner.
- [ ] **Step 4:** Run `flutter test test/workouts`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(programs): local program entities and fields`

### Task 3: Schedule maths (pure)

**Files:** `lib/features/programs/domain/program_schedule.dart`, with tests in `test/programs/program_schedule_test.dart`.

**Interfaces:**
- `int programDayIndex(DateTime localDate, int firstDayWeekday)` returns `(localDate.weekday - firstDayWeekday) mod 7`.
- `String localDateKey(DateTime localDate)` returns `yyyy-MM-dd`.
- `ProgramDayRecord dayFor(TrainingProgramRecord p, DateTime localDate)`.
- `List<({int weekday, ProgramDayRecord day})> calendarWeek(TrainingProgramRecord p)`: the 7 days in program order, each labelled with its weekday.

- [ ] **Step 1:** Write failing table tests for every `firstDayWeekday` from 1 to 7, each against a Monday and a Sunday. Also test a date key with padding.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(programs): program day and weekday maths`

### Task 4: Program repository: import, activate, edit, archive

**Files:** `lib/features/programs/domain/program_repository.dart` and `lib/features/programs/data/objectbox_program_repository.dart` (sharing the stage 6 materialize helper by extracting it if needed), `lib/features/workouts/data/objectbox_workout_library_repository.dart` (Your plans excludes program plans, and `savePlan` keeps `programUuid`), Riverpod providers, and tests in `test/programs/objectbox_program_repository_test.dart`.

**Interfaces:**
- `TrainingProgramRecord importProgram({required String requestUuid, required CatalogProgram program, required Map<String, List<TemplateRowInput>> templateRows, required Map<String, String> templateNames, required int release, required int firstDayWeekday, required bool makeActive, required DateTime localToday})`:
  - If the program UUID already exists, it returns the program unchanged.
  - Otherwise it runs in **one** transaction:
    1. Materialize the exercises.
    2. Create one plan per distinct template, with a fresh UUID and its rows, using the stage 6 row mapping and `programUuid` set.
    3. Create the program with a unique name and its 7 days.
    4. If `makeActive`, deactivate the others and activate this one.
  - Any throw rolls everything back. Add a `@visibleForTesting debugImportHook` that is called after each numbered step.
- `void setActive(String programUuid, bool active, DateTime localToday)`
- `void setFirstWeekday(String programUuid, int weekday)`
- `void setDayPlan(String programUuid, int dayIndex, String? planUuid)`: the plan must belong to this program, otherwise it throws `ArgumentError`.
- `void archiveProgram(String programUuid, int nowMs)`: archives the program and its plans, deactivates it, and leaves sessions untouched.
- `Stream<List<TrainingProgramRecord>> watchPrograms()`, which excludes archived programs, and `TrainingProgramRecord? activeProgram()`.

- [ ] **Step 1:** Write failing tests:
  - An import with a template used on two days creates exactly one plan for it.
  - Plan rows carry targets and rest.
  - Replaying the same request returns the same program; a new request gives "(2)".
  - For each hook point, a failure leaves no programs, days, plans, rows or new definitions.
  - Activating program B deactivates A.
  - `setDayPlan` with a foreign plan throws.
  - Archiving leaves a session that referenced the program unchanged.
  - Your plans excludes program plans.
  - Editing a program plan with `savePlan` keeps its `programUuid`.
  - A catalogue sync to a newer release leaves imported plans unchanged.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/programs test/workouts`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(programs): atomic program import, activation, schedule edits and archive`

### Task 5: Start today's program workout

**Files:** `lib/features/workouts/domain/live_workout_engine.dart`, `lib/features/workouts/data/objectbox_live_workout_engine.dart` and `lib/features/train/active_workout_state.dart`, with tests.

**Interfaces:**
- `startWorkout` gains an optional `({String programUuid, String localDate})? programDay`. It applies only with `planUuid`, and the plan's `programUuid` must equal `programDay.programUuid`, otherwise it throws `ArgumentError`. The value is stored on the session inside the existing transaction and checked again on replay.
- `WorkoutActions.startProgramDay(TrainingProgramRecord p, DateTime localNow)`:
  - It computes today's day. On a rest day it throws `StateError`.
  - Otherwise it starts that day's plan with `programDay`, where `localDate` is `localDateKey(localNow)`.
  - It uses the same readiness confirmation and active-workout message as other starts.

- [ ] **Step 1:** Write failing tests:
  - A program-day start stores both fields.
  - A plain plan start of the same plan stores nulls.
  - A mismatched program throws, and nothing is written.
  - A start at 23:50 local stores that date (inject the clock).
  - Replay is idempotent.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(programs): start today's program workout with its program day`

### Task 6: Program screens

**Files:**
- Create: `lib/features/train/programs_page.dart`, `lib/features/train/program_detail_page.dart`, `lib/features/train/my_program_page.dart` and `lib/features/catalog/application/programs_provider.dart`.
- Modify: `train_page.dart` (the "Programs" card in More ways to move, with subtitle "Multi-week plans with a weekly schedule", and the "Your program" card when one is active) and `beyondrep_app.dart` (routes `/train/programs`, `/train/programs/:id` and `/train/program/:uuid`).
- Tests: in `test/train/`.

**Interfaces:**
- **Programs list:** search over name and description, plus level chips. Each row shows "<n> days a week · <level> · about <m> min" and the equipment. It has the same unavailable and outdated-app states as Workouts.
- **Program detail:**
  - A header with the description, level, days per week, minutes and equipment.
  - Then the week: one `NsListCard` per day reading "Day 1 · Push day · 5 exercises", or "Day 2 · Rest". Tapping a training day shows its prescriptions inline below it (expand and collapse) using `prescriptionLabel`, `restLabel` and the notes.
  - "Add program" opens the sheet from the Decisions. On success it goes to `/train/program/:uuid` with a `showNsMessage`. The button is disabled while running, and the request UUID rotates after success.
- **Your program:**
  - A header with the name and an Active or Not active tag.
  - "Start today's workout" (or "Rest day today") calls `startProgramDay`, then goes to `/train/workout`.
  - A 7-row week labelled with weekdays (`calendarWeek`). Each row opens a sheet with "Edit workout" (opens `/train/plans/:id/edit`), "Change to…" (an `NsDropdown` of the program's plans and Rest) and nothing else.
  - Then "Change start day", "Make active" or "Stop using this program", and "Archive program" (confirm).
- **Train:** the "Your program" card is shown only when a program is active. Imported but inactive programs are listed under the Programs card's screen in a "Your programs" section at the top.

- [ ] **Step 1:** Write failing widget tests:
  - List filtering.
  - The detail shows 7 day rows and expands a day.
  - Add program with weekday Wednesday and active creates the program and navigates.
  - A double tap on Add gives one program.
  - Your program: changing a day to Rest, changing the start day, archive confirm, and starting today's workout opens the logger with the program fields.
  - A rest day shows "Rest day today" and no start.
  - The Train card appears only with an active program, and program plans are not under Your plans.
  - Text scale 2.0, light and dark, with no overflow on the detail page and the Your program screen.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/train test/programs test/design_kit_guard_test.dart`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(train): browse, add and manage programs`

### Task 7: Program content

**Files:** `catalog/programs/programs.json`, `catalog/templates/program_sessions.json` (the new `standalone: false` templates), and `tool/test_catalog_content.py`.

**Interfaces (content tests):**
- `test_program_templates_loggable`: every template a program uses passes the stage 6 template tests. The existing tests must cover non-standalone templates too.
- `test_program_shape`: `daysPerWeek` from 2 to 6. Each listed level is at least as hard as the hardest of its templates, with beginner < intermediate < advanced. `estimatedMinutes` is within 5 of the average of its days. A 2-sentence description with no outcome claims.
- `test_program_equipment_matches_templates`: the equipment is the union over the program's templates, using the stage 6 bodyweight rule.
- `test_no_orphan_program_templates`: every `standalone: false` template is used by at least one program.
- `test_program_rest_spacing`: a program with 4 or fewer training days has no more than 2 training days in a row, so it spreads its training out. 5 and 6 day splits are exempt.

- [ ] **Step 1:** Write the tests. Prove each one fails on a deliberately bad fixture, then remove the fixture.
- [ ] **Step 2:** Write the programs and the new templates following the Decisions.
  - Push/Pull/Legs 6 runs the three days twice, then rests.
  - 5×5 uses fixed 5-rep rows (`repsMin` = `repsMax` = 5) with 3 min rest on the compound lifts.
  - The advanced low-volume program uses 1 to 2 hard working sets of compound lifts with long rests. Drop it if it can't meet the content tests honestly.
  - Calisthenics uses the pull-up bar and bodyweight exercises, and its pull-up rows carry the assisted-variation note.
- [ ] **Step 3:** Run `python3 -m unittest tool.test_catalog_content` and `python3 scripts/catalog_build.py check`. Expected: PASS.
- [ ] **Step 4:** Commit `feat(catalog): training programs and their sessions`

### Task 8: Publish release 4 and document it

- [ ] **Step 1:** Run `python3 scripts/catalog_build.py check`. Expected: PASS.
- [ ] **Step 2:** Publish with `--timestamp 20261126050000 --published-at 2026-11-26T05:00:00Z`, or a later matching pair if a newer migration exists. Never hand-edit the output.
- [ ] **Step 3:** Update the docs:
  - `docs/CATALOG.md`: program rules.
  - `docs/OBJECTBOX.md`: the new entities and fields.
  - `docs/ROADMAP.md`.
  - `docs/RELEASE.md` device rows: add a program, switch the active program, edit the schedule, start today's workout, an old database upgrade, and text scale 2.0.
- [ ] **Step 4:** Run the full Running checks. Expected: all PASS.
- [ ] **Step 5:** Commit `feat(catalog): publish release 4 with training programs`
