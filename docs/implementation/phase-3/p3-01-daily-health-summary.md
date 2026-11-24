# P3-01 Daily health summary (read-only)

**Status:** implemented in source on the Phase 3 branch (Tasks 1-5), **not released or device-verified**. Decision: [ADR-0008](../../adr/0008-daily-health-summary-reads.md). Design: [spec](../../superpowers/specs/2026-11-24-phase-3-health-reads-design.md). Release gates: [RELEASE.md](../../RELEASE.md).

## What exists

- **Metrics:** sleep (asleep, light, deep, REM from local 18:00 the previous day until now, overlaps merged once), steps since local midnight, newest resting heart rate in 7 days, newest weight in 30 days (kg). Missing values show a dash, never zero.
- **Provider:** `health` 14.0.0 (exact pin) behind a `HealthReader` interface. `platform_health_reader.dart` is the only package importer besides `account_gate.dart`, which constructs `Health()` (guard test).
- **Opt-in:** per-account `HealthConnectionEntity` in the account-partitioned ObjectBox store (additive model change, pre-change database fixture test). Holds no health values; erased with the partition on deletion.
- **No health-value cache:** readings live in Riverpod state, re-read on view, resume and pull-to-refresh. Nothing health-related reaches Supabase, the outbox, export, logs or Firebase.
- **UI:** Health tab and Today row render real states (loading, connect, needs install, no data, not allowed, couldn't read, unsupported), using the shared component kit. The hardcoded demo values and the Today insight were removed.
- **Platform behavior:** iOS cannot tell denial from no data, so it shows "No data", treats steps 0 as no data and hints to check the Health app. Android shows "Not allowed" per type; a partial grant is connected when at least one type is granted. Android 8 (API 26-27) has no Health Connect and shows "not available".
- **Native setup (hand-edited, see Task 5):** Android minSdk 26, four `READ_*` permissions, rationale intent filter and `ViewPermissionUsageActivity` alias (`TODO(#52)`), `MainActivity` now extends `FlutterFragmentActivity`; iOS `NSHealthShareUsageDescription` and `Runner.entitlements` (HealthKit, no write usage string).

## Evidence (run in the development container)

| Task | Commit | Checks run |
| --- | --- | --- |
| 2 opt-in flag | 06e1be0 | repository tests 5/5 (incl. pre-health upgrade fixture); full suite 454 |
| 3 controller | ee92711 | controller tests 7/7; full suite 461 |
| 4 UI | da488f7, 94a88ae | format, page, Today row, resume and double-tap tests; full suite 486 |
| 5 reader and native | 8c8cae2 | `flutter test test/health` 53; full suite 505; `dart format`, `flutter analyze` clean; `python3 -m unittest discover -s tool` 71 OK |

Each task followed red-then-green TDD; the reports are kept with the plan notes, not in the repository.

## Not run

- `flutter build apk --debug`: no Android SDK here. The first APK build happens in GitHub Actions on the PR.
- Any Xcode build or archive. The `Runner.xcodeproj` file reference ID for the entitlements file was written by hand and is unverified.
- All physical-device checks: iPhone with and without Apple Watch (grant, deny, revoke); Android 14+ and 9-13 with and without the Health Connect app; partial grant; Android deny twice, then tap Not allowed · Manage (Health Connect may stop showing the sheet); Android source writing only sleep sessions without stages shows No sleep recorded; Android workout JSON export after the `FlutterFragmentActivity` change; account A, sign out, account B shows Connect.
- Store prerequisites (all owner actions, not done): HealthKit capability on the App ID plus regenerated App Store provisioning profile, privacy policy (#52) and Health Connect rationale wiring, App Store privacy labels, Play Data Safety and Health Connect declaration.

## Data ownership and rollback

Health data stays on the device and is read-only; ADR-0005 backup scope is unchanged. Rollback is reverting the source change; the opt-in flag row is inert without the feature. Health writes, history, trends and any cache need a new ADR.
