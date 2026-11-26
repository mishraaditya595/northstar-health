# Training library stage 8: Today and scheduling, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Today shows the active program's workout for today, or a rest day, with a Start button.
- Today also shows a "Missed <weekday>: <workout>" line that starts that missed day.
- Each program day knows whether it is done, missed, today or upcoming, following the spec's rules.
- Workouts and Programs get the remaining filters: goal, equipment and days per week.
- The owner can retire a workout template or program so it leaves the lists. Users' copies are unaffected.

**Architecture:**
- **Day statuses** are pure functions over the program record, the local date and the user's finished sessions. They are computed fresh each time and never stored.
- **Missed day:** Today and Your program call the existing program-day start path. To start a missed day it takes an explicit missed date, which is checked again at the tap.
- **Filters** live in a pure `catalogue filter` model plus a kit sheet, following the exercise filter pattern from stage 5.
- **Retiring** adds an optional `status` to templates and programs in the catalogue schema. This is additive, so `minAppCatalogSchema` stays 1. The validator, the phone parser and the browse lists honour it.

**Tech Stack:** Python validator and build, Flutter 3.47.7, ObjectBox 5 (no entity changes expected), Riverpod 3, go_router.

**Spec:** `docs/superpowers/specs/2026-11-25-training-library-design.md` sections 6.5 (all of it), 6.7 (Today, My program) and 9 (Schedule). Also read `docs/CATALOG.md` (including "Changing content after launch"), the stage 7 plan and code under `lib/features/programs/`, and `lib/features/today/`.

## Decisions this plan makes

- **Only the active program schedules.** Starting a program day is allowed only for the active program. Stage 7 allowed inactive programs; that is tightened here. An inactive program's screen shows "Make this your active program to start its workouts" instead of Start. Its older sessions keep their program fields, but nothing reads them unless the program becomes active again.
- **The program week:** `weekStart` is the most recent date on or before today whose ISO weekday equals `firstDayWeekday`. The window for missed days runs from `max(weekStart, activatedLocalDate)` to yesterday.
- **Day statuses**, for each date in the current program week:
  - `rest`: the scheduled day has no plan.
  - `unavailable`: the day's plan is missing or archived.
  - `done`: a finished session exists, meaning `completed`, not deleted, with `programUuid` equal to this program and `programDayLocalDate` equal to that date.
  - `today`: the date is today and the day is not done.
  - `missed`: the date is in the missed-day window and the day is not done.
  - `upcoming`: any later date, and any earlier date in the week that falls before the program was activated.
  - Sessions from My Plans, templates or Quick workout never count, even when they use the same plan.
- **Today card**, in priority order:
  1. An unfinished workout or a recovery error keeps today's hero, exactly as now.
  2. With an active program, a program hero replaces the "Next up" plan hero:
     - Eyebrow: `TODAY · <PROGRAM NAME>`.
     - Title: the workout name, "Rest day", or "Done for today".
     - Subtitle: "<n> exercises · about <m> min" for a training day, or "Next: <weekday> · <workout>" on a rest or done day.
     - Actions: "Start" on a training day that isn't done, plus "Open program".
  3. Without an active program, today's `nextPlan` hero is unchanged.
- **Missed line:** with an active program and at least one missed day, an `NsListCard` under the hero reads "Missed <weekday>: <workout>" for the most recent missed day. Tapping it opens a kit confirm, "Start <workout> for <weekday>?". Confirming starts it with `programDayLocalDate` set to the missed date, which marks that day done. Older misses in the same week are reachable from Your program, where each missed row has "Start for <weekday>". A new program week clears them.
- **Re-checking at the tap:**
  - For a missed day: at the tap, the start re-checks that the date is still missed against the current clock and the current schedule. If not, it refreshes and shows "This day changed. Check it and try again."
  - For today: the stage 7 rule is kept.
- **Your program week view:** each row gets an `NsTag` (Done, Missed, Today, Rest, Upcoming or Unavailable). It keeps the stage 7 edit sheet and adds "Start for <weekday>" on missed rows.
- **Filters:**
  - Workouts and Programs each get a "Filters" `SquareButton` in the header that opens a `showNsSheet` of `NsChip` groups:
    - Goal, multi-select, any match.
    - "Equipment I have", multi-select. An item is shown when every piece of equipment it needs is selected. `bodyweight` always counts as available. With nothing selected, this filter is off.
    - Days per week, Programs only, 2 to 6, single select.
  - The level chips stay where they are.
  - A "Filters (n)" label shows how many filters are active, and the sheet has "Clear".
  - Filters are not persisted.
- **Retiring templates and programs:**
  - Add an optional `"status": "active" | "retired"` to template and program objects in `catalog.schema.json`. It is optional and defaults to `active`, so existing JSON stays valid.
  - **Validator:** an active program must not use a retired template. A retired template or program may stay referenced only by retired programs.
  - **Older-app safety:** a retired template must still reference only active exercises. Older apps ignore `status` and still check those references.
  - **Phone:** `browsableTemplates` and `browsablePrograms` hide retired items. The detail routes for a retired item show "This workout is no longer available" or "This program is no longer available". Copies, imported programs and sessions are never touched.
  - **Known limit,** documented in CATALOG.md: app builds from before stage 8 ignore `status`, so they keep showing a retired item until they update. Hiding it on those builds would need a `minAppCatalogSchema` bump.
  - **No new catalogue release in this stage.** It changes the schema and code only, and the next content release can use `status`.
- **Out of scope:** history of schedule edits, rolling 14-day programs, notifications and reminders, and progress or insight changes.

## Running checks

From the repo root, run `python3 -m unittest discover -s tool -p 'test_*.py'` and `python3 scripts/catalog_build.py check`. From `apps/mobile/`, run `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze` and `flutter test`. Flutter is at `/opt/sdk/flutter/bin`.

## Global Constraints

- No sync contract change. Program fields stay local-only, and no new upload keys are added.
- No ObjectBox entity changes are expected. If one turns out to be needed, follow the additive and migration-test rules from stage 7 and report it.
- Design kit only: `NsHeroFrame`, `NsHeroAction`, `NsListCard`, `NsTag`, `NsChip`, `SquareButton`, `showNsSheet`, `showNsConfirm` and `showNsMessage`. Support light and dark, text scale 2.0 at 390 × 844, and screen-reader labels, for example "Missed Tuesday: Pull day. Start it now".
- Clock: every status and start decision uses the injectable clock (`workoutClockProvider` and `localNowProvider`). Never call `DateTime.now()` inside pure functions.
- Synthetic data only in tests.

## Review Focus

1. **Status rules** at every `firstDayWeekday` from 1 to 7, across a week boundary, and with an activation in the middle of the week. Check that a session from My Plans for the same plan never marks a day done (Task 1).
2. **Midnight and time zones:** a session started at 23:50 and finished after midnight counts for its start date. A clock moving between build and tap re-checks before starting (Tasks 1 and 3).
3. **Missed start:** it marks exactly that date done, is refused for a date that is no longer missed, and is refused for an inactive program (Task 3).
4. **Today priority:** an unfinished workout is shown above the program hero, and with no active program the existing behaviour is unchanged (Task 4).
5. **Retired content:** the validator rules, browse hiding, the detail message, existing copies unaffected, and the older-app reference safety (Task 6).
6. **Text scale 2.0** on Today with the missed line, on Your program with tags, and on the filter sheets (Tasks 4, 5 and 7).

---

### Task 1: Day status rules (pure)

**Files:** `lib/features/programs/domain/program_schedule.dart` (or a new `program_status.dart`), with tests in `test/programs/program_status_test.dart`.

**Interfaces:**
- `enum ProgramDayStatus { rest, unavailable, done, today, missed, upcoming }`
- `DateTime programWeekStart(DateTime localToday, int firstDayWeekday)`
- `List<({DateTime date, int dayIndex, ProgramDayRecord day, ProgramDayStatus status})> programWeekStatus({required TrainingProgramRecord program, required DateTime localToday, required Iterable<WorkoutSessionRecord> sessions, required Set<String> availablePlanUuids})`
- `({DateTime date, ProgramDayRecord day})? latestMissed(...)`, using the same inputs.
- `({DateTime date, ProgramDayRecord day})? nextTraining(...)`, for the "Next:" subtitle. It may look into the next week.

- [ ] **Step 1:** Write failing table tests:
  - Every `firstDayWeekday` from 1 to 7 against two "today" dates.
  - Activated mid-week, so earlier days are upcoming, not missed.
  - A done day from a matching session.
  - A completed session with no program or another program's UUID is not done.
  - A discarded or deleted session is not done.
  - A session dated yesterday marks yesterday done.
  - A rest day is never missed.
  - An unavailable plan.
  - A new week clears the misses.
  - `latestMissed` picks the most recent missed day.
  - `nextTraining` skips rest days and wraps into next week.
- [ ] **Step 2:** Run `flutter test test/programs`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/programs`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(programs): done, missed and upcoming day rules`

### Task 2: Session source for statuses

**Files:** `lib/features/programs/application/program_providers.dart`, plus a repository method if needed, and tests.

**Interfaces:**
- `programWeekProvider` (autoDispose) combines the active program, its available plan UUIDs, `localNowProvider` and the finished sessions that carry the active program's UUID.
- Prefer an indexed query on `WorkoutSessionEntity.programUuid` through the workout repository, for example `listProgramSessions(programUuid, fromLocalDate)`, over loading all history. Add an `@Index()` only if it is missing, as an additive model change with a regenerated model and a migration-test update.
- The provider is invalidated after a workout is finished or discarded, after program edits, and on resume (through `localNowProvider`).

- [ ] **Step 1:** Write failing tests:
  - Finishing a program-day workout flips that day to done in the provider.
  - Discarding it does not.
  - An account switch shows the other account's programs only.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(programs): weekly program status provider`

### Task 3: Start rules: active only, missed days

**Files:** `lib/features/train/active_workout_state.dart` (`startProgramDay`), `lib/features/train/my_program_page.dart`, with tests.

**Interfaces:**
- `startProgramDay(program, {required String? expectedPlanUuid, DateTime? missedDate})`:
  - It throws `StateError` when the program is not active.
  - Without `missedDate`: today's day, as in stage 7.
  - With `missedDate`: at the tap, it recomputes `programWeekStatus` with the clock, the current schedule and the sessions. The date must be `missed` and its plan must equal `expectedPlanUuid`; otherwise it throws `ProgramDayChanged`. The session's `programDayLocalDate` is set to `localDateKey(missedDate)` and `startedAtUtc` to now.
- Your program: status tags on each row, and "Start for <weekday>" on missed rows. An inactive program shows the "Make this your active program…" line instead of Start.

- [ ] **Step 1:** Write failing tests:
  - Starting an inactive program throws, and nothing is written.
  - Starting a missed day stores that date and the day becomes done.
  - A missed date that is now done, or is now a rest day after an edit, throws `ProgramDayChanged`.
  - A missed date outside the window throws.
  - A widget test for the tags and the start on a missed row.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/programs test/train`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(programs): start missed days and only the active program`

### Task 4: Today program card and missed line

**Files:** `lib/features/today/today_page.dart` (with a new `today_program_card.dart` if that is cleaner), with tests in `test/today/`.

**Interfaces:** follow the Today card and Missed line rules in the Decisions. Start goes through `startProgramDay` with the readiness confirmation and the active-workout message, then navigates to `/train/workout`. "Open program" goes to `/train/program/:uuid`.

- [ ] **Step 1:** Write failing widget tests:
  - Training day, with Start leading to the logger.
  - Rest day showing the "Next:" subtitle.
  - Done for today.
  - The missed line, confirm, start, and the missed date recorded.
  - With no active program, the old Next up hero.
  - An unfinished workout takes priority.
  - Text scale 2.0 in light and dark with the missed line.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/today test/programs`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(today): active program card and missed day line`

### Task 5: Goal, equipment and frequency filters

**Files:** `lib/features/catalog/domain/catalog_filter.dart` (pure), a kit-built `lib/features/train/catalog_filter_sheet.dart`, `workout_templates_page.dart` and `programs_page.dart`, with tests.

**Interfaces:**
- `class CatalogFilter { Set<String> goals; Set<String> equipment; int? daysPerWeek; String? level; String query; bool get isEmpty; int get activeCount; }`
- `bool matchesTemplate(CatalogTemplate, CatalogFilter)` and `bool matchesProgram(CatalogProgram, CatalogFilter)`, following the rules in the Decisions. Equipment labels come from the existing equipment label map.

- [ ] **Step 1:** Write failing unit tests for every rule, including bodyweight always counting as available and an empty filter matching everything. Write widget tests too: open the sheet, pick a goal and equipment, the list narrows, "Filters (2)" appears, and Clear restores the list. Include text scale 2.0 on the sheet.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `flutter test test/catalog test/train test/design_kit_guard_test.dart`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(train): goal, equipment and days-per-week filters`

### Task 6: Retire templates and programs

**Files:** `catalog/schema/catalog.schema.json`, `scripts/catalog_validate.py`, the `tool/test_catalog_*.py` tests, the phone parser and models, `browsableTemplates`, `browsablePrograms`, the template and program detail pages, `docs/CATALOG.md` and `catalog/README.md`.

**Interfaces:**
- Schema: an optional `status` on template and program, from the existing enum.
- Validator: an active program must not use a retired template, and every template must use only active exercises (unchanged).
- Phone: `CatalogTemplate.status` and `CatalogProgram.status`, defaulting to active. Hide retired items, and show the "no longer available" detail message.
- First confirm that the parser shipped at `68064b3` and `b9559ad` ignores unknown keys on templates and programs. Read it with `git show <sha>:apps/mobile/lib/features/catalog/domain/catalog_parser.dart`. If either would reject `status`, stop and report, because that needs a `minAppCatalogSchema` decision.

- [ ] **Step 1:** Write failing tests:
  - Python: a retired template used by an active program is rejected; a retired program and its retired template are accepted; a retired template with a retired exercise is rejected.
  - Dart: parsing `status`, the browse lists hiding retired items, the detail message, and an existing copied plan or imported program staying unchanged.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. Update CATALOG.md's "Templates and programs cannot be retired yet" bullet to describe the feature and the older-build limit, and update `catalog/README.md`.
- [ ] **Step 4:** Run the Python checks and `flutter test test/catalog test/train`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(catalog): retire workout templates and programs`

### Task 7: Docs and device rows

- [ ] **Step 1:** Update `docs/ROADMAP.md` (stage 8) and the "Today and scheduling" device rows in `docs/RELEASE.md`. The rows cover: the program card on a training day, a rest day and a done day; the missed line and starting it; a session across midnight; a time-zone change after starting; a schedule edit after sessions; a program switch; the filters; and text scale 2.0.
- [ ] **Step 2:** Run all the Running checks. Expected: PASS.
- [ ] **Step 3:** Commit `docs: stage 8 Today and scheduling`
