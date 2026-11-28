# Energy score, stage 3 (personal tuning) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Learn each person's usual training hours (the awake dip is waived in them) and one bounded drain multiplier from their last 90 days, on device and in memory only, and apply both to energy now.

**Architecture:** A pure-Dart `domain/energy_tuning.dart` turns completed BeyondRep sessions plus a past-readiness function into an `EnergyTuning` (usual hours, multiplier, calibrated). `energyNow` takes the tuning. The overview reads about 120 days of sleep, HRV and resting heart rate once per local day per account through an in-memory cache (`energyHistoryCacheProvider`) and computes the tuning on every read from the cached samples and the current session list. `_readinessOn`/`_nightScore` move from `health_details.dart` to a domain file so past days are scored exactly as the detail history scores them.

**Tech Stack:** Flutter 3.47.7, Riverpod 3. No new dependencies, permissions, read types or ObjectBox changes.

**Spec:** `docs/superpowers/specs/2026-11-27-energy-score-design.md` (Learning), `docs/adr/0013-energy-score.md` decisions 4, 7 and 8, stage list in `docs/superpowers/plans/2026-11-27-energy-score-stage-1.md`. Builds on stage 2 (`docs/superpowers/plans/2026-11-27-energy-score-stage-2.md`).

## Global Constraints

- Run Flutter from `apps/mobile/` (`~/sdk/flutter/bin/flutter`). Before each commit: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze` clean, the task's tests pass. Commit messages end with the session's attribution lines.
- **Memory only.** Usual hours, multiplier, past energies, performance values and the cached history samples are never written to ObjectBox, Supabase, the outbox, export, logs or telemetry, and never sent to the watch.
- **Extra reads:** exactly three, `readSleep`, `readSeries(hrv)` and `readSeries(restingHeartRate)` from `day − 120` (sleep and HRV from 18:00 of that day, as the overview's own sleep read starts at 18:00), at most once per local day per (owner, `connectedAt`, `accessScope`). A failed extra read is cached as failed for that key (no retry until the key changes), and energy falls back to generic tuning. The main overview reads and their results never depend on the extra reads.
- `lib/features/health/domain/` imports only `dart:`, other `domain/` files and `features/workouts/domain/`.
- **Constants** (named `const` in `energy_tuning.dart`):

  | Name | Value |
  |---|---|
  | `energyUsualHoursMinSessions` | 8 |
  | `energyUsualHourMinCount` | 3 |
  | `energyUsualHourMinShare` | 0.25 |
  | `energyHistoryDays` | 120 |
  | `energyNormSessions` / `energyNormMinSessions` | 5 / 2 |
  | `energyRpeWeight` / `energyRpeMaxDiff` | 0.05 / 3.0 |
  | `energyTuneMinPairs` | 10 |
  | `energyTuneMinSpread` | 10.0 points |
  | `energyExpectedLowRatio` | 0.95 |
  | `energyTuneGain` | 8.0 |
  | `energyDrainMultiplierFloor` / `energyDrainMultiplierCeiling` | 0.6 / 1.4 |

- **Sessions used:** completed BeyondRep sessions (`status == completed`, `completedAtUtc` set) with `completedAtUtc` in the 90 days up to now (`energyLearningWindowDays`), excluding any that start in the current waking day.
- **Usual hours:** with at least 8 such sessions, local clock hour `h` is usual when the number of sessions whose local start hour is `h − 1`, `h` or `h + 1` (mod 24) is at least `max(3, ceil(0.25 × n))`. With fewer than 8 sessions, no hour is usual. Not gated on calibration.
- **Awake dip:** unchanged formula, but no awake item when `now`'s local hour is usual.
- **Past energy at a session's start:** the session's waking day is `wakingDayOf(nights, session.start)`; skip the session without one. Start = `readinessOn(wakingDay.day, …)` from the cached nights, HRV and resting HR (no sleep heart rate), skip unless `ReadinessReady`. Past energy = start − Σ `minutes × intensity × energyWorkoutPointsPerLoad` over load sessions that end after the wake and not after the session's start. No active energy, awake dip or naps.
- **Performance index:** per exercise (`exerciseUuid` via the exercise's `definitionUuid`, else `nameSnapshot` lower-cased), volume over completed working sets = Σ kg × reps when any set has load and reps, else Σ reps, else Σ seconds. Norm = mean of that exercise's volume in the up to 5 most recent earlier sessions (any session in the read, also older than 90 days) that contain it; needs at least 2. Session ratio = mean over exercises with a norm of volume / norm; skip the session without one. RPE: when the session's mean working-set RPE and the norm sessions' mean RPE both exist, ratio × (1 − 0.05 × clamp(rpe − normRpe, −3, 3)).
- **Multiplier:** pairs `(pastEnergy, ratio)`. Calibrated = `energyLearningOf(...).show == false` (20 sessions in 90 days and baseline ≥ 14 days, stage 1 rule). Not calibrated, or fewer than 10 pairs → 1.0. Else sort pairs by energy, lower half = first `n ~/ 2`, upper half = the rest; if mean energy of the upper half − lower half < 10 → 1.0; else `r = mean ratio(lower) / mean ratio(upper)`, multiplier = `clamp(1 + 8 × (0.95 − r), 0.6, 1.4)`.
- **Applied to:** workout drain and active drain (the active cap of 15 applies after multiplying). Not to the awake dip or naps. The nap cap still uses the drain total after multiplying.
- **Copy (fixed):** on the readiness detail "Since you woke" panel, when the dip was waived: caption `You usually train around now, so time awake costs nothing today.`; on the detail summary and the Health tab hero subtitle area, when calibrated and multiplier ≠ 1.0: caption `Tuned to your last 90 days.` "How energy works" gains: `Once you have 20 workouts and 14 days of data, BeyondRep tunes how much workouts and active calories lower your energy from how you trained at different energy levels, and learns the hours you usually train, when time awake costs nothing. This is worked out on your phone each time and never saved.` No other surface changes.

## Review Focus

1. **Health Connect quota:** a resume re-read every 5 minutes must not repeat the three extra reads; a new local day or a reconnect must. Pinned in Task 3.
2. **Account switch mid-day:** account B never gets account A's cached history or tuning. Pinned in Task 3.
3. **Late-night trainer:** sessions mostly starting 22:00–23:00; at 23:30, 16 h after waking, no awake item; at 15:00 the dip applies. Pinned in Task 1 and Task 2.
4. **Few or mixed sessions:** bodyweight-only, timed-only, no RPE, a new exercise with no norm, sessions with no waking day: no crash, no NaN, the multiplier stays in [0.6, 1.4]. Pinned in Task 1.
5. **Extra read failure or Android without history access** (only ~30 days readable): energy still shows with generic tuning, the overview has no gap because of it. Pinned in Task 3.

---

### Task 1: `energy_tuning.dart` and the shared past-readiness function

**Files:**
- Create: `apps/mobile/lib/features/health/domain/readiness_on.dart` (move `_readinessOn` and `_nightScore` out of `application/health_details.dart` unchanged, public as `readinessOn` and `nightScoreOf`; `health_details.dart` calls them)
- Create: `apps/mobile/lib/features/health/domain/energy_tuning.dart`
- Test: `apps/mobile/test/health/energy_tuning_test.dart`; existing readiness history tests must stay green

**Interfaces:**
- Produces:
  - `class EnergyTuning { const EnergyTuning({required Set<int> usualHours, required double drainMultiplier, required bool calibrated}); static const generic = EnergyTuning(usualHours: {}, drainMultiplier: 1.0, calibrated: false); }`
  - `Set<int> usualTrainingHours(List<WorkoutSessionRecord> sessions)` (sessions already filtered)
  - `double? sessionPerformance(WorkoutSessionRecord s, List<WorkoutSessionRecord> earlier)`
  - `double drainMultiplierOf(List<({double energy, double ratio})> pairs, {required bool calibrated})`
  - `EnergyTuning energyTuningOf({required List<WorkoutSessionRecord> sessions, required List<LoadSession> load, required List<SleepNight> nights, required ReadinessResult Function(DateTime day) readinessOnDay, required WakingDay? currentDay, required DateTime now, required bool calibrated})`

- [ ] **Step 1: Failing tests** — usual hours: 8 sessions at 22:10 and 22:40 local → `{21, 22, 23}`; 7 sessions → `{}`; 20 sessions spread 1 per hour across 20 hours → `{}` (share rule); hour wrap: sessions at 23:30 and 00:15 → includes 0 and 23. Performance: same exercise 100 kg × 5 × 3 sets with two earlier sessions at 90 kg × 5 × 3 → ratio ≈ 1.111; bodyweight reps and timed sets use reps / seconds; a warm-up or skipped set is ignored; one earlier session only → null; RPE 9 vs norm 8 → ratio × 0.95. Multiplier: not calibrated → 1.0; 9 pairs → 1.0; spread 8 points → 1.0; lower half ratio 0.85 vs upper 1.0 → 1.4 (clamped); 1.0 vs 1.0 → 0.6; 0.95 vs 1.0 → 1.0; never NaN with zero-volume norms (skip such exercises). `energyTuningOf`: sessions inside `currentDay` are excluded; a session with no waking day or a not-ready start yields no pair; past energy subtracts an earlier same-day workout (start 80, earlier 60 min × 1.0 intensity → 68).
- [ ] **Step 2: Run** `flutter test test/health/energy_tuning_test.dart` → FAIL.
- [ ] **Step 3: Implement** the move (no behaviour change; `flutter test test/health/` stays green) and `energy_tuning.dart` per Global Constraints.
- [ ] **Step 4: Run** `flutter test test/health/` → PASS.
- [ ] **Step 5: Commit** `feat(health): learn usual training hours and a drain multiplier in memory`.

### Task 2: `energyNow` applies the tuning

**Files:**
- Modify: `apps/mobile/lib/features/health/domain/energy.dart` (`energyNow` gains `EnergyTuning tuning = EnergyTuning.generic`; `Energy` gains `final bool awakeWaived` and `final bool tuned`)
- Test: `apps/mobile/test/health/energy_test.dart`

**Interfaces:**
- Consumes: `EnergyTuning` (Task 1).
- Produces: `energyNow({..., EnergyTuning tuning = EnergyTuning.generic})`; `Energy.awakeWaived` (true when the hour was usual and the dip would have been non-zero), `Energy.tuned` (`tuning.calibrated && tuning.drainMultiplier != 1.0`).

- [ ] **Step 1: Failing tests** — multiplier 1.4: a 60 min × 1.0 workout drains 17 (12 × 1.4 = 16.8 → apportioned) instead of 12; active drain 400 kcal excess with multiplier 1.4 → capped at 15; usual hours `{22,23}`, 16 h awake at 23:30 → no awake item, `awakeWaived` true; same at 15:00 with 16 h awake → awake item present; generic tuning gives exactly stage 1 results (existing tests unchanged).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/health/energy_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat(health): energy now uses the personal tuning`.

### Task 3: Once-a-day history cache wired into the overview

**Files:**
- Create: `apps/mobile/lib/features/health/application/energy_history_cache.dart`
- Modify: `apps/mobile/lib/features/health/application/health_overview.dart` (`_read` and its caller; `EnergyOverview` gains `final EnergyTuning tuning`)
- Test: `apps/mobile/test/health/health_overview_test.dart`, new `apps/mobile/test/health/energy_history_cache_test.dart`

**Interfaces:**
- Produces: `typedef EnergyHistoryKey = ({String owner, DateTime day, DateTime? connectedAt, int accessScope});` `class EnergyHistory { final List<SleepSegment>? sleep; final List<HealthSample>? hrv; final List<HealthSample>? restingHr; bool get usable => sleep != null && (hrv != null || restingHr != null); }` and `final energyHistoryCacheProvider = NotifierProvider<EnergyHistoryCache, ({EnergyHistoryKey key, Future<EnergyHistory> history})?>` with `Future<EnergyHistory> historyFor(EnergyHistoryKey key, Future<EnergyHistory> Function() read)` that returns the held future when the key matches and otherwise replaces the single held entry (so only one account's data is ever held). Not `autoDispose`.

- [ ] **Step 1: Failing tests** — with the fake reader used by `health_overview_test.dart`: two reads 10 minutes apart on the same day make the three extra read calls once (count calls by type and start date `day − 120`); a read the next local day makes them again; a read after `connectedAt` changes makes them again; switching owner A → B makes them for B and B's overview tuning never uses A's samples (give A samples that would produce usual hours and assert B has none); an extra read that throws → overview energy still `SectionData` with `tuning == EnergyTuning.generic`, and a second read the same day does not retry; existing read-call expectations for the main reads unchanged. End to end: a fixture with 20 completed sessions at 22:30 over 90 days, 14+ baseline days, now 23:30 at 16 h awake → `currentEnergyScore(...)!.items` has no awake item.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — `_read` starts the cached history future in parallel with the main reads (do not await it before them), builds nights/HRV/RHR dailies from it as the overview does for its own reads, computes `energyTuningOf(...)` with `readinessOnDay` from `readinessOn` and `calibrated` from the existing learning counts, passes it to `energyNow`, and stores it on `EnergyOverview`. Any exception in the history or tuning path yields `EnergyTuning.generic`.
- [ ] **Step 4: Run** `flutter test test/health/` → PASS.
- [ ] **Step 5: Commit** `feat(health): read the tuning history once a day and keep it in memory`.

### Task 4: Copy, docs and full verification

**Files:**
- Modify: `apps/mobile/lib/features/health/detail/readiness_detail_page.dart` (captions from Global Constraints), `apps/mobile/lib/features/health/widgets/readiness_card.dart` (`Tuned to your last 90 days.` under the change line when `energy.tuned`)
- Modify: `docs/adr/0013-energy-score.md` (status: stage 3 implemented in source; "Stage 3 defaults" table with every constant above and the rules), `docs/ROADMAP.md`, `docs/RELEASE.md` (stage 3 rows, all `not run`: late-night trainer shows no awake dip at the usual hour; first Health open of the day on Android does not hit the read quota on repeated resumes; account switch drops the cached history), `docs/HEALTH_DATA.md` (the 120-day memory-only read), `docs/PRIVACY_POLICY_INPUTS.md`, root `CLAUDE.md` project-state energy line
- Test: `apps/mobile/test/health/readiness_detail_test.dart`, `apps/mobile/test/health/readiness_card_test.dart`

- [ ] **Step 1: Failing widget tests** for the two captions (shown / hidden).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** the two files, then the whole `flutter test` once, and `python3 -m unittest discover -s tool -p 'test_*.py'` from the repo root → PASS.
- [ ] **Step 5: Commit** `feat(health): explain energy tuning; docs for energy stage 3`.
