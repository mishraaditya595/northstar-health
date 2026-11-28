# Energy score, stage 2 (energy on every surface, readiness leaves the UI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show energy now (with the "still learning" note) instead of morning readiness on Today, the Train strip, the pre-workout note, "Better fit today" and the watch snapshot, plot the detail chart as starting energy, and remove the word "readiness" from every user-visible string.

**Architecture:** Stage 1 already computes `HealthOverview.energy` (`EnergyOverview` with `energy`, `start`, `wake`, `learning`) at every read and shows it on the Health tab hero and the readiness detail Today view. This stage adds one selector, `currentEnergyScore`, and switches every remaining consumer of `todaysReadiness(...)` to it, then changes copy. No new reads, no stored values, no contract change: the watch `health_snapshot.readiness` object keeps its keys and carries energy.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, existing design kit. Swift (watchOS app and `BeyondRepWatchCore`) for two strings only. Astro website copy.

**Spec:** `docs/superpowers/specs/2026-11-27-energy-score-design.md`, `docs/adr/0013-energy-score.md`, and the stage list in `docs/superpowers/plans/2026-11-27-energy-score-stage-1.md` ("Stage 2: every other surface and the words").

## Global Constraints

- Run Flutter from `apps/mobile/` (Flutter at `~/sdk/flutter/bin` in the cloud container). Before each commit: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze` clean, the task's tests pass. Commit messages end with the session's attribution lines.
- **Store nothing, read nothing new.** No ObjectBox, Supabase, outbox, export, log or telemetry change. `test/health/health_overview_test.dart` read expectations unchanged.
- **No wire change.** `contracts/watch_link/v1/message.schema.json` and the Dart/Swift codecs are not edited. The snapshot key stays `readiness` with `score`, `band`, `headline`, `reason` (≤ 140 chars), optional `factors`.
- Internal identifiers (`ReadinessCard`, `ReadinessHero`, `ReadinessStrip`, `MetricKey.readiness`, route `/health/readiness`, file names, `readinessBandOf`) stay; only user-visible text changes. No renames.
- **Energy for "now" means `currentEnergy(overview, now)?.energy`.** It is the value computed at the overview's last read; the Train page and Today already call `refreshIfStale()` on show and resume, so it is at most 5 minutes old when a workout starts. No recompute at tap time.
- **No energy, no score.** When `currentEnergy(...)` is null, or its `energy` is null (no waking day, or the start not ready), a surface never falls back to the morning readiness value. The only non-score state shown outside the Health tab is the building line when the start is `ReadinessNotReady(daysUntilBaseline: n)` with `n != null`.
- **Watch keeps the local-midnight rule** (ADR-0012): `buildHealthSnapshot` still returns no `readiness` object unless `dayOf(overview.readAt) == dayOf(localNow)`; inside that, it uses `currentEnergyScore`.
- Kit widgets only (`test/design_kit_guard_test.dart` green); light/dark, text scale 2.0 at 320 dp without overflow; no animations.
- **Copy (fixed):**
  - Band words (`readinessBandWords`): good `Good to train`, fair `Train as planned, watch effort`, low `Take it easier` (was `Recovery low`).
  - Building: every surface uses `energyBuildingText(n)` → `Energy starts after 2 more days with data.`; `readinessBuildingText` is deleted.
  - Learning: `energyLearningText(learning)` (stage 1 copy, unchanged) wherever it is shown.
  - Today hero: eyebrow `ENERGY NOW · GOOD` (band name upper case), title band words, subtitle `energyChangeText(e)`, learning text in the hero's `child` slot, ring caption `Energy`. Semantics label: `Energy now 62 of 100, <words>. <change text>. <learning text if shown> See why` (each sentence ends with a full stop, single spaces).
  - Train strip: line 1 `Good energy. Good to train.` / `Fair energy. Train as planned, watch effort.` / `Low energy. Take it easier.`; line 2 (muted) the learning text when shown; line 3 (muted, low only) `Your plans are not changed`. Semantics `Energy 62, <words>. <learning text if shown> See why`.
  - Pre-workout note: title `Energy is low right now`; message unchanged (`Consider dropping a set per exercise or keeping effort around RPE 7.` + blank line + `Your plans are not changed`).
  - Watch snapshot: `headline` = band words; `reason` = `Started at 78 · down 16 since morning` (same rules as `energyChangeText` but `Started at` instead of `Started today at`), plus ` · still learning` when `learning.show`; `factors` = the start's factors as today.
  - Watch status summary (`watchSentSummary`): `Energy, health, 3 plans`.
  - Watch app: accessibility labels `Energy \(score) of 100, …`, hint `Opens energy details`; `GlanceState.watchCaption` = `From this watch. Open BeyondRep on your iPhone for energy`.
  - Detail range view: panel title `Starting energy`, empty `No starting energy in these 30 days.`, chart semantics `Starting energy, <dates>. …`, `DetailUnavailable` metric name `Energy`.
  - Explain sheet `MetricKey.readiness`: title `Energy`, summary `How much energy you have to train right now`, `what`: `A 0 to 100 score worked out on your phone. Each day starts from your recovery when you wake (HRV, resting heart rate, last night's sleep, your sleep over the past week and your recent training load), then goes down with each workout you finish, with active calories above your usual and a little with long hours awake. A nap adds a few points back.`, `tells`: unchanged thresholds text with `It compares you only with your own last 30 days. While it is still learning your patterns, the score can move more.` appended in place of the last sentence, `inBeyondRep`: `Shown on Today, Health, Train and Apple Watch. It never changes your plans. It is guidance, not medical advice.` Every other explanation's `readiness` becomes `energy` (e.g. `Feeds energy.`, `Not part of energy.`, `One of the inputs to energy once you have 14 days of workout history. Today's workouts count from tomorrow in the starting value and lower energy today.`).
  - No user-visible Dart string literal in `lib/` contains `readiness` in any case, except the wire key literal `'readiness'` and route paths containing `/health/readiness` (enforced by Task 5's guard test).

## Review Focus

1. **After midnight, before the next main sleep (00:30 after a 07:00 wake):** Today hero and Train strip show the waking day's energy; the watch snapshot has no `readiness` object (local-midnight rule). Pinned in Task 2 and Task 4.
2. **Start is ready but there is no waking day** (yesterday's sleep, nothing in the last 20 h): no hero, no strip, no low note, no low plan pick, no watch score; never the morning readiness. Pinned in Task 1 and Task 3.
3. **Good morning start, drained to Low by a workout:** the pre-workout note shows and "Better fit today" uses the low rule. Pinned in Task 3.
4. **Text scale 2.0 at 320 dp with the learning line** on the Today hero and the Train strip (low band, three lines): no overflow. Pinned in Task 2 and Task 3.
5. **Watch reason length:** a long change line plus ` · still learning` stays ≤ 140 chars and never sends the morning reasons when energy exists. Pinned in Task 4.

---

### Task 1: `currentEnergyScore` selector and shared copy

**Files:**
- Modify: `apps/mobile/lib/features/health/application/health_overview.dart` (next to `currentEnergy`)
- Modify: `apps/mobile/lib/features/health/widgets/readiness_card.dart` (`readinessBandWords` low, delete `readinessBuildingText`)
- Modify: callers of `readinessBuildingText` (`today_health_row.dart`, `readiness_strip.dart`, any other) to call `energyBuildingText`
- Test: `apps/mobile/test/health/health_overview_test.dart` (or the file that already tests `currentEnergy`; add a group `currentEnergyScore`), `apps/mobile/test/health/readiness_card_test.dart`

**Interfaces:**
- Produces: `Energy? currentEnergyScore(HealthOverview o, DateTime now)` → `currentEnergy(o, now)?.energy`. Produces `({int days})? energyBuilding(HealthOverview o, DateTime now)` returning the start's `daysUntilBaseline` when `currentEnergy(o, now)` is non-null, its `energy` is null and `start.result` is `ReadinessNotReady(daysUntilBaseline: final d?)`; else null. Later tasks use only these two plus `currentEnergy` for the learning note.

- [ ] **Step 1: Failing tests** — `currentEnergyScore`: returns the energy for an overview whose `energy` section is `SectionData` with `energy` set and `now` within 20 h of `wake`; null at `wake + 20h 1m`; null when `energy` is null but `start.result` is `ReadinessReady` (no waking day) — assert also that `todaysReadiness` would be non-null in that fixture, so the test proves no fallback; null for a `SectionGap`. `energyBuilding`: `(days: 2)` for a NotReady start with `daysUntilBaseline: 2`; null for NotReady with null days. `readinessBandWords(ReadinessBand.low) == 'Take it easier'`. Build fixtures with the helpers the existing energy/overview tests use.
- [ ] **Step 2: Run** `flutter test test/health/` filtered with `--plain-name currentEnergyScore` and `--plain-name energyBuilding` → FAIL (undefined).
- [ ] **Step 3: Implement** the two functions, change the low band words, delete `readinessBuildingText` and switch its callers to `energyBuildingText` (behaviour on those surfaces changes again in Tasks 2–3; here only the text). Update existing test expectations that pinned `Recovery low` or `Readiness starts after`.
- [ ] **Step 4: Run** `flutter test test/health/` → PASS.
- [ ] **Step 5: Commit** `feat(health): energy score selector and shared energy copy`.

### Task 2: Today shows energy

**Files:**
- Modify: `apps/mobile/lib/features/health/widgets/readiness_hero.dart`
- Modify: `apps/mobile/lib/features/health/widgets/today_health_row.dart` (hero switch near line 84–112)
- Test: the existing Today health row / hero widget tests under `apps/mobile/test/health/` or `apps/mobile/test/today/` (extend; find with `grep -rln ReadinessHero test`)

**Interfaces:**
- Consumes: `currentEnergy`, `currentEnergyScore`, `energyBuilding` (Task 1); `energyChangeText`, `energyLearningText` (`energy_text.dart`).
- Produces: `ReadinessHero({required Energy energy, required EnergyLearning learning, required HealthPlatformKind platform, required VoidCallback onOpen})` (the `readiness` and `reasons` parameters go away).

- [ ] **Step 1: Failing widget tests** on the Today health row: (a) energy 62 fair with start 78 → hero shows `62`, eyebrow `ENERGY NOW · FAIR`, title `Train as planned, watch effort`, subtitle `Started today at 78 · down 16 since morning`, semantics label as in Global Constraints; (b) learning `workoutsNeeded: 12` → hero shows `Still learning your patterns: 12 more workouts for a calibrated score.`; (c) start NotReady with 2 days → `InsightCard` with `Energy starts after 2 more days with data.`; (d) start ready but `energy` null → no hero and no `Readiness`/`Energy` number; (e) `now` = 00:30 next calendar day, wake 07:00 previous day, overview read 00:28 → hero shows energy (Review Focus 1); (f) text scale 2.0, width 320, learning shown → `tester.takeException()` is null; (g) no widget text anywhere in the row contains `Readiness`.
- [ ] **Step 2: Run** those tests → FAIL.
- [ ] **Step 3: Implement** — `today_health_row.dart` picks the hero from `currentEnergy(overview, now)`: energy present → `ReadinessHero(energy:, learning:, …)`; else `energyBuilding` → building `InsightCard`; else no hero. `ReadinessHero` renders the fixed copy; the info button stays `MetricKey.readiness`.
- [ ] **Step 4: Run** the Today/health widget tests → PASS.
- [ ] **Step 5: Commit** `feat(today): show energy now on the Today hero`.

### Task 3: Train strip, pre-workout note and "Better fit today" use energy

**Files:**
- Modify: `apps/mobile/lib/features/health/widgets/readiness_strip.dart`
- Modify: `apps/mobile/lib/features/health/widgets/readiness_note.dart`
- Modify: `apps/mobile/lib/features/train/train_library_state.dart` (`planFitProvider`)
- Test: existing strip, note and plan-fit tests (`grep -rln "ReadinessStrip\|confirmReadinessBeforeStart\|planFitProvider" test`)

**Interfaces:**
- Consumes: `currentEnergy`, `currentEnergyScore`, `energyBuilding` (Task 1).
- Produces: nothing new; `confirmReadinessBeforeStart` and `suggestPlan(..., lowReadiness:)` keep their signatures.

- [ ] **Step 1: Failing tests** — strip: energy 45 low with learning `workoutsNeeded: 3` → texts `Low energy. Take it easier.`, `Still learning your patterns: 3 more workouts for a calibrated score.`, `Your plans are not changed`; semantics `Energy 45, Take it easier. Still learning your patterns: 3 more workouts for a calibrated score. See why`; good band → `Good energy. Good to train.`, no plans line; start ready but no energy → `SizedBox.shrink` (no text); building → `Energy starts after 2 more days with data.`; text scale 2.0 at 320 dp low with learning → no exception. Note: start 80 good but energy 45 low (drained by a workout item) → dialog titled `Energy is low right now` shows; start 40 low but energy null (no waking day) → returns true with no dialog; once per owner per day unchanged. Plan fit: same two fixtures → `lowReadiness` true for drained-to-low energy (suggestion is the lightest recovered plan, as the existing low test asserts), false for no-energy.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — the three consumers replace `todaysReadiness(...)` with `currentEnergyScore(...)` (band from `Energy.band`); the strip shows the learning line from `currentEnergy(...)!.learning`; note title constant changes.
- [ ] **Step 4: Run** strip, note, plan-fit, `test/train/` and `test/today/` → PASS.
- [ ] **Step 5: Commit** `feat(train): energy drives the Train strip, low note and plan pick`.

### Task 4: Watch carries energy

**Files:**
- Modify: `apps/mobile/lib/features/watch/application/watch_snapshots.dart` (`buildHealthSnapshot`, readiness block near line 276)
- Modify: `apps/mobile/lib/features/health/widgets/energy_text.dart` (add `energyWatchReason`)
- Modify: `apps/mobile/lib/features/watch/domain/watch_status.dart` (`watchSentSummary` word)
- Modify: `apps/watch_os/Sources/Features/Home/HomePage.swift`, `apps/watch_os/Sources/Features/Detail/ReadinessDetailView.swift` (accessibility strings), `apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Glance/GlanceState.swift` (`watchCaption`) and its expectation in `apps/watch_os/Packages/BeyondRepWatchCore/Tests/BeyondRepWatchCoreTests/GlanceStateTests.swift`
- Test: existing `buildHealthSnapshot` and `watchSentSummary` tests (`grep -rln "buildHealthSnapshot\|watchSentSummary" test`), plus the golden/fixture test if it builds a snapshot from an overview

**Interfaces:**
- Consumes: `currentEnergy`, `currentEnergyScore` (Task 1); `readinessFactors` (existing).
- Produces: `String energyWatchReason(Energy e, EnergyLearning l)` — `Started at 78 · down 16 since morning` / `· no change since morning` / `· up 3 since morning`, plus ` · still learning` when `l.show`.

- [ ] **Step 1: Failing tests** — `energyWatchReason`: the three change forms and the learning suffix. Snapshot: energy 62 fair, start 78, learning shown → `readiness == {'score': 62, 'band': 'fair', 'headline': 'Train as planned, watch effort', 'reason': 'Started at 78 · down 16 since morning · still learning', 'factors': <start factors as before>}`; start ready but no energy → no `readiness` key; `readAt` and `localNow` on the next calendar day at 00:30 with a current waking day → no `readiness` key (midnight rule); `reason.length <= 140` for start 100, energy 0, learning shown. The snapshot still validates against `message.schema.json` if the existing test checks that. `watchSentSummary(hasReadiness: true, hasHealth: true, planCount: 3) == 'Energy, health, 3 plans'`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the Dart changes, then the Swift string changes (no logic change). Swift tests run on CI only (`watchos_smoke.yml`); update the `watchCaption` expectation in `GlanceStateTests.swift` and `grep -rn "for readiness" apps contracts` to catch any other copy of it.
- [ ] **Step 4: Run** `flutter test test/watch/` (and whatever paths the grep found) → PASS. Record "Swift not run locally".
- [ ] **Step 5: Commit** `feat(watch): send energy now in the watch snapshot`.

### Task 5: Detail chart, explain sheets, glossary and the wording guard

**Files:**
- Modify: `apps/mobile/lib/features/health/detail/readiness_detail_page.dart` (`_RangeView` strings near lines 345–440)
- Modify: `apps/mobile/lib/features/health/domain/metric_explanations.dart` (all `readiness` copy)
- Modify: `apps/mobile/lib/features/health/detail/health_terms_page.dart` if any term or text still says readiness
- Modify: any other `lib/` file the guard finds
- Create: `apps/mobile/test/energy_wording_guard_test.dart`
- Test: `apps/mobile/test/health/readiness_detail_test.dart`, `apps/mobile/test/health/health_terms_page_test.dart`, explanation tests

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Failing guard test** `energy_wording_guard_test.dart`: reads every `lib/**/*.dart`, extracts single- and double-quoted string literals (a regex over each line is enough; skip `import`/`export` lines and `///`/`//` comments), and fails listing `file:line` for any literal matching `/readiness/i` other than exactly `'readiness'` or one containing `/health/readiness`. Also extend detail tests: 7-day view shows `Starting energy` and `No starting energy in these 7 days.` when nothing scored; explanation for `MetricKey.readiness` has title `Energy`.
- [ ] **Step 2: Run** `flutter test test/energy_wording_guard_test.dart` → FAIL listing the remaining literals.
- [ ] **Step 3: Implement** the fixed copy from Global Constraints; for each other hit, replace "readiness" with "energy" in user text (the "How energy works" caption, factor/status texts, `readinessHrvName` is fine as it has no such word). Comments and identifiers are not touched.
- [ ] **Step 4: Run** the guard, `test/health/` and then the whole suite `flutter test` once → PASS.
- [ ] **Step 5: Commit** `feat(health): energy wording on the detail chart, explain sheets and glossary`.

### Task 6: Docs and website

**Files:**
- Modify: `docs/adr/0013-energy-score.md` (Status: stage 2 implemented in source; add a short "Stage 2" section listing the surfaces, the watch reason format and "no wire change")
- Modify: `docs/ROADMAP.md` (energy entry: stage 2 implemented in source, not released or device-verified; replace the release gate sentence with: energy stages 1 and 2 ship together; stage 3 tuning is not started)
- Modify: `docs/RELEASE.md` (energy section: release gate replaced as above; add stage 2 rows, all `not run`: Today hero shows energy and the learning line; Train strip and low note after a draining workout; "Better fit today" on a low-energy afternoon; watch Home and detail show energy and `· still learning`, cleared at local midnight; VoiceOver/TalkBack read "Energy")
- Modify: `docs/HEALTH_DATA.md`, `docs/PRIVACY_POLICY_INPUTS.md`, `docs/DESIGN_SYSTEM.md`, root `CLAUDE.md` project-state energy line — "readiness score" in user-facing descriptions becomes "energy score"; keep historical ADR references
- Modify: `apps/website/src/pages/privacy.astro`, `support.astro`, `features.astro`, `index.astro` — "readiness score" → "energy score" in visible copy (read `apps/website/AGENTS.md` first)

- [ ] **Step 1:** Make the edits. Nothing in docs may claim release or device verification.
- [ ] **Step 2: Run** `python3 -m unittest discover -s tool -p 'test_*.py'` from the repo root → OK; `cd apps/website && npm ci && npm test && npm run build && npm run check-links` → pass (if Node 22 is unavailable, record "website checks not run").
- [ ] **Step 3: Commit** `docs: energy score stage 2 status, release rows and website copy`.
