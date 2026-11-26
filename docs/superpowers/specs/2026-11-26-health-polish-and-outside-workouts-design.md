# Health polish and workouts from other apps: design

Date: 2026-11-26. Owner: Adi. Status: draft for approval.
Mockups: https://claude.ai/artifact/1koEPBL8LPodG9CgjhLGhw (options A1, B3 and C1 were picked).

## Why

TestFlight use on Adi's iPhone turned up four problems:

1. Activity shows only steps and active calories. Apple Health also lists workouts that other apps recorded (for example "Traditional Strength Training, 32 min, 131 kcal"), and BeyondRep ignores them, so its picture of training is incomplete.
2. Many users won't know what resting HR, HRV, deep/core/REM sleep or readiness mean.
3. The Today "Recent health" tiles look unpolished. Three equal tiles squeeze "Readiness" into "Readine/ss" and the heights are uneven.
4. On Train, readiness is a single text line unless the score is Low, so people miss it.

## Goals

- Stage 1 (polish): Today health layout A1, readiness inside the Train start card (B3), explanation sheets on every metric plus a glossary (C1).
- Stage 2 (other apps' workouts): read workouts from HealthKit / Health Connect and show them in Activity and Progress history. Merge them with BeyondRep sessions that cover the same time. Add recent training load (BeyondRep and outside workouts) as a readiness input.

## Non-goals

- Writing workouts to HealthKit / Health Connect (Phase 4).
- Outside workouts feeding the muscle recovery map, the Progress "Workouts" count, volume/PR charts or the Progress empty state (Adi confirmed 2026-11-26: counts stay BeyondRep-only), the Today "This week" dots, the "Better fit today" suggestion, sync, backup or export.
- Editing, deleting or "claiming" an outside workout as a BeyondRep log.
- New dependencies or a chart library.

## Anti-goals (a failure even if it works)

- Any health value or outside workout written to ObjectBox, Supabase, logs, telemetry or export. "Read fresh, store nothing" (ADR-0009) still holds.
- A session counted twice because the watch recorded the same lift.
- Explanations that read as medical advice or compare the user with other people.
- Readiness shown as a number when it can't be computed, or missing inputs shown as zero.
- New one-off UI widgets outside `lib/core/design/` (AGENTS.md rule 4).

## Constraints

- `package:health` 14.0.0 is imported only by `platform_health_reader.dart` (guard test).
- Features use the design kit (`showNsSheet`, `NsListCard`, `InsightCard`, `NsScoreRing`, ...). If a piece is missing, extend the kit first, theme-first, in light and dark.
- Light/dark, phone/tablet, text scaling to 2x, reduced motion and screen readers (AGENTS.md rule 5). The Train header already overflows at 2x text (known bug). Don't make it worse.
- Health Connect returns 30 days before the grant unless the history permission is granted. HRV is SDNN on iOS and RMSSD on Android, and the two are not comparable.
- The bands stay the same: Good 70+, Fair 50-69, Low under 50.

## Approaches

1. **Two stages, polish first (picked by Adi).** Stage 1 needs no new permission and doesn't change the score, so a visible upgrade ships quickly. Stage 2 carries the permission, the merge and the formula change.
2. Two stages, outside workouts first. Tiles would be designed with the data from the start, but the polish waits behind the riskiest part.
3. One build. One PR and the largest review, and every part waits for the slowest.

Adi picked 1 because each stage is a smaller, independently reviewable PR.

## Stage 1: polish

### Today "Recent health" (A1)

- **Readiness hero**, full width, on the dark green hero gradient: score ring colored by band (lime Good, amber Fair, red Low), "Readiness · Fair", an ⓘ, the band advice as the headline, and a chevron to `/health/readiness`. Shown only when readiness is ready for today, as now.
- When readiness isn't ready, the hero becomes one slim kit row with the existing not-ready copy (for example "Readiness needs 4 more days of data") and no number. *My call: the current code simply drops the readiness tile in that case. A slim row keeps the layout steady and tells the user why.*
- **2×2 grid** of equal-height tiles. Each tile has the same order: icon + label (+ ⓘ), value, one-line caption.
  - Sleep: time asleep, "Ended 7:59 AM".
  - Steps: today's count, "As of 12:51 PM".
  - Resting HR: bpm, "Today" or the date, plus "N below/above usual" when a 14-day baseline exists.
  - Workouts: count today and the first one's type and duration, for example "1 today · Strength · 32 min". In stage 1 this counts finished BeyondRep sessions only. "None yet today" when there are none.
- Gaps keep today's wording (Allow more data, Not allowed · Manage, Couldn't read · Try again, ...) inside the tile, and never show a zero.
- One footer line names the source ("From Apple Health · Aditya's Apple Watch" when all values share a device, otherwise "From Apple Health"). Captions no longer repeat it.
- At text scale ≥ 1.6 or narrow width (< 360 dp), the grid becomes one column. Tiles tap through to their Health detail screen. *My call.*
- The Connect card, loading and error states stay as they are.

### Train: readiness in the start card (B3)

- The "Start training" card gets a readiness strip just above its main button, every day: score in band color, "Fair readiness. Train as planned, watch effort.", chevron to `/health/readiness`. The strip background uses the band's soft color (amber soft for Fair, red soft for Low, forest soft for Good).
- **Today's program workout.** When `activeProgramCardProvider` has a workout today (not a rest day and not unavailable), the card's title becomes that workout, and its main button "Start <workout>" calls the existing `startProgramDay` path, the same one My program uses. "Quick workout" becomes a secondary text button. On rest days, without a program, or when the day is unavailable, the card stays as today (Quick workout). The "Your program" row below stays as the way into the program; missed days stay on Today only. *Confirmed by Adi 2026-11-26.*
- When readiness isn't ready or health isn't connected, the strip shows nothing (no empty slot). One exception: when it is waiting on baseline days, a muted one-liner says so. *My call.*
- The standalone `ReadinessNote` row above "Start training" is removed. The Low variant's "Plans are never changed for you" moves into the strip as a caption when the band is Low. The once-per-day in-memory Low note before a workout starts stays unchanged.

### Explanations (C1)

- An ⓘ next to each metric's name opens a kit bottom sheet (`showNsSheet`) with:
  1. **What it is**: one or two plain sentences.
  2. **Yours**: the user's usual range against today's value on a small range bar. Usual = mean ± 1 sd over the 30 days before today (the baseline code readiness already uses), shown only with at least 14 days of data, otherwise "We'll show your usual range after 14 days of data." The values come from the overview/detail state already in memory. No new reads, nothing stored. *My call after the builder check:* the block appears only for metrics with a daily series in memory where the sheet opens. From the overview that's resting HR, HRV, weight, body fat, VO₂ max and time asleep. From a detail screen it's also the metrics that screen has read (walking HR, respiratory rate, blood oxygen, wrist temperature, deep/REM share). Steps and active calories show "Your daily average" with no today marker, because a partial day would always look low. Readiness and sleep score show their 30-day usual only where their trend is already in memory. Muscle recovery has no "Yours" block. A missing block is simply left out.
  3. **What it tells you**: what tends to move it, in plain words, with no diagnosis.
  4. **In BeyondRep**: how the app uses it (for example "one of the inputs to your readiness score").
  5. Link: "All health terms" opens the glossary.
- **Glossary page** `/health/terms`: an alphabetical list with a one-line summary each. Tapping an entry opens the same sheet without the "Yours" block. It's reachable from the Health tab header and from every sheet.
- Metrics covered: readiness, sleep score, time asleep, deep, core/light, REM, awake, sleep heart rate, respiratory rate, blood oxygen, wrist temperature, resting heart rate, HRV, VO₂ max, walking heart rate, steps, active calories, weight, body fat, muscle recovery. Stage 2 adds training load and "workouts from other apps".
- The light stage is labeled per platform: "Core" on Apple Health (Apple's name) and "Light" on Health Connect. The sheet says they're the same stage.
- The HRV sheet says Apple and Android measure HRV differently, so the numbers aren't comparable across phones, and only your own trend matters.
- All copy lives in one Dart file (`features/health/domain/metric_explanations.dart`), as `const` data keyed by metric. **Adi reviews the copy before merge.** The deep-sleep share stays "15 to 25%", consistent with the existing detail copy.
- Where ⓘ appears: Today hero and tiles, Health tab card headers, every detail screen's metric headings, the Train readiness strip (on the detail it leads to) and the readiness detail's input rows. The tap target is at least 48 dp, with the semantics label "About <metric>".

## Stage 2: workouts from other apps

Agreed with Adi: read fresh, store nothing, never back up. Entries are read-only and tagged with their source. Overlaps merge into the BeyondRep session. Training load counts both BeyondRep and outside workouts. Outside workouts don't affect the muscle map. The Health Connect 30-day limit is accepted.

### Reading

- Add `HealthDataType.WORKOUT` to both request lists, and on Android add `android.permission.health.READ_EXERCISE` to the manifest. Already-connected users see "Allow more data" (the existing `MetricGap.needsAccess` path), which requests only the new type.
- `PlatformHealthReader` returns `OutsideWorkout` values: platform id, activity type (mapped to a friendly name: "Strength training", "Running", "Cycling", ... with "Workout" as the fallback), start, end, active kcal (nullable), distance (nullable) and source name via `friendlySource` (never a raw bundle id).
- Window: the last 90 local days, read with the rest of the overview refresh (Health Connect may return less; that's accepted). *My call after the builder check:* 90 days lets the readiness trend score training load for its 60 days back with a 28-day lookback, so trend and hero agree. Average HR for a workout comes from `HEART_RATE` samples inside its window (permission already held). It's nullable and never fabricated.
- Our own writes: drop any workout whose source is BeyondRep's app id (`in.beyondrep.app`). No such workouts exist yet. This guards Phase 4.

### Merge rule

- Outside workouts that overlap each other by at least 50% of the shorter are the same workout written by two sources (for example Samsung Health and Fit, or Strava copying an Apple Watch run). They collapse to one before merging, keeping the one with kcal, then the longer, then the earlier start.
- An outside workout merges into a finished BeyondRep session when their time ranges overlap by at least 50% of the shorter of the two. *My call on the threshold.* Each outside workout merges into at most one session (the largest overlap). One session can absorb several outside workouts. Calories add up, and average HR is computed from HR samples inside the BeyondRep session's own window.
- Merged sessions show "From Apple Watch · 131 kcal · avg 112 bpm" under the BeyondRep row (per the mockup). Unmerged outside workouts are listed on their own.
- The merge happens in memory, in an application-layer provider that joins `completedWorkoutHistoryProvider` with the outside-workout read, following the stage 3 training-insights join pattern.

### Where they show

- **Activity detail**: a new "Workouts" section with a 7/30-day bar chart of workout minutes per day (BeyondRep plus outside, merged, using the existing chart kit), then a list with type, time, duration, kcal and source.
- **Progress history**: outside workouts appear in date order among BeyondRep sessions, with a "From <source> · read only" tag. Tapping one opens a read-only detail (type, date and time, duration, kcal, distance, avg HR, source). History shows outside workouts within the 90-day read window, with a small note at that boundary in the all-time view. When health isn't connected or workouts aren't allowed, history looks exactly as it does today.
- **Today Workouts tile**: counts BeyondRep plus unmerged outside workouts today.

### Training load in readiness

- Session load = minutes × intensity.
  - BeyondRep: minutes = completed minus started. Intensity = mean RPE of rated working sets / 10, or 0.8 when none are rated (the recovery default).
  - Outside: minutes = end minus start. Intensity is 0.7 by default. *My call: there's no reliable HR-max without age, which we don't collect.*
  - Merged: the BeyondRep values only.
- Ratio r = (7-day load / 7) ÷ (28-day load / 28), today excluded. Needs at least 14 days since the earliest known workout in the window and a non-zero 28-day load. Otherwise the input is absent, not zero.
- Part score: r ≤ 0.8 → 90, 0.8-1.3 → linear 90→70, 1.3-1.8 → linear 70→30, ≥ 1.8 → 30. Base weight 0.15, rescaled with the others as now (HRV .40, RHR .25, sleep .25, debt .10, load .15). The readiness detail lists it as "Training load" with its own ⓘ. *Starting point. Tune after device use.*
- No training load in the 28 days still yields a score from the other inputs, as today.
- The readiness trend (`readinessHistoryProvider`) scores load for past days the same way, from the same 90-day read and the full local BeyondRep history, so today's trend point equals the hero.

### Docs and ADR

- New ADR-0011, "Read workouts from health platforms". It records: workouts from other apps are read fresh, joined in memory, never stored, synced or exported. It also records the merge rule and that training load is a readiness input, and it amends ADR-0009's "training-load input not implemented". Update `docs/HEALTH_DATA.md`, `docs/ROADMAP.md`, `docs/RELEASE.md` (new device rows: iPhone with Watch logging the same lift, a third-party app workout, Android with and without the history permission, permission added after connect) and the CLAUDE.md status line.

## Testing (both stages)

- Unit: tile mapping per gap, the one-column fallback, the usual range (fewer than 14 days hides it), explanation coverage (every metric shown has an entry, guard test), merge rule edge cases (exactly 50%, two outside workouts against one session, an outside workout touching two sessions, own-app source dropped), training-load ratio and score bands, absent vs zero.
- Widget: A1 states (ready, not ready, disconnected, gaps), B3 with and without a program workout today, at every band, at 2x text and 320 dp. Sheet open and close, semantics labels, light and dark goldens where the suite has them.
- Guards: `package:health` import guard, design-kit guard, and "no health or outside-workout type in ObjectBox/sync/export imports" (extending the existing guard).
- Device (owner, `docs/RELEASE.md`): not run by agents.

## Left to the builder

- Exact copy wording within the rules above (Adi reviews it).
- Icon choices from Material Icons.
- How the 2×2 grid and the range bar are built inside the kit, provided the kit additions are theme-first and reused.
- Activity-type name mapping beyond the common types.
