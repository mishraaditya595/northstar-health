# Health polish (stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the Today health cards (A1), move readiness into the Train start card (B3) and add plain-language explanation sheets plus a glossary for every health metric (C1).

**Architecture:** The kit gains an info button, a range bar, an icon/info slot on `StatTile` and band colours. Explanations are `const` data in `features/health/domain/metric_explanations.dart`, shown by one sheet (`showMetricInfo`) and one glossary page (`/health/terms`). Today and Train re-render existing overview state; no new health reads, nothing stored.

**Tech Stack:** Flutter 3.47.7, Riverpod, go_router, existing design kit (`lib/core/design/`). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-26-health-polish-and-outside-workouts-design.md` (Stage 1 sections). Mockups: https://claude.ai/artifact/1koEPBL8LPodG9CgjhLGhw (A1, B3, C1).

## Global Constraints

- Run everything from `apps/mobile/`. Before each commit: `dart format --output=none --set-exit-if-changed lib test` and `flutter analyze` clean; the task's tests pass.
- No new health reads, no new permissions, no readiness formula change. Nothing health-derived is written to ObjectBox, Supabase, logs or export.
- `package:health` is imported only by `platform_health_reader.dart` (`test/health/health_import_guard_test.dart`).
- Features never call raw `showModalBottomSheet`, `showDialog`, `SnackBar`, `ChoiceChip`, etc. (`test/design_kit_guard_test.dart`). New visual pieces go in `lib/core/design/` first, theme-aware in light and dark.
- Missing values show `—` or are left out, never `0`. Readiness shows a number only when `ReadinessReady` for today.
- Band colours: Good = `colorScheme.primary` (lime dark / forest light), Fair = amber, Low = red (`#FF8587` dark / `#9F3041` light, soft `#47262A` dark / `#FBE4E6` light).
- Every ⓘ: tap target ≥ 48 dp, semantics label `About <metric name>` (metric name as in the explanation's `title`).
- Text scale to 2.0 and 320 dp width must not overflow (existing Train header overflow is a known pre-existing bug; do not make it worse).
- Copy: plain words, no diagnosis, never compares the user with other people except the published deep-sleep share "15 to 25%". Copy in Task 2 is fixed; Adi reviews it in the PR.
- Commit messages end with the session's attribution lines.

## Review Focus

1. **Readiness not ready or health disconnected on Train** — the start card must look exactly like today's card (no empty strip, no number), except the one muted "needs N more days" line. Tested in Task 6.
2. **Program day is rest / unavailable / already started a workout** — the start card falls back to Quick workout; an in-progress workout must block a second start with the existing failure message. Tested in Task 6.
3. **Large text (2.0) and 320 dp** on Today grid and Train strip — one-column grid, no overflow. Tested in Tasks 5 and 6.
4. **Platform naming** — Health Connect users must see "Light", Apple Health users "Core", in sheet and glossary. Tested in Task 2 and 3.
5. **Usual range with < 14 days or partial-day metrics** — no "Yours" block / "Your daily average" without a today marker for steps and active calories. Tested in Task 2 and 3.

---

### Task 1: Kit additions (band colours, info button, range bar, StatTile slots)

**Files:**
- Modify: `lib/core/design/beyondrep_theme.dart` (palette: `redDark`, `redLight`, `redSoftDark`, `redSoftLight`)
- Create: `lib/core/design/info_button.dart`
- Create: `lib/core/design/charts/range_bar.dart`
- Modify: `lib/core/design/stats.dart` (`StatTile` gains `icon`, `iconColor`, `onInfo`, `infoLabel`, `minHeight`)
- Modify: `docs/DESIGN_SYSTEM.md` (catalog the three additions)
- Test: `test/core/design/info_button_test.dart`, `test/core/design/range_bar_test.dart`, `test/stats_widgets_test.dart`

**Interfaces:**
- Produces:
  - `class NsInfoButton extends StatelessWidget { const NsInfoButton({required String label, required VoidCallback onPressed}); }` — 18 px outlined "i" glyph in muted colour inside a 48×48 tap target; `Semantics(button: true, label: label)`.
  - `class NsRangeBar extends StatelessWidget { const NsRangeBar({required double low, required double high, double? value, required double min, required double max}); }` — track (soft), usual band (forest soft / primary at .35), optional 4 px marker at `value`; `excludeSemantics` (the caption carries meaning).
  - `StatTile({..., IconData? icon, Color? iconColor, VoidCallback? onInfo, String? infoLabel, double? minHeight})` — icon left of the label, `NsInfoButton` right of the label when `onInfo != null` (`infoLabel` required then, assert), `minHeight` applied via `ConstrainedBox`.

- [ ] **Step 1: Write failing tests**
  - `NsInfoButton`: `tester.getSize(find.byType(NsInfoButton))` is ≥ 48×48; `find.bySemanticsLabel('About Resting heart rate')` taps call `onPressed`.
  - `NsRangeBar`: with `value: null` no marker is painted (expose marker as a `Key('ns-range-marker')` child when present); with `value` outside `[min,max]` the marker clamps (no exception).
  - `StatTile`: with `onInfo` and `infoLabel: 'About Steps'` finds that semantics label and a tap calls `onInfo` without calling `onTap`; with `icon` finds the `Icon`; existing StatTile tests still pass.
- [ ] **Step 2: Run** `flutter test test/core/design test/stats_widgets_test.dart` — Expected: FAIL (types missing).
- [ ] **Step 3: Implement** the three widgets and palette constants above.
- [ ] **Step 4: Run** the same command — Expected: PASS. Run `flutter test test/design_kit_guard_test.dart` — PASS.
- [ ] **Step 5: Commit** `feat(design): info button, range bar, StatTile icon and info slots`

### Task 2: Metric explanations and usual range (domain)

**Files:**
- Create: `lib/features/health/domain/metric_explanations.dart`
- Test: `test/health/domain/metric_explanations_test.dart`

**Interfaces:**
- Consumes: `baselineOf`, `Baseline`, `DayValue` (`domain/readiness.dart`, `domain/daily_series.dart`), `HealthPlatformKind`.
- Produces:
  - `enum MetricKey { readiness, sleepScore, timeAsleep, deepSleep, lightSleep, remSleep, awake, sleepHeartRate, respiratoryRate, bloodOxygen, wristTemperature, restingHeartRate, hrv, vo2Max, walkingHeartRate, steps, activeCalories, weight, bodyFat, muscleRecovery }`
  - `class MetricExplanation { final String title; final String summary; final String what; final String tells; final String inBeyondRep; }`
  - `MetricExplanation explanationFor(MetricKey key, HealthPlatformKind platform)` — `lightSleep` title is `Core sleep` on Apple Health and `Light sleep` on Health Connect; its `what` text below already names both.
  - `class MetricUsual { final double low; final double high; final double? today; final bool dailyAverage; }` (`dailyAverage` true → `low == high` = the average, no today marker).
  - `MetricUsual? usualFrom(List<DayValue> daily, DateTime today, {double? todayValue})` — null when `baselineOf(daily, today, sdFloor: (_) => 0)` is null (fewer than 14 of the 30 days before today); else `low = mean - sd`, `high = mean + sd`, `today = todayValue`.
  - `MetricUsual? dailyAverageFrom(List<DayValue> daily, DateTime today)` — mean of the 30 days before today, null under 14 days; `dailyAverage: true`.

Copy (fixed; `summary` is the glossary line):

| key | title | summary | what | tells | inBeyondRep |
|---|---|---|---|---|---|
| readiness | Readiness | How ready your body is to train today | A 0 to 100 score for today, worked out on your phone from your HRV, resting heart rate, last night's sleep and your sleep over the past week. | 70 and up is Good: train as planned. 50 to 69 is Fair: train, but watch your effort. Under 50 is Low: consider an easier session. It compares you only with your own last 30 days. | Shown on Today, Health and Train. It never changes your plans. It is guidance, not medical advice. |
| sleepScore | Sleep score | Our 0 to 100 view of last night | A score for last night from how long you slept, your deep and REM sleep, time awake in bed, how regular your bedtime was and your sleeping heart rate. | Higher means more restful sleep. One poor night is normal; look at the trend over a week. | Feeds readiness. Without a sleep score, readiness uses your time asleep instead. |
| timeAsleep | Time asleep | Hours you were actually asleep | The time you were asleep last night, not counting time awake in bed. | Most adults need around 7 to 9 hours. Short nights add up and lower readiness over the week. | Feeds readiness, both last night and your average over the past week. |
| deepSleep | Deep sleep | Repair and recovery | The slowest, most restful stage of sleep. Your body does much of its physical repair here. | Most adults spend about 15 to 25% of the night in deep sleep. It tends to drop after late meals, alcohol or a late hard workout. | Part of your sleep score. |
| lightSleep | Core sleep / Light sleep | Light sleep, most of the night | The lighter stage you spend most of the night in, moving between deep and REM sleep. Apple Health calls it Core sleep and Health Connect calls it Light sleep; they are the same stage. | Usually about half the night or more. That is normal and useful sleep. | Counts towards time asleep. |
| remSleep | REM sleep | Dreaming, memory and learning | The stage when most dreaming happens. It helps with memory and learning, and comes in longer stretches towards morning. | Cutting a night short usually cuts REM sleep the most. | Part of your sleep score. |
| awake | Awake | Short wake-ups in the night | Time awake after you first fell asleep. | A few short wake-ups are normal and you usually won't remember them. | Lowers your sleep score when there is a lot of it. |
| sleepHeartRate | Sleeping heart rate | Your average heart rate while asleep | Your average heart rate during last night's sleep. | It is usually lower than your daytime resting heart rate. A higher than usual night can follow alcohol, a late meal, illness or hard training. | Part of your sleep score. |
| respiratoryRate | Respiratory rate | Breaths per minute while asleep | How many breaths you take per minute while asleep. | It stays steady from night to night for most people, so a change from your usual is what matters. | Shown on Sleep details only. |
| bloodOxygen | Blood oxygen | Oxygen in your blood | The share of oxygen your blood is carrying, measured by your watch. | Readings are usually in the mid to high 90s. Watch readings can be off if the fit is loose. This is not a medical measurement. | Shown on Sleep details only. |
| wristTemperature | Wrist temperature | Change in skin temperature while asleep | How your wrist temperature during sleep differs from your usual. | Small changes are normal. Changes can follow illness, alcohol, a warm room or your cycle. | Shown on Sleep details only. |
| restingHeartRate | Resting heart rate | Beats a minute at full rest | How many times your heart beats in a minute when you're fully at rest. Your watch measures it while you're still or asleep. | Lower than your usual often means you're well recovered. Five or more beats above your usual can come from poor sleep, stress, alcohol, illness or a hard training block. | One of the inputs to readiness, compared only with your own last 30 days. |
| hrv | Heart rate variability (HRV) | Small changes in time between heartbeats | The tiny differences in time from one heartbeat to the next. Apple and Android measure it in different ways, so the numbers can't be compared between phones or with other people. | Higher than your usual generally means you're rested; lower can mean stress, poor sleep, illness or hard training. Only your own trend matters. | The biggest input to readiness, compared only with your own last 30 days. |
| vo2Max | VO₂ max | Your aerobic fitness | An estimate of how much oxygen your body can use during hard exercise, made by your watch from walks and runs. | Higher means fitter. It changes slowly over weeks, so look at the trend. | Shown on Heart details. Not part of readiness. |
| walkingHeartRate | Walking heart rate | Average heart rate while walking | Your average heart rate during everyday walking. | Going down over weeks often means your fitness is improving. | Shown on Heart details only. |
| steps | Steps | Steps taken today | Steps counted by your phone or watch today. | Steps add up over the day, so the morning number is always low. Your daily average is a better guide than any one day. | Shown on Today and Activity. Not part of readiness. |
| activeCalories | Active calories | Energy burned by moving | Energy you burned by moving and exercising today, on top of what your body uses at rest. | Like steps, it adds up through the day. Watch estimates can be off, so compare with your own average. | Shown on Activity. Not part of readiness. |
| weight | Weight | Your latest weigh-in | Your most recent weight from a scale or entered by hand. | Day-to-day changes of a kilo or so are mostly water. Look at the trend over weeks. | Shown on Body. Not part of readiness. |
| bodyFat | Body fat | Share of your weight that is fat | Your most recent body fat percentage from a smart scale or other device. | Home scales vary a lot between readings; the trend over weeks is more useful than one number. | Shown on Body. Not part of readiness. |
| muscleRecovery | Muscle recovery | Which muscles are still recovering | How recently each muscle group was worked, from the sets you logged in BeyondRep. Small muscles recover in about 48 hours and larger ones in about 72. | Shaded muscles are still recovering. Training them hard again soon is fine now and then, but recovered muscles are the better fit today. | Used for the "Better fit today" suggestion on Train. Uses only your logged workouts. |

- [ ] **Step 1: Write failing tests** in `metric_explanations_test.dart`:
  - `every MetricKey has non-empty title, summary, what, tells, inBeyondRep` for both platforms.
  - `lightSleep title is Core sleep on Apple Health and Light sleep on Health Connect`.
  - `no copy says diagnos, disease, normal range or should see a doctor` (case-insensitive scan of all strings).
  - `hrv what mentions both Apple and Android`.
  - `usualFrom returns null with 13 days and a range with 14`: 14 values `[50..63]` on the 30 days before `today` → `low ≈ mean - sd`, `high ≈ mean + sd`, `today` passed through.
  - `usualFrom ignores today's own value in the baseline` (today's DayValue excluded).
  - `dailyAverageFrom gives the mean and dailyAverage true`; null under 14 days.
- [ ] **Step 2: Run** `flutter test test/health/domain/metric_explanations_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** as specified; copy verbatim from the table (for `lightSleep` use the platform title).
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): plain-language metric explanations and usual range`

### Task 3: Explanation sheet, glossary page and route

**Files:**
- Create: `lib/features/health/widgets/metric_info_sheet.dart`
- Create: `lib/features/health/detail/health_terms_page.dart`
- Modify: `lib/app/beyondrep_app.dart` (route `/health/terms` next to the other `/health/*` routes)
- Modify: `lib/features/health/health_page.dart` (header action "Health terms" → `/health/terms`, using the existing page-header action pattern)
- Test: `test/health/metric_info_sheet_test.dart`, `test/health/health_terms_page_test.dart`

**Interfaces:**
- Consumes: Task 1 `NsRangeBar`, `NsInfoButton`; Task 2 `MetricKey`, `explanationFor`, `MetricUsual`.
- Produces:
  - `Future<void> showMetricInfo(BuildContext context, MetricKey key, {required HealthPlatformKind platform, MetricUsual? usual, String? unit, bool showUsualPlaceholder = false, bool showTermsLink = true})` — `showNsSheet(heightFactor: 0.7)`, scrollable. Sections in order: title (header semantics), `what`; **Yours** block when `usual != null`: `NsRangeBar` + caption `Your usual 55 to 61 bpm` / `Today 58` (or `Your daily average 6,084` when `dailyAverage`), numbers formatted with the existing `health_format.dart` helpers for that metric; when `usual == null && showUsualPlaceholder`: `We'll show your usual range after 14 days of data.`; headings `What it tells you` → `tells`, `In BeyondRep` → `inBeyondRep`; text button `All health terms` → `context.push('/health/terms')` after popping the sheet (hidden when `showTermsLink` false).
  - `Widget metricInfoButton(BuildContext context, MetricKey key, {required HealthPlatformKind platform, MetricUsual? usual, String? unit, bool showUsualPlaceholder = false})` — `NsInfoButton(label: 'About ${explanationFor(key, platform).title}', onPressed: () => showMetricInfo(...))`.
  - `class HealthTermsPage extends ConsumerWidget` — title `Health terms`; list sorted by `title`, each row `NsListCard`-style (kit) with `title` and `summary`; tap → `showMetricInfo(key, platform, showTermsLink: false)`. Platform from the health summary state, default `appleHealth` on iOS / `healthConnect` on Android via `defaultTargetPlatform` when not connected.

- [ ] **Step 1: Write failing tests**
  - sheet: `shows what, tells and inBeyondRep for restingHeartRate`; `shows Your usual 55 to 61 bpm and Today 58 when usual given`; `shows the 14-day placeholder when usual null and showUsualPlaceholder`; `shows neither when usual null and no placeholder`; `steps with dailyAverage shows Your daily average and no marker (Key ns-range-marker absent)`; `All health terms opens /health/terms` (GoRouter test harness as in existing detail tests).
  - glossary: `lists every MetricKey sorted by title`; `Health Connect shows Light sleep, Apple Health shows Core sleep`; `tapping HRV opens its sheet without the All health terms link`.
  - health page: `Health terms action navigates to /health/terms`.
- [ ] **Step 2: Run** `flutter test test/health/metric_info_sheet_test.dart test/health/health_terms_page_test.dart test/health/health_page_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** same — Expected: PASS; plus `flutter test test/design_kit_guard_test.dart test/health/health_import_guard_test.dart` PASS.
- [ ] **Step 5: Commit** `feat(health): metric explanation sheet and health terms page`

### Task 4: ⓘ on Health cards and detail screens

**Files:**
- Modify: `lib/features/health/widgets/health_card_frame.dart` (`HealthCardFrame` gains `Widget? info`, rendered right of the title before any chevron)
- Modify: `lib/features/health/widgets/detail_layout.dart` (`DetailPanel` gains `Widget? info` beside `title`; `DetailRow` gains `Widget? info` after the label)
- Modify: `widgets/readiness_card.dart`, `sleep_card.dart`, `heart_card.dart`, `activity_card.dart`, `body_card.dart`, and `detail/*_detail_page.dart`
- Test: `test/health/health_cards_test.dart`, `test/health/detail_pages_test.dart`, `test/health/readiness_detail_test.dart`, `test/health/sleep_detail_test.dart`

**Interfaces:**
- Consumes: Task 3 `metricInfoButton`; Task 2 `usualFrom`, `dailyAverageFrom`.

Placement and usual source (usual only from data already in memory at that widget):

| Where | Key | usual |
|---|---|---|
| Health readiness card header | readiness | none |
| Sleep card header | sleepScore | none |
| Sleep card Deep / REM pairs | deepSleep / remSleep | none |
| Heart card resting HR / HRV / VO₂ max | restingHeartRate / hrv / vo2Max | `usualFrom(restingHrDaily, readAt, todayValue: restingHr?.value)` / same with `hrvDaily` / `usualFrom(vo2MaxDaily, …)` |
| Activity card steps / active calories | steps / activeCalories | `dailyAverageFrom(stepsDaily, readAt)` / `dailyAverageFrom(activeEnergyDaily, readAt)` |
| Body card weight / body fat | weight / bodyFat | `usualFrom(weightDaily, …)` / none |
| Readiness detail: "How readiness works" panel + each input row in "What made the score" | readiness, hrv, restingHeartRate, timeAsleep (sleep and sleep-debt rows) | none, `showUsualPlaceholder: true` for hrv and RHR |
| Sleep detail: Stages panel rows Deep/Core-or-Light/REM/Awake, Time asleep panel, Averages rows (sleep HR, respiratory rate, blood oxygen, wrist temperature) | matching keys | none |
| Heart detail: Resting heart rate, HRV panels; walking HR row | restingHeartRate, hrv, walkingHeartRate | panel's own daily series via `usualFrom` |
| Activity detail: Steps, Active calories panels | steps, activeCalories | `dailyAverageFrom` of the panel's series |
| Body detail: Weight panel; body fat row | weight, bodyFat | weight: `usualFrom` of its series |

- [ ] **Step 1: Write failing tests** — for each card and detail page in the existing test files, using the existing fakes/fixtures: `find.bySemanticsLabel('About <title>')` exists for every row of the table; one tap test per file opens the sheet (finds the explanation's `what` text); `heart card RHR sheet shows Your usual` with the fixture's ≥14 days; `activity card steps sheet shows Your daily average`.
- [ ] **Step 2: Run** `flutter test test/health` — Expected: the new tests FAIL, existing ones pass.
- [ ] **Step 3: Implement** the `info` slots and wire the table.
- [ ] **Step 4: Run** `flutter test test/health test/accessibility` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(health): explain each metric from Health cards and detail screens`

### Task 5: Today "Recent health" (A1)

**Files:**
- Create: `lib/features/health/widgets/today_health_tiles.dart` (pure tile mapping, moved out of `today_health_row.dart`)
- Create: `lib/features/health/widgets/readiness_hero.dart`
- Modify: `lib/features/health/widgets/today_health_row.dart`
- Test: `test/today/today_health_tiles_test.dart`, `test/today/today_health_row_test.dart`

**Interfaces:**
- Consumes: Task 1 `StatTile` slots, palette band colours; Task 3 `metricInfoButton`/`showMetricInfo`; `completedWorkoutHistoryProvider`; `todaysReadiness`, `readinessBandWords`, `readinessReasons`; existing not-ready copy in `readiness_card.dart` (`'Readiness starts after $days more day(s) with data.'`).
- Produces:
  - `Color readinessBandColor(ThemeData theme, ReadinessBand band)` and `Color readinessBandSoftColor(ThemeData theme, ReadinessBand band)` in `readiness_card.dart` (Good primary / forest soft, Fair amber / amber soft, Low red / red soft). `readiness_detail_page.dart`'s private `_bandColor` is replaced by `readinessBandColor` (Low turns red there too, matching the spec).
  - `TodayTile` record with `label, icon, value, unit, caption, gap, route, infoKey, usual` and functions `TodayTile sleepTile(HealthOverview o)`, `stepsTile(HealthOverview o)`, `restingHrTile(HealthOverview o)`, `TodayTile workoutsTile(List<WorkoutSessionRecord> completed, DateTime localNow)`.
  - `class ReadinessHero extends StatelessWidget { const ReadinessHero({required Readiness readiness, required String reasons, required HealthPlatformKind platform, required VoidCallback onOpen}); }` built on `NsHeroFrame` (eyebrow `READINESS · GOOD|FAIR|LOW`, `leading: NsScoreRing(size: 64, color: readinessBandColor)`, title = `readinessBandWords(band)`, subtitle = reasons, ⓘ readiness, whole hero tappable → `/health/readiness`). If `NsHeroFrame` can't host a trailing info button and tap, extend the kit frame with `Widget? trailing` and `VoidCallback? onTap` (Task-local kit change, keep existing callers unchanged).

Tile rules:
- Sleep: icon `Icons.bedtime_outlined` (sleep colour), value `formatDuration(asleep)`, caption `Ended 7:59 AM`; info `timeAsleep`.
- Steps: `Icons.directions_walk`, caption `As of 12:51 PM`; info `steps`, usual `dailyAverageFrom(stepsDaily)`.
- Resting HR: `Icons.favorite_outline`, unit `bpm`, caption `Today` or date, plus ` · N below usual` / ` · N above usual` / ` · about usual` when `usualFrom(restingHrDaily)` exists (N = rounded `today - mean`; |N| < 1 → about); info `restingHeartRate`.
- Workouts: `Icons.fitness_center`, count of completed sessions whose `completedAtUtc` is on the local day of `localNow`; value `'$n'`, unit `today`, caption `<first session name> · <minutes> min` (minutes = completed − started, rounded); `n == 0` → value `—`, caption `None yet today`; no info button, route `/progress`.
- Gaps keep today's captions and actions (`Allow more data`, `Not allowed · Manage`, `Couldn't read · Try again`, `Not available on this device`).
- Footer: `From Apple Health · <device>` when sleep and steps share one source name other than the platform name, else `From Apple Health` / `From Health Connect`. Sleep caption no longer repeats the source.
- Layout: hero (when `ReadinessReady` today) else a slim `InsightCard` with the not-ready copy only when `ReadinessNotReady(daysUntilBaseline != null)`, nothing otherwise; then a 2×2 grid (`Row`s of `Expanded` with `IntrinsicHeight`, gap 10, equal heights); one column when `MediaQuery.textScalerOf(context).scale(1) >= 1.6` or available width < 360.

- [ ] **Step 1: Write failing tests**
  - `today_health_tiles_test.dart`: `sleepTile caption is Ended 7:59 AM`; `restingHrTile says 2 below usual` (14-day fixture mean 60, today 58); `restingHrTile omits usual under 14 days`; `workoutsTile counts only today's completed sessions` (one yesterday, two today → `2`, caption first-of-today name and minutes); `workoutsTile with none is — and None yet today`; `gap tiles keep Allow more data / Not allowed · Manage / Couldn't read · Try again`; `missing steps never shows 0`.
  - `today_health_row_test.dart`: `ready readiness shows hero with READINESS · FAIR and advice`; `Low hero uses red ring colour` (find `NsScoreRing` with `color == BeyondRepPalette.redDark` in dark theme); `building baseline shows the N more days row and no number`; `not enough data shows no hero`; `grid shows Sleep, Steps, Resting HR, Workouts`; `text scale 2.0 uses one column and has no overflow` (`tester.takeException()` null); `320 dp width one column`; `About Steps opens the sheet`; `hero tap navigates to /health/readiness`; existing disconnected/loading/error tests unchanged.
- [ ] **Step 2: Run** `flutter test test/today` — Expected: new tests FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/today test/health test/accessibility` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(today): readiness hero and 2x2 health tiles`

### Task 6: Train start card with readiness strip (B3)

**Files:**
- Create: `lib/features/health/widgets/readiness_strip.dart` (replaces the `_Row`/`_LowCard` widgets; `ReadinessStartNoteShown`, `readinessStartNoteShownProvider` and `confirmReadinessBeforeStart` stay in `readiness_note.dart`, the `ReadinessNote` widget is deleted)
- Create: `lib/features/programs/presentation/start_program_day.dart`
- Modify: `lib/features/train/my_program_page.dart` (use the extracted function for today's start; missed-day start unchanged in behaviour)
- Modify: `lib/features/train/train_page.dart` (remove `ReadinessNote()`; start card per below)
- Test: `test/train/train_readiness_note_test.dart` → rename to `test/train/train_start_card_test.dart`; `test/train/readiness_start_note_test.dart` stays passing; `test/train/programs_pages_test.dart` stays passing; `test/train/train_header_text_scale_test.dart` stays passing.

**Interfaces:**
- Consumes: Task 5 `readinessBandColor`, `readinessBandSoftColor`; `activeProgramCardProvider` (`ActiveProgramCard.todayWorkout`, `.unavailable`, `.program`); `workoutActionsProvider.startProgramDay`, `dayFor`, `ProgramDayChanged`, `confirmReadinessBeforeStart`.
- Produces:
  - `class ReadinessStrip extends ConsumerStatefulWidget` — keeps `ReadinessNote`'s refresh-if-stale on show and resume. Ready: soft band background, score in band colour, text `<Good|Fair|Low> readiness. <readinessBandWords>.`, chevron → `/health/readiness`; Low adds caption `Your plans are not changed`. `ReadinessNotReady(daysUntilBaseline: n)` → muted line `Readiness starts after n more day(s) with data.`. Anything else (loading, error, disconnected, not enough data, not today) → `SizedBox.shrink()`. Semantics: one button labelled `Readiness <score>, <band words>. See why`.
  - `Future<void> startProgramDay(BuildContext context, WidgetRef ref, TrainingProgramRecord program, {DateTime? missedDate, String? missedPlanUuid, required void Function(String message) onFailed})` — the body of `_MyProgramPageState._start` minus the `_busy` handling, same messages (`"Today's workout changed. Check it and try again."`, `'This day changed. Check it and try again.'`, the existing start-failed message).

Start card rules (`train_page.dart`):
- `programToday = card != null && !card.unavailable && card.todayWorkout != null`.
- When `programToday`: tag `Program`, title = `card.todayWorkout`, subtitle `Today in <program name>`, `ReadinessStrip`, filled button `Start <todayWorkout>` → `startProgramDay(...)`, then a `TextButton` `Quick workout` → existing `_startQuick`.
- Otherwise: today's card unchanged (`Strength`, `Build the work.`, copy, filled `Quick workout`) with `ReadinessStrip` inserted between the copy and the button.
- "Your program" `NsListCard` stays as is.

- [ ] **Step 1: Write failing tests** in `train_start_card_test.dart` (reuse `program_test_support.dart` and the readiness fakes from the old note test):
  - `good readiness shows strip in the start card above Quick workout` (strip's vertical position < button's).
  - `fair strip text is Fair readiness. Train as planned, watch effort.`; `low strip shows Your plans are not changed and red colour`.
  - `building baseline shows the N more days line`; `disconnected, loading and not-enough-data show no strip and the card is unchanged`.
  - `active program with a workout today: title is the workout, button Start <name> starts the program day and opens /train/workout` (fake `workoutActions` records the call with `expectedPlanUuid` of today).
  - `rest day, unavailable day and no program fall back to Quick workout`.
  - `an unfinished workout blocks Start <name> with the existing failure message`.
  - `low readiness still shows the once-per-day note before a program start`.
  - `text scale 2.0 at 320 dp: no overflow in the start card` (only assert no exception from the card; the header bug is pre-existing).
  - `Your program row is still shown`.
- [ ] **Step 2: Run** `flutter test test/train/train_start_card_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement**; delete `ReadinessNote` and its old test file.
- [ ] **Step 4: Run** `flutter test test/train test/programs test/today` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): readiness strip and today's program workout in the start card`

### Task 7: Docs and full verification

**Files:**
- Modify: `docs/ROADMAP.md` (health insights: stage "polish" implemented in source, not released or device-verified), `docs/RELEASE.md` (new device rows: Today A1 light/dark/2x text/tablet, Train start card with and without a program today, every ⓘ sheet opens, Core vs Light naming on Android), `CLAUDE.md` project-state line for health insights, `docs/HEALTH_DATA.md` only if it names the Train note.

- [ ] **Step 1:** Update the docs above (no status claims beyond "implemented in source").
- [ ] **Step 2: Run** `python3 -m unittest discover -s tool -p 'test_*.py'` from repo root — Expected: OK.
- [ ] **Step 3: Run** from `apps/mobile`: `dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test` — Expected: all pass. Record the test count.
- [ ] **Step 4: Commit** `docs: health polish stage 1 status and device checks`
