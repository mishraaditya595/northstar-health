# Energy score design: a readiness number that moves through the day and learns your habits

**Date:** 2026-11-27 · **Status:** approved by the owner on 2026-11-27; not implemented · **Amends:** health insights design (`2026-11-24-health-insights-design.md`, ADR-0009 stage 2 readiness and stage 3 training load) · **ADR:** [ADR-0013](../../adr/0013-energy-score.md)

## Intent

Today's readiness score (`features/health/domain/readiness.dart`, `scoreReadiness`) is fixed once last night's sleep syncs. Only late HRV or resting HR readings move it, and today's activity never does. The owner's view: a morning number "doesn't make much sense" for people who train in the afternoon or evening, at the gym or at sports. They want a number that says how much energy they have **at the moment they are about to train**, so they know how hard to push.

Two further owner decisions:

- The number should **learn each person's behaviour** from their last 90 days. Someone who regularly trains late at night may not be less energetic then, and the score should not punish them for their usual hour.
- **Show it early.** From day 3 to 5 of data, show a score with a note that the app is still learning, and say how many more workouts it needs for a calibrated score. Do not wait for sessions before showing anything.

## What the person sees

Energy replaces readiness everywhere readiness shows today: the Health tab hero and card, the Today strip and health row, the Train strip, the pre-workout note, the "better fit today" plan pick, the readiness detail screen and the watch snapshot.

```
 Energy now           62  Fair
 Started today at 78 · down 16 since morning
   - Workout at 7:10 AM        -9
   - Active day so far         -8
   - Nap at 2:40 PM            +3   (capped)
 Still learning your patterns: 12 more workouts for a calibrated score
```

- The big number is **energy now**, recomputed on every read (same triggers as today: Health or Today screen shown or app resumed with a read older than 5 minutes, and pull to refresh).
- "Started today at" is this morning's recovery, which is today's readiness formula (HRV, resting HR, sleep, sleep debt, training load) under a new label. Its breakdown stays on the detail screen as "Why you started at 78".
- Bands keep the readiness thresholds: 70+ good, 50 to 69 fair, under 50 low.
- The learning note shows until the score is calibrated (see Learning), and states the number of workouts still needed. When the morning baselines are still short too, it also says how many days of wearable data are still needed.
- The detail screen's trend chart plots each past day's **starting** value, so history doesn't depend on what time you last opened the app. (Owner can override: end-of-day or at-session-time values are the alternatives.)

## How the number works

`energy now = clamp(start − drain − awake dip + recharge, 0, 100)`

- **start:** today's readiness formula, unchanged except the baseline minimum (below).
- **drain since waking:** from data the app already reads, so no new expensive reads:
  - Workouts finished today (BeyondRep sessions and outside workouts, already merged in memory by `loadSessions`): minutes × intensity, the same load unit training load already uses.
  - Active energy above the person's usual for the hour so far (hourly totals are already read for the Activity card). Steps are not used on their own: easy walking barely tires people, and active energy already rises with harder movement.
  - Each part is turned into points by a drain rate (default set by the builder from the load scale, tuned per person by Learning).
- **recharge:** naps today from the sleep read (a sleep session that is not the main night). Points per nap minute, **capped** (builder picks the default, about +10 total), because naps return a little and often mean a short night.
- **awake dip:** a small decline with hours awake since the main sleep ended, for everyone (builder picks the default; a few points over a long day, not tens). **Waived during the person's usual training hours** once Learning has found them, so a regular late-night trainer is not shown as drained at their usual hour. Owner decision, 2026-11-27.
- Training load in the starting value still excludes today, so a workout is never counted twice.
- **The energy day runs from waking to the next main sleep**, not midnight to midnight. After midnight and before the next main sleep ends, the app keeps showing the current waking day's energy, so a late-night trainer still sees a number at 00:30, and a session from 00:30 to 01:30 drains that waking day. Workouts are counted in drain if they end after this waking day's main sleep ended and before the next one. This replaces the midnight cut-off in `todaysReadiness` / `hasStaleReadiness`; the starting value is still scored for the wake date as today. (My call.)
- Active energy "above usual for the hour" excludes the hours covered by a counted workout, so a workout's energy is not counted twice. (My call.)

**Out of this version:** daytime heart rate (time at a raised heart rate, calm stretches). Heart rate is Health Connect's most expensive read under its foreground quota, and the 2026-11-24 design ruled out strain from heart rate zones. It can be a later stage.

## Learning (personal tuning)

Learns from the last 90 days, computed on device every read and **held in memory only**, like every other health-derived value (HEALTH_DATA.md, ADR-0009). No tuning value is stored, synced or logged.

Two things are learned from completed BeyondRep sessions in the window:

1. **Usual training hours.** From session start times alone (workout data, no health read). During an hour the person regularly trains, the awake dip is waived. Before enough sessions exist to find usual hours, the dip applies at all hours.
2. **Personal drain multiplier.** One multiplier applied to all drain parts (not one rate per part). For each past session, compute a simplified energy at its start time: that day's starting value minus workouts finished earlier that waking day. This needs only HRV, resting HR, sleep and session history, not 90 days of hourly active energy or past naps, which keeps the extra read within the quota anti-goal. Compute and a performance index (working-set volume against that plan's or exercise's recent norm, plus average RPE where logged). If performance holds up when energy at start was low, the person's drain rate shrinks toward the floor; if it drops, the rate grows toward the ceiling. Bounded both ways so one odd week can't swing it.

**Calibrated** means at least **20 completed sessions** in the 90-day window and at least 14 baseline days. Before that, the generic rates are used and the learning note shows "N more workouts for a calibrated score".

**Showing early:** the HRV and resting HR baseline minimum drops from 14 days to **3 days**, with the learning note shown while it is under 14. Days count days of wearable data, not days since install, so most iPhone users and Android users with history access already have 30 days and see a score on day one.

## Goals

- One number, energy, that moves through the day with effort and naps, and is what the Train tab acts on at the time you start.
- Personal: people who train at their usual late hour are not told they are drained just because it is late.
- A score from day 3 to 5 of data, clearly marked as still learning, with the workouts still needed.
- Every point the number moved since morning is listed with its reason.

## Non-goals

- Storing any health value, energy value or tuning value (unchanged owner rule).
- Daytime heart rate reads, stress, HRV during the day (later stage).
- Changing a plan's sets, reps or weights; the Train tab still only suggests.
- Background reads, notifications or widgets.
- A trained machine-learning model (owner chose formula plus tuning).

## Anti-goals

- A score built from missing data, or a missing value shown as 0 (AGENTS.md).
- Energy dropping after a workout and then that same workout counting again tomorrow beyond today's training load rules.
- A noisy 3-day baseline presented as reliable: the learning note must be visible whenever it applies.
- The Health tab getting slower or hitting Health Connect's read quota because of the 90-day learning window.
- Medical or "train through it" advice.

## Constraints

- Repo rules: `AGENTS.md`, `docs/HEALTH_DATA.md`, ADR-0003, ADR-0008, ADR-0009, ADR-0011, ADR-0012. Read-only, on device, memory only.
- The 90-day learning window needs HRV, resting HR and sleep for about 120 days (30-day baselines behind each past session) on top of the session history. On Android without history access only data from 30 days before the connect date is readable, so tuning starts later there.
- Health Connect read quota: the extra history should be read at most once per day per account and held in memory, not on every 5-minute re-read.
- iOS SDNN and Android RMSSD stay separate, as today.
- Watch snapshot (ADR-0012): the `readiness` field carries energy at send time; watch rules unchanged.

## Approaches considered

1. **Same formula for everyone.** Quickest; ignores habits. Rejected by the owner.
2. **Formula plus personal tuning from 90 days, about 20 sessions to calibrate.** Chosen by the owner (2026-11-27).
3. **A trained model.** Needs far more data than one person's 90 days and can't explain its number. Rejected.

Earlier in the discussion a separate energy number beside a fixed morning readiness was proposed; the owner chose to replace readiness with energy, keeping the morning recovery as energy's starting point.

## Decided by the owner

- Energy moves through the day with effort; naps give some back.
- Energy replaces morning readiness.
- Learn from each person's last 90 days, including their usual training time.
- Formula plus personal tuning (option 2).
- Energy dips a little with hours awake, waived at the person's usual training hours once learned.
- Show a score from day 3 to 5 with a "still learning" note and the number of workouts still needed for a calibrated score.

## My calls (owner can change)

- Effort comes from workouts and active energy, not steps alone; no daytime heart rate this version.
- Nap credit is capped.
- The energy day runs from waking to the next main sleep, so post-midnight sessions count for the day you're still awake in.
- Learning tunes one drain multiplier from a simplified past energy (starting value minus earlier workouts that day).
- 20 sessions and 14 baseline days define calibrated; 3 days is the minimum to show.
- Energy drives the plan pick and the pre-workout note at the time of starting.
- The trend chart plots each day's starting value.
- Bands keep 70 and 50.

## Left to the builder

- Default drain and recharge rates, the drain rate floor and ceiling, and the performance index formula, chosen with tests and written into the ADR.
- How "usual training hours" is detected (bins, minimum count).
- How the extra history read is cached in memory and invalidated (account switch, new day, permission change).
- Exact copy, in line with `docs/DESIGN_SYSTEM.md` and existing readiness copy.
- Stage split and PR order. Owner's rule for the build: Opus agents plan and review, Sonnet agents implement with strict test-driven development.
