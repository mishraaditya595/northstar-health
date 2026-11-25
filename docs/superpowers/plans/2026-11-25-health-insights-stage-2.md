# Health insights, stage 2 (readiness) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an on-device readiness score (0-100) built from HRV, resting HR and last night's sleep against the person's own 30-day baseline. It shows as a hero card at the top of the Health tab with its own detail screen, as a note on Train and once a day before a workout starts on a low day, and in the Today row. Nothing is stored and plans are never changed.

**Architecture:** A pure-Dart `domain/readiness.dart` computes baselines and the score from data stage 1 already reads. `healthOverviewProvider` gains a readiness section with no new platform reads. The readiness detail screen computes a 7/30-day history from the 60-night sleep and per-night heart-rate providers stage 1 built, plus one 60-day HRV read and one 60-day resting HR read. The Today hero frame moves into the kit so the readiness hero reuses it. Train and Today read readiness from the overview.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, go_router 16, `health` 14.0.0 (pinned), existing chart kit. No new dependencies, no new permissions, no ObjectBox change.

**Spec:** `docs/superpowers/specs/2026-11-24-health-insights-design.md` (sections "Screens", "Scores", "Delivery stages"; mockups `Main.dc.html`, `Train.dc.html`, `NoWatch.dc.html`). Stage 1 code is merged on `main` (PR #61).

## Global Constraints

- No health value, readiness score or derived number is ever written to disk, ObjectBox, Supabase, the outbox, the export, logs or analytics. The once-per-day start note flag is in memory only.
- `platform_health_reader.dart` stays the only importer of `package:health`. `lib/features/health/domain/` imports only `dart:` and other `domain/` files. `features/train` and `features/today` read readiness only through `healthOverviewProvider` / `application/` APIs, never the reader.
- Never fabricate readiness (AGENTS.md). Readiness exists only when **all** hold: last night's main sleep exists (`overview.sleep` data with `lastNight.date == dayOf(readAt)`); HRV or resting HR has a value **for today**; that measure has **≥ 14 days** with values in the 30 days before today. Otherwise a not-ready state names what is missing.
- Weights: HRV 40, resting HR 25, sleep 25, sleep debt 10. A missing HRV or resting HR (including one without a 14-day baseline) drops out and the remaining weights are rescaled. Bands: **≥ 70 "Good to train"**, **50-69 "Train as planned, watch effort"**, **< 50 "Recovery low"**.
- Copy is a suggestion, never an instruction or a medical statement. No "you may be sick", no "you must rest". Plans are never changed; the Low note says "Your plans are not changed".
- HRV copy names the measure: "HRV (SDNN)" on iOS, "HRV (RMSSD)" on Android. iOS and Android values are never compared.
- Every better/worse signal is arrow + words + colour. Charts have a text `semanticsLabel`. Kit widgets only (`test/design_kit_guard_test.dart` green). Light/dark, tablet two-column, text scale 2.0, no animations.
- Account separation: readiness is part of the overview, so it inherits its owner reset; the start-note flag is keyed by owner id and local date.
- Synthetic data only. Public repo.
- After each task, from `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, that task's tests. Full `flutter test` at Task 9.

## Review Focus

1. **Baseline still building** (HRV on 9 of the last 30 days, no resting HR): no score; the hero says "Readiness starts after 5 more days with data." Pinned in Task 1 and Task 4.
2. **No wearable** (sleep from a phone app, no HRV or RHR): no score; the dashed card lists "HRV: none", "Resting HR: none" and what provides them. Train and Today show nothing about readiness; the start note never appears. Pinned in Tasks 1, 4, 6, 7.
3. **HRV today but no resting HR yet** (Apple posts resting HR later in the day): a score from HRV + sleep, labelled "Based on HRV and sleep". Pinned in Task 1 and Task 4.
4. **Low day, two workouts started the same day**: the note shows before the first start only, whether started from Train (quick or plan) or Today; it shows again the next day; switching account shows it for the other account. Pinned in Task 7.
5. **Tiny-variance baseline** (HRV 45 ms every day for 20 days, today 43): the SD floor keeps the score from collapsing; today reads as about normal, not "Recovery low". Pinned in Task 1.

---

## File map

```
lib/core/design/hero_frame.dart                 NsHeroFrame (moved from today_page.dart's _HeroFrame)
lib/features/health/domain/readiness.dart       Baseline, baselineOf, ReadinessInput, Readiness, ReadinessBand, NotReady, scoreReadiness
lib/features/health/application/health_overview.dart   + ReadinessOverview, overview.readiness
lib/features/health/application/health_details.dart    + readinessHistoryProvider
lib/features/health/widgets/readiness_card.dart        hero / not-enough-data / building states
lib/features/health/detail/readiness_detail_page.dart  /health/readiness
lib/features/health/widgets/readiness_note.dart        Train note + chip, start-note dialog helper
lib/features/train/train_page.dart, lib/features/today/today_page.dart  note + start gate
lib/features/health/widgets/today_health_row.dart       readiness slot
docs: ADR-0009, HEALTH_DATA.md, ROADMAP.md, RELEASE.md, CLAUDE.md, DESIGN_SYSTEM.md (kit catalog)
```

---

### Task 1: Readiness domain

**Files:**
- Create: `lib/features/health/domain/readiness.dart`
- Test: `test/health/domain/readiness_test.dart`

**Interfaces:**
- Consumes: `DayValue`, `dayOf` (`daily_series.dart`), `SleepNight`, `SleepScore`.
- Produces:
  ```dart
  class Baseline { final double mean; final double sd; final int days; }   // sd already floored
  Baseline? baselineOf(List<DayValue> daily, DateTime today, {required double Function(double mean) sdFloor});
      // values on the 30 local days before `today` (today excluded); null with < 14 such days
  double hrvSdFloor(double mean) => max(0.05 * mean, 2.0);
  double rhrSdFloor(double mean) => 1.5;
  enum ReadinessBand { good, fair, low }        // ≥70, 50-69, <50
  enum ReadinessInput { hrv, restingHr, sleep, sleepDebt }
  class ReadinessPart { final ReadinessInput input; final double score; /*0-100*/ final double weight; /*rescaled, sums to 1*/ final double? z; }
  class Readiness { final int value; final ReadinessBand band; final List<ReadinessPart> parts; }
  sealed class ReadinessResult {}
  final class ReadinessReady extends ReadinessResult { final Readiness readiness; }
  final class ReadinessNotReady extends ReadinessResult {
    final bool noSleep;            // no main sleep last night
    final bool noHrvOrRhrToday;    // neither measure has a value today
    final int? daysUntilBaseline;  // set when a today value exists but no measure has 14 baseline days: 14 - max(days)
  }
  ReadinessResult scoreReadiness({
    required DateTime today,
    required SleepNight? lastNight,          // null or not today's → noSleep
    required SleepScore? sleepScore,
    required List<SleepNight> priorNights,   // for the 7-night average
    required List<DayValue> hrvDaily,
    required List<DayValue> restingHrDaily,
  });
  ```
- Part scores (pinned here; the spec lets the builder pick curves, these are the pick):
  - HRV: `clamp(70 + 15 * z, 0, 100)`, z = (today − mean) / sd.
  - Resting HR: `clamp(70 − 15 * z, 0, 100)`.
  - Sleep: `sleepScore.value` when present, else `clamp(100 * asleepMinutes / 450, 0, 100)`.
  - Sleep debt: r = last night asleep / mean asleep of the nights in the 7 dates before it (needs ≥ 3 such nights, else this part drops out and is rescaled); `clamp((r − 0.7) / 0.3 * 100, 0, 100)`.
  - value = round(Σ score × weight) after rescaling the base weights 0.40 / 0.25 / 0.25 / 0.10 over the parts present.

- [ ] **Step 1: Failing tests** (synthetic data):
  - `baselineOf` excludes today and days older than 30, returns null at 13 days, non-null at 14, applies the floor (`HRV 45 every day → sd 2.25`).
  - `normal day scores Good`: HRV and RHR equal to their means, sleep score 85, last night equal to the week average → 77 (0.4×70 + 0.25×70 + 0.25×85 + 0.1×100 = 76.75), band good.
  - `mockup low day`: HRV z −2, RHR z +2, no sleep stages and 340 min asleep, r = 0.8 → 48, band low.
  - `tiny variance` (Review Focus 5): HRV 45 for 20 days, today 43, RHR absent → band not low.
  - `HRV only today, no resting HR` → ready, parts are hrv/sleep/sleepDebt, weights sum to 1.
  - `HRV today with 9 baseline days, no RHR` → NotReady(daysUntilBaseline: 5).
  - `no sleep last night` → NotReady(noSleep: true), even with HRV. `last night is an older date` → noSleep.
  - `no HRV or RHR today` (values only on earlier days) → NotReady(noHrvOrRhrToday: true).
  - Band edges: 70 → good, 69 → fair, 50 → fair, 49 → low.
- [ ] **Step 2: Run** `flutter test test/health/domain/readiness_test.dart` → FAIL (file missing).
- [ ] **Step 3: Implement.** The domain guard test must stay green.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(health): readiness score and baselines`.

### Task 2: Readiness in the overview

**Files:**
- Modify: `lib/features/health/application/health_overview.dart`
- Test: `test/health/health_overview_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class ReadinessOverview {
    final ReadinessResult result;
    final bool hasHrv, hasRestingHr, hasSleep;   // today's inputs present, for the "what's missing" chips
    final TrendResult? hrvVsNormal, restingHrVsNormal;   // today vs baseline mean, for the hero chips
    final Baseline? hrvBaseline, restingHrBaseline;
    final bool hrvIsSdnn;
  }
  // HealthOverview gains: final Section<ReadinessOverview> readiness;
  ```
- Built from the data the overview already holds (sleep, heart sections). **No new reader calls**; a test asserts the recorded reader calls are unchanged from stage 1. A section with a gap (e.g. heart notAllowed) still yields `SectionData` with a NotReady result, so the hero can say what is missing; `SectionGap` is used only when both sleep and heart sections are gaps for the same reason (then that reason).

- [ ] **Step 1: Failing tests:** ready overview from fixtures (score matches the domain for the same inputs); no-wearable fixture → NotReady with hasHrv/hasRestingHr false; account switch → B never sees A's readiness (reuse the stage-1 switch harness); reader call log unchanged.
- [ ] **Step 2-4:** run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat(health): readiness in the overview`.

### Task 3: Hero frame into the kit

**Files:**
- Create: `lib/core/design/hero_frame.dart`
- Modify: `lib/features/today/today_page.dart` (use the kit frame, delete `_HeroFrame`), `docs/DESIGN_SYSTEM.md` (catalog row)
- Test: `test/core/design/hero_frame_test.dart`; existing Today tests stay green unchanged.

**Interfaces:**
- Produces: `NsHeroFrame({required String eyebrow, String? title, String? subtitle, List<NsHeroAction> actions = const [], Widget? leading, Widget? child})` and `NsHeroAction(String label, VoidCallback onPressed)`. Same look as today's `_HeroFrame` (dark green, `heroBorder`, radius 25, lime primary action). `leading` sits left of the title block (for the score ring); `child` goes under the subtitle (for chips). A null title still shows the loading spinner as today.

- [ ] Steps: failing kit test (renders eyebrow/title/subtitle, first action filled, `leading` and `child` placed, text scale 2.0 no overflow at 320 px) → implement by moving the code → Today tests unchanged and green → commit `refactor(design): move the hero frame into the kit`.

### Task 4: Readiness hero card on the Health tab

**Files:**
- Create: `lib/features/health/widgets/readiness_card.dart`
- Modify: `lib/features/health/health_page.dart` (card first, above Sleep), `lib/app/beyondrep_app.dart` (route `/health/readiness`, placeholder target until Task 5 if needed)
- Test: `test/health/readiness_card_test.dart`

States (match `Main.dc.html` and `NoWatch.dc.html`):
- **Ready:** `NsHeroFrame` with eyebrow `READINESS`, `NsScoreRing` as `leading`, title = band words, subtitle = one reasons sentence built from the parts (e.g. "HRV (SDNN) above your normal · resting HR about normal · slept 7h 12m"), three chips (HRV, Resting HR, Sleep), each with `NsTrendLabel` (better/worse/same). When a measure dropped out: "Based on HRV and sleep" / "Based on sleep and resting HR". Tap → `/health/readiness`. Semantics: "Readiness 77 of 100, Good to train, …".
- **Baseline building:** dashed card "Readiness starts after N more days with data." plus which measure is building.
- **Not enough data:** dashed card "Not enough data for a score", one sentence on what provides the inputs (iOS: "A watch or ring that syncs to Apple Health provides these."; Android: "…to Health Connect…"), one chip per input: `Sleep: none` / `HRV: none` / `Resting HR: none` when missing, and the value when present (e.g. `Sleep: 7h 12m`).
- **Gap:** the overview's `MetricUnavailable` copy (Not allowed · Manage / Couldn't read · Try again).
- Not connected or loading: as the other cards.

- [ ] **Step 1: Failing tests:** each state's text and semantics; band words at 70/69/49; "Based on HRV and sleep"; SDNN on iOS and RMSSD on Android; tap opens `/health/readiness`; text scale 2.0 at 320 px with no overflow; light and dark build.
- [ ] Steps 2-4, commit `feat(health): readiness card`.

### Task 5: Readiness detail screen

**Files:**
- Modify: `lib/features/health/application/health_details.dart`
- Create: `lib/features/health/detail/readiness_detail_page.dart`
- Modify: `lib/app/beyondrep_app.dart` (route)
- Test: `test/health/readiness_detail_test.dart`

**Interfaces:**
- Produces: `final readinessHistoryProvider = FutureProvider.autoDispose.family<List<({DateTime day, ReadinessResult result})>?, SleepRange>(...)` for `week`/`month`. It reuses `sleepRangeNightsProvider(range)` and `sleepRangeHrProvider(range)` (no new sleep or heart-rate reads) and adds exactly one HRV read and one resting HR read covering 60 days before the range end, reduced as the overview does. Each day's result comes from `scoreReadiness` with that day as `today`. Owner checks as in stage 1 (`_stillOwner` after awaits).

Screen (`HealthDetailScaffold`, `NsChip` row `Today | 7 days | 30 days`):
- **Today:** score ring and band; one row per part: input name, today's value, "your normal" range (baseline mean ± sd, rounded), its 0-100 part score and its share of the total; parts that dropped out are listed with why ("No resting HR today yet"). A short "How readiness works" paragraph (inputs, your own 30-day normal, needs 14 days, a suggestion, not medical advice). Not-ready states reuse the card copy.
- **7 / 30 days:** `NsBarChart` of daily readiness (days without a score have no bar; the axis keeps the gap), reference line at 70 labelled "Good to train", average of scored days, count "Scored on 18 of 30 days"; `NsTrendLabel` vs the previous period only when it had ≥ 5 scored days.

- [ ] **Step 1: Failing tests:** Today rows with normal ranges and SDNN/RMSSD naming; 7-day history issues exactly one HRV and one RHR read and no extra sleep or heart-rate reads beyond the sleep providers'; days without a baseline draw no bar and are excluded from the average; previous-period label hidden with < 5 scored days; account switch drops history.
- [ ] Steps 2-4, commit `feat(health): readiness detail screen`.

### Task 6: Readiness note on Train

**Files:**
- Create: `lib/features/health/widgets/readiness_note.dart`
- Modify: `lib/features/train/train_page.dart` (note above "Start training")
- Test: `test/train/train_readiness_note_test.dart`

**Interfaces:**
- Produces: `ReadinessNote` (ConsumerWidget, reads `healthOverviewProvider`). Renders nothing when not connected, loading, a gap, or NotReady. **Low:** full card per `Train.dc.html`: score, "Recovery is low today", reasons line (same builder as Task 4), "Consider dropping a set per exercise or keeping effort around RPE 7.", "See why" → `/health/readiness`, and "Your plans are not changed". **Fair/Good:** a compact chip row ("Readiness 64 · Train as planned, watch effort", "See why").
- Train must not show a spinner or error for readiness; health failures never affect Train.

- [ ] **Step 1: Failing tests:** Low/Fair/Good/NotReady/not-connected/overview error; See why route; copy contains no "must", "should rest" or medical words (assert on the rendered strings).
- [ ] Steps 2-4, commit `feat(train): readiness note`.

### Task 7: Low-day note before a workout starts

**Files:**
- Modify: `lib/features/health/widgets/readiness_note.dart`, `lib/features/train/train_page.dart` (`_start`), `lib/features/today/today_page.dart` (`_startPlan`)
- Test: `test/train/readiness_start_note_test.dart`

**Interfaces:**
- Produces: `Future<bool> confirmReadinessBeforeStart(BuildContext context, WidgetRef ref)`. Returns true at once unless today's readiness is Low **and** the note has not been shown today for this owner. Otherwise shows an `NsDialog` with the Low note text and actions "Start workout" (true) and "Not now" (false), and marks it shown. `final readinessStartNoteShownProvider = NotifierProvider<…, ({String owner, DateTime day})?>` holds the in-memory flag.
- Quick workout: the gate runs after the name dialog, before starting. Plan start (Train and Today): before `startPlan`.

- [ ] **Step 1: Failing tests:** Low day: first start shows the note, the second the same day doesn't; "Not now" doesn't start a workout; next day shows again (fake clock); another owner shows again; Fair/Good/NotReady/not connected never show it; nothing is written to ObjectBox (the workout store sees only the normal start).
- [ ] Steps 2-4, commit `feat(train): low readiness note before a workout starts`.

### Task 8: Today row readiness slot

**Files:**
- Modify: `lib/features/health/widgets/today_health_row.dart`
- Test: existing Today row tests + new cases.

Slots become **[Readiness, Sleep, Steps]** when readiness is ready, else stay **[Sleep, Steps, Resting HR]** (stage 1). The readiness tile shows the score and band words; tap opens `/health/readiness`.

- [ ] Steps: failing tests for both slot sets and the tap route → implement → commit `feat(today): readiness in the health row`.

### Task 9: Docs and full gate

- [ ] ADR-0009: stage 2 implemented in source, not device-verified; readiness computed on device, never stored. `docs/HEALTH_DATA.md`: readiness inputs and "never stored". `docs/ROADMAP.md`, `CLAUDE.md`: stage 1 merged on main (not "on a feature branch"), stage 2 implemented in source and not device-verified, stage 3 (except the workout-only muscle map already on main) not implemented. `docs/RELEASE.md` stage-2 rows, all "not run": good day with a watch, low day note on Train and the start note once per day, HRV without resting HR, baseline building, phone only.
- [ ] Spec status line: "stage 2 implemented, not device-verified".
- [ ] From `apps/mobile/`: format, analyze, full `flutter test`; from root `python3 -m unittest discover -s tool -p 'test_*.py'`. Record iOS build and device QA as not run.
- [ ] Commit `docs: health insights stage 2 status`.
