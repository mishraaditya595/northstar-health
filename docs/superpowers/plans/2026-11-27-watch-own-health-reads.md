# Watch reads its own health (sleep, steps, HRV, resting heart rate) — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (Adi's choice: one Sonnet agent runs the whole plan, then an Opus review). Steps use checkbox (`- [ ]`) syntax. Strict TDD: write the failing test first.

**Why (Adi, 2026-11-27):** "for datapoints which can be directly accessed from the watch, we should show them without a sync from the phone. For eg: sleep, steps, hrv."

**Goal:** the watch Home tiles (Sleep, Resting HR, HRV, Steps) and their detail screens show values the watch reads itself from its own HealthKit store, so they appear before (or without) a phone sync. Readiness, sleep score, "vs usual" lines and the 7-day trends still come only from the phone (ADR-0012 decision 4: scores stay on the phone).

**Architecture:**
- **Pure Swift in `BeyondRepWatchCore`** (tested by `swift test`):
  - `WatchHealthDerivation`: a port of the phone's day rules. It covers `buildNights` and `mergedSleepMinutes` (`apps/mobile/lib/features/health/domain/sleep_nights.dart`), `hrvDailyOf` (`health_overview.dart`), and `reduceDaily(.latest)` for resting heart rate (`daily_series.dart`).
  - `WatchHealth` value type and the merge rule with the phone snapshot, inside `GlanceState.make` and the detail model.
- **Golden cases in `contracts/watch_link/v1/cases/health/`** run through both the Dart functions and the Swift port, so the two produce the same numbers. This is ADR-0012 decision 7: shared logic is checked by language-neutral files.
- **App target:** `apps/watch_os/Sources/HealthKit/HealthGlanceReader.swift` (new) reads raw samples with HealthKit queries and hands them to the core. `AppModel` holds the result in memory only.

## Global constraints

- **Public repository:** synthetic data only. Read `AGENTS.md`, `apps/watch_os/AGENTS.md` and `apps/mobile/AGENTS.md` first.
- **Never stored:** watch-read health values live only in memory, in `AppModel`. They are not stored in the SQLite journal, `UserDefaults` or files. They are never sent to the phone, logged or put in the ack.
- **Missing is "—", never 0.** As on the phone: an iOS steps total of 0 shows as missing, and a failed or denied read shows as missing.
- **Account binding still required.** With no binding the Home stays `.notPaired` and nothing is read.
- **Merge rule per tile (today's local date only):**
  - Sleep (asleep minutes): the phone's value if today's snapshot has one, else the watch's. Sleep score: the phone only.
  - Resting HR and HRV: the phone's value if present, else the watch's. "vs usual" lines appear only when the phone sent a usual value. When the value came from the watch, compare the watch's value against the phone's usual.
  - Steps: the larger of the phone's and the watch's. Steps only grow during a day, and each device's store may lack the other's samples.
  - Readiness, factors and reason: the phone only. Without a phone snapshot there is no readiness hero.
  - 7-day trends: the phone's days. Today's point in a trend detail uses the merged tile value.
- **Caption:**
  - With a phone snapshot, unchanged ("as of 10:43").
  - Without one, but with any watch value: "From this watch. Open BeyondRep on your iPhone for readiness".
  - With neither: the existing refresh caption.
- **HealthKit read types added on the watch:** `stepCount`, `sleepAnalysis`, `heartRateVariabilitySDNN`, `restingHeartRate`. `heartRate` and `activeEnergyBurned` are already there. Share types stay as they are (workout only).
- **Authorization:** one `requestAuthorization` for workout share plus all read types. It is asked when the Home first shows with a binding and `getRequestStatusForAuthorization` says `.shouldRequest`. Workout start keeps asking too, which is a no-op once decided. Never loop on a denial (HealthKit hides read denials, so a denied read just returns no samples, which shows as missing).
- **Refresh:**
  - On scene active.
  - On Home appear.
  - After each phone `health_snapshot`.
  - At local midnight (the existing timer).
  - Every 5 minutes while the app is active and no workout is running.
  - Values are dropped on sign out or `account_cleared`, and when the local date changes.
- **Usage strings:** `NSHealthShareUsageDescription` in `apps/watch_os/project.yml` becomes "BeyondRep reads your sleep, steps, heart rate, HRV and active energy to show them on your watch and during a workout." Keep every other place that copies it (check `tool/embed_watch_target.rb` and `tool/test_*.py`) in sync.
- **Out of scope:** phone changes beyond the Dart golden test, complications, background delivery, Wear OS, live handoff (stage 5).

## Review focus

1. Do the Swift port and the Dart functions agree on every golden case, including a nap, two sources, a session gap over 60 minutes, a night ending before 03:00, and HRV both inside and outside a night? *(Task 1 and Task 2.)*
2. Are no watch-read values written anywhere? *(Task 3: grep plus a journal test asserting no new rows.)*
3. Is "missing" kept as missing, never 0 (steps 0, denied reads, a failed query)? *(Task 2 and Task 4 tests.)*
4. Does the merge rule hold, and is today's local date the only date that is ever shown? *(Task 2.)*
5. Is the watch value ever shown for a different account after a rebind? Values are cleared on `account_cleared` and on a binding change. *(Task 4.)*

---

### Task 1: Golden cases and the Dart runner

**Files:**
- Create `contracts/watch_link/v1/cases/health/*.json`, at least 8 synthetic cases.
- Modify `contracts/watch_link/v1/README.md` to describe the folder.
- Create `apps/mobile/test/watch/health_derivation_cases_test.dart`.

Case shape:

```json
{
  "description": "...",
  "utc_offset_minutes": 0,
  "now": "2026-11-20T09:30:00Z",
  "sleep": [{"from": "...Z", "to": "...Z", "stage": "light|deep|rem|asleep_unspecified|awake|in_bed", "source_key": "com.example.watch"}],
  "hrv": [{"from": "...Z", "to": "...Z", "value": 48.2}],
  "resting_hr": [{"from": "...Z", "to": "...Z", "value": 57}],
  "expected": {"asleep_minutes": 431, "hrv_ms": 48, "resting_hr_bpm": 57}
}
```

`expected` keys are omitted when missing. Values are rounded the way `watch_snapshots.dart` rounds them (`.round()`), and "today" is the local date of `now`.

- [ ] Write the cases. Cover:
  - one plain night;
  - stages from two sources (the source with more deep, rem and light wins);
  - a nap only;
  - a nap plus the main sleep;
  - a gap over 60 minutes splitting sessions;
  - a session ending at 02:30 (not a main-sleep candidate unless it crosses a date);
  - awake and in-bed segments attached by the padded window;
  - HRV samples inside the night (overnight mean) and HRV with no night (daytime mean);
  - resting HR latest-of-today;
  - an empty input, which gives an empty `expected`.
- [ ] The Dart test runs each case through `buildNights`, `hrvDailyOf` and `reduceDaily(DailyReduction.latest)`, picking today's values exactly as `watch_snapshots.dart` does, and asserts `expected`. `buildNights` uses `toLocal()`, so skip a case with a clear reason when `DateTime.now().timeZoneOffset` differs from its `utc_offset_minutes`. CI runs in UTC, so keep every case at offset 0.
- [ ] Run it: `flutter test test/watch/health_derivation_cases_test.dart`. The cases must pass against the unchanged phone code. If one fails, the case is wrong, not the phone.
- [ ] Commit.

### Task 2: Swift port, `WatchHealth`, merge into the glance

**Files:**
- Create `Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Glance/WatchHealthDerivation.swift` and `WatchHealth.swift`.
- Modify `Glance/GlanceState.swift` and `Glance/DetailModel.swift`.
- Tests: `Tests/BeyondRepWatchCoreTests/WatchHealthDerivationTests.swift` (loads the golden cases with `FixtureLoader.files(in: "contracts/watch_link/v1/cases/health")`), plus additions to `GlanceStateTests.swift` and the detail model tests.

The types:
- `public struct SleepSample { from, to: Date; stage: SleepStage; sourceKey: String }`
- `public struct ValueSample { from, to: Date; value: Double }`
- `public struct WatchHealth: Equatable { localDate: String; asleepMinutes, restingHrBpm, hrvMs, steps: Int? }`
- `WatchHealthDerivation.today(sleep:hrv:restingHr:steps:now:timeZone:) -> WatchHealth`. It applies the same rules as the Dart code. Steps arrive already summed by HealthKit statistics, and 0 becomes nil.

- [ ] Failing test: every golden case gives `expected`, using the case's `utc_offset_minutes` as a fixed-offset time zone.
- [ ] Port the rules. Match the Dart code line by line: session gap 60 minutes, the main-sleep candidate rule (end hour ≥ 3 or crosses a date), longest per source and date, the `_beats` order, and merged minutes counting overlaps once. Then make the test pass.
- [ ] Failing tests for `GlanceState.make(journal:now:timeZone:locale:watch:)`. `watch` is a new optional `WatchHealth?` parameter, defaulting to nil so existing callers compile. Cover:
  - no snapshot plus watch values: tiles show the watch values, there is no readiness, and the caption is the "From this watch" text;
  - snapshot plus watch values: sleep, RHR and HRV from the phone, steps the max;
  - phone steps 9,000 and watch 9,450 gives 9,450;
  - a watch value for another `localDate` is ignored;
  - a watch value with RHR present and a phone usual value present gives a "vs usual" line;
  - all nil stays "—".
- [ ] Implement it. The detail model's today point uses the merged value the same way. Make the tests pass.
- [ ] Commit.

### Task 3: HealthKit reads on the watch

**Files:**
- Create `apps/watch_os/Sources/HealthKit/HealthGlanceReader.swift`.
- Modify `Sources/HealthKit/WorkoutRecorder.swift` (read types and a shared authorization helper), `apps/watch_os/project.yml` (usage string), and the embed tool and its tests if they copy the string.
- Run `cd tool && bundle exec ruby embed_watch_target.rb` because a Swift file is added, and commit the `Runner.xcodeproj` change.

- [ ] `HealthGlanceReader.read(now:timeZone:) async -> WatchHealth`. It reads:
  - sleep `HKCategorySample`s from yesterday 12:00 local to now;
  - HRV SDNN samples over the same window;
  - resting HR samples from today's local midnight to now;
  - a steps `HKStatisticsQuery` with `.cumulativeSum` from local midnight to now.
- [ ] Map `HKCategoryValueSleepAnalysis` stages: `inBed` → in_bed, `asleepUnspecified` → asleep_unspecified, `asleepCore` → light, `asleepDeep` → deep, `asleepREM` → rem, `awake` → awake. Use the bundle identifier as `sourceKey`, as the phone's `sourceId` does.
- [ ] Each query failing on its own leaves only that value nil. Then call `WatchHealthDerivation.today`. Nothing is stored.
- [ ] Add the authorization helper: one request for workout share plus all reads, and `shouldRequestGlanceAuthorization()` using `getRequestStatusForAuthorization`.
- [ ] No unit test is possible for HealthKit itself. Keep the reader a thin mapping, and put any logic in the core where it is tested.
- [ ] Run `grep -rn "watchHealth\|WatchHealth" apps/watch_os/Sources` and confirm the values are never passed to the journal, `PhoneLink` or the logs.
- [ ] Commit.

### Task 4: AppModel wiring and the Home

**Files:**
- Modify `Sources/App/AppModel.swift`, `Sources/App/BeyondRepWatchApp.swift`, `Sources/Features/Home/HomePage.swift` (only if it needs the auth trigger), and `Sources/Features/Root/RootView.swift` if needed.

- [ ] `AppModel` keeps `private var watchHealth: WatchHealth?` and `refreshWatchHealth()`. The refresh returns immediately when there is no binding. Otherwise it reads, assigns on the main actor, and calls `refresh()`. `refresh()` passes `watchHealth` to `GlanceState.make`.
- [ ] Clear `watchHealth` on `account_cleared`, on a binding with a different account key, and in the midnight refresh before re-reading.
- [ ] Triggers:
  - scene active (after `pruneStale`);
  - Home `onAppear`;
  - after a `health_snapshot` is applied;
  - a 5-minute repeating task while active, cancelled on background and while `workout != nil`.
- [ ] The first Home appear with a binding asks for authorization when `shouldRequest` is true, then reads.
- [ ] Tests: if `AppModel` has none, add core tests for any logic you move into the core, such as a pure "should clear on binding change" helper.
- [ ] Commit.

### Task 5: Docs and the ADR

- [ ] ADR-0012 decision 4: add "Amendment, 2026-11-27 (requested by Adi)". It says the watch reads sleep, steps, HRV and resting heart rate from its own HealthKit store, in memory only, to show them before a phone sync, using the same day rules (checked by `contracts/watch_link/v1/cases/health/`). The phone value wins for sleep, resting HR and HRV, and steps take the larger value. Scores stay on the phone.
- [ ] `docs/HEALTH_DATA.md`: add the watch read types and the in-memory rule.
- [ ] `docs/RELEASE.md`: add device rows, all "not run":
  - permission prompt on first Home;
  - values with the phone off;
  - steps grow;
  - the phone value takes over for sleep;
  - deny permission shows "—".
- [ ] `docs/ROADMAP.md` and the `CLAUDE.md` Phase 4 line: one sentence each, "implemented in source, not released or device-verified".
- [ ] Run `python3 -m unittest discover -s tool -p 'test_*.py'`.
- [ ] Commit.

## Checks before handing back

From `apps/mobile`:
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- the new test file, then the full `flutter test`

From the repo root:
- `python3 -m unittest discover -s tool -p 'test_*.py'`

Swift cannot run here. CI `watchos_smoke.yml` runs `swift test` and both builds.
