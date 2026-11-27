# ADR-0013 — Energy score replaces readiness

**Status:** **Accepted** — decided by the human owner on 2026-11-27 (design approved). Not implemented.
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
