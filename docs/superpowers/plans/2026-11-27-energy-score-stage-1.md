# Energy score, stage 1 (energy now on the Health tab) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compute "energy now" on device from today's readiness (the starting value) minus drain from today's workouts, active calories above the usual for the hour and a small awake dip, plus a capped nap credit, over a waking day that runs from the end of the main sleep to the next one; show it with a "still learning" note on the Health tab hero and the readiness detail screen.

**Architecture:** Pure-Dart `domain/energy_day.dart` (waking day, naps, active excess, awake dip) and `domain/energy.dart` (the score, its itemised changes, the learning note) use only data the overview already reads. `healthOverviewProvider` gains an `energy` section, computed at every read from the same sleep segments, hourly active energy and load sessions it already holds; nothing new is read and nothing is stored. The readiness baseline minimum for scoring drops from 14 to 3 days. The Health tab hero (`ReadinessCard`) and the readiness detail Today view switch to energy; every other surface keeps showing the morning readiness until stage 2.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, go_router, existing design kit and chart kit. No new dependencies, permissions, reads or ObjectBox changes.

**Spec:** `docs/superpowers/specs/2026-11-27-energy-score-design.md` and `docs/adr/0013-energy-score.md`. Builds on health insights stage 2 and health polish stage 2 (readiness with training load, outside workouts), both in source.

## Stages

1. **Stage 1 (this plan): energy now, generic formula.** Start from readiness; drain from today's workouts and active calories above the usual for the hour; generic awake dip; capped nap credit with naps detected from sleep segments; the waking-day boundary; the 3-day baseline minimum; the learning note (days still needed under 14, workouts still needed toward 20). Wired into the overview; shown on the Health tab hero and card states and the readiness detail Today view. Today, Train, the pre-workout note, plan pick and the watch keep the morning readiness. The note hides once 20 sessions and 14 baseline days exist, although tuning only lands in stage 3.
2. **Stage 2: every other surface and the words.** Today hero, strip and tiles; Train strip; pre-workout note and "Better fit today" using energy at the time of starting; the watch `health_snapshot` `readiness` field carries energy at send time (watch still clears at local midnight); the detail 7/30-day chart plots each day's starting value under energy wording; the word "readiness" leaves the UI; explanation sheets (`MetricKey.readiness` becomes energy), Health terms glossary, `docs/HEALTH_DATA.md`, `docs/PRIVACY_POLICY_INPUTS.md`.
3. **Stage 3: personal tuning.** Usual training hours from session start times (awake dip waived in them); one drain multiplier bounded both ways from a performance index against simplified past energy; the 120-day HRV / resting HR / sleep history read at most once per local day per account, held in memory and dropped on account switch, disconnect and permission change; calibrated at 20 sessions and 14 baseline days; constants recorded in ADR-0013.

## Global Constraints

- Run Flutter from `apps/mobile/`. Before each commit: `dart format --output=none --set-exit-if-changed lib test` and `flutter analyze` clean; the task's tests pass. Commit messages end with the session's attribution lines.
- **Store nothing:** energy, its items, naps, usual-hour values and learning counts live only in the in-memory overview. Never written to ObjectBox, Supabase, the outbox, export, logs or telemetry.
- **No new reads:** energy uses only the overview's existing sleep read (raw segments), hourly active-energy totals (30 days), outside workouts and completed BeyondRep history. `test/health/health_overview_test.dart` read-call expectations stay unchanged.
- `lib/features/health/domain/` imports only `dart:`, other `domain/` files and `features/workouts/domain/` (as `training_load.dart` does). `package:health` stays in `platform_health_reader.dart` only.
- Missing is never zero: an input that cannot be computed adds no item and no points; no item ever reads `0` or `+0` / `−0`.
- Kit widgets only (`test/design_kit_guard_test.dart` green); light/dark, text scale 2.0 at 320 dp, tablet grid; no animations.
- Surfaces other than the Health tab hero and the readiness detail Today view are not changed in this stage (Today, Train, watch, plan pick, pre-workout note, explain sheets, glossary).
- **Formula:** `energy now = clamp(start + Σ items, 0, 100)` where items are drains (negative) and recharge (positive), rounded as in Task 3. Bands from `readinessBandOf`: ≥ 70 good, 50–69 fair, < 50 low.
- **Constants** (named, `const`, in the file shown; stage 3 tunes the drain ones):

  | Name | Value | File |
  |---|---|---|
  | `readinessBaselineMinDays` | 3 | `readiness.dart` |
  | `energyMaxWakingDay` | `Duration(hours: 20)` | `energy_day.dart` |
  | `energyNapAfterWake` | `Duration(minutes: 60)` | `energy_day.dart` |
  | `energyNapJoinGap` | `Duration(minutes: 30)` | `energy_day.dart` |
  | `energyNapMinMinutes` / `energyNapMaxMinutes` | 10 / 180 | `energy_day.dart` |
  | `energyUsualMinDays` | 7 | `energy_day.dart` |
  | `energyAwakeDipStart` | `Duration(hours: 8)` | `energy_day.dart` |
  | `energyAwakeDipPerHour` / `energyAwakeDipMax` | 0.5 / 5.0 points | `energy_day.dart` |
  | `energyWorkoutPointsPerLoad` | 0.2 points per load unit (minutes × intensity) | `energy.dart` |
  | `energyActivePointsPerKcal` / `energyActiveMaxPoints` | 0.025 (1 point per 40 kcal) / 15.0 | `energy.dart` |
  | `energyNapPointsPerMinute` / `energyNapMaxPoints` | 0.2 / 10.0 | `energy.dart` |
  | `energyCalibratedSessions` / `energyCalibratedBaselineDays` / `energyLearningWindowDays` | 20 / 14 / 90 | `energy.dart` |

- **Waking day:** the latest night from `buildNights` whose `end` is not after `now` and with `now − end ≤ energyMaxWakingDay`; its `date` is the waking day, its `end` the wake time. Otherwise there is no waking day and energy falls back to today's readiness (not ready). The starting value is `scoreReadiness` for the waking day's date; training load in it still excludes that date.
- **Workout drain:** each `LoadSession` with `end = start + minutes` after the wake and not after `now`; points `minutes × intensity × 0.2`. One item per workout, labelled by its local start time.
- **Active drain:** hourly active-energy buckets with `to` after the wake and `from` before `now`, skipping any bucket that overlaps a counted workout (`from < workoutEnd && to > workoutStart`). Usual for a clock hour = mean of that hour's value over the "usual days" (local dates before the waking day, in the read, with at least one bucket value > 0), counting 0 for a usual day with no bucket in that hour. Needs ≥ 7 usual days, else no active item. Excess per bucket `max(0, value − usual)`; points `min(Σ excess × 0.025, 15)`.
- **Awake dip:** `min(max(0, hoursAwake − 8) × 0.5, 5)`; `hoursAwake = (now − wake)` in hours (fractional).
- **Naps:** asleep-stage segments (`light`, `deep`, `rem`, `asleepUnspecified`; any source) with `from ≥ wake + 60 min` and `to ≤ now`; merged across sources and joined into one nap when the gap between them is ≤ 30 min; a nap's minutes are its merged asleep minutes (`mergedSleepMinutes`); kept when 10 to 180 minutes. Raw credit `minutes × 0.2`; total recharge capped at **min(10, total drain so far)**, so a nap never lifts energy above the morning start; when capped, each nap's credit is scaled by the same factor and every nap item is marked `capped`.
- **Learning note:** `workoutsNeeded = max(0, 20 − completed BeyondRep sessions with completedAtUtc in the 90 days up to now)`, null when the history read failed; `daysNeeded = 14 − baselineDays` when `baselineDays < 14`, else null, where `baselineDays` is the larger day count of the HRV and resting HR baselines the score used. Shown when `workoutsNeeded > 0` or `daysNeeded != null`.
- **Copy (fixed):**
  - Hero eyebrow `ENERGY NOW` (score) / `ENERGY` (other states); ring caption `Energy`; loading label `Loading energy`; gap metric name `Energy`.
  - Change line: `Started today at 78 · down 16 since morning`; when equal `Started today at 78 · no change since morning`.
  - Learning: `Still learning your patterns: 12 more workouts for a calibrated score.` / `Still learning your patterns: 9 more days of data for a calibrated score.` / `Still learning your patterns: 12 more workouts and 9 more days of data for a calibrated score.` Singular `1 more workout`, `1 more day`.
  - Building: `Energy starts after 2 more days with data.` (singular `1 more day`). Not enough data: title `Not enough data for a score`, body `Energy needs last night's sleep plus HRV or resting heart rate. A watch or ring that syncs to <platform> provides these.`
  - Items: `Workout at 7:10 AM`, `Active day so far`, `Awake 10 hours` (`Awake 1 hour`; whole hours, rounded down), `Nap at 2:40 PM`, with ` (capped)` appended to a capped nap. Points `−9` (U+2212) / `+3`.

## Review Focus

1. **Late session after midnight** (woke 06:30, trained 23:30–00:30, opens the app at 00:40): energy is shown for the waking day that started at 06:30, the session drains it, and calendar readiness for the new date stays not ready. Pinned in Task 2 (`wakingDayOf`) and Task 4.
2. **Next morning before last night's sleep syncs** (07:30, latest main sleep ended 25 h ago): no drained energy from yesterday is shown as today's; the hero shows the not-enough-data state. Pinned in Task 2, Task 4 and Task 5.
3. **Two sources around waking or a nap** (watch says woke 06:30, phone logs asleep to 06:50; or watch and phone both log the same nap): no nap is found at the wake edge and a doubly logged nap counts once. Pinned in Task 2.
4. **Active energy not allowed, failed or under 7 usual days:** no `Active day so far` row and no zero; energy is still computed from the other parts. Pinned in Task 2 and Task 4.
5. **A workout's own calories:** the hours a counted workout covers never add active drain on top of the workout item. Pinned in Task 2 and Task 4.

---

## File map

```
lib/features/health/domain/readiness.dart          readinessBaselineMinDays, baselineOf(minDays), Readiness.baselineDays
lib/features/health/domain/energy_day.dart         WakingDay, wakingDayOf, Nap, napsIn, activeExcessKcal, awakeDipPoints
lib/features/health/domain/energy.dart             EnergyItemKind, EnergyItem, Energy, apportion, energyNow, EnergyLearning, energyLearningOf, completedSessionsWithin
lib/features/health/application/health_overview.dart   EnergyOverview, HealthOverview.energy, currentEnergy, hasStaleEnergy
lib/features/health/widgets/energy_text.dart       copy helpers
lib/features/health/widgets/readiness_card.dart    Health tab hero shows energy
lib/features/health/health_page.dart               hero tap and stale check use energy
lib/features/health/detail/readiness_detail_page.dart  Energy Today view
test/support/health_overview_fixtures.dart         energySection, overview(energy:)
docs: ADR-0013 (stage 1 defaults), ROADMAP.md, RELEASE.md, CLAUDE.md
```

---

### Task 1: Readiness scores from 3 baseline days

**Files:**
- Modify: `lib/features/health/domain/readiness.dart`
- Modify: `lib/features/health/application/health_overview.dart` (`_readiness` baselines)
- Test: `test/health/domain/readiness_test.dart`, `test/health/health_overview_test.dart`, `test/health/readiness_detail_test.dart` (fixtures only if they relied on 14)

**Interfaces:**
- Produces:
  - `const readinessBaselineMinDays = 3;`
  - `Baseline? baselineOf(List<DayValue> daily, DateTime today, {required double Function(double mean) sdFloor, int minDays = 14})` — default unchanged so `usualFrom` / `dailyAverageFrom` (metric explanations) keep 14.
  - `scoreReadiness` uses `readinessBaselineMinDays` for both baselines and for `daysUntilBaseline` (`3 − most`).
  - `Readiness` gains `final int? baselineDays;` (optional constructor parameter) — the larger `Baseline.days` among the HRV and resting HR parts present; null when neither part is present.
  - `_readiness` in the overview passes `minDays: readinessBaselineMinDays` to both `baselineOf` calls, so `ReadinessOverview.hrvBaseline` / `restingHrBaseline` exist from 3 days.

- [ ] **Step 1: Write failing tests** in `readiness_test.dart`:
  - `baselineOf with minDays 3: null with 2 days, value with 3`; existing `n(13)` null / `n(14)` non-null with the default stays.
  - `HRV today with 3 baseline days and no RHR scores` (ready, parts HRV + sleep).
  - `HRV today with 2 baseline days, no RHR is not ready` → `daysUntilBaseline == 1` (replaces the 9-day test, which expected 5).
  - `HRV without baseline drops out while RHR is ready` and `no sleep and baseline building names both`: change their HRV series from 9 days to 2 days (latter expects `daysUntilBaseline == 1`).
  - `daysUntilBaseline uses the larger count`: HRV 1 day, RHR 2 days → `1`.
  - `baselineDays is the larger used baseline`: HRV 5 days, RHR 9 days → `9`; `baselineDays is 5 with only the HRV part`.
  - In `health_overview_test.dart`: rename `fewer than 14 baseline days has no baseline` to `fewer than 3 baseline days has no baseline`: HRV on 2 prior days plus today, resting HR on 2 prior days plus today → `hrvBaseline` null, `daysUntilBaseline == 1`; and `5 HRV days now give a baseline of 5 days` (`r.hrvBaseline!.days == 5`).
- [ ] **Step 2: Run** `flutter test test/health/domain/readiness_test.dart test/health/health_overview_test.dart` — Expected: new and edited tests FAIL.
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run** `flutter test test/health test/today test/train test/watch` — Expected: PASS. If a readiness-detail history test relied on days 3–13 having no score (e.g. `days without a baseline draw no bar and skip the average`), shorten that fixture's history to under 3 days so it keeps its intent; do not weaken assertions.
- [ ] **Step 5: Commit** `feat(health): score readiness from 3 baseline days`

### Task 2: Waking day, naps, active excess and awake dip (domain)

**Files:**
- Create: `lib/features/health/domain/energy_day.dart`
- Test: `test/health/domain/energy_day_test.dart`

**Interfaces:**
- Consumes: `SleepNight`, `mergedSleepMinutes` (`sleep_nights.dart`); `SleepSegment`, `SleepStage`, `HealthSample` (`health_types.dart`); `dayOf` (`daily_series.dart`); `LoadSession` (`training_load.dart`).
- Produces (constants from Global Constraints live here):
  - `typedef WakingDay = ({DateTime day, DateTime wake});` — `day` local midnight of the night's date; `wake` the night's `end`.
  - `WakingDay? wakingDayOf(List<SleepNight> nights, DateTime now)` — rule from Global Constraints (`nights` ascending, as `buildNights` returns).
  - `typedef Nap = ({DateTime start, DateTime end, int minutes});`
  - `List<Nap> napsIn(List<SleepSegment> segments, {required DateTime wake, required DateTime now})` — ascending by start.
  - `DateTime loadSessionEnd(LoadSession s)` — `s.start` plus `s.minutes` minutes (seconds precision).
  - `double? activeExcessKcal(List<HealthSample> hourly, {required WakingDay day, required DateTime now, List<LoadSession> workouts = const []})` — null under 7 usual days; `workouts` are the counted ones whose hours are skipped.
  - `double awakeDipPoints(Duration awake)`.

- [ ] **Step 1: Write failing tests** (synthetic local times on 27 Nov 2026; nights built with `SleepNight(...)` directly):
  - `wakingDayOf`: `night ended 06:31 today, now 15:00 → day 27 Nov, wake 06:31`; `at 00:40 on 28 Nov the waking day is still 27 Nov`; `exactly 20 hours after waking is still the waking day; 20h 1m is null`; `no nights → null`; `a night ending after now is skipped and the earlier one is used`.
  - `napsIn` (wake 07:00, now 17:00): `a 14:00–14:40 light segment is one 40-minute nap`; `asleep 07:30–07:50 from a second source (inside 60 min of waking) is no nap`; `a 5-minute doze is no nap`; `a 4-hour sleep 12:00–16:00 is no nap`; `watch 14:00–14:30 and phone 14:10–14:40 are one 40-minute nap`; `14:00–14:20 and 14:35–14:55 join into one nap of 40 minutes starting 14:00`; `14:00–14:20 and 15:00–15:20 are two naps`; `awake and inBed segments are ignored`; `a segment ending after now is ignored`.
  - `activeExcessKcal` (wake 07:00, now 15:00, usual 20 kcal every hour on each usual day): `two hours at 84 kcal give 128`; `an hour below usual adds nothing, never negative`; `the 09:00 bucket is skipped when a workout ran 09:00–10:00 and the 10:00 bucket is not`; `null with 6 usual days, value with 7`; `a day with no buckets is not a usual day (no zeros)`; `the 05:00–06:00 bucket before waking is ignored`; `usual for an hour counts 0 on a usual day without that hour` (7 days of 20 kcal at 10:00 only on 3 of them, other hours at 20 → usual at 10:00 is 60/7).
  - `awakeDipPoints`: `7 h → 0`, `8 h → 0`, `10 h → 1.0`, `13 h → 2.5`, `18 h → 5.0`, `20 h → 5.0`.
- [ ] **Step 2: Run** `flutter test test/health/domain/energy_day_test.dart` — Expected: FAIL (file missing).
- [ ] **Step 3: Implement** `energy_day.dart` per the interfaces and Global Constraints.
- [ ] **Step 4: Run** `flutter test test/health/domain/energy_day_test.dart test/health/health_import_guard_test.dart` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): waking day, naps and activity inputs for energy`

### Task 3: Energy now and the learning note (domain)

**Files:**
- Create: `lib/features/health/domain/energy.dart`
- Test: `test/health/domain/energy_test.dart`

**Interfaces:**
- Consumes: Task 1 `Readiness` (`value`, `baselineDays`), `ReadinessBand`, `readinessBandOf`; Task 2 everything; `LoadSession`; `WorkoutSessionRecord`, `WorkoutStatus`.
- Produces:
  - `enum EnergyItemKind { workout, activeDay, awake, nap }`
  - `class EnergyItem { const EnergyItem({required this.kind, required this.points, this.at, this.awakeHours, this.capped = false}); final EnergyItemKind kind; final int points; final DateTime? at; final int? awakeHours; final bool capped; }` — `points` signed (drain negative); `at` = workout start or nap start (as given, callers format `.toLocal()`); `awakeHours` whole hours for `awake`.
  - `class Energy { const Energy({required this.value, required this.band, required this.start, required this.items}); final int value; final ReadinessBand band; final int start; final List<EnergyItem> items; }`
  - `List<int> apportion(List<double> parts)` — largest remainder: target `parts.sum.round()` (Dart `round`, ties away from zero); start from each `floor()`; add 1 to the parts with the largest `x − x.floor()` until the sum is the target; ties go to the earlier index.
  - `Energy energyNow({required Readiness start, required WakingDay day, required DateTime now, required List<LoadSession> sessions, required List<HealthSample> hourlyActiveEnergy, required List<SleepSegment> sleepSegments})` — raw items in order: workouts (by start), active day, awake, naps (by start); recharge cap from Global Constraints; points by `apportion`; items with 0 points are dropped; `value = clamp(start.value + Σ points, 0, 100)`; `band = readinessBandOf(value)`.
  - `class EnergyLearning { const EnergyLearning({this.workoutsNeeded, this.daysNeeded}); final int? workoutsNeeded; final int? daysNeeded; bool get show; }`
  - `EnergyLearning energyLearningOf({required int? completedSessions, required int? baselineDays})` — `baselineDays` null gives `daysNeeded` null.
  - `int completedSessionsWithin(List<WorkoutSessionRecord> sessions, DateTime now)` — status completed, `completedAtUtc` non-null, after `now − 90 days` and not after `now`.

- [ ] **Step 1: Write failing tests** (wake 27 Nov 07:00 local; `start` = `Readiness(value: 78, band: good, parts: const [])` unless stated):
  - `apportion([-9.6, -8.4, -1.5, 3.0]) == [-10, -8, -2, 3]`; `apportion([0.4, 0.4, 0.4]) == [1, 0, 0]`; `apportion([]) == []`.
  - `a full day lists every change`: now 17:00; workout 07:10 for 60 min at 0.75; hourly 20 kcal every hour on 17–26 Nov, today 07:00 and 08:00 at 200, 09:00–13:00 at 84, 14:00–16:00 at 20; nap 14:00–14:15 light → items `[(workout, −9, at 07:10), (activeDay, −8), (awake, −1, awakeHours 10), (nap, +3)]`, `value 63`, `band fair`, `start 78`.
  - `nothing since waking: no items and value equals start` (now 09:00).
  - `a workout that ended before waking or yesterday is not counted`.
  - `energy never goes below 0`: start 10, workout 07:30 for 120 min at 0.9, now 10:00 → `value 0`, items `[(workout, −22)]`.
  - `naps cap at 10 in total`: start 80, workout 07:30 for 100 min at 1.0, naps 14:00–14:40 and 16:00–16:30, now 17:00 → points `[−20, −1, +6, +4]`, both naps `capped`, `value 69`.
  - `a nap never lifts energy above the start`: start 70, no workouts, no hourly data, nap 13:00–13:30, now 17:00 → items `[(awake, −1), (nap, +1, capped)]`, `value 70`.
  - `no active item with under 7 usual days` (same full day with 6 usual days → no `activeDay` item).
  - `energyLearningOf`: `(8, 5) → 12 workouts, 9 days, show`; `(20, 14) → show false`; `(null, 9) → workouts null, days 5, show`; `(19, 30) → 1 workout, days null`; `(25, null) → show false`.
  - `completedSessionsWithin counts the last 90 days`: completed 89 days ago counts, 91 days ago does not, an in-progress session does not.
- [ ] **Step 2: Run** `flutter test test/health/domain/energy_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** `energy.dart`.
- [ ] **Step 4: Run** `flutter test test/health/domain` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): energy now from readiness, drain and naps`

### Task 4: The overview holds energy

**Files:**
- Modify: `lib/features/health/application/health_overview.dart`
- Modify: `test/support/health_overview_fixtures.dart`
- Test: `test/health/health_overview_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3; in `_read`: `nights`, `_list(sleepResult)`, `_list(energyResult)`, `sessions`, the load list already passed to `_readiness`, `sleep`, `heart`, `hrvAll`, `rhrAll`, `platform`, `inputFailed`.
- Produces:
  - `class EnergyOverview { const EnergyOverview({required this.day, required this.wake, required this.start, required this.energy, required this.learning}); final DateTime day; final DateTime? wake; final ReadinessOverview start; final Energy? energy; final EnergyLearning learning; }` — `start` is the readiness for `day`; `energy` null unless `start.result` is `ReadinessReady` and a waking day exists.
  - `HealthOverview.energy` (`Section<EnergyOverview>`, constructor default `SectionGap(MetricGap.noData)`).
  - In `_read`: `wakingDayOf(nights, now)`; `day = waking?.day ?? today`; start section = the existing readiness section when `day == today`, else `_readiness(sleep, heart, <hrvAll from day − 30>, rhrAll, day, platform, inputFailed: <same>, load: <same>)`. A gap start gives the same gap for energy. `learning = energyLearningOf(completedSessions: sessions == null ? null : completedSessionsWithin(sessions, now), baselineDays: <ready start>.baselineDays)` (null `baselineDays` when not ready). The `readiness` section is unchanged (calendar today).
  - `EnergyOverview? currentEnergy(HealthOverview o, DateTime now)` — null for a gap; with `wake` non-null, the value while `now − wake ≤ energyMaxWakingDay`; with `wake` null, the value while `dayOf(o.readAt) == dayOf(now)`.
  - `bool hasStaleEnergy(HealthOverview o, DateTime now)` — `currentEnergy(o, now) == null && o.energy is SectionData`.
  - Fixtures: `Section<EnergyOverview> energySection(Section<ReadinessOverview> start, {Energy? energy, EnergyLearning learning = const EnergyLearning(), DateTime? wake, DateTime? day})` — for a ready start without `energy`, an `Energy` equal to the start with no items; `overview({..., Section<EnergyOverview>? energy})` defaults to `energySection(readiness ?? SectionGap(noData), wake: <readAt's date at 06:31 when the start is ready, else null>, day: <readAt's date>)`, so existing widget tests keep their behaviour.

- [ ] **Step 1: Write failing tests** in `health_overview_test.dart` (use `readinessWeek()`; wake is 24 Nov 06:30; add helper `_loggedAt(String id, DateTime start, Duration length)`):
  - `energy starts at readiness and drains for a workout finished today`: now 24 Nov 15:00, history `[_logged('today', 0)]` → `e.start.result` value equals `o.readiness` value; `e.energy!.items.single` is `(workout, −10)`; `e.energy!.value == start − 10`; `e.day == 24 Nov`, `e.wake == 24 Nov 06:30`.
  - `after midnight the waking day continues`: now 25 Nov 00:40, session 24 Nov 23:30 for 60 min → `e.day == 24 Nov`; points `[−10, −5]` (workout, awake); `o.readiness` result is `ReadinessNotReady` with `noSleep`.
  - `next morning before sleep syncs there is no energy`: now 25 Nov 07:30 → `e.wake` null, `e.energy` null, `e.start.result` not ready with `noSleep`.
  - `active calories above the usual hour drain, skipping the workout hour`: now 24 Nov 15:00, workout 09:00–10:00, `totals[activeEnergy]` 20 kcal every hour on 14–23 Nov, today 06:00–08:00 at 20, 09:00 at 300, 10:00 at 20, 11:00 and 12:00 at 84, 13:00 and 14:00 at 20 → points `[−10, −3]` (workout, activeDay).
  - `not allowed active energy adds no active item`: same with `totalsResults[activeEnergy] = SeriesNotAllowed()` → no `activeDay` item, energy non-null.
  - `a nap today credits energy`: now 15:00, workout today, nap segment 13:00–13:30 → items `(workout, −10)`, `(nap, +6)`; `value == start − 4`.
  - `learning counts sessions in the last 90 days`: 8 sessions 1–8 days back → `workoutsNeeded 12`, `daysNeeded` null; with a failing history → `workoutsNeeded` null.
  - `account B never sees A's energy` (as the readiness owner-switch test): mid-switch value null; B's energy start is not ready.
  - `currentEnergy`: fixture overview with wake 24 Nov 06:31 → non-null at 25 Nov 02:31, null at 25 Nov 02:32 and `hasStaleEnergy` true; a not-ready energy (wake null) read 24 Nov is null on 25 Nov 00:01.
  - `no extra reads`: the read-call expectations of the first overview test are unchanged (existing test passes untouched).
- [ ] **Step 2: Run** `flutter test test/health/health_overview_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/health test/today test/train test/watch` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): compute energy in the health overview`

### Task 5: Health tab hero shows energy

**Files:**
- Create: `lib/features/health/widgets/energy_text.dart`
- Modify: `lib/features/health/widgets/readiness_card.dart`
- Modify: `lib/features/health/health_page.dart` (hero `onTap`: `hasStaleEnergy` → refresh, else `tapFor(overview.energy, '/health/readiness')`)
- Test: `test/health/energy_text_test.dart`, `test/health/readiness_card_test.dart`, `test/health/health_page_test.dart`, `test/health/health_wide_layout_test.dart`

**Interfaces:**
- Consumes: Task 3 `Energy`, `EnergyItem`, `EnergyLearning`; Task 4 `EnergyOverview`, `currentEnergy`, `hasStaleEnergy`; `formatClockTime`.
- Produces (`energy_text.dart`, copy exactly as Global Constraints):
  - `String energyChangeText(Energy e)`, `String? energyLearningText(EnergyLearning l)` (null when `!l.show`), `String energyItemLabel(EnergyItem i)`, `String energyPointsText(int points)`, `String energyBuildingText(int days)`.
- `ReadinessCard` (same constructor) reads `overview.energy` instead of `overview.readiness`: stale check `hasStaleEnergy`; gap and not-ready states use `start` with the energy copy and `ENERGY` eyebrow; the ready state shows `energy.value` in the ring (caption `Energy`), band words of the energy band as title, subtitle lines `energyChangeText`, then the start's `readinessReasons` sentence, then `Based on …` when it applies; the three input chips as now; the learning text under the chips when shown. Semantics label starts `Energy now <value> of 100, <band words>. <change text>.` then reasons, based-on, learning text and chips. The About button stays `MetricKey.readiness` until stage 2.

- [ ] **Step 1: Write failing tests**
  - `energy_text_test.dart`: `down 16 since morning`, `no change since morning`; the three learning sentences and singulars; `null when not shown`; `Workout at 7:10 AM`, `Awake 1 hour`, `Awake 10 hours`, `Nap at 2:40 PM (capped)`; `−9`, `+3`; `Energy starts after 1 more day with data.`
  - `readiness_card_test.dart` new: `ready: energy 62, Fair, started at 78 and the learning note` (`overview(energy: energySection(ready(value: 78), energy: Energy(value: 62, band: ReadinessBand.fair, start: 78, items: [...]), learning: EnergyLearning(workoutsNeeded: 12)))` → finds `62`, `ENERGY NOW`, `Train as planned, watch effort`, text containing `Started today at 78 · down 16 since morning`, `Still learning your patterns: 12 more workouts for a calibrated score.`, no `78` ring); `no learning note when calibrated`; `after midnight the waking day's energy still shows` (add a `DateTime? now` parameter to `pump`, default `clock`, used for both clock overrides; readAt 24 Nov 23:50, now 25 Nov 00:40, wake 24 Nov 06:31 → score shown); the existing `yesterday's score is not shown today; Try again re-reads` keeps passing unchanged (readAt 23 Nov, wake 23 Nov 06:31, clock 24 Nov 07:45 is over 20 h); `building says Energy starts after 2 more days with data.`
  - Update existing card tests' expected copy (`READINESS` → `ENERGY` / `ENERGY NOW`, `Loading readiness` → `Loading energy`, `Readiness 77 of 100` → `Energy now 77 of 100`, building and not-enough copy); keep every other assertion, including no zeros on phone-only and text scale 2.0 at 320 dp without overflow in light and dark.
  - `health_page_test.dart`: `tapping the energy hero opens /health/readiness`.
- [ ] **Step 2: Run** `flutter test test/health/energy_text_test.dart test/health/readiness_card_test.dart test/health/health_page_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/health test/accessibility test/design_kit_guard_test.dart` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): show energy now on the Health tab hero`

### Task 6: Energy on the readiness detail screen

**Files:**
- Modify: `lib/features/health/detail/readiness_detail_page.dart`
- Test: `test/health/readiness_detail_test.dart`

**Interfaces:**
- Consumes: Task 4 `currentEnergy`, `hasStaleEnergy`, `EnergyOverview`; Task 5 copy helpers; existing `DetailPanel(title:, trailing:, info:, children:)`, `DetailRow(label, value)`, `HealthCaption`, `NsScoreRing`.
- Rules:
  - Page title `Energy`; the 7/30-day tabs and their chart are unchanged in this stage.
  - The builder switches on `overview.energy` and uses `currentEnergy` / `hasStaleEnergy` in place of `todaysReadiness` / `hasStaleReadiness`; `_Today` takes the `EnergyOverview`.
  - Score (energy non-null): summary panel with ring `energy.value` (caption `Energy`), band words, `HealthCaption(energyChangeText)` and the learning text when shown. Then panel `Since you woke`, trailing `Woke at <formatClockTime(wake.toLocal())>`: one `DetailRow(energyItemLabel(i), energyPointsText(i.points))` per item; when any nap is capped `HealthCaption('Naps add back up to 10 points, and never more than the day has used.')`; with no items `HealthCaption('Nothing has changed your energy since you woke.')`. Then the existing parts panel built from `start`, titled `Why you started at <start value>`.
  - Not ready: `ReadinessCard` as now (it shows the energy states from Task 5).
  - `whyNot` copy: `Your normal needs 3 days of HRV in the last 30.` and `Your normal needs 3 days of resting HR in the last 30.`
  - Replace the `How readiness works` panel with `How energy works` (same About button) and this text, `$hrvName` as now: `Energy starts each day from your recovery when you wake: today's $hrvName and resting heart rate against your own normal (their average over the 30 days before), last night's sleep, your sleep over the past week and your recent training load. A measure counts once it has 3 days of data. Until it has 14, and until you have logged 20 workouts in BeyondRep, the score is still learning. Through the day energy goes down with each workout you finish, with active calories above your usual for that hour, and a little with long hours awake; a nap adds a few points back. Your day runs from waking to your next main sleep, so a late session counts for the day you are still awake in. The 7 and 30 day comparison scores the days before the period without sleep heart rate. Energy is a suggestion for planning your training, not medical advice.`

- [ ] **Step 1: Write failing tests** (`_todayOverview()` and the other directly built overviews also pass `energy: energySection(...)`):
  - `Today shows energy, the change line and every item`: energy 62 from 78 with items workout −9 at 7:10 AM, active −8, awake −1 (10 h), nap +3 at 2:40 PM → finds `62`, `Started today at 78 · down 16 since morning`, `Since you woke`, `Woke at 6:31 AM`, rows `Workout at 7:10 AM`/`−9`, `Active day so far`/`−8`, `Awake 10 hours`/`−1`, `Nap at 2:40 PM`/`+3`, `Why you started at 78`.
  - `a capped nap explains the cap`; `no items says nothing has changed`; `learning note shows days and workouts`.
  - `the breakdown is the start's parts` (existing `one row per part with its normal range and share` passes under the new title).
  - `a part that dropped out says why` now expects `Your normal needs 3 days of HRV in the last 30.`
  - `yesterday's overview never shows yesterday's energy` (as the existing test, overview read the day before the clock, more than 20 h after its wake) and `a re-read in flight shows loading, not the old score` adapted to energy.
  - Existing `no overflow at text scale 2.0 in dark mode` passes with the new panels.
- [ ] **Step 2: Run** `flutter test test/health/readiness_detail_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/health test/accessibility` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): energy, its changes and its start on the detail screen`

### Task 7: Docs and full verification

**Files:**
- Modify: `docs/adr/0013-energy-score.md` (add `## Stage 1 defaults`: the constants table and the waking-day, nap, active and recharge-cap rules from Global Constraints, marked as a starting point to tune after device use; status line notes stage 1 implemented in source, not released or device-verified)
- Modify: `docs/ROADMAP.md` (health insights paragraph: energy stage 1 implemented in source, not released or device-verified; stages 2 and 3 not started)
- Modify: `docs/RELEASE.md` (device rows: a morning gym session drains energy and shows its row; a late session after midnight on the previous waking day; a nap tracked by Apple Watch / a Health Connect source; the next morning before sleep syncs shows no stale energy; Android without active-energy permission shows no active row)
- Modify: `CLAUDE.md` (project-state health line: energy stage 1 implemented in source on the Health tab and readiness detail; other surfaces still show readiness)

- [ ] **Step 1:** Write the doc updates; claim nothing beyond "implemented in source, not released or device-verified".
- [ ] **Step 2: Run** from repo root `python3 -m unittest discover -s tool -p 'test_*.py'` — Expected: OK.
- [ ] **Step 3: Run** from `apps/mobile`: `dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test` — Expected: format clean, `No issues found!`, all tests pass; record the test count.
- [ ] **Step 4: Commit** `docs: energy score stage 1 defaults and status`
