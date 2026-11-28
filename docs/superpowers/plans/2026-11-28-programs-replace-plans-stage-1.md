# Programs replace plans, stage 1: Train tab and custom programs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove "plans" from the Train tab and every user-visible string; offer Quick workout and Programs, with a "Create program" builder and richer program editing, without any backend change.

**Architecture:** Plans stay as `WorkoutPlanEntity` rows, but every new one is owned by a program (`programUuid` set). `ProgramRepository` gains create, rename and add-workout writes, each one ObjectBox transaction. The plan editor gains two modes (add to a program, return a draft). Train, Today, the template page and the watch snapshot stop surfacing standalone plans.

**Tech Stack:** Flutter 3.47.7, Riverpod, go_router, ObjectBox (no entity or model change in this stage), Swift and Kotlin string edits only.

**Spec:** `docs/superpowers/specs/2026-11-28-programs-replace-plans-design.md` (stage 1 section). Read it first.

## Global Constraints

- Read `AGENTS.md` and `apps/mobile/AGENTS.md`. Kit components only (`lib/core/design/`); no raw `TextField`, `showModalBottomSheet`, `showDialog`, `SnackBar`, chips (`test/design_kit_guard_test.dart`).
- No ObjectBox entity, `objectbox-model.json` or `objectbox.g.dart` change in stage 1.
- No change to `contracts/`, `supabase/`, sync code, or watch message shapes. `plan_id` and other wire names stay.
- Limits: program name 1-100 chars trimmed, description up to 1000 (use the existing `_clip`), at most **30** non-archived workouts per program (every workout the program owns, used by a day or not), at most 100 exercises per workout, row bounds from `PlanExerciseRecord.validate()`.
- No user-visible "plan"/"plans" (whole word, any case) in string literals under `lib/` except route paths (`/train/plans/...`). Code identifiers stay.
- Copy uses "workout" for a single session template and "program" for the schedule. Exact strings below are fixed by this plan.
- Every write that can fail shows the existing kit message (`showNsMessage`) and leaves nothing half saved.
- From `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test` must pass at the end. Flutter is at `/tmp/claude-0/sdk/flutter/bin` (add to PATH).
- Commits end with the attribution lines given by the controller.

## Review Focus

1. A repeated Save tap (double tap or retry after a crash mid-write) on Create program must not create two programs: `createProgram` is idempotent by `requestUuid` (Task 1 test `createProgram repeat returns the same program`).
2. Adding a 31st workout must fail cleanly with the message "A program can hold up to 30 workouts." and change nothing (Task 1 test + Task 5 widget test).
3. A user who only has old saved plans and no program must still reach them: Create program offers "Copy one of my saved workouts" only when `listPlans()` is non-empty (Task 3 test).
4. Leaving the Create program page with unsaved days must ask "Discard this program?" (Task 4 test).
5. With no active program, Today, Train and both watches must still offer Quick workout and never show an empty or broken card (Tasks 7, 8, 10 tests).

---

### Task 1: Program repository writes (create, rename, add workout, limit)

**Files:**
- Modify: `apps/mobile/lib/features/programs/domain/program_repository.dart`
- Modify: `apps/mobile/lib/features/programs/domain/program_models.dart`
- Modify: `apps/mobile/lib/features/programs/data/objectbox_program_repository.dart`
- Test: `apps/mobile/test/programs/objectbox_program_repository_test.dart`

**Interfaces:**
- Produces (in `program_models.dart`):

```dart
const maxProgramWorkouts = 30;

/// Where a new program-owned workout's rows come from.
sealed class ProgramWorkoutSource {
  const ProgramWorkoutSource();
}
/// Rows built in the editor; exercise UUIDs must exist locally.
class DraftWorkoutSource extends ProgramWorkoutSource {
  const DraftWorkoutSource({required this.name, required this.description, required this.rows});
  final String name; final String description; final List<PlanExerciseRecord> rows;
}
/// A catalogue template; exercises are materialized in the same transaction.
class TemplateWorkoutSource extends ProgramWorkoutSource {
  const TemplateWorkoutSource({required this.name, required this.description, required this.rows, required this.release});
  final String name; final String description; final List<TemplateRowInput> rows; final int release;
}
/// A copy of an existing plan (an old saved plan or another program's workout).
class CopyWorkoutSource extends ProgramWorkoutSource {
  const CopyWorkoutSource(this.planUuid);
  final String planUuid;
}

class ProgramWorkoutLimit implements Exception { const ProgramWorkoutLimit(); }
```

- Produces (on `ProgramRepository`):

```dart
/// Creates a custom program (sourceId 'custom', sourceRelease 0) in one
/// transaction: one program-owned workout per [workouts] entry, seven days
/// where week[i] is an index into [workouts] or null for rest. Repeating
/// [requestUuid] returns the existing program. Needs at least one training
/// day, every index valid and every workout used; otherwise ArgumentError.
TrainingProgramRecord createProgram({
  required String requestUuid,
  required String name,
  required String description,
  required List<ProgramWorkoutSource> workouts,
  required List<int?> week,
  required int firstDayWeekday,
  required bool makeActive,
  required DateTime localToday,
});

/// Renames and redescribes a live program. Same name rules as create.
void updateDetails(String programUuid, {required String name, required String description});

/// Adds one program-owned workout and returns its plan UUID. Throws
/// ProgramWorkoutLimit when the program already owns 30 live workouts.
String addWorkout(String programUuid, ProgramWorkoutSource source);
```

- [ ] **Step 1: Write failing tests** in `objectbox_program_repository_test.dart` (use the file's existing store and fake UUID setup):
  - `createProgram builds days and owned workouts`: two `DraftWorkoutSource`s, `week: [0, null, 1, null, 0, null, null]`; expect `sourceId == 'custom'`, `days[2].planUuid` equals the second workout's UUID, `days[0].planUuid == days[4].planUuid`, `programPlans(uuid).length == 2`, each with `programUuid == uuid`, `listPlans()` (library) unchanged.
  - `createProgram repeat returns the same program`: same `requestUuid` twice gives one program in `listPrograms()`.
  - `createProgram rejects all-rest, bad index, unused workout, empty or 101-char name`: each throws `ArgumentError` and `listPrograms()` stays empty.
  - `createProgram with makeActive deactivates the old active program`.
  - `createProgram from a template materializes its exercises` (use `template_test_support.dart` or `program_test_support.dart` helpers).
  - `createProgram unique name adds (2)` when a live program already has the name (reuse the import naming loop; extract it to a private helper).
  - `CopyWorkoutSource copies rows with new row UUIDs and leaves the source plan untouched`.
  - `addWorkout returns a plan setDayPlan accepts`.
  - `addWorkout refuses the 31st workout` with `ProgramWorkoutLimit`, count stays 30.
  - `createProgram with 31 workouts throws ProgramWorkoutLimit`.
  - `updateDetails trims and renames; empty name throws ArgumentError`.
  - `a throw mid-create leaves nothing` using `debugImportHook` (call it at the same step names during create).
- [ ] **Step 2: Run** `flutter test test/programs/objectbox_program_repository_test.dart`. Expected: FAIL (missing members).
- [ ] **Step 3: Implement.** Reuse `_library.planItemsFromRows`, `_library.materializeInTransaction`, `_clip`, `_deactivateAll`. Draft rows are validated with `PlanExerciseRecord.validate()` and given fresh row UUIDs and positions. A `CopyWorkoutSource` reads the plan inside the transaction (`ArgumentError` when missing or archived). Workout names are trimmed, 1-100 chars.
- [ ] **Step 4: Run** the same test file. Expected: PASS.
- [ ] **Step 5: Commit** `feat(programs): create custom programs and add workouts`.

### Task 2: Plan editor modes (add to program, return a draft) and its wording

**Files:**
- Modify: `apps/mobile/lib/features/train/plan_editor_page.dart`
- Modify: `apps/mobile/lib/app/beyondrep_app.dart` (route `/train/programs/:uuid/workouts/new`)
- Test: `apps/mobile/test/train/plan_builder_widget_test.dart`

**Interfaces:**
- Consumes: Task 1 `addWorkout`, `DraftWorkoutSource`, `ProgramWorkoutLimit`.
- Produces:

```dart
class PlanEditorPage extends ConsumerStatefulWidget {
  const PlanEditorPage({this.planUuid, this.programUuid, this.returnDraft = false, this.initialDraft, super.key});
  final String? planUuid;          // edit an existing workout
  final String? programUuid;       // new workout added to this program; pops with the new plan UUID (String)
  final bool returnDraft;          // nothing saved; pops with DraftWorkoutSource
  final DraftWorkoutSource? initialDraft; // prefill when returnDraft
}
```

- Route `/train/programs/:uuid/workouts/new` builds `PlanEditorPage(programUuid: uuid)`. The old `/train/plans/new` route is removed; `/train/plans/:id/edit` stays (it edits program workouts).

- [ ] **Step 1: Write failing widget tests**: `program mode saves through addWorkout and pops the UUID`; `draft mode pops a DraftWorkoutSource and writes nothing` (library `listPlans()` and programs unchanged); `draft mode prefills initialDraft`; `program mode at 30 workouts shows "A program can hold up to 30 workouts."`; titles are "New workout" (new, any mode) and "Edit workout"; error copy "Enter a workout name and valid exercise targets.", "This workout changed while you were editing. Reload the latest version before saving.", "Could not save this workout. Nothing was partially saved."; discard dialog message "Changes to this workout have not been saved."; the archive action is never shown (standalone plans are gone from the UI).
- [ ] **Step 2: Run** `flutter test test/train/plan_builder_widget_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `_save`, branch on mode: `returnDraft` pops `DraftWorkoutSource(name: name.text.trim(), description: description.text.trim(), rows: items)` after running `PlanExerciseRecord.validate()` on each row and checking name 1-100 (same `ArgumentError` message path); `programUuid` calls `ref.read(programRepositoryProvider).addWorkout(...)` then `invalidatePrograms(ref)` and pops the UUID. Remove `_archive` and its button. Replace every "plan" string in the file with the copy above.
- [ ] **Step 4: Run** the test file. Expected: PASS. Update other tests that push `/train/plans/new` in the tasks that remove those entry points.
- [ ] **Step 5: Commit** `feat(train): workout editor adds to a program or returns a draft`.

### Task 3: Workout source sheet

**Files:**
- Create: `apps/mobile/lib/features/train/workout_source_sheet.dart`
- Test: `apps/mobile/test/train/workout_source_sheet_test.dart`

**Interfaces:**
- Produces:

```dart
sealed class DayChoice { const DayChoice(); }
class RestChoice extends DayChoice { const RestChoice(); }
class NewWorkoutChoice extends DayChoice { const NewWorkoutChoice(); }
class TemplateChoice extends DayChoice { const TemplateChoice(this.template); final CatalogTemplate template; }
class SavedPlanChoice extends DayChoice { const SavedPlanChoice(this.planUuid); final String planUuid; }
class ExistingChoice extends DayChoice { const ExistingChoice(this.key); final String key; } // a workout already in this program
class EditChoice extends DayChoice { const EditChoice(this.key); final String key; }

/// [existing] maps a key (plan UUID, or a builder-local key) to a name.
/// [current] is the key on this day, or null for rest.
Future<DayChoice?> showDaySheet(BuildContext context, WidgetRef ref, {
  required String title,               // e.g. weekday name or "Day 3"
  required Map<String, String> existing,
  required String? current,
  required bool canAddWorkout,         // false at 30 workouts
});
```

- Sheet content (kit `showNsSheet`, buttons and `NsListCard`): "Edit workout" (only when `current != null`), "Rest day", "New workout", "Copy a ready-made workout", "Copy one of my saved workouts" (only when `trainLibraryProvider` has any `plans`), then a "In this program" list of `existing`. With `canAddWorkout == false` the three add options are disabled with the subtitle "A program can hold up to 30 workouts.".
- "Copy a ready-made workout" opens a second sheet listing `templatesProvider` entries by name (with the search field from `NsTextField` when more than 8); "Copy one of my saved workouts" lists `listPlans()` by name. Each returns the matching choice.

- [ ] **Step 1: Write failing widget tests**: options shown with and without saved plans; `canAddWorkout: false` disables the add options and shows the limit subtitle; tapping a template returns `TemplateChoice` with that template; tapping a saved plan returns `SavedPlanChoice`; tapping an existing workout returns `ExistingChoice`; "Rest day" returns `RestChoice`.
- [ ] **Step 2: Run** `flutter test test/train/workout_source_sheet_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the sheet.
- [ ] **Step 4: Run** the test. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): day sheet to pick a workout source`.

### Task 4: Create program page

**Files:**
- Create: `apps/mobile/lib/features/train/create_program_page.dart`
- Modify: `apps/mobile/lib/app/beyondrep_app.dart` (route `/train/programs/new`, declared before `/train/programs/:id`)
- Modify: `apps/mobile/lib/features/train/programs_page.dart`
- Test: `apps/mobile/test/train/create_program_page_test.dart`, `apps/mobile/test/train/programs_pages_test.dart`

**Interfaces:**
- Consumes: Task 1 `createProgram` and sources, Task 2 draft mode, Task 3 `showDaySheet`, `program_weekday_sheet.dart`.
- Produces: `CreateProgramPage` widget; on success it replaces itself with `/train/program/<uuid>`.

Layout (kit only): page header "Create program"; `NsTextField` "Name" and "Description (optional)"; "Starts on" row opening the weekday sheet (default today's weekday from `localNowProvider`); seven `NsListCard` rows "Day 1" to "Day 7" with subtitle "Rest" or the workout name and the weekday it lands on; switch "Make this my active program" (default on); `FilledButton` "Save program". The builder keeps workouts in memory as `(key, ProgramWorkoutSource, name)` with keys from `SecureUuidFactory`; `ExistingChoice` reuses a key; `EditChoice` on a draft reopens the editor with `initialDraft` and replaces it. Template and saved-plan choices cannot be edited before Save (pass `current: null`-style behaviour by hiding "Edit workout" for them); they are editable on Your program afterwards. One `requestUuid` per page instance.

Validation messages: empty name "Give the program a name."; no training day "Add at least one workout day."; `ProgramWorkoutLimit` "A program can hold up to 30 workouts."; any other failure "Could not save this program. Nothing was saved.".

- [ ] **Step 1: Write failing widget tests**: build a program with one new workout (fake the editor result by pushing the route and popping a `DraftWorkoutSource` through a test override, or drive the real editor), one template copy, two rest-only days, save; expect one program with those days, active, and navigation to `/train/program/<uuid>`. Also: save with no name shows the name message; all rest shows the day message; back with changes asks "Discard this program?" ("Keep editing" / "Discard"); double tap on Save creates one program. In `programs_pages_test.dart`: Programs page shows a "Create program" button that opens `/train/programs/new`, and "Your programs" subtitle reads "Active · your own" / "Your own" for `sourceId == 'custom'`, "Active" / "Not active" otherwise. Programs page intro copy becomes "A weekly schedule of workouts. Add a ready-made one or create your own."
- [ ] **Step 2: Run** both test files. Expected: FAIL.
- [ ] **Step 3: Implement** the page, the route and the Programs page changes.
- [ ] **Step 4: Run** both test files. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): create a custom program`.

### Task 5: Your program page edits

**Files:**
- Modify: `apps/mobile/lib/features/train/my_program_page.dart`
- Test: `apps/mobile/test/train/programs_pages_test.dart` (or the existing My program tests there)

**Interfaces:**
- Consumes: Task 1 `updateDetails`, `addWorkout`; Task 2 program mode route; Task 3 `showDaySheet`.

- [ ] **Step 1: Write failing widget tests**: "Edit name" action (app bar icon, tooltip "Edit name") opens a kit dialog/sheet with name and description, saves via `updateDetails`; day sheet "New workout" pushes `/train/programs/<uuid>/workouts/new`, and the returned UUID is set on that day; "Copy a ready-made workout" adds and sets it; "Copy one of my saved workouts" adds a copy and sets it; at 30 workouts the add options are disabled; the old `NsDropdown` "Change to…" is gone (replaced by the sheet's list).
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement**, replacing `_editDay`'s sheet with `showDaySheet`; for `TemplateChoice` build `TemplateWorkoutSource` with `templateRowInputs(template, snapshot)` and `snapshot.release` from `catalogStateProvider`; `SavedPlanChoice` and other-program copies use `CopyWorkoutSource`; then `setDayPlan`. Failures use the existing `_failed` path with "Could not save this change. Try again." except the limit message.
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): add and rename workouts on Your program`.

### Task 6: Better fit today on Your program, with a swap start

**Files:**
- Modify: `apps/mobile/lib/features/train/train_library_state.dart` (`planFitProvider`)
- Modify: `apps/mobile/lib/features/train/active_workout_state.dart` (`startProgramDay`)
- Modify: `apps/mobile/lib/features/programs/presentation/start_program_day.dart`
- Modify: `apps/mobile/lib/features/train/my_program_page.dart`
- Test: `apps/mobile/test/train/train_plan_fit_test.dart`, `apps/mobile/test/programs/start_program_day_test.dart`

**Interfaces:**
- `planFitProvider` now reads the active program's workouts: `ref.watch(programWeekProvider)?.plans.values` (empty, so null fit, when no active program). `trainLibraryProvider` still supplies exercises.
- `WorkoutActions.startProgramDay(TrainingProgramRecord program, {required String? expectedPlanUuid, DateTime? missedDate, String? swapPlanUuid})`: when `swapPlanUuid != null` (only valid with `missedDate == null`), today must be a training day equal to `expectedPlanUuid` (else `ProgramDayChanged`), the swap plan must be a live workout of this program (else `StateError`), and the session starts with `planUuid: swapPlanUuid` and `programDay` today.
- `startProgramDay(...)` UI helper gains `String? swapPlanUuid` and passes it through.

- [ ] **Step 1: Write failing tests**: plan fit is computed over the active program's workouts and ignores standalone plans; null without an active program; swap starts a session with the swapped plan UUID and today's `programDayLocalDate`, after which `programWeekStatus` marks today done; swap on a rest day throws `ProgramDayChanged`; swap with a foreign plan throws `StateError`. Widget test: Your program shows a "Better fit today" card (existing `_fitCard` copy: "<groups> still recovering · this workout rests them" and "Lightest workout with recovered muscles · keep effort around RPE 7") when the suggestion differs from today's workout, and its Start uses the swap; per-day rows show the recovery line from `_recoveryLine`.
- [ ] **Step 2: Run** the two test files. Expected: FAIL.
- [ ] **Step 3: Implement**; move `_fitCard` and `_recoveryLine` from `train_page.dart` to a shared file `apps/mobile/lib/features/train/plan_fit_widgets.dart` and use them on Your program.
- [ ] **Step 4: Run**. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): better fit today suggests among the program's workouts`.

### Task 7: Train tab without plans

**Files:**
- Modify: `apps/mobile/lib/features/train/train_page.dart`
- Test: `apps/mobile/test/train/train_start_card_test.dart`, `train_plan_fit_test.dart`, `train_wide_layout_test.dart`, `training_library_layout_test.dart`, `training_library_wide_test.dart`, `train_header_text_scale_test.dart`

- [ ] **Step 1: Write failing widget tests**: Train shows no "Your plans", no "Create training plan", no "Better fit today"; quick-start card copy "Start recording reps and weights offline, or follow a program."; library cards "Programs" with subtitle "Ready-made and your own", "Workouts" with "Ready-made sessions to start", "Exercise library" unchanged; with an active program the "Your program" card and today's start remain; wide layout still two columns with the remaining content.
- [ ] **Step 2: Run** those files. Expected: FAIL.
- [ ] **Step 3: Implement**: delete `_startPlan`, `_planList`, `_fitCard`, `_recoveryLine` uses, the plans section and create button. Fix the start failure copy to "Could not start this workout. Check any unfinished workout.".
- [ ] **Step 4: Run**. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): Train offers quick workout and programs`.

### Task 8: Today without saved-plan suggestions

**Files:**
- Modify: `apps/mobile/lib/features/today/today_page.dart`, `apps/mobile/lib/features/today/today_overview.dart`
- Test: `apps/mobile/test/today/today_page_test.dart`, `today_overview_test.dart`

- [ ] **Step 1: Write failing tests**: with no active program the hero reads eyebrow "GET STARTED", title "No program yet", subtitle "Pick a program to get a workout each day, or start a quick workout and add exercises as you go.", actions "Pick a program" (opens `/train/programs`) and "Go to Train"; standalone plans never appear on Today even when they exist; with an active program Today is unchanged.
- [ ] **Step 2: Run**. Expected: FAIL.
- [ ] **Step 3: Implement**: remove `nextPlan`, `NextPlan`, `_startPlan` and their tests; `_Hero` becomes the no-program hero only.
- [ ] **Step 4: Run**. Expected: PASS.
- [ ] **Step 5: Commit** `feat(today): point to programs instead of saved plans`.

### Task 9: Template page without "Copy to My Plans"

**Files:**
- Modify: `apps/mobile/lib/features/train/template_detail_page.dart`
- Modify: `apps/mobile/lib/features/workouts/domain/workout_library_repository.dart`, `.../data/objectbox_workout_library_repository.dart` (remove `copyCatalogTemplate`, now unused)
- Test: `apps/mobile/test/train/template_detail_page_test.dart` and the repository tests that cover `copyCatalogTemplate`

- [ ] **Step 1: Write failing test**: the template page shows "Start workout" and no copy button; library doc comment above class no longer mentions My Plans.
- [ ] **Step 2: Run**. Expected: FAIL.
- [ ] **Step 3: Implement**: remove `_copy`, `onCopy`, `_saved`, the copy button, `copyCatalogTemplate` and its tests (check `grep -rn copyCatalogTemplate lib test` is empty).
- [ ] **Step 4: Run** the template and workouts tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): ready-made workouts are start-only`.

### Task 10: Watch snapshot and watch wording

**Files:**
- Modify: `apps/mobile/lib/features/watch/application/watch_snapshots.dart`
- Modify: `apps/watch_os/Sources/Features/Train/TrainPage.swift` (file holding "No plans yet..."), `apps/watch_os/Sources/Features/Workout/PlanPreviewView.swift`
- Modify: `apps/wear_os/app/src/main/java/in/beyondrep/wear/ui/TrainScreen.kt`, `.../ui/PlanPreviewScreen.kt`
- Test: `apps/mobile/test/watch/watch_snapshots_test.dart`

- [ ] **Step 1: Write failing tests**: with an active program the snapshot lists today's workout first, then the program's other workouts in day order (each once), and no standalone plan; without an active program it lists nothing and the today slot is absent; a workout with a blank name is sent as "Workout"; byte budget behaviour unchanged.
- [ ] **Step 2: Run** `flutter test test/watch/watch_snapshots_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement**: `others` comes from `week.plans` ordered by first `dayIndex` that uses each (then unused workouts by name); drop `library.plans` as a source. Swift: "No program yet. Pick one in BeyondRep on your iPhone." and "This workout is not on your watch yet."; Kotlin: "No program yet. Pick one in BeyondRep on your phone." and "This workout is not on your watch yet.". Grep both watch trees for other user-visible "plan" strings and change them the same way; leave identifiers and wire keys.
- [ ] **Step 4: Run** the watch tests. Swift and Kotlin compile on CI only; say so in the PR.
- [ ] **Step 5: Commit** `feat(watch): watches show the active program's workouts`.

### Task 11: Wording guard and docs

**Files:**
- Create: `apps/mobile/test/plan_wording_guard_test.dart` (modelled on `test/energy_wording_guard_test.dart`)
- Modify: any `lib/` string the guard finds (for example `start_program_day.dart` `_startFailedMessage` becomes "Could not start this workout. Check the program and any unfinished workout.")
- Modify: `docs/ROADMAP.md`, `docs/RELEASE.md` (device checks: create a program, add workouts on Your program, Better fit swap, watch Train page), `CLAUDE.md` project state (one bullet: implemented in source, not released or device-verified), `docs/DESIGN_SYSTEM.md` only if a new pattern was added, `docs/CATALOG.md` if it mentions copying to My Plans.

- [ ] **Step 1: Write the guard test**: every string literal under `lib/` matching `\bplans?\b` (case-insensitive) fails, except literals containing `/train/plans/` and the watch wire keys (`plan_id`, `plans`) in `lib/features/watch/`.
- [ ] **Step 2: Run** `flutter test test/plan_wording_guard_test.dart`. Expected: FAIL listing remaining hits.
- [ ] **Step 3: Fix** each hit with "workout" or "program" wording.
- [ ] **Step 4: Run** the full gate: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, and from the repo root `python3 -m unittest discover -s tool -p 'test_*.py'`. Expected: all pass.
- [ ] **Step 5: Commit** `test: no user-visible plan wording; docs for programs stage 1`.
