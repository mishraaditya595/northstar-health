# Health insights design: richer cards, trends, readiness and training tie-ins

**Date:** 2026-11-24 · **Status:** approved; stages 1-2 merged; stage 3 implemented in source (two of four insights), not device-verified · **Builds on:** Phase 3 (`2026-11-24-phase-3-health-reads-design.md`, ADR-0008) · **Before:** Phase 4 (write-back)

Mockups (fictional values): five 390 px phone screens, source in `2026-11-24-health-insights-mockups/` next to this file (`Main` = Health tab with a watch, `Sleep`, `Heart`, `Train` on a low day, `NoWatch` = phone-only). They are HTML with inline styles; colours, sizes, radii and layout in them are the visual reference for the kit widgets and cards, alongside `docs/DESIGN_SYSTEM.md`. The 30-day bars there are not stacked by stage; the build stacks them. Rival research: `2026-11-24-health-insights-rival-research.md`.

## Intent

Phase 3 shipped four large cards, each holding one absolute number (sleep minutes, steps today, latest resting HR, latest weight). The owner's verdict: "huge boxes that only hold an absolute value; this does not feel complete." Rival apps (Garmin Connect, Fitbit, Oura, Whoop, Bevel, Athlytic, Apple Health) show scores, sleep stages, sleep heart rate, HRV, readiness and week/month trends with improvement or decline.

The owner wants a **mix of three jobs**, built in this order:

1. **"How am I doing?"** Richer cards and a detail screen per metric, with 7-day and 30-day trends that say whether things are getting better or worse.
2. **"Should I train hard today?"** A readiness score from sleep, HRV and resting HR against the person's own normal. It shows on the Health tab and reaches the Train tab as a note and a "better fit today" plan suggestion.
3. **"How is my training affecting my body?"** Health trends joined with the workouts logged in BeyondRep, which no generic tracker can do.

All three are designed here so they fit together; stage 1 is built first and each stage ships on its own.

## Goals

- Every card shows more than one number, plus a trend against the person's own recent average. Tapping a card opens its detail screen.
- Sleep: our own sleep score, time asleep, deep, core/light, REM, awake, sleep heart rate; detail adds a stage timeline for the night, bed/wake consistency, respiratory rate, blood oxygen and wrist/skin temperature where available.
- Heart: resting HR and HRV with trend and "your normal" band; VO2 max and (iOS) walking heart rate.
- Activity: steps and active energy today vs daily average; daily bars for 7/30 days.
- Body: weight and body fat when logged; 30-day change and average weekly change.
- Readiness 0-100 with its reasons listed, shown only when its inputs exist.
- Train tab: a readiness note and a plan suggestion. Plans are never changed.
- Works with any wearable that writes to Apple Health or Health Connect (Apple Watch, Garmin, Oura, Fitbit, Samsung, Withings...) and for people with no wearable. Each card says plainly what is missing and why.

## Non-goals

- Storing any health value on disk (owner decision, below).
- Writing to Apple Health or Health Connect (Phase 4).
- Changing a plan's sets, reps or weights automatically (owner chose note + suggestion only).
- Background reads, notifications, home-screen widgets, watch apps.
- Medical claims, illness detection or alerts (no "you may be getting sick").
- Strain/cardio load from heart rate zones (Whoop/Bevel style). Our load comes from logged sets in stage 3.
- Nutrition, mindfulness, cycle tracking, blood glucose, blood pressure.
- User-set goals (sleep goal, step goal). Fixed defaults this round; a goal setting is a later small change.
- Comparisons between people or against population norms beyond fixed reference ranges in copy.

## Anti-goals (a failure even if it works)

- A readiness or sleep score made from missing data, or a missing value shown as `0` (AGENTS.md: never fabricate readiness, never show missing as zero).
- Any health value or derived score reaching Supabase, the sync outbox, the workout export, ObjectBox, logs, analytics or crash reports.
- Advice that reads as medical or that pushes someone to train through poor recovery.
- The Health tab becoming slow to open or burning Health Connect's read quota so later reads fail.
- Comparing iOS HRV with Android HRV as if they were the same measure.
- A colour-only better/worse signal.

## Constraints

- Repo rules: `AGENTS.md`, `docs/HEALTH_DATA.md`, ADR-0003, ADR-0008. Health data is read-only and on-device. UI uses `lib/core/design/`; new chart widgets go into the kit in their own small PR first (AGENTS.md rule 4). Widgets never call SDKs.
- `health` 14.0.0 (pinned). Platform facts that shape the design:
  - No platform provides a sleep or readiness score; we compute both.
  - HRV: iOS reads `HEART_RATE_VARIABILITY_SDNN`, Android reads `HEART_RATE_VARIABILITY_RMSSD`. Baselines are per person per phone, so each is compared only with itself. Copy names the measure.
  - Health Connect returns only 30 days before the grant unless `READ_HEALTH_DATA_HISTORY` is granted (Android 15, or 14 with SDK extension 13; check `isHealthDataHistoryAvailable`). iOS has no such limit, though iOS 27 lets a person share only a recent window.
  - iOS hides read denial: a denied type reads as empty. Android reports denial per type.
  - Daily aggregates come from `getHealthIntervalDataFromTypes` (one call per type) and `getTotalStepsInInterval`; Health Connect de-duplicates activity and sleep by its app priority list.
  - Health Connect has a foreground read quota; the README's cost table applies (heart rate is the expensive type).
  - iOS-only types: walking HR, HR recovery, sleeping wrist temperature, exercise time. Android-only: skin temperature (Android 15+), total calories.
- The store prerequisite from Phase 3 still holds: privacy policy (#52) before a store build. The policy text must cover the added types and on-device scoring.
- Repo is public: synthetic data only in tests, fixtures, docs, screenshots.

## Owner decisions

| Decision | Choice |
|---|---|
| Purpose | A mix of all three jobs, built in stages 1 → 2 → 3, each shippable. |
| History source | **Read fresh, store nothing** (decision card). Trends are re-read from the platform each time; values live only in memory while the app runs. Trends cover about 30 days on Android without the history permission, more on iPhone. |
| Who it serves | Watch/ring wearers and phone-only people alike; missing data is explained, never faked. |
| Readiness in Train | Yes: (1) a note on Train and before starting a workout, (2) a "better fit today" plan suggestion using the muscle recovery map. Plans are never auto-adjusted. |
| Low-day suggestion | The lightest recovered plan: fewest planned sets among plans whose muscles are recovered; never a plan hitting recovering muscles (decision card). |
| Metric set | Five cards: Readiness, Sleep, Heart, Activity, Body, each with a detail screen (7 and 30 days). Training tie-ins on Health, Progress and Train. |
| Look | The mockups, accepted as drawn ("this looks neat"). |

## Approaches considered

| | Approach | Trade-off | Outcome |
|---|---|---|---|
| Storage A | Read fresh each time, nothing on disk | Keeps the Phase 3 privacy promise and no cache purge logic; 30-day window on Android without history permission; more platform reads | **Chosen by owner** |
| Storage B | Daily summary rows per metric in the account's ObjectBox partition, never synced | Longer history, faster loads; needs ADR, purge on disconnect/revocation, privacy policy change | Rejected for now; screens don't depend on it, so it can be added later |
| Charts A | Draw charts in the design kit (`CustomPaint`), like the Progress tab's bar chart | No new dependency, exact visual match, light on low-end Android; more code up front | **Designer's pick** (owner handed over the how) |
| Charts B | `fl_chart` package | Faster, tooltips built in; new dependency, harder to theme, heavier | Rejected |
| Readiness in Train | Note only / note + plan suggestion / auto-adjust session | Auto-adjust acts on an invented score and plans have no weights to scale | **Note + suggestion, chosen by owner** |

## Design

### Screens (match the mockups)

**Health tab** (connected), top to bottom:

1. Date line: `Tue 24 Nov · Apple Health · updated 7:42 AM`.
2. **Readiness hero** (dark green gradient hero from the design system): ring with score, one-line verdict, one sentence of reasons, three chips (HRV, resting HR, sleep) each with its arrow. Not enough data → dashed card "Not enough data for a score" listing which inputs are missing and what provides them. Baseline still building → "Readiness starts after N more days with data."
3. **Sleep card:** score, time asleep, change vs 7-day average, a stage bar (deep/core/REM/awake proportions), four small stats (deep, core, REM, sleep HR), source and time range. Without stages: time asleep only, with "Stages need a watch or ring that records them."
4. **Heart card:** resting HR and HRV side by side, each with 30-day sparkline and arrow + words; footer VO2 max when present.
5. **Activity** and **Body** half-width cards: steps with 7-day mini bars and active kcal; weight with 30-day sparkline and body fat.
6. **From your training** insight line (stage 3), only when an insight passes its minimum-data rule.

Phone/tablet: on tablets and split screen the cards flow into the existing two-column grid; Activity and Body stay a pair.

**Detail screens** (go_router sub-routes of Health, e.g. `/health/sleep`): back button, segmented control. Sleep has `Last night | 7 days | 30 days`; others `7 days | 30 days`.

- **Sleep / Last night:** score ring, asleep, in bed, efficiency, start-end, source; stage timeline (hypnogram rows Awake/REM/Core/Deep); per-stage totals with share of night; sleep heart rate line with average and lowest; "What made the score" contributors each labelled Good / Fair / Short etc.; breathing rate, blood oxygen, wrist/skin temperature deviation where available.
- **Sleep / 7 or 30 days:** bars of time asleep per night (stacked by stage when stages exist) with a dashed 7h30 reference line; average, change vs previous period (only when the previous period was readable); averages of score, deep, REM, sleep HR (on both tabs; heart rate is read once per night window, never across the range, with at most 5 reads in flight); usual bedtime ± spread; one plain-language observation.
- **Heart:** resting HR line with "your normal" band (lower is better); HRV dots with 7-day rolling average and normal band (higher is better), with the SDNN/RMSSD note; VO2 max latest and change; walking HR (iOS).
- **Activity:** daily step bars, 7/30-day averages, active kcal bars, best day.
- **Body:** weight line, average weekly change, body fat and lean mass when present.

**Train tab:** readiness note card at the top when readiness exists (full note on Low days, a compact chip otherwise), "See why" links to Health. "Better fit today" section suggests one plan with a one-line reason; each plan row gets a recovery line from the muscle map. The workout start sheet shows the Low-day note once per day. Nothing shows when readiness can't be computed; the plan suggestion still works without a wearable (it uses logged workouts only).

**Today tab:** the "Recent health" row becomes readiness (or sleep when readiness is unavailable), sleep and steps, using the compact form of the same cards.

**Phone-only Health tab:** same layout; cards without data show `—`, one sentence on what's missing and what would provide it; Activity and Body work normally.

### Better/worse direction

| Metric | Better is |
|---|---|
| Sleep time, sleep score, deep, REM, efficiency | higher (up to the reference range) |
| Resting HR, sleep HR | lower |
| HRV, VO2 max, steps, active energy | higher |
| Weight, body fat | neutral: shown as change, no better/worse colour (goals differ) |

A change counts only when it's beyond a small dead band (e.g. sleep ±10 min, RHR ±1 bpm, HRV ±3 ms or 5%, steps ±5%); otherwise "about the same". Every signal is arrow + words + colour (lime better, amber worse, grey neutral).

### Data reads (all fresh, in memory only)

A `HealthReader` extension adds range reads; `PlatformHealthReader` stays the only `package:health` importer.

| Need | Read |
|---|---|
| Last night's sleep (stages + window) | Sleep stage samples from 18:00 yesterday to now (as today) |
| Several sources for one night | Use one source per night for stages, duration and score: the source with the most staged asleep minutes in the main sleep (ties: most total asleep minutes). Other sources are ignored for that night and the caption names the source used. Merging stage samples across devices would mix two devices' deep/REM shares. |
| Main sleep selection | Cluster samples into sessions (gap > 60 min splits); pick the longest session that ends after 03:00 local; shorter ones are naps and don't count. Fixes the known "afternoon nap counts as last night" bug. |
| Sleep HR | `HEART_RATE` samples inside the main sleep window only |
| 7/30-night sleep series | Sleep stage samples for 31 nights, clustered per night the same way |
| Resting HR, HRV, VO2 max, respiratory rate, SpO2, walking HR, wrist/skin temp, weight, body fat, lean mass | Samples in the window, reduced to one value per local day (resting HR: latest that day; HRV: mean of overnight samples, else day mean; weight: latest that day) |
| Steps, active energy | Daily buckets via `getHealthIntervalDataFromTypes` / per-day `getTotalStepsInInterval` (builder picks after checking aggregation and DST behaviour) |

Windows: the overview needs last night plus 30 days of RHR/HRV/sleep (for baselines and sparklines) and 7 days of steps; detail screens reuse the same in-memory data and only add what they lack (e.g. 31 nights of stages, heart rate for one night). Reads per metric run in parallel and fail independently.

**In-memory lifetime:** a Riverpod cache keyed by account, held while the app runs, refreshed on tab show, app resume (if older than 5 minutes) and pull-to-refresh; dropped on sign-out, account switch, Disconnect and process death. Nothing is written to disk.

**Android history:** where `isHealthDataHistoryAvailable` is true, the Connect sheet also asks for `READ_HEALTH_DATA_HISTORY`, so 30-day comparisons have a previous period. Without it, "vs previous 30 days" is hidden when the earlier period is outside the readable window, never shown against missing data.

**Permissions:** the Connect request grows to the added read types: sleep awake/in-bed, heart rate, HRV, respiratory rate, blood oxygen, VO2 max, active energy, body fat, lean mass, walking HR (iOS), sleeping wrist temperature (iOS), skin temperature (Android 15+). Accounts connected under Phase 3 see an "Allow more data" prompt on cards whose types were never requested; on iOS the request sheet only shows new types, on Android `hasPermissions` tells us which are missing. iOS `NSHealthShareUsageDescription` and the Android manifest/Health Connect declaration are updated.

### Scores (pure Dart, unit-tested, never stored)

All formulas live in a `health_insights` domain layer with no Flutter or plugin imports. The values below are the starting formula; the builder may tune weights with tests, but must keep the input and minimum-data rules.

**Sleep score (0-100)**, requires stage data (deep and REM present) for the main sleep:

| Contributor | Weight | Full marks |
|---|---|---|
| Duration asleep | 35 | ≥ 7h30m; linear to 0 at 4h |
| Deep share | 15 | 15-25% of asleep |
| REM share | 15 | 20-25% of asleep |
| Efficiency (asleep / in bed or session span) | 15 | ≥ 90% |
| Timing consistency (bedtime vs 14-night median) | 10 | within 30 min; 0 at 2h |
| Sleep HR vs resting HR | 10 | sleep avg ≤ resting HR; 0 at +10 bpm |

Missing optional inputs (sleep HR, < 5 prior nights for consistency) drop out and the remaining weights are rescaled; the detail screen says which were used. No stages → no score, only duration.

**Readiness (0-100)**, requires last night's main sleep **and** at least one of HRV or resting HR for today, **and** at least 14 prior days of that measure in the last 30 (the baseline). Inputs as z-scores against the person's 30-day mean and SD (SD floored to avoid tiny-variance spikes):

| Input | Weight | Direction |
|---|---|---|
| HRV today vs baseline | 40 | higher better |
| Resting HR today vs baseline | 25 | lower better |
| Sleep score (or duration vs 7h30 when no score) | 25 | higher better |
| Sleep duration vs 7-night average (debt) | 10 | higher better |

Missing HRV or RHR → its weight is rescaled to the others and the hero says "Based on sleep and resting HR". Bands: **≥ 70 Good to train**, **50-69 Train as planned, watch effort**, **< 50 Recovery low**. Copy is always a suggestion, never an instruction or a medical statement. Stage 3 may add a 10% "recent training load" input once its numbers are proven.

### Training tie-ins (stage 3)

- **Muscle recovery map with real data.** Replace `MuscleRecovery.sample` (the swap point in `features/progress/muscle_recovery.dart`) with a calculation from completed workouts in ObjectBox: per muscle, load from sets × reps × relative intensity (RPE when logged) decaying over ~72 h (48 h for small muscles). Exercises carry a coarse `muscleGroup` (Legs, Back, Chest, Shoulders, Arms, Core); the builder maps groups to map muscles (Legs → quads, hamstrings, glutes, calves; etc.). This needs no health data and works for everyone.
- **Better fit today:** score each plan by how recovered its exercises' muscles are; suggest the best one when it is clearly better than the rest; reason line names the recovering muscles. **On a Recovery low day (owner decision):** suggest, among plans whose muscles are recovered, the one with the fewest planned sets, alongside the note to keep effort down. Never suggest a plan that hits recovering muscles; if none qualifies, suggest nothing. Readiness Good or Fair (or unavailable) leaves the recovery-only rule as is.
- **Insights joining health and training** (computed in memory, shown on Health/Heart/Sleep detail and Progress): e.g. average sleep after leg days vs other days, morning resting HR after the heaviest sessions, weekly volume next to average readiness, weight trend next to estimated strength trend. Each insight has a minimum-sample rule (as built: ≥ 5 matching days with data on each side, sleep differing by ≥ 30 min, resting HR by ≥ 3 bpm; the Health tab shows one of the two, sleep first) and a minimum effect size; otherwise it isn't shown. Health values are joined with workout data only in memory and never written to workouts, outbox, sync or export.

### Code shape

```
lib/core/design/charts/            // new kit widgets, own PR first: bar series, line + band,
                                   // dot series with rolling avg, sleep stage timeline, sparkline,
                                   // score ring, trend label (arrow + words)
lib/features/health/
  data/health_reader.dart          // + range/series reads, sleep sample type
  data/platform_health_reader.dart // only package:health importer
  domain/                          // pure Dart: sleep sessionizing, daily series, baselines,
                                   // sleep score, readiness, trend direction
  application/                     // in-memory insight cache per account; overview + detail providers
  health_page.dart                 // overview
  detail/sleep_detail_page.dart, heart_detail_page.dart, activity_detail_page.dart, body_detail_page.dart
  widgets/                         // cards built from kit widgets
lib/features/progress/muscle_recovery.dart   // stage 3: real calculation
lib/features/train/                // stage 2/3: readiness note, better-fit suggestion
lib/features/today/                // compact readiness/sleep/steps row
```

### Privacy guarantees and checks

- Existing guard tests extended: `package:health` imported only by `platform_health_reader.dart`; `features/sync`, `features/account`, `core/storage` and the export never import `features/health`.
- New guard: nothing under `features/health/domain` or `application` imports ObjectBox or writes files.
- Insight cache is cleared on sign-out/account switch/disconnect (tested).
- Errors map to sealed states; raw exception text is never logged or shown.

### Testing

- Domain unit tests with synthetic data: sleep sessionizing (nap vs main sleep, across midnight, DST change, timezone travel, overlapping sources), stage totals, sleep score contributors and rescaling, readiness minimum-data rules and bands, z-score SD floor, trend dead bands and direction table, daily reduction per metric, Android 30-day window hiding the previous-period comparison, muscle load decay and plan suggestion.
- Reader tests with the fake `Health` facade: each new type, denied (Android) vs empty (iOS), unsupported type, history permission present/absent.
- Widget tests: overview connected/phone-only/mixed/stale-baseline; each detail screen and segment; Train note on Low/Fair/Good/unavailable; light/dark, tablet two-column, text scale 2.0, reduced motion. Chart kit widgets expose a text summary for screen readers.
- Account separation: insight cache from account A never visible after switching to B.
- Performance: overview first paint shows cards with skeletons and fills per metric; a test asserts reads are issued in parallel and that the overview doesn't read heart-rate samples beyond the sleep window.
- Manual device QA (owner, recorded as run/not run): iPhone + Apple Watch; iPhone only; iPhone with a Garmin/Oura syncing to Apple Health; Android 14+ with a watch; Android without history permission; a night with a nap.

### Delivery stages

1. **Chart kit** PR (kit widgets with golden-free widget tests).
2. **Stage 1: richer data and trends.** ADR-0009, reader range reads, domain (sleep sessionizing, series, trends, sleep score), overview cards, four detail screens, permissions update, Today row.
3. **Stage 2: readiness.** Baselines, readiness score, hero card, Train note and start-sheet note.
4. **Stage 3: training tie-ins.** Real muscle recovery, better-fit suggestion, joined insights.

Each stage passes `dart format`, `flutter analyze`, `flutter test`, and gets its own review.

## Calls made by the designer (owner may override)

- Charts drawn in the kit, no chart package.
- Sleep and readiness formulas and bands above; "Good to train / Train as planned, watch effort / Recovery low" wording.
- Fixed 7h30 sleep reference and no user goals this round.
- Readiness needs ≥ 14 days of baseline in the last 30.
- Main-sleep selection rule (longest session ending after 03:00) replacing the current window rule.
- Ask for Android's history permission where available. This reverses ADR-0008's "history not requested" line; ADR-0009 records why (30-day comparisons need a previous period) and the Health Connect declaration gains its justification.
- One source per night for sleep stages (most staged minutes), replacing the cross-source time merge in `sleep_merge.dart` for stage data.
- The once-per-day Low-day note on the start sheet is tracked in memory only.
- Custom exercises whose muscle group doesn't map to the body map are ignored by the muscle recovery calculation.
- In-memory cache with a 5-minute resume refresh.
- Weight and body fat shown as neutral change.
- Today row becomes readiness/sleep/steps.
- ADR-0009 records: derived scores computed on device and never stored, expanded read types, history permission. `docs/HEALTH_DATA.md`, `docs/ROADMAP.md`, `CLAUDE.md` status lines updated.

## Left to the builder

- Exact dead-band values and contributor curve shapes, within the rules above, pinned by tests.
- Steps daily buckets: interval API vs per-day totals, whichever handles DST and de-duplication correctly.
- Muscle group → map muscle table and decay constants.
- Wording of individual insights and empty states, following `docs/DESIGN_SYSTEM.md` and the mockups.
- PR split inside each stage.
