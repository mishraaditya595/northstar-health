# Phase 4 stage 1: tablet layouts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On windows 840 dp and wider, Today, Health, Health details, Progress, the training library and Train use the width (grids, two columns, list and detail side by side); narrower windows keep today's layouts unchanged.

**Architecture:** Four layout primitives go into the shared kit (`lib/core/design/layout.dart`) first; each feature then swaps its single column for one of them when `isWideWindow(context)` is true. Detail pages gain an `embedded` mode so the same page renders inside a list's right pane. No data, provider, route or storage changes.

**Tech Stack:** Flutter 3.47.7, Riverpod, go_router, flutter_test widget tests.

**Spec:** `docs/superpowers/specs/2026-11-26-phase-4-watch-and-tablet-design.md` §5.1. Mockups: https://claude.ai/artifact/Ti6r6dNGEiJF9zReV9b57V (the look; real content wins where the mockup simplified it).

## Global Constraints

- Wide means **window width ≥ 840 dp** (`MediaQuery.sizeOf(context).width`). Below 840 every screen must render exactly as on `main` (existing tests stay green unmodified).
- Shell cap stays 1120 dp (`beyondrep_app.dart`); the rail still appears at 600. Do not touch the shell.
- Portrait iPad (820 × 1180) and split view (507 × 1024) are **not** wide.
- Live workout (`/train/workout`), sign-in, account, plan editor and the conflict review stay single column.
- Kit rule (AGENTS.md 4): layout widgets live in `lib/core/design/`; features never call raw `TextField`, `showDialog`, etc. `test/design_kit_guard_test.dart` must pass.
- Must hold at 200 % text: no `RenderFlex overflowed` at 1194 × 834 and 1366 × 1024.
- Light and dark both render (theme tokens only, no new colours).
- Each task ends with `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze` and the task's tests green, run from `apps/mobile/`.

## Review Focus

1. **Window narrows while a detail is open** (iPad split view dragged from 1194 to 507): the open item must stay open as a pushed page, not vanish. Test in Task 1 (kit) and Task 4 (Progress).
2. **Embedded detail pops the tab:** an action inside an embedded detail that used to `pop`/`pushReplacement` (program detail "Add program") must not remove the list page. Test in Task 5.
3. **Selected item disappears** (workout deleted elsewhere, account switch, catalogue refresh drops an id): the pane falls back to the empty-detail message, no exception. Test in Task 4.
4. **200 % text on 1194 wide:** grids drop to fewer columns instead of overflowing. Test in Task 1 (grid) and Task 7 (sweep).
5. **Phone unchanged:** 390 × 844 screens must not pick up wide layouts through a `LayoutBuilder` width check (content can be ≥ 840 only on a wide window). Test in Task 7.

---

### Task 1: Layout primitives in the kit

**Files:**
- Create: `apps/mobile/lib/core/design/layout.dart`
- Modify: `docs/DESIGN_SYSTEM.md` (add four rows to the "Shared Flutter components" table)
- Test: `apps/mobile/test/core/layout_test.dart`

**Interfaces:**
- Produces:
  - `const double kWideWindowWidth = 840;`
  - `bool isWideWindow(BuildContext context)` — `MediaQuery.sizeOf(context).width >= kWideWindowWidth`.
  - `class NsResponsiveGrid extends StatelessWidget` — `({required List<Widget> children, double minItemWidth = 320, int maxColumns = 3, double spacing = 12})`. Columns = clamp(floor((width + spacing) / (textScaler.scale(minItemWidth) + spacing)), 1, maxColumns) from its `LayoutBuilder` width; rows of equal-width cells, top-aligned; the last row's empty cells stay empty (no stretching).
  - `class NsSplitColumns extends StatelessWidget` — `({required List<Widget> main, required List<Widget> side, int mainFlex = 3, int sideFlex = 2, double gap = 20})`. Wide window: a `Row` of two top-aligned `Column`s; otherwise one `Column` of `main` then `side`.
  - `class NsListDetail extends StatefulWidget` — `({required Widget list, required Widget? detail, required Widget emptyDetail, String? selectedRoute, ValueChanged<String>? onCollapsed, double listWidth = 360})`. Wide window: `Row(list in SizedBox(width: listWidth), VerticalDivider(width: 1), Expanded(detail ?? emptyDetail))`. Narrow: `list` only. When a build goes from wide to narrow while `selectedRoute != null`, it calls `onCollapsed(selectedRoute)` once in a post-frame callback.
  - `void openListItem(BuildContext context, {required String route, required VoidCallback select})` — wide: calls `select`; narrow: `context.push(route)`.

- [ ] **Step 1: Write the failing tests** (`layout_test.dart`)
  - `isWideWindow is false at 839 and true at 840`
  - `NsResponsiveGrid uses 3 columns at 1040 wide, 2 at 700, 1 at 360` (assert cell x-offsets: three distinct `getTopLeft().dx` values, etc.)
  - `NsResponsiveGrid drops to 2 columns at 1040 wide with 2.0 text scale` (no overflow exception: `expect(tester.takeException(), isNull)`)
  - `NsSplitColumns puts side beside main when wide, below main when narrow` (compare `getTopLeft` of a side child vs the main child at 1194 × 834 and 390 × 844)
  - `NsListDetail shows emptyDetail when detail is null and wide`
  - `NsListDetail shows only the list when narrow`
  - `NsListDetail calls onCollapsed once with the selected route when the window narrows` (pump at 1194, then set `physicalSize` 507 × 1024, `pump()` twice; expect the callback list `== ['/x/1']`)
  - `openListItem selects when wide and pushes when narrow` (use a `GoRouter` with `/` and `/x/:id`; narrow expects the `/x/1` page on top)

- [ ] **Step 2: Run** `flutter test test/core/layout_test.dart` — expect FAIL (`layout.dart` missing).
- [ ] **Step 3: Implement** `layout.dart` with the signatures above.
- [ ] **Step 4: Run** the test file — expect PASS. Run `flutter test test/design_kit_guard_test.dart` — PASS.
- [ ] **Step 5: Document** the four primitives in `docs/DESIGN_SYSTEM.md` (Need / Use / File rows: "Wide-window check", "Equal-width card grid", "Main and side columns", "List with detail pane").
- [ ] **Step 6: Commit** `feat(design): wide-window layout primitives`

---

### Task 2: Today on a wide window

**Files:**
- Modify: `apps/mobile/lib/features/today/today_page.dart` (`build`, ~lines 140–250)
- Test: `apps/mobile/test/today/today_wide_layout_test.dart`

**Interfaces:**
- Consumes: `isWideWindow`, `NsSplitColumns` (Task 1).

Layout when wide: `PageHeader` and `BackupStatusNotice` stay full width on top. Below, `NsSplitColumns(mainFlex: 1, sideFlex: 1)`: **main** = the hero branch (unfinished / recovery / program hero / next plan / error / loading, unchanged), `TodayMissedLine`, "This week" heading and `_WeekCard`; **side** = "Recent health" heading and `TodayHealthRow`. Narrow keeps the current `ListView` children order exactly.

- [ ] **Step 1: Write the failing tests** using the helpers in `test/today/today_program_test_support.dart` (`pumpTodayProgram(..., size:)`):
  - `wide Today puts Recent health beside the hero` — at 1194 × 834: `find.text('Recent health')` dy < the `_WeekCard` text `'This week'` dy, and its dx > half the content width.
  - `portrait iPad Today keeps one column` — at 820 × 1180: 'Recent health' dy > hero dy and dx equal to the hero's left edge.
  - `wide Today at 2x text has no overflow` — 1366 × 1024, `textScaleFactor` 2.0 via `MediaQuery`, `tester.takeException()` is null.
- [ ] **Step 2: Run** `flutter test test/today/today_wide_layout_test.dart` — FAIL.
- [ ] **Step 3: Implement** the branch in `today_page.dart`.
- [ ] **Step 4: Run** the new file and `flutter test test/today` — PASS.
- [ ] **Step 5: Commit** `feat(today): two-column Today on wide windows`

---

### Task 3: Health tab and Health detail screens

**Files:**
- Modify: `apps/mobile/lib/features/health/health_page.dart` (the readiness card plus the `LayoutBuilder` pairing block, ~lines 238–275)
- Modify: `apps/mobile/lib/features/health/widgets/detail_layout.dart` (add `DetailPanels`)
- Modify: the five detail pages in `apps/mobile/lib/features/health/detail/` (`readiness_`, `sleep_`, `heart_`, `activity_`, `body_detail_page.dart`): every **top-level** `Column` of `DetailPanel`s returned to `HealthDetailScaffold.builder` becomes `DetailPanels`
- Test: `apps/mobile/test/health/health_wide_layout_test.dart`

**Interfaces:**
- Consumes: `isWideWindow`, `NsResponsiveGrid`, `NsSplitColumns`.
- Produces: `class DetailPanels extends StatelessWidget` — `({required List<Widget> children, double spacing = 12})`. Wide: `NsSplitColumns(main: [children.first], side: children.skip(1) with spacing)`; narrow: the same `Column` the pages build today (same spacing, so narrow goldens/tests do not move).

Health tab when wide: `NsResponsiveGrid(maxColumns: 3, minItemWidth: 320)` over `[ReadinessCard, Sleep, Heart, Activity, Body]` in that order. Everything above (date line, insight cards) and below (From your training, iOS hint, Disconnect) is unchanged. Narrow keeps the existing `pair()` logic untouched.

- [ ] **Step 1: Write the failing tests** (use `pumpHealth` from `test/health/health_cards_test.dart` or `test/support/fake_health_overview.dart` with `health_overview_fixtures.dart`):
  - `wide Health lays the five cards in three columns` — at 1194 × 834 the Readiness, Sleep and Heart card titles share one dy; Activity and Body share the next.
  - `narrow Health keeps readiness full width` — at 390 × 844 the readiness card width equals the content width (unchanged).
  - `wide sleep detail shows later panels beside the first` — pump `SleepDetailPage` at 1194 × 834 with the fixture overview; the second `DetailPanel`'s dx > the first's dx.
  - `wide health details at 2x text have no overflow` — each of the five detail pages at 1366 × 1024, text scale 2.0, `takeException()` null.
- [ ] **Step 2: Run** `flutter test test/health/health_wide_layout_test.dart` — FAIL.
- [ ] **Step 3: Implement** `DetailPanels`, the grid branch in `health_page.dart`, and swap the top-level Columns in the five pages.
- [ ] **Step 4: Run** the new file and `flutter test test/health` — PASS (existing detail tests unchanged).
- [ ] **Step 5: Commit** `feat(health): card grid and split detail screens on wide windows`

---

### Task 4: Progress history as list and detail

**Files:**
- Modify: `apps/mobile/lib/features/progress/progress_page.dart` (session tap ~line 254, outside workout tap ~line 221, `build`)
- Modify: `apps/mobile/lib/features/progress/workout_history_detail_page.dart`, `outside_workout_detail_page.dart` (add `embedded`)
- Test: `apps/mobile/test/progress/progress_wide_layout_test.dart`

**Interfaces:**
- Consumes: `NsListDetail`, `openListItem`, `isWideWindow`.
- Produces: `WorkoutHistoryDetailPage({required String sessionUuid, bool embedded = false})` and `OutsideWorkoutDetailPage({required String workoutId, bool embedded = false})`. `embedded: true` → `AppBar(automaticallyImplyLeading: false, leading: null)`; nothing else changes.

`_ProgressPageState` keeps `String? _selectedRoute` (`/progress/workouts/<uuid>` or `/progress/health-workouts/<id>`). Taps use `openListItem(context, route: ..., select: () => setState(() => _selectedRoute = route))`. The existing scrolling page becomes `NsListDetail.list`; `detail` is the embedded page for the route (parse the id from the route), keyed by route so switching items resets state. `emptyDetail`: centred `HealthCaption`-style muted text **"Pick a workout to see its sets."** `onCollapsed`: clear `_selectedRoute`, then `context.push(route)`. If the selected session uuid is no longer in `completedWorkoutHistoryProvider` (or the outside id no longer in its provider), render `emptyDetail` and clear the selection.

- [ ] **Step 1: Write the failing tests** (reuse the pump helper in `test/progress/progress_page_widget_test.dart`, passing a size):
  - `wide Progress opens a workout in the right pane` — 1194 × 834, tap a session card; its detail title appears and `find.byType(ProgressPage)` is still present; no route pushed (`GoRouter.of(...).state.uri.path == '/progress'`).
  - `narrow Progress still pushes the detail page` — 390 × 844, tap; path is `/progress/workouts/<uuid>`.
  - `wide Progress shows the empty message before a pick` — text "Pick a workout to see its sets." present.
  - `selected workout removed falls back to the empty message` — select, then override the history provider without that session, pump; empty text shown, `takeException()` null.
  - `narrowing with a workout open pushes it` — select at 1194, resize to 507 × 1024, pump twice; path is `/progress/workouts/<uuid>`.
- [ ] **Step 2: Run** `flutter test test/progress/progress_wide_layout_test.dart` — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the new file and `flutter test test/progress` — PASS.
- [ ] **Step 5: Commit** `feat(progress): history list and detail side by side on wide windows`

---

### Task 5: Exercises, Workouts and Programs as list and detail

**Files:**
- Modify: `apps/mobile/lib/features/train/exercise_catalog_page.dart` (tap ~line 180), `workout_templates_page.dart` (~142), `programs_page.dart` (catalogue programs ~155 only; "Your programs" rows at ~70 keep pushing `/train/program/<uuid>`)
- Modify: `exercise_detail_page.dart`, `template_detail_page.dart`, `program_detail_page.dart` (add `embedded`)
- Test: `apps/mobile/test/train/training_library_wide_test.dart`

**Interfaces:**
- Consumes: `NsListDetail`, `openListItem`.
- Produces: `ExerciseDetailPage({required String exerciseId, bool embedded = false})`, `TemplateDetailPage({required String templateId, bool embedded = false})`, `ProgramDetailPage({required String programId, bool embedded = false})`.

Same pattern as Task 4 with empty messages **"Pick an exercise to see how it's done."**, **"Pick a workout to see every exercise."**, **"Pick a program to see its weeks."** In `program_detail_page.dart`, after "Add program" succeeds: `embedded ? context.push('/train/program/${created.uuid}') : context.pushReplacement(...)` (as today). Template "Start now" keeps `context.push('/train/workout')`.

- [ ] **Step 1: Write the failing tests** with `pumpLibraryScreen` and the fixtures in `test/train/training_library_harness.dart`:
  - `wide exercise catalogue opens detail beside the list` (location `/train/exercises`, 1194 × 834; note the harness's existing 1180 × 820 size is also wide, 820 × 1180 is not).
  - `wide workouts list opens a template beside the list and Copy to My Plans works there` (tap the action in the pane; the plan is created; list still visible).
  - `wide Add program from the pane keeps the programs list underneath` — after Add, pop once and the `/train/programs` list is on screen.
  - `narrow library taps still push` — 390 × 844 for each of the three lists.
- [ ] **Step 2: Run** `flutter test test/train/training_library_wide_test.dart` — FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the new file and `flutter test test/train` — PASS (including `training_library_layout_test.dart` unchanged).
- [ ] **Step 5: Commit** `feat(train): library lists with a detail pane on wide windows`

---

### Task 6: Train on a wide window

**Files:**
- Modify: `apps/mobile/lib/features/train/train_page.dart` (sections "Start training" ~175, "Your program" ~232, "Your plans" ~243, "More ways to move" ~263)
- Test: `apps/mobile/test/train/train_wide_layout_test.dart`

**Interfaces:**
- Consumes: `NsSplitColumns`, `NsResponsiveGrid`.

Wide: "Start training" (main) and "Your program" (side) in `NsSplitColumns(mainFlex: 1, sideFlex: 1)`; when there is no program, Start training stays full width. "Your plans" cards in `NsResponsiveGrid(maxColumns: 2, minItemWidth: 320)`. "More ways to move" unchanged.

- [ ] **Step 1: Write the failing tests:**
  - `wide Train puts Your program beside Start training` (1194 × 834, program fixture from `today_program_test_support.dart`).
  - `wide Train without a program keeps Start training full width`.
  - `wide Train lays plans in two columns` (three plans: first two share dy).
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** the file and `flutter test test/train` — PASS.
- [ ] **Step 5: Commit** `feat(train): two-column Train on wide windows`

---

### Task 7: Layout sweep and release docs

**Files:**
- Create: `apps/mobile/test/accessibility/wide_layout_sweep_test.dart`
- Modify: `docs/RELEASE.md` (Phase 4 stage 1 section), `docs/ROADMAP.md` (Phase 4 renamed "Apple Watch companion and tablet layouts"; old write-back phase moved after it as "Phase 5 — User-controlled completed-workout export", watch-recording text folded into Phase 4, Wear OS listed as its own later phase), `CLAUDE.md` (one line under Project state: stage 1 implemented in source, not released or device-verified)

- [ ] **Step 1: Write the sweep test.** For each location in `['/today', '/train', '/train/exercises', '/train/workouts', '/train/programs', '/progress', '/health', '/health/readiness', '/health/sleep', '/health/heart', '/health/activity', '/health/body']`, each size in `{390×844, 820×1180, 507×1024, 1194×834, 1366×1024}`, both brightnesses, text scale 1.0 and 2.0: pump the signed-in app (`signedInApp` in `test/app_test.dart` style with the existing fakes), `pumpAndSettle`, and `expect(tester.takeException(), isNull)`. Plus `phone sizes never show a detail pane`: at 390 × 844 no `VerticalDivider` inside `NsListDetail` is found on `/progress` and `/train/exercises`.
- [ ] **Step 2: Run** it — PASS (it guards Tasks 2–6; fix any overflow it finds in the owning file).
- [ ] **Step 3: Add** to `RELEASE.md` a "Phase 4 stage 1: tablet layouts" table with rows, all **not run**: iPad simulator landscape (Today, Train, library, Progress, Health, each detail) in light and dark; split view dragged across 840 with a detail open; 200 % text on iPad; iPad portrait unchanged.
- [ ] **Step 4: Update** `ROADMAP.md` and `CLAUDE.md` as listed.
- [ ] **Step 5: Run** the full gate from `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`; and `python3 -m unittest discover -s tool -p 'test_*.py'` from the repo root (docs edits). All PASS.
- [ ] **Step 6: Commit** `test: wide layout sweep; docs: Phase 4 stage 1 status`
