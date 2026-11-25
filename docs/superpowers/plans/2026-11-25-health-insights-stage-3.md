# Health Insights Stage 3 (Training Tie-ins) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Join logged training with recovery and health: a volume-and-effort muscle recovery model, a "Better fit today" plan suggestion and per-plan recovery lines on Train, and two health-and-training insights on the Health tab and the Sleep/Heart detail screens.

**Architecture:** `MuscleRecovery` (on `main`, presence-only linear 72 h fade) is upgraded to weigh each muscle group's working sets by reps and RPE and to fade over 72 h for large and 48 h for small muscles. Plan fit is a pure function over it and the plan library. Insights are pure Dart in `features/health/domain/` over sleep nights, resting-HR days and per-day training summaries; an application provider joins the current overview with the completed workout history in memory, for the same account only. Nothing new is read from HealthKit/Health Connect and nothing is stored.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, go_router, ObjectBox (read-only here), design kit in `lib/core/design/`.

**Spec:** `docs/superpowers/specs/2026-11-24-health-insights-design.md` ("Training tie-ins (stage 3)", "Screens", "Decisions"). Stages 1-2 are merged on `main` (#61, #64). Paths below are under `apps/mobile/` unless they start with `docs/`.

## Global Constraints

- Health values are joined with workout data **only in memory**; never written to workouts, ObjectBox, outbox, sync, export, logs or analytics.
- Never fabricate: an insight shows only when it passes its minimum-sample rule (≥ 3 matching days with data on each side) **and** its minimum effect size; otherwise nothing is shown. Missing is never shown as zero.
- Copy is a suggestion or an observation, never an instruction or a medical statement (no "must", "should rest", "injury", "overtraining").
- Plans are never changed automatically. Never suggest a plan that hits recovering muscles; if none qualifies, suggest nothing.
- Recovered = muscle load `< 0.1` in the upgraded `MuscleRecovery`; recovering = `≥ 0.1` (lowered from 0.25 in the final review so a light session still reads recovering).
- Custom muscle groups that map to no drawn muscle are ignored by plan fit (spec decision).
- Account separation: an insight uses an overview and a history of the same owner; on account switch nothing from the previous account shows.
- Kit-only UI (`test/design_kit_guard_test.dart`); light/dark, tablet, text scale 2.0, screen-reader labels.
- `features/health/domain/` stays pure Dart (imports only `dart:` and other domain files; existing guard test).
- Plan fit and the recovery lines work without health data (no wearable, Health not connected).
- Owner decision 2026-11-25: build Better fit + 2 insights **and** upgrade the muscle map (sets, reps, RPE; 48 h small muscles). The other two spec insights (weekly volume vs readiness, weight vs strength) are out of scope.

## Review Focus

1. **No completed workouts yet / history loading or failed:** no Better fit section and no recovery lines; Train is otherwise unchanged. (Task 3 test.)
2. **Plans whose exercises are all custom unmapped groups, or empty plans:** excluded from suggestion; row shows no recovery line. (Task 2 test.)
3. **Two plans tie, or all plans equally recovered:** nothing is suggested (no "clearly better" plan). (Task 2 test.)
4. **Low readiness but every plan hits recovering muscles:** nothing suggested; the Low note still shows. (Task 2 test.)
5. **Account switch while the Health tab is open:** insight lines from account A never render for account B. (Task 5 test.)

---

### Task 1: Muscle recovery from sets, reps and effort

**Files:**
- Modify: `lib/features/progress/muscle_recovery.dart` (`MuscleRecovery.fromWorkouts`, constants; the 0..1 `load`/`groups` shape and `muscleRecoveryProvider` stay)
- Modify (only if a legend or caption states "72 hours"): `lib/features/progress/muscle_map.dart`
- Test: `test/progress/muscle_recovery_test.dart` (new) and existing `test/progress/muscle_map_test.dart`

**Interfaces:**
- Consumes: `WorkoutSessionRecord` (`status`, `completedAtUtc`, `exercises` with `uuid`, `muscleSnapshot`; `sets` with `exerciseUuid`, `kind`, `status`, `reps`, `rpe`).
- Produces: same `MuscleRecovery(load, groups)` API and `static List<Muscle> MuscleRecovery.musclesOf(String group)` (the existing group table plus drawn-muscle-name fallback; used by Task 2).

Model (constants pinned by tests; builder's choice per spec "Left to the builder"):
- Per completed `working` set: `stimulus = repsFactor × effortFactor`.
  - `repsFactor`: reps null → 1.0; else `clamp(reps / 10, 0.5, 1.5)`.
  - `effortFactor`: RPE null → 0.8; RPE ≥ 8 → 1.0; 6 ≤ RPE < 8 → 0.75; RPE < 6 → 0.5.
- Per session and muscle group: `fresh = min(1, Σ stimulus / 10)` (about ten hard sets of ten saturate a group).
- Fade: linear from `fresh` at `completedAtUtc` to 0 at the group's window: **72 h** for chest, back, legs; **48 h** for shoulders, arms, core and custom groups named after a small drawn muscle (calves, biceps, triceps, forearms, abs, obliques); other custom groups 72 h.
- Several sessions add up per group, capped at 1. Each drawn muscle takes its group's value; `groups` keeps the display-name map as today.
- `window` (72 h) stays the outer cut-off; a 48 h group contributes 0 after 48 h.

- [ ] **Step 1: Failing tests** (synthetic sessions, fixed `nowUtc`):
  - 10 sets × 10 reps @ RPE 8 legs, finished now → quads/hamstrings/glutes/calves load 1.0; after 36 h → 0.5; after 72 h → 0 (absent or 0).
  - Same volume for arms: after 24 h → 0.5; after 48 h → 0.
  - 4 sets × 10 reps, RPE null → fresh 0.32; 4 sets × 5 reps @ RPE 5 → fresh 0.1.
  - Two leg sessions 24 h apart, each fresh 0.6 → sum capped at 1.0 at the second finish.
  - Warm-up, skipped and in-progress-session sets ignored; non-completed sessions ignored (as today).
  - `musclesOf('Legs')` → quads, hamstrings, glutes, calves; `musclesOf('Glutes')` → glutes; `musclesOf('Grip')` → empty.
  - Custom group "Grip" still named in `groups` (existing behaviour).
- [ ] **Step 2:** run the new test file → fails.
- [ ] **Step 3:** implement; keep `fromWorkouts`' signature. Update `test/progress/muscle_map_test.dart` expectations only where they assert the old linear presence values, and say which in the report. Check the Progress muscle card's copy still reads true (e.g. any "last 72 hours" text) and adjust it to the 48/72 h rule if it states a single window.
- [ ] **Step 4:** `flutter test test/progress` passes.
- [ ] **Step 5:** commit `feat(progress): muscle recovery from sets, reps and effort`.

### Task 2: Plan fit domain

**Files:**
- Create: `lib/features/train/plan_fit.dart`
- Test: `test/train/plan_fit_test.dart`

**Interfaces:**
- Consumes: Task 1's `MuscleRecovery` (`load`, `groups`, `loadOf`, `musclesOf`), `WorkoutPlanRecord` (`uuid`, `name`, `exercises: List<PlanExerciseRecord>` with `exerciseUuid`, `targetSets`), `ExerciseRecord` (`uuid`, `muscleGroup`).
- Produces:
  - `const recoveredBelow = 0.1;`
  - `class PlanRecovery { final String planUuid; final Set<String> groups; final Set<String> recovering; final double worstLoad; final int totalSets; bool get isRecovered => recovering.isEmpty; }` where `groups` are the plan's mapped group display names (capitalised as in `MuscleRecovery.groups`), `recovering` those with load `≥ recoveredBelow`, `worstLoad` the max `loadOf` over the plan's muscles.
  - `PlanRecovery? planRecoveryOf(WorkoutPlanRecord plan, Map<String, ExerciseRecord> exercisesByUuid, MuscleRecovery recovery)`: null when no exercise maps to a drawn muscle.
  - `sealed class PlanSuggestion` with `SuggestRecovered(PlanRecovery plan, Set<String> restedGroups)` and `SuggestLightest(PlanRecovery plan)`.
  - `PlanSuggestion? suggestPlan(List<PlanRecovery> plans, {required bool lowReadiness})`.

- [ ] **Step 1: Failing tests** (synthetic plans and `MuscleRecovery` values):
  - `planRecoveryOf`: chest+arms plan with chest load 0.6, arms 0.1 → `recovering == {'Chest'}`, `worstLoad == 0.6`, `totalSets` = sum of `targetSets`; unmapped-only plan → null; empty plan → null; exercise missing from the map → ignored.
  - `suggestPlan(lowReadiness: false)`: picks the plan with the lowest `worstLoad` only when it `isRecovered` and its `worstLoad` is at least `0.2` lower than every other plan's; `restedGroups` = union of `recovering` across the other plans minus the chosen plan's groups. Tie within 0.2 → null. Best plan not recovered → null. A single plan → null (nothing to compare).
  - `suggestPlan(lowReadiness: true)`: among recovered plans, fewest `totalSets`; tie → earlier in list; no recovered plan → null; returns `SuggestLightest`.
  - Empty list → null.
- [ ] **Step 2:** run `flutter test test/train/plan_fit_test.dart` → fails (missing symbols).
- [ ] **Step 3:** implement as specified; plan_fit.dart imports only `muscle_recovery.dart` and workout domain models (no Riverpod, no Flutter).
- [ ] **Step 4:** tests pass.
- [ ] **Step 5:** commit `feat(train): plan fit from muscle recovery`.

### Task 3: Better fit today and recovery lines on Train

**Files:**
- Modify: `lib/features/train/train_page.dart` ("Your plans" section), `lib/features/train/train_library_state.dart` (provider)
- Test: `test/train/train_plan_fit_test.dart`

**Interfaces:**
- Consumes: Tasks 1-2; `muscleRecoveryProvider` (`lib/features/progress/muscle_recovery.dart`), `trainLibraryProvider` (plans + exercises), `healthOverviewProvider` + `todaysReadiness(overview, now)` and `localNowProvider` for the Low flag; `ReadinessBand.low`.
- Produces: `final planFitProvider = Provider.autoDispose<PlanFit?>` with `class PlanFit { final Map<String, PlanRecovery> byPlan; final PlanSuggestion? suggestion; }`. Null while the library or completed history is loading or failed, or when there are no completed workouts at all.

UI (kit components only; follow the existing plan list cards):
- **Better fit today** card above the plan list when `suggestion != null`: plan name, one reason line, Start button (same `_startPlan`, so the Task-7 start note still applies).
  - `SuggestRecovered`: `"<Groups> still recovering · this plan rests them"`, groups joined `"A and B"` / `"A, B and C"`, max 3 then `" and more"`.
  - `SuggestLightest`: `"Lightest plan with recovered muscles · keep effort around RPE 7"`.
- **Recovery line** under each plan row's subtitle when `byPlan[plan.uuid] != null`: `"Recovered"` when `isRecovered`, else `"<Groups> recovering"`.
- Low readiness = today's readiness is Ready with `ReadinessBand.low`; readiness unavailable/not connected → `lowReadiness: false`. A health error never hides plan fit.

- [ ] **Step 1: Failing tests:** suggestion card with reason and Start for a clear winner; Low-readiness day picks the lightest recovered plan and shows the RPE line; no completed workouts → no card and no recovery lines; history error → same; unmapped-only plan → no line on that row; recovery lines "Recovered" / "Legs recovering"; health overview error → plan fit still shows; Start on the card calls `startPlan` with the suggested uuid; text scale 2.0 at 390 px and dark theme → no exception; screen-reader label on the card reads plan name and reason.
- [ ] Steps 2-4, commit `feat(train): better fit today and plan recovery lines`.

### Task 4: Training insights domain

**Files:**
- Create: `lib/features/health/domain/training_insights.dart`
- Test: `test/health/training_insights_test.dart`

**Interfaces:**
- Consumes: `SleepNight` (`date`, `asleep`), `DayValue` (`({DateTime day, double value})`).
- Produces (pure Dart):
  - `typedef TrainingDay = ({DateTime day, int workingSets});` — local date of a finished workout and its completed working sets (summed if several that day).
  - `class SleepAfterTraining { final Duration afterTraining, otherNights; final int trainingNights, otherNightsCount; Duration get difference; }`
  - `SleepAfterTraining? sleepAfterTraining(List<SleepNight> nights, List<TrainingDay> training)`: a night is "after training" when a training day equals the day before `night.date`. Mean `asleep` per side. Needs ≥ 3 nights each side and `|difference| ≥ 20 min`; else null.
  - `class RestingHrAfterHard { final double afterHard, otherDays; final int hardDays, otherDaysCount; double get difference; }`
  - `RestingHrAfterHard? restingHrAfterHardSessions(List<DayValue> restingHr, List<TrainingDay> training)`: hard days = training days in the top third by `workingSets` (ceil of n/3, at least 1, ties at the cut included), needs ≥ 3 training days; the morning after = resting HR on the next local date. Compare mean RHR the day after hard days vs all other days with RHR. Needs ≥ 3 values each side and `|difference| ≥ 2 bpm`; else null.
- Day arithmetic uses calendar dates (`DateTime(y, m, d + 1)`), DST-safe.

- [ ] **Step 1: Failing tests:** sleep: 4 nights after training at 7h40 vs 5 others at 7h00 → +40 min; only 2 after-training nights → null; 15-min difference → null; night whose previous day had no workout counts as other; DST week still pairs correctly. Resting HR: 9 training days, top 3 by sets, 3 next-morning RHR at 58 vs 6 others at 55 → +3; 2 training days → null; 1.5 bpm → null; missing next-morning RHR → that hard day dropped (and null if fewer than 3 remain); ties at the cut included.
- [ ] Steps 2-4, commit `feat(health): training insights domain`.

### Task 5: Training insights provider

**Files:**
- Create: `lib/features/health/application/training_insights.dart`
- Test: `test/health/training_insights_provider_test.dart`

**Interfaces:**
- Consumes: Task 4; `healthOverviewProvider` (sleep `nights`, heart `restingHrDaily`, `ownerId`), `healthOwnerIdProvider`, `completedWorkoutHistoryProvider` (`WorkoutHistorySnapshot.sessions`).
- Produces: `class TrainingInsights { final SleepAfterTraining? sleep; final RestingHrAfterHard? restingHr; }` and `final trainingInsightsProvider = Provider.autoDispose<TrainingInsights?>` — null unless the overview is loaded for the current owner and the history is loaded; training days built from sessions with `status == completed` and `completedAtUtc` inside the overview's 30-day window, local date of `completedAtUtc.toLocal()`, counting `completed` + `working` sets.

- [ ] **Step 1: Failing tests:** both insights computed from a synthetic overview + history; overview owner ≠ current owner → null; history loading/error → null; overview gap sections → that insight null; sessions outside the window ignored; in-progress/discarded sessions ignored; nothing written (fake history repository records only reads).
- [ ] Steps 2-4, commit `feat(health): training insights from overview and history`.

### Task 6: Insight lines on Health, Sleep and Heart

**Files:**
- Create: `lib/features/health/widgets/training_insight_line.dart`
- Modify: `lib/features/health/health_page.dart` (after the cards: "From your training"), `lib/features/health/detail/sleep_detail_page.dart` (7/30-day view), `lib/features/health/detail/heart_detail_page.dart`
- Test: `test/health/training_insight_line_test.dart`

**Interfaces:**
- Consumes: Task 5.
- Produces: `TrainingInsightLine` (kit insight-card style, see `docs/DESIGN_SYSTEM.md` catalog) with copy:
  - Sleep: `"You slept <d> more on nights after training"` / `"<d> less"` (`formatDuration`), caption `"<n> nights after training vs <m> other nights, last 30 days"`.
  - Resting HR: `"Resting HR was <x> bpm higher the morning after your hardest sessions"` / `"lower"` (rounded to whole bpm), caption `"<n> mornings vs <m> other days, last 30 days"`.
- Health tab: one "From your training" line showing the sleep insight if present, else the resting-HR insight; nothing when both are null. Sleep detail: sleep insight only. Heart detail: resting-HR insight only.

- [ ] **Step 1: Failing tests:** each copy variant (more/less, higher/lower); Health tab picks sleep first then RHR; nothing rendered when null; account switch (provider override flips to null) → line gone; text scale 2.0 at 390 px and dark → no exception; copy contains no banned words.
- [ ] Steps 2-4, commit `feat(health): training insight lines`.

### Task 7: Docs and full gate

- [ ] ADR-0009 and `docs/HEALTH_DATA.md`: stage 3 implemented in source, not device-verified; insights joined in memory only, never stored; minimum-sample and effect rules. `docs/ROADMAP.md`, `CLAUDE.md`: stage 3 implemented in source (sets/reps/effort muscle recovery, better fit, recovery lines, two insights), not released or device-verified; the other two spec insights are not implemented. `docs/RELEASE.md`: stage-3 rows, all "not run" (muscle map after a heavy leg day and an arm day, Better fit with real history, Low day lightest plan, insights after 30 days of data, no wearable). Spec status line.
- [ ] From `apps/mobile/`: format, analyze, full `flutter test`; from root `python3 -m unittest discover -s tool -p 'test_*.py'` (then delete `scripts/__pycache__`, `tool/__pycache__`). Record device QA as not run.
- [ ] Commit `docs: health insights stage 3 status`.
