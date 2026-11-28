# ADR-0013 — Energy score replaces readiness

**Status:** **Accepted** — decided by the human owner on 2026-11-27 (design approved). Stages 1 (energy on the Health tab hero and the readiness detail Today view) and 2 (every other surface and the words) are implemented in source, not released or device-verified; stage 3 is not started.
**Amends:** [ADR-0009](0009-health-insights-trends.md) stage 2 (readiness score, its 14-day baseline minimum and its midnight cut-off) and [ADR-0011](0011-read-workouts-from-health-platforms.md) decision 6 (training load stays a starting-value input). Does not alter ADR-0003 ownership, ADR-0005 backup scope or ADR-0012 watch rules. Design: [`docs/superpowers/specs/2026-11-27-energy-score-design.md`](../superpowers/specs/2026-11-27-energy-score-design.md).

## Context

The readiness score is fixed once last night's sleep syncs: only late HRV or resting heart rate readings move it, and today's activity never does. The owner wants a number that says how much energy a person has at the moment they are about to train, including people who train in the afternoon, the evening or late at night, and that learns each person's habits from the last 90 days.

## Decision

1. **Energy replaces readiness on every surface.** Health hero and card, Today strip and row, Train strip, the pre-workout note, the "better fit today" plan pick, the readiness detail screen and the watch `health_snapshot` `readiness` field. `energy now = clamp(start − drain − awake dip + recharge, 0, 100)`. Bands stay 70 and 50.
2. **Start** is today's readiness formula, unchanged except decision 6. Training load in it still excludes today.
3. **Drain** comes from workouts finished in the current waking day (BeyondRep sessions and outside workouts, as merged today) and from hourly active energy above the person's usual for that hour, excluding hours a counted workout covers. Steps are not an input on their own. Daytime heart rate is not read in this version.
4. **Awake dip** is a small decline with hours since the main sleep ended, waived during the person's usual training hours once learned. **Recharge** is a capped credit for naps that day.
5. **The energy day runs from the end of the main sleep to the end of the next one**, not midnight to midnight. After midnight and before the next main sleep ends, the current waking day's energy is shown. This replaces the midnight cut-off in `todaysReadiness` for energy. The watch snapshot still clears at local midnight (ADR-0012 unchanged).
6. **Shown from 3 baseline days.** The HRV and resting HR baseline minimum drops from 14 to 3 days. Until the score is calibrated, a "still learning your patterns" note shows with the number of workouts still needed and, under 14 baseline days, the days still needed.
7. **Personal tuning, memory only.** From completed BeyondRep sessions in the last 90 days the app learns (a) usual training hours from session start times and (b) one drain multiplier, bounded both ways, from a performance index (working-set volume against the recent norm, plus RPE where logged) against a simplified energy at each session's start (that day's start minus earlier workouts). Calibrated means at least 20 sessions in the window and at least 14 baseline days; before that the generic rates apply. Tuning values are recomputed on device and never stored, synced, backed up, exported, logged or sent to telemetry.
8. **Reads.** The extra history (about 120 days of HRV, resting heart rate and sleep) is read at most once per day per account and held in memory, invalidated on account switch, disconnect and permission change. No new read type and no new permission.

   | Approach | Trade-off | Outcome |
   | --- | --- | --- |
   | Same formula for everyone | Quickest; ignores habits | Rejected by the owner |
   | Formula plus personal tuning, about 20 sessions to calibrate | Learns usual hours and drain rate; fallback until then | **Chosen** |
   | A trained model | Needs far more data than one person has; unexplainable | Rejected |

## Consequences

- The word "readiness" leaves the UI; the morning breakdown stays on the detail screen as "why you started at N". Copy, explanation sheets and glossary change.
- Energy can be shown with as few as 3 baseline days, so it is noisier early; the learning note must be visible whenever it applies.
- Default rates, caps, floor and ceiling are a starting point chosen with tests and recorded in the stage plans, to tune after device use.
- Storing any tuning or energy value, reading daytime heart rate, or adding a read type needs a new ADR.

## Stage 1 defaults

Implemented in source, not released or device-verified. These values are a starting point chosen with tests, to tune after device use (stage 3 tunes the drain ones). `energy now = clamp(start + Σ items, 0, 100)`, where items are drains (negative) and recharge (positive).

| Constant | Value | File |
| --- | --- | --- |
| `readinessBaselineMinDays` | 3 | `readiness.dart` |
| `energyMaxWakingDay` | 20 hours | `energy_day.dart` |
| `energyNapAfterWake` | 60 minutes | `energy_day.dart` |
| `energyNapJoinGap` | 30 minutes | `energy_day.dart` |
| `energyNapMinMinutes` / `energyNapMaxMinutes` | 10 / 180 | `energy_day.dart` |
| `energyUsualMinDays` | 7 | `energy_day.dart` |
| `energyAwakeDipStart` | 8 hours | `energy_day.dart` |
| `energyAwakeDipPerHour` / `energyAwakeDipMax` | 0.5 / 5.0 points | `energy_day.dart` |
| `energyWorkoutPointsPerLoad` | 0.2 points per load unit (minutes × intensity) | `energy.dart` |
| `energyActivePointsPerKcal` / `energyActiveMaxPoints` | 0.025 (1 point per 40 kcal) / 15.0 | `energy.dart` |
| `energyNapPointsPerMinute` / `energyNapMaxPoints` | 0.2 / 10.0 | `energy.dart` |
| `energyCalibratedSessions` / `energyCalibratedBaselineDays` / `energyLearningWindowDays` | 20 / 14 / 90 | `energy.dart` |

- **Waking day:** the latest night whose end is not after now and at most 20 hours before it. Its date is the waking day and its end the wake time. Otherwise there is no waking day and energy falls back to today's readiness (not ready). The start value is the readiness score for the waking day's date; training load in it still excludes that date.
- **Workout drain:** each workout that ends after the wake and not after now costs minutes × intensity × 0.2 points, one item per workout.
- **Active drain:** hourly active energy above the person's usual for that clock hour (mean over earlier days in the read with active energy, at least 7 such days, else no active item), skipping buckets that overlap a counted workout. Points are excess kcal × 0.025, capped at 15.
- **Awake dip:** `min(max(0, hoursAwake − 8) × 0.5, 5)` points.
- **Naps:** asleep segments from any source that start at least 60 minutes after the wake and end by now, merged across sources and joined when the gap is 30 minutes or less, kept at 10 to 180 minutes. Credit is minutes × 0.2, and total recharge is capped at the smaller of 10 and the drain so far, so a nap never lifts energy above the morning start; when capped, each nap's credit is scaled by the same factor and its item is marked capped.
- **Learning note:** shown while fewer than 20 completed BeyondRep sessions fall in the last 90 days, or while the baseline has under 14 days. In stage 1 the generic rates apply; no personal tuning is learned yet.

## Stage 2

Implemented in source, not released or device-verified. One selector, `currentEnergyScore`, replaces `todaysReadiness` on every remaining consumer; there is no new read, no stored value and no wire change.

- **Surfaces:** the Today hero (`ENERGY NOW · GOOD`, change since morning, learning note), the Train strip, the once-per-day low note before a workout ("Energy is low right now"), the "Better fit today" low rule, and the watch snapshot. With no energy (no waking day, or the start not ready) a surface shows nothing and never falls back to the morning score; the only other state is the building line while the start has `n` days to go.
- **Watch:** the snapshot key stays `readiness` (`score`, `band`, `headline`, `reason` up to 140 characters, optional `factors`) and carries energy. `reason` is `Started at 78 · down 16 since morning`, plus ` · still learning` while the learning note applies. It is sent only for a waking day that began on the watch's local date (ADR-0012 local-midnight rule). The watch app's accessibility labels and caption say energy.
- **Words:** no user-visible string says readiness. The explain sheet, the detail chart ("Starting energy") and the glossary are updated; `test/energy_wording_guard_test.dart` enforces it. Identifiers, routes and the wire key keep the old name.
