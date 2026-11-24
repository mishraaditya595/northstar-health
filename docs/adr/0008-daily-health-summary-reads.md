# ADR-0008 — Daily health summary reads (Phase 3)

**Status:** **Accepted** — decided by the human owner on 2026-11-24.
**Amends:** [ADR-0003](0003-data-cloud-health.md) and `docs/HEALTH_DATA.md` for the Phase 3 read scope only (it narrows the optional expiring cache to none). Does not alter ADR-0005 backup scope. Design: [`docs/superpowers/specs/2026-11-24-phase-3-health-reads-design.md`](../superpowers/specs/2026-11-24-phase-3-health-reads-design.md).

## Context

The Health tab and the Today "Recent health" row show hardcoded fictional values. Phase 3 replaces them with the person's real readings from Apple Health and Health Connect, as a quick daily summary. It is not a training-advice or analytics feature. Health data stays read-only, on-device and never in Supabase. A new dependency and a provider choice are involved, so a numbered ADR is required.

## Decision

1. **Four metrics only**, each read on demand:

   | Metric | Window |
   | --- | --- |
   | Sleep | Asleep stages only (asleep, light, deep, REM), from local 18:00 the previous day until now, overlapping intervals merged once; on Android, if no stage points exist, the merged sleep-session duration for the same window is used. Initial definition, confirmed at implementation and implemented this way |
   | Steps | Since local midnight today (platform de-duplicated aggregate) |
   | Resting heart rate | Newest sample in the last 7 days |
   | Weight | Newest sample in the last 30 days, shown in kg |

   Out of scope: charts, history, averages, trends, the Today insight, imported activities, any write to Apple Health or Health Connect (Phase 4), background reads, other metrics.

2. **Provider: the community `health` Flutter package (carp-dk), pinned to exactly `14.0.0`**, wrapping HealthKit and Health Connect.

   | Approach | Trade-off | Outcome |
   | --- | --- | --- |
   | A. `health` package | One new dependency, a few hundred lines of Dart; we inherit its release cadence and bugs | **Chosen** |
   | B. Hand-written Swift and Kotlin bridges | Full control; about 3-4x the work, two native codebases to test, still adds Google's `connect-client` | Rejected for a four-number glance |

   Only a small `HealthReader` interface is visible to screens, so B stays possible later without UI changes. `platform_health_reader.dart` is the only importer of `package:health` (it also exposes `PlatformHealthReader.system()`); `account_gate.dart` provides the reader override and is the one explicit exception allowed to import `features/health` from account code. A guard test resolves every import and export URI, so relative imports are caught. On Android, Not allowed · Manage opens Health Connect's permission settings through a small `northstar/health_settings` method channel instead of re-requesting access.

3. **No health-value cache.** Readings live in Riverpod state for the life of the process and are re-read on view, app resume and pull-to-refresh. This deliberately uses none of the optional expiring cache that `HEALTH_DATA.md` allows, so there is no TTL or stale-purge logic and no health value is ever written to disk.

4. **Per-account opt-in flag.** "Connected" is stored as a single-row ObjectBox entity `HealthConnectionEntity { id, connectedAt }` in the account-partitioned store. The OS grants access to the app, not to a BeyondRep account, so without the flag a second account on the same phone would see the first person's data without tapping Connect. The flag holds no health values, is erased with the partition on account deletion, and returns when the same account signs back in. Permission is requested only when the person taps Connect. Disconnect deletes the flag; it cannot revoke OS access.

5. **iOS denial is indistinguishable from no data.** HealthKit hides read denial: a denied read returns empty results and steps of `0`. iOS therefore shows "No data" (never "Not allowed"), treats steps `0` as no data, and adds a one-line hint to check access in the Health app. Android reports denial per type and shows "Not allowed". On Android a partial grant counts as connected when at least one type is granted; the other types show "Not allowed". Android 8 (API 26-27) has no Health Connect, so the summary shows "not available" there. Missing values always show `—`, never `0`.

6. **Dropped per-value fields.** `HEALTH_DATA.md` asks for a platform sample ID and date imported on each value. A no-cache daily glance needs neither, so they are dropped. Type, unit, measured time and source are kept.

7. **Android requirements.** `minSdk = 26`; `MainActivity` extends `FlutterFragmentActivity` (existing export method channel kept); read permissions `READ_SLEEP`, `READ_STEPS`, `READ_RESTING_HEART_RATE`, `READ_WEIGHT`; the `ViewPermissionUsageActivity` privacy-policy alias. `READ_HEALTH_DATA_HISTORY` is not requested; the 30-day limit suffices. iOS gets HealthKit read-only with `NSHealthShareUsageDescription` and no `NSHealthUpdateUsageDescription`.

8. **Store prerequisites** before any store build with health permissions: the privacy policy page (issue #52) live, App Store privacy labels, Google Play Data Safety, and the Health Connect permissions declaration. These are release tasks, not code. Development and TestFlight internal builds may proceed before #52.

## Consequences

- No health value may reach Supabase, the sync outbox, the workout export file, logs or diagnostics. A guard test enforces that `features/sync`, `features/account` (except `account_gate.dart`), `core/storage` and `features/workouts` never import `features/health`.
- Errors map to sealed states (no data, not allowed, couldn't read, unsupported); raw exception text is never logged or shown.
- A new ObjectBox entity requires stable UIDs, committed `objectbox.g.dart` and `objectbox-model.json`, and a test that opens a pre-change database.
- The workout logger, sign-in and sync must keep working when health is unavailable, denied or throwing.
- Adding a cache, more metrics, history, writes or any cloud path needs a new ADR.
- Implemented in source (Tasks 1-5, see [p3-01](../implementation/phase-3/p3-01-daily-health-summary.md)). Not released or device-verified: owner device QA (iPhone with and without Watch, Android 14+, Android 9-13 with and without Health Connect) has not been run.
