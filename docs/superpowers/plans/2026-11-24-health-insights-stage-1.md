# Health insights, stage 1 (chart kit + richer data and trends) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Health tab's four single-number cards with richer Sleep, Heart, Activity and Body cards, each opening a detail screen with 7 and 30 day trends, all read fresh from Apple Health / Health Connect and never stored.

**Architecture:** New chart widgets go into the design kit first (`lib/core/design/charts/`). Health gains a pure-Dart `domain/` layer (sleep nights, sleep score, daily reduction, trends) fed by new range reads on the existing `HealthReader` interface. A new in-memory `healthOverviewProvider` builds the overview per account; detail screens read the extra data they need through their own providers. Readiness (stage 2) and training tie-ins (stage 3) get their own plans.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, go_router 16, `health` 14.0.0 (pinned), `CustomPaint` for charts. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-24-health-insights-design.md` (mockups in `docs/superpowers/specs/2026-11-24-health-insights-mockups/`).

## Global Constraints

- No health value or derived score is ever written to disk, ObjectBox, Supabase, the outbox, the export, logs or analytics. In-memory only, dropped on sign-out, account switch, Disconnect and process death.
- `platform_health_reader.dart` stays the only importer of `package:health`. `features/sync`, `features/account` (except `account_gate.dart`), `core/storage` and the export never import `features/health`.
- `lib/features/health/domain/` imports only `dart:` libraries and other files in `domain/` (no Flutter, Riverpod, ObjectBox, plugin).
- Missing data shows `—` with a reason, never `0`. iOS denial reads as empty (no data); Android reports "Not allowed".
- Every better/worse signal is arrow + words + colour; colour alone never carries it. Weight and body fat are neutral (change only).
- Features use kit widgets only; `test/design_kit_guard_test.dart` must stay green. Charts live in `lib/core/design/charts/`.
- Every chart has a text `semanticsLabel`.
- Support light/dark, phone and tablet two-column, text scale 2.0, reduced motion (no chart animations).
- Synthetic data only in tests and docs. Public repo: no keys, project refs or real data.
- HRV: iOS reads `HEART_RATE_VARIABILITY_SDNN`, Android `HEART_RATE_VARIABILITY_RMSSD`; copy names which ("HRV (SDNN)" / "HRV (RMSSD)").
- Sleep reference line: 7h30m. No user goals.
- After each task, from `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, the task's tests. Full `flutter test` at the end of each part.

## Review Focus

1. **A night with a nap** (main sleep 23:30-06:30 plus a 14:00-14:40 nap the next day): last night is the main sleep; the nap counts nowhere. Pinned in Task 7.
2. **Daylight-saving night and a UTC+05:30 zone**: hourly buckets summed into the right local day; a 23 h or 25 h day neither drops nor double counts an hour. Pinned in Task 6 and Task 10.
3. **Watch and ring both record the same night**: stages, duration and score come from one source (most staged minutes), never mixed. Pinned in Task 7.
4. **An account connected under Phase 3** opens the new tab: new types were never requested, so cards needing them show "Allow more data" (not "No data") and one tap requests only the missing types. Pinned in Task 10 and Task 13.
5. **Android, connected 10 days ago, no history permission**: 30-day views show the readable days and hide "vs previous 30 days"; nothing is compared against an unreadable period. Pinned in Task 6 and Task 12.
6. **Account switch while a read is in flight**: B never sees A's overview. Pinned in Task 12.

---

## File map

```
lib/core/design/charts/
  trend_label.dart        NsTrendTone, NsTrendLabel
  score_ring.dart         NsScoreRing
  bar_series.dart         NsBarChart (+ reference line, stacked segments)
  line_chart.dart         NsLineChart (line or dots, optional rolling avg, optional band), NsSparkline
  sleep_stages.dart       NsStageBar, NsStageTimeline, NsStageColors
lib/features/health/
  domain/health_types.dart     DayValue, HealthSample, SleepStage, SleepSegment
  domain/daily_series.dart     reduceDaily, hourlyToDaily, PeriodSummary, summarizePeriod
  domain/trend.dart            TrendMetric, TrendResult, trendOf
  domain/sleep_nights.dart     SleepNight, buildNights
  domain/sleep_score.dart      SleepContributor, ContributorResult, SleepScore, scoreSleep
  data/health_reader.dart      + HealthSeriesType, HealthTotalType, SeriesResult, range-read methods
  data/platform_health_reader.dart  + implementations, expanded permissions
  application/health_overview.dart  overview model + healthOverviewProvider
  application/health_details.dart   sleepDetailProvider, heartDetailProvider
  widgets/sleep_card.dart, heart_card.dart, activity_card.dart, body_card.dart, metric_unavailable.dart
  detail/sleep_detail_page.dart, heart_detail_page.dart, activity_detail_page.dart, body_detail_page.dart
  health_page.dart, health_format.dart (extended)
docs/adr/0009-health-insights-trends.md
```

---

## Part A: chart kit (own PR)

### Task 1: Trend label and score ring

**Files:**
- Create: `lib/core/design/charts/trend_label.dart`, `lib/core/design/charts/score_ring.dart`
- Test: `test/core/design/charts/trend_label_test.dart`, `test/core/design/charts/score_ring_test.dart`

**Interfaces:**
- Produces:
  - `enum NsTrendTone { better, worse, neutral, same }`
  - `NsTrendLabel({required NsTrend direction, required NsTrendTone tone, required String text})` (reuses `NsTrend` from `stats.dart`). Renders `▲`/`▼`/`●` + text. Colours: better = `colorScheme.primary` (lime dark / forest light), worse = `BeyondRepPalette.amberDark`/`amberLight`, neutral and same = muted.
  - `NsScoreRing({required int? value, required double size, required Color color, String caption = ''})`: ring filled `value/100`, centre text value or `—` when null; `Semantics(label: '$caption $value of 100')`.

- [ ] **Step 1: Write failing tests**
  - `NsTrendLabel shows arrow and text`: pump `NsTrendLabel(direction: NsTrend.down, tone: NsTrendTone.better, text: '3 bpm this month')`; `expect(find.text('▼ 3 bpm this month'), findsOneWidget)`.
  - `better and worse differ in colour, neutral is muted` (dark theme): read the `Text` style colours; better == `BeyondRepPalette.lime`, worse == `BeyondRepPalette.amberDark`, neutral == `BeyondRepPalette.darkMuted`.
  - `NsScoreRing null shows a dash`: `find.text('—')` and semantics label contains `no score`.
  - `NsScoreRing semantics`: value 74, caption `Sleep score` → `find.bySemanticsLabel('Sleep score 74 of 100')`.
- [ ] **Step 2: Run** `flutter test test/core/design/charts/` → FAIL (files missing).
- [ ] **Step 3: Implement** both widgets. Ring via `CustomPaint` (track = `BeyondRepColors.border`, stroke 8% of size, round caps). Null value semantics: `'$caption: no score'`.
- [ ] **Step 4: Run** same command → PASS. Format + analyze clean.
- [ ] **Step 5: Commit** `feat(design): add trend label and score ring`.

### Task 2: Bar chart, line chart, sparkline

**Files:**
- Create: `lib/core/design/charts/bar_series.dart`, `lib/core/design/charts/line_chart.dart`
- Test: `test/core/design/charts/bar_series_test.dart`, `test/core/design/charts/line_chart_test.dart`

**Interfaces:**
- Produces:
  - `class NsBar { const NsBar({required this.segments, this.highlight = false}); final List<({double value, Color color})> segments; final bool highlight; }` (a bar with an empty `segments` list is a no-data day: drawn as a 2 px muted stub, never a zero bar).
  - `NsBarChart({required List<NsBar> bars, required String semanticsLabel, double? referenceValue, String? referenceLabel, double height = 130, List<String> axisLabels = const []})`. Max = max(bar totals, referenceValue) × 1.1. Reference line dashed.
  - `NsLineChart({required List<double?> values, required String semanticsLabel, bool dots = false, List<double?>? rollingAverage, ({double low, double high, String label})? band, double height = 120, String? startLabel, String? endLabel})`. `null` values are gaps (line breaks; no dot). Band drawn as a filled soft rectangle behind.
  - `NsSparkline({required List<double?> values, required Color color, required String semanticsLabel, double width = 150, double height = 30})`.

- [ ] **Step 1: Write failing tests**
  - `NsBarChart exposes its semantics label` → `find.bySemanticsLabel('Time asleep, 7 nights')`.
  - `NsBarChart paints with an empty-segment bar` (no exception; `tester.takeException()` is null) for bars `[NsBar(segments: []), NsBar(segments: [(value: 400, color: Colors.purple)])]`.
  - `NsBarChart with all bars empty and no reference` → renders, no exception (max falls back to 1).
  - `NsLineChart handles null gaps and a single value` → no exception for `[null, 54, null]` and `[54]`.
  - `NsSparkline exposes semantics`.
  - Each test also pumps at `MediaQuery(textScaler: TextScaler.linear(2))` without overflow (`tester.takeException()` null).
- [ ] **Step 2: Run** `flutter test test/core/design/charts/` → FAIL.
- [ ] **Step 3: Implement** with `CustomPainter`s (`shouldRepaint` compares inputs). Axis labels are `Text` widgets under the paint area, not painted text, so they scale. No animation.
- [ ] **Step 4: Run** → PASS; format + analyze.
- [ ] **Step 5: Commit** `feat(design): add bar, line and sparkline charts`.

### Task 3: Sleep stage bar and timeline, catalog entry

**Files:**
- Create: `lib/core/design/charts/sleep_stages.dart`
- Modify: `docs/DESIGN_SYSTEM.md` (Shared Flutter components table)
- Test: `test/core/design/charts/sleep_stages_test.dart`

**Interfaces:**
- Produces:
  - `enum NsStage { awake, rem, core, deep }` (kit-level; the feature maps its own stage enum onto it).
  - `class NsStageColors { static Color of(NsStage s, Brightness b); }` dark: deep `#5B48A8`, core `#8E7AE0`, rem `BeyondRepPalette.sleepDark`, awake `BeyondRepPalette.amberDark`; light: deep `#3E2F7A`, core `#6650AB`, rem `#9C86E0`, awake `BeyondRepPalette.amberLight`.
  - `NsStageBar({required Map<NsStage, Duration> totals, required String semanticsLabel})`: one 10 px rounded bar of proportions in order deep, core, rem, awake.
  - `NsStageTimeline({required List<({DateTime from, DateTime to, NsStage stage})> segments, required String startLabel, required String endLabel, required String semanticsLabel})`: four rows (Awake, REM, Core, Deep top to bottom), x = time.
- [ ] **Step 1: Failing tests**: semantics labels found; zero total (`{}`) renders an empty muted bar with no exception; timeline with one segment and with overlapping segments renders; row labels `Awake`, `REM`, `Core`, `Deep` present as `Text`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Add rows to the DESIGN_SYSTEM.md table: `Trend arrow + words` → `NsTrendLabel` (`charts/trend_label.dart`); `Score ring` → `NsScoreRing`; `Bars / lines / sparkline` → `NsBarChart`, `NsLineChart`, `NsSparkline`; `Sleep stages` → `NsStageBar`, `NsStageTimeline`.
- [ ] **Step 4: Run** `flutter test test/core/design/charts/ test/design_kit_guard_test.dart` → PASS; full `flutter test` passes.
- [ ] **Step 5: Commit** `feat(design): add sleep stage charts and catalog entries`.

---

## Part B: stage 1, richer data and trends

### Task 4: ADR-0009 and docs

**Files:**
- Create: `docs/adr/0009-health-insights-trends.md`
- Modify: `docs/HEALTH_DATA.md`, `docs/ROADMAP.md`, `CLAUDE.md` (Project state: add a "Health insights (in progress, not released)" bullet; do not mark anything implemented that isn't)

- [ ] **Step 1:** Write ADR-0009 in ADR-0008's format. Status: Accepted, decided by the human owner on 2026-11-24 (design approved). Amends ADR-0008 items 1 (metric list and windows: now the spec's read table), 3 (still no on-disk cache; in-memory cache per account with 5-minute resume refresh), 7 (`READ_HEALTH_DATA_HISTORY` now requested where `isHealthDataHistoryAvailable`, so 30-day comparisons have a previous period). Records: added read types (list from spec "Permissions"), derived scores computed on device and never stored, one source per night for sleep stages, HRV measure differs by platform, alternatives considered (store daily summaries: rejected by owner; fl_chart: rejected).
- [ ] **Step 2:** HEALTH_DATA.md: point the read scope at ADR-0009. ROADMAP: add the stage list. Run `python3 -m unittest discover -s tool -p 'test_*.py'` from repo root → PASS.
- [ ] **Step 3: Commit** `docs: ADR-0009 health insights and trends`.

### Task 5: Domain types and guard

**Files:**
- Create: `lib/features/health/domain/health_types.dart`
- Modify: `test/health/health_import_guard_test.dart`

**Interfaces:**
- Produces:
  - `typedef DayValue = ({DateTime day, double value});` `day` is a local date at 00:00.
  - `typedef HealthSample = ({DateTime from, DateTime to, double value, String source});`
  - `enum SleepStage { awake, light, deep, rem, asleepUnspecified, inBed }`
  - `typedef SleepSegment = ({DateTime from, DateTime to, SleepStage stage, String source});`
- [ ] **Step 1: Failing test** in the guard file: `health domain imports only dart: and domain files` (resolve imports of every file under `lib/features/health/domain/`; each must start with `dart:` or `lib/features/health/domain/`). Also: `no file under features/health/application or domain imports objectbox or dart:io`.
- [ ] **Step 2: Run** `flutter test test/health/health_import_guard_test.dart` → FAIL (no domain dir: make the test fail explicitly when the directory is missing).
- [ ] **Step 3:** Create `health_types.dart`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(health): domain types and import guard`.

### Task 6: Daily series, period summaries, trends

**Files:**
- Create: `lib/features/health/domain/daily_series.dart`, `lib/features/health/domain/trend.dart`
- Test: `test/health/domain/daily_series_test.dart`, `test/health/domain/trend_test.dart`

**Interfaces:**
- Consumes: `DayValue`, `HealthSample` (Task 5).
- Produces:
  - `enum DailyReduction { latest, mean, sum }`
  - `List<DayValue> reduceDaily(List<HealthSample> samples, DailyReduction how)`: groups by local date of `to` (`latest` = value with newest `to`), sorted by day ascending.
  - `List<DayValue> hourlyToDaily(List<HealthSample> hourly)`: sums buckets by local date of `from`.
  - `class PeriodSummary { final double? average; final int daysWithData; final double? previousAverage; }` (`previousAverage` null when not comparable)
  - `PeriodSummary summarizePeriod(List<DayValue> series, {required DateTime lastDay, required int days, DateTime? readableFrom})`: current window = `days` local days ending at `lastDay` inclusive; previous window = the `days` before it. `previousAverage` is set only when `readableFrom == null || !previousStart.isBefore(readableFrom)` **and** the previous window has data on at least `days ~/ 2` days. `average` null when no data.
  - `enum TrendMetric { sleepDuration, sleepScore, deep, rem, restingHr, sleepHr, hrv, vo2Max, steps, activeEnergy, weight, bodyFat }`
  - `class TrendResult { final NsTrendDirection direction; final TrendTone tone; final double delta; }` with domain-local `enum NsTrendDirection { up, down, flat }` and `enum TrendTone { better, worse, neutral, same }` (domain cannot import the kit; the UI maps them).
  - `TrendResult trendOf(TrendMetric m, double current, double reference)`

Dead bands (|delta| ≤ band → `flat`/`same`): sleepDuration 10 (min), sleepScore 3, deep 5 (min), rem 5 (min), restingHr 1, sleepHr 1, hrv max(3, 5% of reference), vo2Max 0.5, steps 5% of reference, activeEnergy 5% of reference, weight 0.2, bodyFat 0.3. Higher is better: sleepDuration, sleepScore, deep, rem, hrv, vo2Max, steps, activeEnergy. Lower is better: restingHr, sleepHr. Neutral: weight, bodyFat.

- [ ] **Step 1: Failing tests**
  - `reduceDaily latest keeps the newest sample per day`; `mean averages`; `sum adds`.
  - `hourlyToDaily in Asia/Calcutta`: hourly samples built with local `DateTime(2026, 11, 23, h)` for h 0..23 value 100 each, plus 24 more on the 24th → `[(day: 23 Nov, value: 2400), (day: 24 Nov, value: 2400)]`.
  - `hourlyToDaily across a 25 h DST day` (construct 25 hourly buckets whose `from` local dates fall on one day: 25 × 10 = 250) and a 23 h day (230). Build them from `DateTime.utc` instants converted `.toLocal()` only if the test runner's TZ has DST; otherwise construct local `DateTime`s directly so the test is TZ-independent (sum keyed by `DateTime(from.year, from.month, from.day)`).
  - `summarizePeriod hides previous when outside readable window`: 30-day series, `readableFrom` = lastDay − 39 days, days 30 → `previousAverage` null; with `readableFrom` null → non-null.
  - `summarizePeriod hides previous when previous window is sparse` (2 of 7 days) → null.
  - `trendOf restingHr 54 vs 57 is down/better, delta -3`; `restingHr 56.5 vs 57 is flat/same`; `hrv 52 vs 46 up/better`; `hrv 48 vs 46 flat (band 3)`; `steps 9000 vs 9400 flat (5% = 470)`; `weight 78.4 vs 79.3 down/neutral`; `sleepDuration 372 vs 408 down/worse`.
- [ ] **Step 2: Run** `flutter test test/health/domain/` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(health): daily series, period summaries and trend directions`.

### Task 7: Sleep nights (sessions, main sleep, one source per night)

**Files:**
- Create: `lib/features/health/domain/sleep_nights.dart`
- Test: `test/health/domain/sleep_nights_test.dart`

**Interfaces:**
- Consumes: `SleepSegment`, `SleepStage`.
- Produces:
  ```dart
  class SleepNight {
    final DateTime date;            // local date the main sleep ended on
    final DateTime start, end;      // first/last asleep segment
    final String source;
    final List<SleepSegment> segments; // this source, this session, all stages incl. awake/inBed
    final Duration asleep, deep, light, rem, awake;
    final Duration? inBed;          // from inBed segments of this source, else null
    bool get hasStages;             // deep + rem > 0
    Duration get span;              // end - start
  }
  List<SleepNight> buildNights(List<SleepSegment> segments); // ascending by date, max one per date
  ```

Algorithm (exact):
1. Group segments by `source`. Within a source, sort by `from`; asleep segments (`light`, `deep`, `rem`, `asleepUnspecified`) form sessions: a new session starts when the gap from the previous asleep segment's `to` exceeds 60 min. `awake` and `inBed` segments attach to the session whose [start − 60 min, end + 60 min] they overlap.
2. A session is a main-sleep candidate when its `end` local time-of-day is at or after 03:00 **or** its end is on a later local date than its start. Its `date` = local date of `end`.
3. Per source and date, keep the longest candidate by asleep time.
4. Per date, pick across sources: most `deep + rem + light` minutes; tie → most asleep minutes; tie → source name ascending.
5. `asleep` = merged (overlap-counted-once, reuse `mergedSleepMinutes` from `data/sleep_merge.dart` by moving it into `domain/sleep_nights.dart` and re-exporting from the old file until Task 15 removes it) asleep segments of the chosen session; stage totals likewise per stage.

- [ ] **Step 1: Failing tests** (synthetic, local `DateTime`s):
  - `main sleep across midnight` 23:30→06:30 one source with stages → one night dated the morning, asleep 7h.
  - `nap is ignored`: same plus 14:00-14:40 the next day → nap ends 14:40 (≥ 03:00!) but it is a separate, shorter candidate on the same date as the *next* night only if no longer session exists; assert the night for the date of the nap contains no nap when a later main sleep that ends next morning exists, and for the nap's own date the 23:30-06:30 session wins (longest). Add `a lone nap with no main sleep that day` → that date has a night with the nap only if it's the only candidate (document: a nap-only day shows the nap; the Phase 3 bug was a nap beating last night's main sleep, which rule 3 fixes).
  - `two sources same night`: watch (stages, deep+rem+light 6h30) and ring (stages 6h) overlapping → night uses watch only; stage totals equal watch's.
  - `asleepUnspecified only` (Android session without stages) → `hasStages` false, asleep set.
  - `gap of 75 min splits sessions`; `awake segments count in awake, not asleep`.
  - `DST fall-back night` (session including a repeated hour, constructed with UTC instants): asleep equals real elapsed minutes.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS (also `test/health/sleep_merge_test.dart`).
- [ ] **Step 5: Commit** `feat(health): sleep nights with main-sleep and single-source rules`.

### Task 8: Sleep score

**Files:**
- Create: `lib/features/health/domain/sleep_score.dart`
- Test: `test/health/domain/sleep_score_test.dart`

**Interfaces:**
- Consumes: `SleepNight`.
- Produces:
  ```dart
  enum SleepContributor { duration, deep, rem, efficiency, timing, sleepHeartRate }
  enum ContributorRating { good, fair, poor }
  class ContributorResult { final double score; final ContributorRating rating; } // score 0..1
  class SleepScore { final int value; final Map<SleepContributor, ContributorResult> contributors; }
  SleepScore? scoreSleep(SleepNight night, {List<SleepNight> priorNights = const [], double? sleepAvgHr, double? restingHr});
  ```

Weights: duration 35, deep 15, rem 15, efficiency 15, timing 10, sleepHeartRate 10. Curves (`m` asleep minutes, shares are of asleep):
- duration: `clamp((m - 240) / (450 - 240), 0, 1)`
- deep share `s`: 1 if 0.15 ≤ s ≤ 0.25; `s / 0.15` below; `max(0, 1 - (s - 0.25) / 0.15)` above.
- rem share: 1 if 0.20 ≤ s ≤ 0.25; `s / 0.20` below; `max(0, 1 - (s - 0.25) / 0.15)` above.
- efficiency `e = asleep / (inBed ?? span)`: `clamp((e - 0.70) / 0.20, 0, 1)`.
- timing: `d` = minutes between `night.start` and the median start of up to 14 most recent `priorNights` (times compared as minutes after 12:00 so midnight wraps); 1 if d ≤ 30, 0 if d ≥ 120, linear between. Omitted when fewer than 5 prior nights.
- sleepHeartRate: `delta = sleepAvgHr - restingHr`; 1 if ≤ 0, 0 if ≥ 10, linear. Omitted when either is null.
- Value = `round(100 × Σ wᵢsᵢ / Σ wᵢ)` over present contributors. Rating: ≥ 0.8 good, ≥ 0.5 fair, else poor.
- Returns `null` when `!night.hasStages`.

- [ ] **Step 1: Failing tests**: `perfect night scores 100` (7h30 asleep, deep 20%, rem 22%, efficiency 0.95, on-time vs 7 prior nights, sleep HR 50 vs RHR 54); `no stages returns null`; `6h12m night from the mockup` (deep 1h03, core 3h14, rem 1h33, awake 31m, inBed 6h43, bedtime 48 min late, sleep HR 51, RHR 54) → value between 70 and 80 and `duration.rating == fair`; `missing HR and <5 prior nights rescales` (only 4 contributors; perfect inputs still 100); `midnight wrap` (prior starts 23:50, tonight 00:10 → timing 1.0).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(health): on-device sleep score`.

### Task 9: Reader interface for range reads

**Files:**
- Modify: `lib/features/health/data/health_reader.dart`, `test/support/fake_health_reader.dart`
- Test: `test/health/fake_health_reader_test.dart` (small: the fake records calls)

**Interfaces:**
- Produces (added to `HealthReader`; existing members unchanged until Task 15):
  ```dart
  enum HealthSeriesType { heartRate, restingHeartRate, hrv, respiratoryRate, bloodOxygen, vo2Max,
    walkingHeartRate, sleepingWristTemperature, skinTemperature, weight, bodyFat, leanMass }
  enum HealthTotalType { steps, activeEnergy }
  sealed class SeriesResult<T> { const SeriesResult(); }
  final class SeriesData<T> extends SeriesResult<T> { const SeriesData(this.data); final T data; }
  final class SeriesNotAllowed<T> extends SeriesResult<T> { const SeriesNotAllowed(); }
  final class SeriesNeedsAccess<T> extends SeriesResult<T> { const SeriesNeedsAccess(); } // type never requested
  final class SeriesFailed<T> extends SeriesResult<T> { const SeriesFailed(); }
  final class SeriesUnsupported<T> extends SeriesResult<T> { const SeriesUnsupported(); }

  // on HealthReader:
  Future<SeriesResult<List<SleepSegment>>> readSleep(DateTime from, DateTime to);
  Future<SeriesResult<List<HealthSample>>> readSeries(HealthSeriesType type, DateTime from, DateTime to);
  /// Hourly buckets from [from] (a local midnight) to [to].
  Future<SeriesResult<List<HealthSample>>> readHourlyTotals(HealthTotalType type, DateTime from, DateTime to);
  Future<bool> needsMoreAccess();          // some current types never requested / not granted
  Future<void> requestMoreAccess();        // requests the full current type list (+ history where available)
  Future<bool> hasHistoryAccess();         // Android: isHealthDataHistoryAuthorized; iOS: true
  ```
  All never throw. `FakeHealthReader` gains settable maps `sleep`, `series[type]`, `totals[type]`, `needsMore`, `history`, a `throwOnSeries` set, and records `seriesCalls` as `(type, from, to)`.
- [ ] **Step 1: Failing test**: fake returns configured `SeriesData` and records the call; unconfigured type returns `SeriesData([])`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `flutter test test/health/` → PASS (existing tests unaffected).
- [ ] **Step 5: Commit** `feat(health): range-read interface`.

### Task 10: Platform reader range reads and permissions; native config

**Files:**
- Modify: `lib/features/health/data/platform_health_reader.dart`, `test/health/platform_health_reader_test.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `tool/test_ios_privacy_strings.py`

**Interfaces:**
- Consumes: Task 9 interface.

Type mapping: heartRate `HEART_RATE`; restingHeartRate `RESTING_HEART_RATE`; hrv iOS `HEART_RATE_VARIABILITY_SDNN` / Android `HEART_RATE_VARIABILITY_RMSSD`; respiratoryRate `RESPIRATORY_RATE`; bloodOxygen `BLOOD_OXYGEN`; vo2Max `VO2_MAX`; walkingHeartRate `WALKING_HEART_RATE` (iOS only, else `SeriesUnsupported`); sleepingWristTemperature `SLEEP_WRIST_TEMPERATURE` (iOS only); skinTemperature `SKIN_TEMPERATURE` (Android only, and only when `isSkinTemperatureAvailable()`); weight `WEIGHT`; bodyFat `BODY_FAT_PERCENTAGE` (normalise to 0-100: check the README/units table for each platform's scale and pin it with a test); leanMass `LEAN_BODY_MASS`. Sleep: `SLEEP_ASLEEP`→asleepUnspecified, `SLEEP_LIGHT`→light, `SLEEP_DEEP`→deep, `SLEEP_REM`→rem, `SLEEP_AWAKE`→awake, `SLEEP_IN_BED` (iOS)→inBed, Android `SLEEP_SESSION`→inBed. Totals: steps `STEPS`, activeEnergy `ACTIVE_ENERGY_BURNED` via `getHealthIntervalDataFromTypes(interval: 3600)`.

Requested read types (`_requestTypes`): the Phase 3 four plus `SLEEP_AWAKE`, `SLEEP_DEEP`, `SLEEP_REM`, `SLEEP_LIGHT`, (iOS) `SLEEP_IN_BED`, (Android) `SLEEP_SESSION`, `HEART_RATE`, the platform HRV type, `RESPIRATORY_RATE`, `BLOOD_OXYGEN`, `VO2_MAX`, `ACTIVE_ENERGY_BURNED`, `BODY_FAT_PERCENTAGE`, `LEAN_BODY_MASS`, (iOS) `WALKING_HEART_RATE`, `SLEEP_WRIST_TEMPERATURE`, (Android, when available) `SKIN_TEMPERATURE`. `requestAccess` and `requestMoreAccess` request the same list; on Android, if `isHealthDataHistoryAvailable()` and not yet authorized, follow with `requestHealthDataHistoryAuthorization()`.

`needsMoreAccess`: iOS → `getRequestStatusForAuthorization(types) == HealthAuthorizationRequestStatus.shouldRequest`; Android → `hasPermissions(types) != true` for the full list. Per-type `readSeries` on Android returns `SeriesNotAllowed` when `hasPermissions([type]) != true`; on iOS a type the app never requested surfaces as `HealthErrorCode.permissionDenied` → `SeriesNeedsAccess`.

Errors: same mapping as `read()` (`permissionDenied` → Android `SeriesNotAllowed` / iOS `SeriesNeedsAccess`, `notSupported` → `SeriesUnsupported`, else `SeriesFailed`). Never log values.

- [ ] **Step 1: Failing tests** with the existing `_FakeHealth` (extend it with `getHealthIntervalDataFromTypes`, `getRequestStatusForAuthorization`, `isHealthDataHistoryAvailable`, `isHealthDataHistoryAuthorized`, `requestHealthDataHistoryAuthorization`, `isSkinTemperatureAvailable`):
  - `readSeries hrv uses SDNN on iOS and RMSSD on Android` (assert requested types).
  - `walking heart rate is unsupported on Android`.
  - `readSleep maps stage types and Android sessions to inBed`.
  - `readHourlyTotals asks for 3600 s intervals over the given range`.
  - `Android denied series returns SeriesNotAllowed; iOS never-requested returns SeriesNeedsAccess`.
  - `requestAccess on Android with history available requests history after the type sheet`; `without history available does not`.
  - `needsMoreAccess is true for a Phase 3 grant` (iOS status `shouldRequest`; Android `hasPermissions` false for the full list).
  - `body fat is returned on a 0-100 scale on both platforms`.
- [ ] **Step 2: Run** `flutter test test/health/platform_health_reader_test.dart` → FAIL.
- [ ] **Step 3: Implement.** Manifest: add `READ_HEART_RATE`, `READ_HEART_RATE_VARIABILITY`, `READ_RESPIRATORY_RATE`, `READ_OXYGEN_SATURATION`, `READ_VO2_MAX`, `READ_ACTIVE_CALORIES_BURNED`, `READ_BODY_FAT`, `READ_LEAN_BODY_MASS`, `READ_SKIN_TEMPERATURE`, `READ_HEALTH_DATA_HISTORY` (check each name against the package's Android setup table). Info.plist `NSHealthShareUsageDescription`: "BeyondRep reads your sleep, heart, activity and body measurements to show your daily summary and trends. This data stays on your phone." Python test: assert the share string mentions `trends`.
- [ ] **Step 4: Run** the Dart test file → PASS; `python3 -m unittest tool.test_ios_privacy_strings` from repo root → PASS.
- [ ] **Step 5: Commit** `feat(health): platform range reads and expanded read permissions`.

### Task 11: Repository exposes connectedAt

**Files:**
- Modify: `lib/features/health/data/health_connection_repository.dart`, `test/health/health_connection_repository_test.dart`

**Interfaces:**
- Produces: `DateTime? connectedAt(String ownerAccountId)` on `HealthConnectionRepository` (null when not connected). Used as the approximate grant time for Android's readable window.
- [ ] **Step 1: Failing test**: connect at `DateTime(2026, 11, 20, 9)` → `connectedAt` equals it; other owner → null; after disconnect → null.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (read `connectedAtMs`). **Step 4:** PASS. **Step 5: Commit** `feat(health): expose connectedAt`.

### Task 12: Overview model and provider

**Files:**
- Create: `lib/features/health/application/health_overview.dart`
- Test: `test/health/health_overview_test.dart`

**Interfaces:**
- Consumes: Tasks 6-11; `healthSummaryProvider` (connection state), `healthOwnerIdProvider`, `healthClockProvider`, `healthConnectionRepositoryProvider`.
- Produces:
  ```dart
  enum MetricGap { noData, notAllowed, needsAccess, failed, unsupported }
  sealed class Section<T> {}  final class SectionData<T> extends Section<T> { final T value; }  final class SectionGap<T> extends Section<T> { final MetricGap gap; }
  class SleepOverview { final SleepNight lastNight; final SleepScore? score; final double? sleepAvgHr;
    final List<SleepNight> nights; /* up to 31, ascending */ final TrendResult? vsWeek; /* asleep vs mean of 7 prior nights, ≥3 */ }
  class HeartOverview { final DayValue? restingHr; final List<DayValue> restingHrDaily;
    final DayValue? hrv; final List<DayValue> hrvDaily; final DayValue? vo2Max;
    final TrendResult? restingHrVsMonth; final TrendResult? hrvVsNormal; final bool hrvIsSdnn; }
  class ActivityOverview { final double? stepsToday; final List<DayValue> stepsDaily; final double? activeEnergyToday;
    final List<DayValue> activeEnergyDaily; final double? stepsWeekAverage; }
  class BodyOverview { final DayValue? weight; final List<DayValue> weightDaily; final DayValue? bodyFat; final TrendResult? weightVsMonth; }
  class HealthOverview { final DateTime readAt; final HealthPlatformKind platform; final DateTime? readableFrom; final bool needsMoreAccess;
    final Section<SleepOverview> sleep; final Section<HeartOverview> heart; final Section<ActivityOverview> activity; final Section<BodyOverview> body; }
  final healthOverviewProvider = AsyncNotifierProvider<HealthOverviewController, HealthOverview?>(...); // null when not connected
  class HealthOverviewController { Future<void> refresh(); Future<void> refreshIfStale(); Future<void> requestMoreAccess(); }
  ```

Reads (in parallel, each failing independently): sleep segments from local 18:00 on `today − 31` to now; heart rate only inside last night's `[start, end]` (after sleep resolves); RHR, HRV, weight, body fat for 30 days; VO2 max for 90 days (latest); steps and active energy hourly totals from local midnight `today − 29` to now. Daily reductions: RHR latest, HRV = mean of samples inside each night's window, else that day's mean; weight/body fat latest; VO2 latest. `readableFrom` = Android without history access → `connectedAt − 30 days`; otherwise null. Gap mapping: `SeriesNotAllowed`→notAllowed, `SeriesNeedsAccess`→needsAccess, `SeriesFailed`→failed, `SeriesUnsupported`→unsupported, empty→noData. Heart section is data if either RHR or HRV has data. Steps "today" on iOS: 0 → noData (as Phase 3).

Lifetime: provider watches `healthOwnerIdProvider` and `healthSummaryProvider`; returns null when not connected; keeps the last overview while the app runs (no autoDispose); `refreshIfStale` re-reads only when `readAt` is older than 5 minutes (wired to app resume in Task 13). A result whose owner differs from the current owner when it resolves is discarded (`ref.mounted` / owner check).

- [ ] **Step 1: Failing tests** (fake reader, fixed clock 2026-11-24 07:42 local):
  - `builds sleep, heart, activity and body from synthetic series` (assert lastNight asleep, score not null, restingHr 54, stepsWeekAverage).
  - `vsWeek needs at least 3 prior nights` → null with 2.
  - `phone-only person`: sleep and heart `SectionGap(noData)`, activity data, body data.
  - `Phase 3 account`: reader `needsMore = true` and HRV `SeriesNeedsAccess` → `needsMoreAccess` true, heart still data from RHR.
  - `Android without history, connected 10 days ago` → `readableFrom` = connectedAt − 30 d.
  - `heart rate is read only inside last night's window` (assert the fake's recorded `(heartRate, from, to)` equals night start/end).
  - `account switch mid-read discards the result` (gate the fake's sleep read with a `Completer`, change owner, complete → state is not A's overview).
  - `refreshIfStale does not re-read within 5 minutes` (advance clock 4 min → no new calls; 6 min → new calls).
  - `disconnect clears the overview` (summary becomes not connected → provider value null).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `flutter test test/health/` → PASS.
- [ ] **Step 5: Commit** `feat(health): in-memory health overview`.

### Task 13: Overview cards and Health page

**Files:**
- Create: `lib/features/health/widgets/sleep_card.dart`, `heart_card.dart`, `activity_card.dart`, `body_card.dart`, `metric_unavailable.dart`
- Modify: `lib/features/health/health_page.dart`, `lib/features/health/health_format.dart`, `test/health/health_page_test.dart`, `test/health/health_format_test.dart`, `lib/app/beyondrep_app.dart` (resume hook calls `refreshIfStale`; find the existing resume refresh and extend it)
- Test: `test/health/health_cards_test.dart`

**Interfaces:**
- Consumes: `healthOverviewProvider`; kit charts.
- Produces: `SleepCard({required Section<SleepOverview> section, VoidCallback? onTap, VoidCallback? onAllowMore})` and equivalents `HeartCard`, `ActivityCard`, `BodyCard`; `MetricUnavailable({required MetricGap gap, required String metricName, required HealthPlatformKind platform, VoidCallback? onAction})`. Formatters in `health_format.dart`: `formatDuration(Duration)` (`6h 12m`, `45m`), `formatTrend(TrendMetric, TrendResult)` (e.g. `▼ 36m vs 7-day avg` text without arrow; the label adds it), `nsTrendOf(TrendResult)` mapping domain → kit enums.

Layout and copy follow `Main.dc.html` and `NoWatch.dc.html` (mockups dir), minus the Readiness hero and the "From your training" line (stage 2/3). Date line: `Tue 24 Nov · Apple Health · updated 7:42 AM`. Gap copy:
- Sleep noData: "No sleep recorded. A watch, ring or sleep app that writes to {Apple Health|Health Connect} fills this in."
- Sleep without stages: value = asleep, plus "Stages need a watch or ring that records them."
- Heart noData (iOS): "iPhone alone doesn't measure heart rate. Shown when a wearable provides it." (Android: "Shown when a watch or ring provides it.")
- needsAccess: "Allow more data" action → `requestMoreAccess()`. notAllowed: "Not allowed · Manage" (existing behaviour). failed: "Couldn't read · Try again". unsupported: "Not available on this device".
Tablet (≥ 560 px): Sleep and Heart side by side, Activity and Body side by side. Keep Disconnect footer and iOS hint.

- [ ] **Step 1: Failing tests**:
  - `connected overview shows sleep score, stages and trend` (find `74`, `6h 12m`, `Deep`, `REM`, `Sleep HR`, `▼ 36m vs 7-day avg`).
  - `phone-only shows explanations not zeros` (no `0 bpm`, finds the sleep and heart copy above).
  - `needsAccess shows Allow more data and calls requestMoreAccess once`.
  - `tapping Sleep navigates to /health/sleep` (use the app router test harness used by existing page tests).
  - `tablet width puts Sleep and Heart side by side` (two cards share a y offset at 800 px width).
  - `text scale 2.0 and dark/light render without overflow`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (routes for `/health/sleep|heart|activity|body` may point at placeholder `Scaffold`s until Task 14/15; register them in `beyondrep_app.dart` now). **Step 4: Run** `flutter test test/health/ test/design_kit_guard_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat(health): richer overview cards`.

### Task 14: Sleep detail screen

**Files:**
- Create: `lib/features/health/application/health_details.dart`, `lib/features/health/detail/sleep_detail_page.dart`
- Modify: `lib/app/beyondrep_app.dart` (route `/health/sleep`)
- Test: `test/health/sleep_detail_test.dart`

**Interfaces:**
- Consumes: `healthOverviewProvider`, reader.
- Produces:
  ```dart
  enum SleepRange { lastNight, week, month }
  class SleepNightExtras { final List<HealthSample> heartRate; final double? respiratoryRate; final double? bloodOxygen; final double? wristTempDeviation; }
  final sleepNightExtrasProvider = FutureProvider<SleepNightExtras?>(...);   // reads only last night's window
  final sleepRangeHrProvider = FutureProvider.family<Map<DateTime, double>, SleepRange>(...); // avg HR per night date, one HEART_RATE read over the range, filtered to night windows
  ```
  Wrist/skin temperature deviation = last night minus mean of prior nights' values when ≥ 7 prior nights exist (detail reads 30 nights of that type), else null (show absolute value instead).

Screen follows `Sleep.dc.html`: `AppBar` with `NsBackButton`, `NsChip` row (Last night / 7 days / 30 days). Last night: `NsScoreRing`, asleep, "In bed 6h 43m · 92% efficient", time range + source; `NsStageTimeline`; per-stage tiles with share and reference range copy ("normal 15–25%" deep, "normal 20–25%" REM); sleep HR `NsLineChart` with "Avg 51 · lowest 46 bpm at 3:10 AM"; "What made the score" rows from `SleepScore.contributors` (label + rating word; duration poor/fair reads "Short · 6h 12m of ~7h 30m"; timing reads "48 min later than usual"); breathing, blood oxygen, temperature tiles only when present. Range tabs: `NsBarChart` stacked by stage (asleep-only nights as one segment), reference 7h30; average + `NsTrendLabel` vs previous period only when `previousAverage != null`; averages of score, deep, REM, sleep HR; "Usual bedtime 11:31 PM ± 34 min" (median start ± median absolute deviation over the range, ≥ 5 nights). No observation sentence in stage 1 (insights are stage 3).

- [ ] **Step 1: Failing tests**: last-night view shows timeline semantics and contributors; `30 days on Android without history hides the comparison`; `nights without stages draw single-segment bars`; `extras absent hides breathing/oxygen/temperature tiles`; `sleep HR is read once per night window` (one heartRate call per night on the 7- and 30-day tabs, at most 5 in flight).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(health): sleep detail screen`.

### Task 15: Heart, Activity and Body detail screens; Today row; remove the old read path

**Files:**
- Create: `lib/features/health/detail/heart_detail_page.dart`, `activity_detail_page.dart`, `body_detail_page.dart`
- Modify: `lib/features/health/application/health_details.dart` (`walkingHrProvider`: iOS 30-day walking HR, else unsupported), `lib/features/health/widgets/today_health_row.dart`, `lib/app/beyondrep_app.dart`, `lib/features/health/application/health_summary_controller.dart`, `lib/features/health/data/health_reader.dart`, `lib/features/health/data/platform_health_reader.dart`, `test/support/fake_health_reader.dart`, affected tests
- Delete: `lib/features/health/widgets/health_metric_card.dart` and `data/sleep_merge.dart` once unused (move their tests' still-relevant cases to the domain tests)
- Test: `test/health/detail_pages_test.dart`, `test/today/...` (existing Today tests updated)

Heart (per `Heart.dc.html`): `NsChip` 7/30 days; resting HR `NsLineChart` with band = baseline mean ± 1 SD over the readable 30 days (label "your normal 53–57"), "Lower is better"; HRV `NsLineChart(dots: true, rollingAverage: 7-day)` with band, "Higher is better", SDNN/RMSSD note; VO2 max tile with change since 30+ days earlier when available; walking HR tile on iOS. Activity: steps bars (today highlighted), 7/30 averages, active kcal bars, best day. Body: weight line, "average weekly change" = least-squares slope × 7 over days with data (≥ 4 points), body fat and lean mass when present; neutral tone.

Today row: sleep, steps, resting HR in compact form from `healthOverviewProvider` (readiness replaces the first slot in stage 2). Then remove `HealthReader.read`, `HealthMetric`, `HealthMeasured`… only if nothing else uses them; `HealthSummaryController` keeps connection state only (`HealthConnected` loses `readings`).

- [ ] **Step 1: Failing tests**: heart band label and "Lower is better"; HRV note says `SDNN` on iOS and `RMSSD` on Android; body weekly change with 3 points shows no rate; activity highlights today; Today row renders from the overview (no `read()` calls recorded).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**, then delete the dead code and fix compile errors. **Step 4: Run** full `flutter test`, `flutter analyze`, format check → PASS.
- [ ] **Step 5: Commit** `feat(health): heart, activity and body details; Today row from overview`.

### Task 16: Finish stage 1

- [ ] **Step 1:** Run the full gate from `apps/mobile/`: format check, `flutter analyze`, `flutter test`; from repo root: `python3 -m unittest discover -s tool -p 'test_*.py'`. All pass.
- [ ] **Step 2:** `flutter build apk --debug --no-pub` (Android manifest sanity). Record native iOS build and all device QA as **not run**.
- [ ] **Step 3:** Update `docs/superpowers/specs/2026-11-24-health-insights-design.md` status line to "stage 1 implemented on branch, not device-verified"; commit `docs: mark health insights stage 1 implemented`.
