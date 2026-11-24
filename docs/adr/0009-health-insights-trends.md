# ADR-0009 — Health insights and trends (Phase 3 extension)

**Status:** **Accepted** — decided by the human owner on 2026-11-24 (design approved).
**Amends:** [ADR-0008](0008-daily-health-summary-reads.md) items 1 (metrics and windows), 3 (cache) and 7 (Android history permission). Does not alter ADR-0005 backup scope or ADR-0003 ownership. Design: [`docs/superpowers/specs/2026-11-24-health-insights-design.md`](../superpowers/specs/2026-11-24-health-insights-design.md).

## Context

The four Phase 3 cards each hold one absolute number, which the owner found incomplete. The Health tab should say how the person is doing against their own recent past, with sleep stages, heart rate and HRV, activity and body trends, a sleep score, and later a readiness score and training tie-ins. Health data stays read-only, on-device and never in Supabase. This widens the read scope and adds derived scores, so a numbered ADR is required.

## Decision

1. **Read scope grows (amends ADR-0008 item 1).** The four-metric list and its windows are replaced by the table below. Trend windows are about 30 days (31 nights for sleep stages); the overview needs last night plus 30 days of resting HR, HRV and sleep, and 7 days of steps. Reads per metric run in parallel and fail independently.

   | Need | Read |
   | --- | --- |
   | Last night's sleep | Stage samples from 18:00 yesterday to now. Main sleep is the longest session (gap over 60 min splits sessions) ending after 03:00 local; shorter ones are naps |
   | Sleep series | Stage samples for 31 nights, clustered per night the same way |
   | Sleep heart rate | Heart rate samples inside the main sleep window only |
   | Resting HR, HRV, VO2 max, respiratory rate, blood oxygen, walking HR, wrist/skin temperature, weight, body fat, lean mass | Samples in the window, reduced to one value per local day |
   | Steps, active energy | Daily buckets (interval API or per-day totals, whichever handles DST and de-duplication correctly) |

   Added read types: sleep awake and in-bed, heart rate, HRV, respiratory rate, blood oxygen, VO2 max, active energy, body fat, lean mass, walking heart rate (iOS), sleeping wrist temperature (iOS), skin temperature (Android 15+). Out of scope still: any write to Apple Health or Health Connect, background reads, notifications, medical claims or alerts, storing any value.

2. **Derived scores are computed on device and never stored.** A sleep score (0-100, needs deep and REM stage data) and, in stage 2, a readiness score (0-100, needs last night's sleep plus HRV or resting HR with at least 14 baseline days of the last 30). The formulas live in a pure Dart `domain` layer with no Flutter, plugin, ObjectBox or file imports. A missing input drops out and the rest are rescaled, or no score is shown; a score is never made from missing data and a missing value shows `—`, never `0`. Copy is a suggestion, not medical advice. Better/worse is arrow plus words plus colour; weight and body fat are neutral.

3. **Cache (amends ADR-0008 item 3).** Still no on-disk cache of any health value or score. A Riverpod cache keyed by account lives in memory while the app runs, refreshes on tab show, on app resume when older than 5 minutes and on pull-to-refresh, and is dropped on sign-out, account switch, Disconnect and process death.

4. **One source per night for sleep stages.** Duration, stages and score use the source with the most staged asleep minutes in the main sleep (ties: most total asleep minutes); other sources are ignored for that night and the caption names the source used. Merging stage samples across devices would mix two devices' deep and REM shares.

5. **HRV differs by platform.** iOS reads SDNN, Android reads RMSSD. Baselines are per person per phone and each is compared only with itself; copy names the measure.

6. **Android history permission (amends ADR-0008 item 7).** `READ_HEALTH_DATA_HISTORY` is requested where `isHealthDataHistoryAvailable` is true (Android 15, or 14 with SDK extension 13), so 30-day comparisons have a previous period. Without it, Health Connect returns only 30 days before the grant and "vs previous 30 days" is hidden when the earlier period is unreadable. The Health Connect declaration gains this justification. Accounts connected under Phase 3 see an "Allow more data" prompt for types never requested. iOS `NSHealthShareUsageDescription` and the Android manifest are updated.

7. **Charts are drawn in the design kit** (`lib/core/design/charts/`, `CustomPaint`); every chart has a text semantics label.

   | Approach | Trade-off | Outcome |
   | --- | --- | --- |
   | Read fresh, store nothing | Keeps the Phase 3 privacy promise, no purge logic; shorter history on Android without the history permission, more platform reads | **Chosen by owner** |
   | Store daily summaries per metric in the account's ObjectBox partition (never synced) | Longer history, faster loads; needs purge on disconnect/revocation and a privacy policy change | Rejected by owner for now; screens do not depend on it, so it can be added later with a new ADR |
   | Charts in the kit | No new dependency, exact theme match, light on low-end Android; more code | **Chosen** |
   | `fl_chart` | Faster, built-in tooltips; new dependency, harder to theme, heavier | Rejected |

8. **Delivery in stages**, each shippable and reviewed on its own: chart kit, stage 1 (richer data, trends, sleep score, detail screens, permissions), stage 2 (readiness, Train note), stage 3 (muscle recovery from logged workouts, better-fit plan suggestion, joined insights). Plans are never changed automatically. Training tie-ins join health values with workouts in memory only.

9. **Store prerequisites** from ADR-0008 item 8 still apply, and the privacy policy (#52) must also cover the added types and on-device scoring.

## Consequences

- No health value or derived score may reach Supabase, the sync outbox, the workout export file, ObjectBox, logs, analytics or crash reports. The existing guard tests are extended, and a new one checks that `features/health/domain` and `application` import no ObjectBox and write no files.
- `platform_health_reader.dart` stays the only importer of `package:health`; `features/health/domain` imports only `dart:` libraries and other files in `domain/`.
- The insight cache is cleared on sign-out, account switch and Disconnect, with tests.
- Errors map to sealed states; raw exception text is never logged or shown. iOS denial still reads as empty; Android reports "Not allowed" per type.
- The cross-source time merge in `sleep_merge.dart` is replaced for stage data by one-source-per-night.
- Adding on-disk storage of summaries, writes or any cloud path needs a new ADR.
- Status: the chart kit widgets exist in source on this branch only. Stages 1-3 are **not implemented yet**. Nothing is released or device-verified; owner device QA (iPhone with and without Watch, iPhone with a third-party wearable, Android 14+, Android without the history permission, a night with a nap) has not been run.
