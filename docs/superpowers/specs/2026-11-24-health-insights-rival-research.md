# Rival research: what health/fitness apps show (2026-11-24)

Compiled from product knowledge and vendor help pages (Garmin manuals, Oura support, Whoop, Bevel App Store listing). Feature names are the vendors'; BeyondRep should use its own names and formulas.

## Sleep
| App | Headline | Detail |
|---|---|---|
| Oura | Sleep score 0-100 | Contributors: total sleep, efficiency, restfulness, REM, deep, latency, timing. Lowest HR and HRV during the night, HR curve, stage hypnogram |
| Garmin | Sleep score 0-100 + "sleep coach" need | Duration, stress, stages (deep/light/REM/awake), restless moments, sleep HR, respiration, SpO2, HRV overnight |
| Fitbit | Sleep score 0-100 | Time asleep, deep+REM, restoration (sleeping HR vs resting HR, restlessness). Sleep profile monthly |
| Whoop | Sleep performance % (actual vs needed) | Sleep need (baseline + strain + debt), consistency, efficiency, stages, respiratory rate |
| Bevel / Athlytic | Sleep score | Stages, time in bed vs asleep, sleep HR, consistency, built on Apple Health data |
| Apple Health | No score (iOS 18 adds Sleep score on watchOS 26) | Stages chart, respiratory rate, wrist temp, Vitals app overnight outliers |

## Recovery / readiness
| App | Inputs |
|---|---|
| Whoop Recovery % | HRV (main), resting HR, respiratory rate, sleep performance, SpO2/skin temp |
| Oura Readiness | RHR, HRV balance, body temp, recovery index, sleep, sleep balance, previous day activity, activity balance |
| Garmin Training Readiness | Sleep score, recovery time, HRV status, acute training load, sleep history, stress history |
| Garmin Body Battery | HRV + stress + activity through the day |
| Bevel / Athlytic Recovery | HRV and RHR vs personal 7/60-day baseline, sleep |
| Fitbit Daily Readiness | HRV, RHR, sleep, recent activity |

Common pattern: compare today vs personal rolling baseline (7-day vs 30/60-day), show each contributor as "optimal / pay attention", give a short sentence of guidance.

## Load / strain
- Whoop Strain 0-21 (HR-based cardio load) + Strength Trainer "muscular load" from logged lifts.
- Garmin acute/chronic training load, load focus, recovery time hours.
- Bevel Strain (HR-zone based) and strength builder with muscle-group load.
- Apple: Training Load (effort-score based, watchOS 11+).

## Trends
- Every app: day/week/month(/6m/year) charts, avg vs previous period, arrow up/down with colour meaning "better/worse" per metric (lower RHR = better).
- Oura/Whoop: "trends" view correlating behaviours (late workout, alcohol) with sleep/recovery.
- Garmin: HRV status 7-day avg vs baseline band.

## Other metrics commonly shown
VO2 max, HRV, respiratory rate, SpO2, wrist/skin temperature deviation, active energy, exercise minutes, body fat %, lean mass, BMI, walking HR average, cardio recovery (HR recovery 1 min).

## What the health 14.0.0 package can read (relevant)
iOS + Android: sleep stages (asleep/light|core/deep/REM/awake), HEART_RATE, RESTING_HEART_RATE, RESPIRATORY_RATE, BLOOD_OXYGEN, VO2_MAX, STEPS, ACTIVE_ENERGY_BURNED, WEIGHT, BODY_FAT_PERCENTAGE, LEAN_BODY_MASS, WORKOUT.
iOS only: HRV SDNN, WALKING_HEART_RATE, HEART_RATE_RECOVERY_ONE_MINUTE, SLEEP_WRIST_TEMPERATURE, EXERCISE_TIME, WORKOUT_EFFORT_SCORE, APPLE_SLEEPING_BREATHING_DISTURBANCES.
Android only: HRV RMSSD, SKIN_TEMPERATURE (Android 15+), TOTAL_CALORIES_BURNED.
No platform sleep score or readiness score: must be computed.
Health Connect: 30 days before grant unless READ_HEALTH_DATA_HISTORY (Android 15 / 14 ext 13). iOS 27: users can limit shared history window.
Daily aggregates: getHealthIntervalDataFromTypes (1 call per type), getTotalStepsInInterval.

## BeyondRep's edge
Rivals estimate strength load from heart rate or ask users to re-log lifts. BeyondRep already has every set, rep and weight in ObjectBox: volume per muscle group, PRs, session RPE if logged. Tie-ins: recovery vs last heavy session, sleep after leg day, weight trend vs strength trend.

Sources: Garmin Training Readiness manual (www8.garmin.com/manuals/webhelp/.../GUID-C21BE0C8...), Oura support 360057791533, ouraring.com/blog/readiness-score, whoop.com/the-data, Bevel App Store listing id6456176249, dcrainmaker.com/2021/11/fitbit-readiness-review.html.
