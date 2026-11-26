# Workouts from other apps (health polish stage 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read workouts that other apps saved to HealthKit / Health Connect, merge them with overlapping BeyondRep sessions, show them in Activity, Progress history and the Today Workouts tile, and add recent training load as a fifth readiness input.

**Architecture:** `PlatformHealthReader` gains one workout read. The health overview reads the last 90 days of outside workouts with its other reads, holds them in memory only (a new `workouts` section) and joins them with BeyondRep's completed-workout history (read-only, as stage 3's training insights do) for the merge and for training load. UI reads the overview; average heart rate per workout is a lazy in-memory read.

**Tech Stack:** Flutter 3.47.7, Riverpod, go_router, `health` 14.0.0 (already a dependency), existing design kit and chart kit. No new dependencies, no ObjectBox schema change.

**Spec:** `docs/superpowers/specs/2026-11-26-health-polish-and-outside-workouts-design.md` (Stage 2 section). Stage 1 (PR #79) is merged.

## Global Constraints

- Run Flutter from `apps/mobile/`. Before each commit: `dart format --output=none --set-exit-if-changed lib test` and `flutter analyze` clean; the task's tests pass.
- **Store nothing:** outside workouts, their kcal/HR/distance and training load are never written to ObjectBox, Supabase, the outbox, export, logs or telemetry. Only `currentHealthAccessScope` (an existing non-health int) changes on disk.
- `package:health` is imported only by `platform_health_reader.dart`. `features/sync`, `features/account`, `core/storage` and the export never import `features/health` (existing guards).
- Outside workouts **do not** change: muscle recovery, the Progress "N finished" count, volume, PR/strength charts, the Progress empty state, the Today "This week" dots, "Better fit today", sync, backup or export.
- Missing values are left out or `—`, never `0`. Average HR comes only from real `HEART_RATE` samples inside the window.
- Read window: 90 local days before now (`daysAgo(89)` .. now). Health Connect may return less; that is accepted.
- Own writes: drop any workout whose `sourceId` or `sourceName` equals `in.beyondrep.app`.
- Merge: an outside workout merges into a completed BeyondRep session when the overlap is ≥ 50% of the shorter of the two durations; each outside workout merges into at most one session (largest overlap; tie → earlier session); a session can absorb several.
- Training load: session load = minutes × intensity. BeyondRep minutes = completed − started; intensity = mean RPE of completed working sets that have an RPE ÷ 10, else 0.8. Outside minutes = end − start; intensity 0.7. Merged outside workouts are not counted separately. Ratio r = (7-day load / 7) ÷ (28-day load / 28) over the days before today (today excluded). Needs ≥ 14 days between the earliest session in the 28-day window and today, and a non-zero 28-day load; otherwise the input is absent. Part score: r ≤ 0.8 → 90; 0.8–1.3 linear 90→70; 1.3–1.8 linear 70→30; ≥ 1.8 → 30. Base weight 0.15 alongside HRV .40, RHR .25, sleep .25, debt .10, rescaled over present parts.
- Android: request only `READ_EXERCISE` (no total-calories or distance permission). Android outside workouts therefore show no kcal and no distance (the plugin returns null without those permissions). iOS kcal is the workout's active energy.
- Kit only for UI (`test/design_kit_guard_test.dart`); light/dark, text scale 2.0 and 320 dp without overflow; every new ⓘ is 48 dp with label `About <title>`.
- Commit messages end with the session's attribution lines.

## Review Focus

1. **Account switch mid-read:** outside workouts and load from account A must never appear for account B. Covered by the owner checks in Task 4.
2. **Workout permission not granted (iOS: never requested; Android: denied):** Activity shows the existing gap pattern ("Allow more data" / "Not allowed · Manage"), Progress and Today look exactly as in stage 1, readiness scores from BeyondRep-only load. Task 4 and Task 6.
3. **A BeyondRep session with no outside overlap and an outside workout that overlaps two BeyondRep sessions** (e.g. a 2-hour watch workout spanning two short logs): merges once into the larger overlap only. Task 1.
4. **Fewer than 14 days of workout history or zero load in 28 days:** readiness unchanged from stage 1 (no training-load part, no "0"). Task 2.
5. **Outside detail opened after a refresh dropped that workout:** shows "This workout is no longer available" instead of crashing. Task 6.

---

### Task 1: Outside workouts and the merge (domain)

**Files:**
- Create: `lib/features/health/domain/outside_workouts.dart`
- Test: `test/health/domain/outside_workouts_test.dart`

**Interfaces:**
- Consumes: `WorkoutSessionRecord`, `WorkoutStatus` (`features/workouts/domain/workout_models.dart`).
- Produces:
  - `enum OutsideWorkoutKind { strength, running, walking, cycling, swimming, hiit, yoga, pilates, rowing, elliptical, hiking, dance, other }`
  - `class OutsideWorkout { final String id; final OutsideWorkoutKind kind; final DateTime start; final DateTime end; final double? activeKcal; final double? distanceMeters; final String source; }` (`start`/`end` UTC; `minutes` getter = `end.difference(start).inMinutes`).
  - `String outsideWorkoutName(OutsideWorkoutKind kind)` → `Strength training`, `Running`, `Walking`, `Cycling`, `Swimming`, `HIIT`, `Yoga`, `Pilates`, `Rowing`, `Elliptical`, `Hiking`, `Dance`, `Workout`.
  - `class WorkoutMerge { final Map<String, List<OutsideWorkout>> mergedIntoSession; final List<OutsideWorkout> standalone; }` (`mergedIntoSession` keyed by `WorkoutSessionRecord.uuid`).
  - `WorkoutMerge mergeWorkouts(List<WorkoutSessionRecord> sessions, List<OutsideWorkout> outside)` — only `WorkoutStatus.completed` sessions with `completedAtUtc` participate; rule from Global Constraints; `standalone` sorted by `start` descending.
  - `({String source, double? kcal})? mergedSummary(List<OutsideWorkout> merged)` — source of the first (largest overlap first in the list), kcal summed over non-null values, null if all null; returns null for an empty list.

- [ ] **Step 1: Write failing tests**
  - `outside workout 10:00-10:30 merges into session 10:05-10:50 (25 of 30 min overlap)`.
  - `exactly 50% of the shorter merges; 49% does not` (session 10:00-11:00, outside 10:30-11:30 → 30/60 merges; outside 10:31-11:31 does not).
  - `a 2-hour outside workout spanning two sessions merges only into the larger overlap`; `on a tie it merges into the earlier session`.
  - `two outside workouts both merge into one session and mergedSummary sums kcal 131 + 40 = 171 and keeps the first source`.
  - `mergedSummary kcal is null when every merged workout has null kcal`.
  - `in-progress and discarded sessions never absorb outside workouts`.
  - `standalone is newest first`.
- [ ] **Step 2: Run** `flutter test test/health/domain/outside_workouts_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): outside workout model and merge with BeyondRep sessions`

### Task 2: Training load as a readiness input (domain)

**Files:**
- Create: `lib/features/health/domain/training_load.dart`
- Modify: `lib/features/health/domain/readiness.dart` (`ReadinessInput.trainingLoad`, weight 0.15, new optional parameter)
- Modify: `lib/features/health/widgets/readiness_card.dart` (`readinessReasons` adds `training load above your usual` when the part exists and r > 1.3)
- Test: `test/health/domain/training_load_test.dart`, existing `test/health/domain/readiness_test.dart` (or wherever `scoreReadiness` is tested; find with `grep -rl scoreReadiness test`)

**Interfaces:**
- Consumes: Task 1 `OutsideWorkout`, `WorkoutMerge`; `WorkoutSessionRecord` and its sets (`WorkoutSetStatus.completed`, `WorkoutSetKind` working sets, `rpe`) using the same "completed working set" predicate as `progress/muscle_recovery.dart`.
- Produces:
  - `typedef LoadSession = ({DateTime start, double minutes, double intensity});`
  - `List<LoadSession> loadSessions(List<WorkoutSessionRecord> sessions, WorkoutMerge merge)` — BeyondRep completed sessions plus `merge.standalone`; merged outside workouts excluded.
  - `({double ratio, double score})? trainingLoadOf(List<LoadSession> sessions, DateTime today)` — `today` is a local day; days bucketed by local date of `start`; rule and score curve from Global Constraints.
  - `scoreReadiness({..., List<LoadSession> loadSessions = const []})` — adds `ReadinessPart(input: ReadinessInput.trainingLoad, score: …, weight: 0.15/total, z: null)` when `trainingLoadOf` is non-null. `Readiness` gains `final double? loadRatio;` for the reasons line. With no load sessions, results are identical to before (existing readiness tests must pass unchanged).

- [ ] **Step 1: Write failing tests**
  - `training_load_test.dart`: score curve: `r 0.8 → 90`, `r 1.05 → 80`, `r 1.3 → 70`, `r 1.55 → 50`, `r 1.8 → 30`, `r 2.5 → 30`, `r 0.4 → 90` (build sessions so 7-day and 28-day loads give these ratios).
  - `null with 13 days of history, value with 14`; `null when the 28-day load is zero`; `today's sessions are ignored`.
  - `BeyondRep intensity is mean rated RPE / 10 (RPE 8 and 9 → 0.85) and 0.8 with none rated`; `warm-up and incomplete sets are ignored for RPE`.
  - `outside standalone uses 0.7; merged outside workouts are not counted`.
  - readiness: `no load sessions gives exactly the stage 1 score` (reuse an existing fixture and compare); `with load, weights are HRV .40/RHR .25/sleep .25/debt .10/load .15 rescaled` (assert part weights `0.40/1.15` etc. when all five present); `reasons add training load above your usual when r 1.4`.
- [ ] **Step 2: Run** `flutter test test/health/domain` — Expected: new tests FAIL, existing pass.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/health` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): training load as a readiness input`

### Task 3: Read workouts from the platform

**Files:**
- Modify: `lib/features/health/data/health_reader.dart` (new read)
- Modify: `lib/features/health/data/platform_health_reader.dart` (add `HealthDataType.WORKOUT` to `_commonRequestTypes`; implement read)
- Modify: `lib/features/health/data/health_connection_repository.dart` (`currentHealthAccessScope = 3`)
- Modify: `android/app/src/main/AndroidManifest.xml` (`<uses-permission android:name="android.permission.health.READ_EXERCISE" />` after `READ_ACTIVE_CALORIES_BURNED`)
- Modify: `ios/Runner/Info.plist` `NSHealthShareUsageDescription` → `BeyondRep reads your sleep, heart, activity, workouts and body measurements to show your daily summary, trends and training history. This data stays on your phone.`
- Modify: `test/support/fake_health_reader.dart`
- Test: `test/health/platform_health_reader_test.dart`, `tool/` tests if any assert the manifest permission list (run them)

**Interfaces:**
- Produces:
  - `Future<SeriesResult<List<OutsideWorkout>>> readWorkouts(DateTime from, DateTime to)` on `HealthReader` — never throws (`_guard`), `SeriesNotAllowed` on Android without permission; maps `WorkoutHealthValue.workoutActivityType` to `OutsideWorkoutKind` (strength: `TRADITIONAL_STRENGTH_TRAINING`, `FUNCTIONAL_STRENGTH_TRAINING`, `STRENGTH_TRAINING`, `WEIGHTLIFTING` if present; running: `RUNNING`, `RUNNING_TREADMILL`; cycling: `BIKING` and its indoor/stationary variants; hiit: `HIGH_INTENSITY_INTERVAL_TRAINING`; dance: any `*DANCE*`; the rest by name; else `other`), `activeKcal` = `totalEnergyBurned` on iOS and **null on Android**, `distanceMeters` = `totalDistance` (null when absent), `id` = `uuid ?? '${sourceId}-${dateFrom.millisecondsSinceEpoch}'`, `source` = `_sleepSourceName`-style (iOS `sourceName`, Android `friendlySource`); own-app filter from Global Constraints.
  - `FakeHealthReader.workouts` (`SeriesResult<List<OutsideWorkout>>`, default `SeriesData([])`).

- [ ] **Step 1: Write failing tests** in `platform_health_reader_test.dart` using its existing fake plugin approach: `maps a TRADITIONAL_STRENGTH_TRAINING workout to strength with 131 kcal on iOS`; `Android kcal is null even when the plugin returns a total`; `drops workouts from in.beyondrep.app`; `permission denied on Android is SeriesNotAllowed`; `WORKOUT is in the request list on both platforms`. Plus `currentHealthAccessScope is 3` in the connection repository test, and the manifest contains `READ_EXERCISE` (add to an existing manifest/tool test if one lists health permissions; otherwise a Dart test reading the file).
- [ ] **Step 2: Run** `flutter test test/health/platform_health_reader_test.dart test/health/health_connection_repository_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** those plus `flutter test test/health/health_import_guard_test.dart` and `python3 -m unittest discover -s tool -p 'test_*.py'` (repo root) — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): read workouts from Apple Health and Health Connect`

### Task 4: Overview holds workouts; readiness gets training load

**Files:**
- Modify: `lib/features/health/application/health_overview.dart`
- Modify: `lib/features/health/application/health_details.dart` (`readinessHistoryProvider`)
- Create: `lib/features/health/application/workout_heart_rate.dart`
- Test: `test/health/health_overview_test.dart`, `test/health/readiness_detail_test.dart`, `test/health/workout_heart_rate_test.dart`

**Interfaces:**
- Consumes: Task 1, 2, 3; `workoutHistoryRepositoryProvider.readCompletedAsync()` (as `application/training_insights.dart` reads history).
- Produces:
  - `class WorkoutsOverview { final List<OutsideWorkout> outside; }` and `HealthOverview.workouts` (`Section<WorkoutsOverview>`), read in `_read` with `daysAgo(89)`..`now`, gaps mapped like the other sections (`SeriesNotAllowed` → `notAllowed`, `SeriesNeedsAccess` → `needsAccess`, failed → `failed`).
  - The controller reads completed BeyondRep history once per overview read; `_readiness(...)` and `_readinessOn(...)` pass `loadSessions(history, mergeWorkouts(history, outside))` (outside = `[]` when the section is a gap). A failed history read means no load sessions (readiness still scores from the other inputs).
  - `final workoutMergeProvider = Provider<WorkoutMerge?>` — `mergeWorkouts(history, outside)` from the current overview and `completedWorkoutHistoryProvider`; null while either is loading; `outside` empty when the workouts section is a gap.
  - `typedef WorkoutWindow = ({DateTime start, DateTime end});` and `final workoutAverageHrProvider = FutureProvider.autoDispose.family<double?, WorkoutWindow>` — reads `HealthSeriesType.heartRate` over the window via `healthReaderProvider`, mean of sample values, null when no samples or not `SeriesData`; drops its result if the health owner changed during the read (same `_stillOwner` pattern as `health_details.dart`).

- [ ] **Step 1: Write failing tests**
  - overview: `reads outside workouts for the last 90 days` (fake records the requested `from` = local midnight 89 days ago); `not allowed maps to MetricGap.notAllowed`; `readiness includes a training load part when 14+ days of sessions exist`; `readiness has no training load part when workouts are not allowed and BeyondRep history is short`; `a history read failure leaves readiness without load but still scored`; `account switch during the read never exposes the other owner's workouts` (follow the existing owner-switch test pattern).
  - readiness history: `today's trend point equals the overview score with load`.
  - workout HR: `mean of HR samples in the window`; `null with no samples or not allowed`; `owner change drops the result`.
  - merge provider: `merges using overview outside workouts and completed history`.
- [ ] **Step 2: Run** `flutter test test/health/health_overview_test.dart test/health/readiness_detail_test.dart test/health/workout_heart_rate_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/health test/today test/train` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): hold outside workouts in the overview and feed training load to readiness`

### Task 5: Activity Workouts section, readiness Training load row and explanations

**Files:**
- Modify: `lib/features/health/domain/metric_explanations.dart` (two keys)
- Modify: `lib/features/health/detail/activity_detail_page.dart`
- Modify: `lib/features/health/detail/readiness_detail_page.dart` ("What made the score" gets a Training load row; "How readiness works" text mentions training load)
- Test: `test/health/domain/metric_explanations_test.dart`, `test/health/detail_pages_test.dart`, `test/health/readiness_detail_test.dart`, `test/health/health_terms_page_test.dart`

**Interfaces:**
- Consumes: Task 4 `workoutMergeProvider`, overview `workouts` section; Task 2 `ReadinessInput.trainingLoad`, `Readiness.loadRatio`; stage 1 `metricInfoButton`, `NsBarChart`.
- Produces: `MetricKey.trainingLoad`, `MetricKey.otherAppWorkouts`.

Copy (fixed; `<platform>` = `Apple Health` or `Health Connect`):

| key | title | summary | what | tells | inBeyondRep |
|---|---|---|---|---|---|
| trainingLoad | Training load | How much you've trained lately compared with usual | How much you trained over the past 7 days compared with your usual week over the past 28 days. Each workout counts its minutes, weighted by effort: your logged RPE for BeyondRep workouts, and a moderate effort for workouts from other apps. | A week well above your usual can leave you less recovered. A steady or slightly lighter week usually means you're fresh. | One of the inputs to readiness once you have 14 days of workout history. Today's workouts count from tomorrow. |
| otherAppWorkouts | Workouts from other apps | Workouts other apps saved to <platform> | Workouts that your watch or other apps saved to <platform>, such as runs, rides or classes. BeyondRep reads them fresh each time and never saves or backs them up. | When one overlaps a workout you logged in BeyondRep, they show as one session, with the calories from the other app added. | Shown in Activity and Progress history and counted in training load. They don't change muscle recovery, your workout count or volume. |

Activity detail "Workouts" panel (below Active calories), using the page's existing 7/30-day chips:
- Title `Workouts` with ⓘ `otherAppWorkouts`.
- `NsBarChart` of minutes per local day over the range: BeyondRep completed sessions (completed − started) plus standalone outside workouts (merged ones not added twice). Caption `<N> workouts · <M> min` for the range.
- List rows (newest first, max 10, then `See all in Progress` → `/progress`): BeyondRep session → name, `Today 10:02 AM · 48 min`, merged line `From Apple Watch · 131 kcal` when merged; outside → `outsideWorkoutName`, time and minutes, `· 286 kcal` when kcal, tag `From <source>`; taps go to `/progress/workouts/:uuid` or `/progress/health-workouts/:id` (Task 6 route).
- Workouts section gap → the page's existing `DetailGapPanel` with metric name `Workouts`; BeyondRep sessions still listed below it.

- [ ] **Step 1: Write failing tests**: both new keys pass the existing copy guards (non-empty, no forbidden words) and appear in the glossary; `Activity shows a Workouts panel with bars and a merged BeyondRep row (From Apple Watch · 131 kcal) and a standalone Running row`; `30-day chip widens the chart`; `workouts not allowed shows the gap panel and still lists BeyondRep sessions`; `readiness detail lists Training load with its ⓘ when the part exists, and not otherwise`.
- [ ] **Step 2: Run** the four test files — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/health test/accessibility` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): workouts in Activity and training load on readiness`

### Task 6: Progress history, outside detail and Today tile

**Files:**
- Modify: `lib/features/progress/progress_page.dart`
- Create: `lib/features/progress/outside_workout_detail_page.dart`
- Modify: `lib/app/beyondrep_app.dart` (route `/progress/health-workouts/:id`)
- Modify: `lib/features/health/widgets/today_health_tiles.dart` (`workoutsTile`)
- Modify: `lib/features/health/widgets/today_health_row.dart` (pass outside standalone)
- Test: `test/progress/progress_page_widget_test.dart` (or the existing progress page test file), `test/progress/outside_workout_detail_page_test.dart`, `test/today/today_health_tiles_test.dart`, `test/today/today_health_row_test.dart`

**Interfaces:**
- Consumes: Task 4 `workoutMergeProvider`, `workoutAverageHrProvider`; Task 1 `mergedSummary`, `outsideWorkoutName`.
- Produces: `class OutsideWorkoutDetailPage extends ConsumerWidget { const OutsideWorkoutDetailPage({required String workoutId}); }`; `TodayTile workoutsTile(List<WorkoutSessionRecord>? completed, List<OutsideWorkout> standaloneOutside, DateTime localNow)`.

Rules:
- **Training summary list:** BeyondRep `_SessionSummaryCard`s and outside rows in one list, newest first, both filtered by the selected period (`workoutsInPeriod` window applied to outside `start`). The action label stays `${sessions.length} finished` (BeyondRep only); summary, volume and charts unchanged.
- **Merged line** on `_SessionSummaryCard` when the session absorbed outside workouts: `From <source> · <kcal> kcal · avg <hr> bpm`, each part omitted when null; HR from `workoutAverageHrProvider((start: session.startedAtUtc, end: session.completedAtUtc!))`, shown when it resolves (no spinner).
- **Outside row:** kit `NsListCard`-style card: title `outsideWorkoutName`, subtitle `<date> · <time> · <M> min[ · <km> km][ · <kcal> kcal]`, `NsTag('From <source>')`; tap → `/progress/health-workouts/<id>`.
- **Empty state:** when there are no BeyondRep sessions in the period, keep `_EmptyProgress`; below it show `SectionHeading('From other apps')` and the outside rows if any.
- **Footer text** replaces the current one: `Only finished BeyondRep workouts count towards your totals and back up to your account. Workouts from other apps are read from <platform> for the last 90 days, never saved, and shown here for reference.` (When the workouts section is a gap or health is disconnected, keep the old footer text and show no outside rows.)
- **Outside detail page:** title = `outsideWorkoutName`; rows: Date, Time (`10:02 AM – 10:30 AM`), Duration, Distance (if any), Active calories (if any), Average heart rate (from `workoutAverageHrProvider`, `—` while loading or none), Source; caption `Read from <platform>. Read only and not saved in BeyondRep.`; ⓘ `otherAppWorkouts`. Unknown id (e.g. after a refresh) → `This workout is no longer available.` with a back button.
- **Today tile:** count = BeyondRep completed today + standalone outside workouts whose `end` is on today's local date; caption uses the newest of those (`<name> · <M> min`); `—`/`Finished today` while history is loading stays as in stage 1.

- [ ] **Step 1: Write failing tests**
  - progress: `outside running row sits between two BeyondRep sessions by date`; `finished count ignores outside workouts`; `merged session shows From Apple Watch · 131 kcal · avg 112 bpm`; `merged session with no kcal and no HR shows From Apple Watch only`; `period 30 days hides an outside workout from 40 days ago`; `no BeyondRep sessions: empty state plus From other apps section`; `disconnected health shows exactly the stage 1 page and footer`; `text scale 2.0 no overflow`.
  - detail: `shows type, duration, kcal, source and read-only caption`; `HR shows — when no samples`; `unknown id shows This workout is no longer available.`
  - today: `standalone outside workout today raises the count to 2 and the newest names the caption`; `a merged outside workout does not raise the count`.
- [ ] **Step 2: Run** those files — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/progress test/today test/health test/accessibility` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(progress): show workouts from other apps in history, with a read-only detail`

### Task 7: ADR-0011, docs and full verification

**Files:**
- Create: `docs/adr/0011-read-workouts-from-health-platforms.md` (follow the format of `docs/adr/0009-*.md`): workouts from other apps are read fresh (90 days), joined in memory, never stored/synced/exported/logged; the merge rule; training load as a readiness input with its formula and weight; Android reads `READ_EXERCISE` only (no kcal/distance); amends ADR-0009's "training-load input not implemented".
- Modify: `docs/HEALTH_DATA.md` (external workouts section: read, displayed, merged, counted in load; never re-exported), `docs/ROADMAP.md`, `docs/RELEASE.md` (device rows: iPhone + Apple Watch logging the same lift as BeyondRep → one merged session; a third-party app workout (e.g. a run) → Activity, Progress, Today; Android 14+ with and without history permission; permission added after an existing connect → "Allow more data"; account switch), `CLAUDE.md` project-state line, `docs/PRIVACY_POLICY_INPUTS.md` §2.6 and §7.2 (add exercise sessions / workouts, `READ_EXERCISE` on Android and HealthKit workouts on iOS, read fresh and never stored), and `apps/website/src/pages/privacy.astro` (list exercise sessions / workouts among the health types read, in the same wording style; follow `apps/website/AGENTS.md` and run `cd apps/website && npm ci && npm test && npm run build && npm run check-links`). Before this task, merge `origin/main` into the branch so PR #80's privacy-policy changes are the base; if #80 is not merged yet, stop and report instead of editing those two files.
- If calories or distance permissions are ever added, list them in both privacy files too.

- [ ] **Step 1:** Write the ADR and doc updates (no claims beyond "implemented in source, not released or device-verified").
- [ ] **Step 2: Run** `python3 -m unittest discover -s tool -p 'test_*.py'` from repo root — Expected: OK.
- [ ] **Step 3: Run** from `apps/mobile`: `dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test` — Expected: all pass; record the count.
- [ ] **Step 4: Commit** `docs: ADR-0011 and status for workouts from other apps`
