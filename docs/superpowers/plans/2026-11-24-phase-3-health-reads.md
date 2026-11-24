# Phase 3 Daily Health Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fictional Health tab and Today "Recent health" values with real sleep, steps, resting heart rate and weight read from Apple Health / Health Connect after each BeyondRep account opts in.

**Architecture:** A per-account opt-in flag lives in the account-partitioned ObjectBox store. A `HealthReader` interface (only `platform_health_reader.dart` imports `package:health`) returns one sealed `HealthReading` per metric. A Riverpod `AsyncNotifier` combines flag + reader into `HealthSummaryState`; widgets only render that state. Nothing else is persisted.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, ObjectBox 5.3, `health` 14.0.0 (carp-dk), HealthKit (iOS 15+), Health Connect (Android 8+/API 26).

**Spec:** `docs/superpowers/specs/2026-11-24-phase-3-health-reads-design.md`

## Global Constraints

- Metrics are exactly: sleep (last night), steps (today since local midnight), resting heart rate (newest in last 7 days), weight (newest in last 30 days, kg).
- Missing values render `—`, never `0`. iOS never shows "Not allowed"; iOS steps `0` → no data.
- Health values are never written to disk, Supabase, the outbox, the export file, logs or diagnostics. The only persisted item is the per-account opt-in flag.
- Permission is requested only from a Connect tap. Each BeyondRep account connects separately.
- `health: 14.0.0` exact pin. No other new dependency.
- Features use the `lib/core/design/` kit (`test/design_kit_guard_test.dart`). Widgets make no SDK calls.
- Copy (verbatim): Connect body "See today's sleep, steps, resting heart rate and weight. Read-only; stays on this phone."; iOS usage string "BeyondRep reads your sleep, steps, resting heart rate and weight to show a daily summary. This data stays on your phone."; Disconnect hint "To stop BeyondRep reading health data on this phone, turn it off in Health settings."; iOS hint "Missing something? Check BeyondRep's access in the Health app."
- Repo is public: synthetic data only; no project refs. Do not merge; PRs only.
- From `apps/mobile/` every task ends green on: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, and the task's tests.

## Review Focus

1. **Sign-out then a different account signs in on the same phone** — the second account must see the Connect card, not the first account's numbers (Task 2 and Task 4 tests).
2. **Plugin throws for one metric** (rate limit, unknown) — that card shows "Couldn't read", the other three still render (Task 3 controller test).
3. **Midnight / DST / timezone change while the app is open** — "today" and "last night" windows are computed from the `now` passed in, in local time; a refresh after midnight reads the new day (Task 5 window tests).
4. **Phone + watch both log the same night's sleep** — overlapping segments counted once (Task 5 `mergedSleepMinutes` test).
5. **Android export after switching to `FlutterFragmentActivity`** — JSON export still saves; manual device check recorded in the PR (Task 5).

---

### Task 1: ADR-0008 and policy docs

**Files:**
- Create: `docs/adr/0008-daily-health-summary-reads.md`
- Modify: `docs/HEALTH_DATA.md` (add "Phase 3 scope" section near top), `docs/ROADMAP.md` (Phase 3 paragraph), `CLAUDE.md` ("Not implemented" line stays until Task 6 lands)

- [ ] **Step 1:** Write ADR-0008 with sections Context / Decision / Consequences recording: the four metrics and windows; `health` 14.0.0 chosen over native bridges (Approaches table from the spec); no health-value cache (deviation from HEALTH_DATA's optional cache); per-account opt-in flag in the account partition and why (OS grant is per app); iOS denial is indistinguishable from no data; dropped per-value fields (platform sample ID, imported-at); Android minSdk 26 + `FlutterFragmentActivity`; store prerequisites (privacy policy #52, App Store privacy labels, Play Data Safety, Health Connect declaration).
- [ ] **Step 2:** In `HEALTH_DATA.md` add a short "Phase 3 shipped scope" section linking ADR-0008; in `ROADMAP.md` note Phase 3 scope is "daily summary of four metrics, ADR-0008".
- [ ] **Step 3:** Run `python3 -m unittest discover -s tool -p 'test_*.py'` from repo root. Expected: OK.
- [ ] **Step 4:** Commit `docs: ADR-0008 daily health summary reads`.

---

### Task 2: Per-account health opt-in flag

**Files:**
- Create: `apps/mobile/lib/features/health/data/health_connection_entity.dart`
- Create: `apps/mobile/lib/features/health/data/health_connection_repository.dart`
- Create: `apps/mobile/test/health/fixtures/objectbox_pre_health_connection.g.dart` (frozen copy of current `lib/objectbox.g.dart`, header comment "FROZEN FROM <commit> BEFORE HealthConnectionEntity. Do not regenerate.")
- Modify (generated): `apps/mobile/lib/objectbox.g.dart`, `apps/mobile/lib/objectbox-model.json`
- Test: `apps/mobile/test/health/health_connection_repository_test.dart`

**Interfaces:**
- Produces:
  - `@Entity() class HealthConnectionEntity { @Id() int id = 0; @Unique() String ownerAccountId; int connectedAtMs; }`
  - `abstract interface class HealthConnectionRepository { bool isConnected(String ownerAccountId); void connect(String ownerAccountId, DateTime at); void disconnect(String ownerAccountId); }`
  - `class ObjectBoxHealthConnectionRepository implements HealthConnectionRepository { ObjectBoxHealthConnectionRepository(Store store); }`
  - `final healthConnectionRepositoryProvider = Provider<HealthConnectionRepository>((ref) => ObjectBoxHealthConnectionRepository(ref.watch(objectBoxStoreProvider)));`

- [ ] **Step 1:** Copy the current `lib/objectbox.g.dart` to the fixture path (fix its import of entity files to `package:` paths as the existing fixtures in `test/workouts/fixtures/` do).
- [ ] **Step 2: Write failing tests** (temp-dir `Store`, as in `test/workouts/objectbox_workout_outbox_test.dart`):
  - `new store is not connected` → `isConnected('owner-a')` is `false`.
  - `connect then disconnect` → `true` after `connect`, `false` after `disconnect`; `connect` twice keeps one row (`box.count() == 1`).
  - `flag is per account directory` → open two stores via `accountStoreRelativePath` under a temp root for two synthetic UUIDs; connect A; B's repository `isConnected(B)` is `false`.
  - `account deletion removes flag` → connect A, close store, `deleteBoundAccountStoreAtRoot(root, A, projectHost: 'example.test')`, reopen → `false`.
  - `pre-health DB upgrades` → open with `pre.getObjectBoxModel()`, put one `WorkoutSessionEntity`, close, reopen with `getObjectBoxModel()`; session still there and `HealthConnectionEntity` box count is 0.
- [ ] **Step 3:** Run `flutter test test/health/health_connection_repository_test.dart`. Expected: FAIL (types undefined).
- [ ] **Step 4:** Implement entity and repository; run `dart run build_runner build --delete-conflicting-outputs`; confirm `objectbox-model.json` only *adds* an entity (existing UIDs unchanged: `git diff lib/objectbox-model.json`).
- [ ] **Step 5:** Run the test file and `flutter test test/workouts test/sync`. Expected: PASS.
- [ ] **Step 6:** Commit `feat(health): per-account health opt-in flag`.

---

### Task 3: Reader interface, summary controller, fake

**Files:**
- Create: `apps/mobile/lib/features/health/data/health_reader.dart`
- Create: `apps/mobile/lib/features/health/application/health_summary_controller.dart`
- Create: `apps/mobile/test/support/fake_health_reader.dart`
- Test: `apps/mobile/test/health/health_summary_controller_test.dart`

**Interfaces:**
- Consumes: `healthConnectionRepositoryProvider`, `accountAuthControllerProvider` (`userId`) from Task 2 / existing code.
- Produces (`health_reader.dart`, no plugin import; name avoids the plugin's own `HealthValue`):
  ```dart
  enum HealthMetric { sleep, steps, restingHeartRate, weight }
  enum HealthPlatformKind { appleHealth, healthConnect }
  enum HealthAvailability { available, needsInstall, unsupported }
  sealed class HealthReading { const HealthReading(); }
  final class HealthMeasured extends HealthReading {
    // sleep: minutes asleep; steps: count; restingHeartRate: bpm; weight: kg
    const HealthMeasured({required this.value, required this.measuredAt, required this.source});
    final double value; final DateTime measuredAt; final String source; }
  final class HealthNoData extends HealthReading { const HealthNoData(); }
  final class HealthNotAllowed extends HealthReading { const HealthNotAllowed(); }
  final class HealthReadFailed extends HealthReading { const HealthReadFailed(); }
  final class HealthUnsupported extends HealthReading { const HealthUnsupported(); }
  abstract interface class HealthReader {
    HealthPlatformKind get platform;
    Future<HealthAvailability> availability();
    Future<void> requestAccess();          // one sheet for all four types
    Future<void> openInstall();            // Android: installHealthConnect
    Future<HealthReading> read(HealthMetric metric, DateTime now); // never throws
  }
  final healthReaderProvider = Provider<HealthReader>((ref) => throw UnimplementedError()); // overridden in Task 5
  ```
- Produces (`health_summary_controller.dart`):
  ```dart
  sealed class HealthSummaryState { const HealthSummaryState(); }
  final class HealthNotConnected extends HealthSummaryState { final HealthAvailability availability; final HealthPlatformKind platform; }
  final class HealthConnected extends HealthSummaryState { final Map<HealthMetric, HealthReading> readings; final DateTime readAt; final HealthPlatformKind platform; }
  class HealthSummaryController extends AsyncNotifier<HealthSummaryState> {
    Future<void> refresh(); Future<void> connect(); Future<void> disconnect(); }
  final healthSummaryProvider = AsyncNotifierProvider<HealthSummaryController, HealthSummaryState>(HealthSummaryController.new);
  final healthClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
  ```
  `FakeHealthReader` (test support): settable `availabilityResult`, `readings` map, `requestAccessCalls`, `readCalls`, and `throwOn` set of metrics.

- [ ] **Step 1: Write failing tests** (`ProviderContainer` with overrides for reader, repository on a temp store, auth with synthetic userId, fixed clock `DateTime(2026, 11, 24, 18, 20)`):
  - `not connected by default` → state is `HealthNotConnected`, `fake.readCalls` is empty (no platform reads before opt-in).
  - `connect requests access, stores flag, reads four metrics` → after `connect()`: `requestAccessCalls == 1`, `repo.isConnected(owner)`, state `HealthConnected` with 4 keys.
  - `one failing metric does not blank others` → `throwOn = {steps}` on a fake whose `read` throws; state readings[steps] is `HealthReadFailed`, sleep is the fake's `HealthMeasured`.
  - `disconnect clears flag and stops reading` → `HealthNotConnected`, `repo.isConnected(owner)` false.
  - `different account sees not connected` → connect as A; new container with same store dir but auth userId B → `HealthNotConnected`.
  - `needsInstall is surfaced` → availability `needsInstall` → `HealthNotConnected(availability: needsInstall)`; `connect()` calls `openInstall`, not `requestAccess`.
- [ ] **Step 2:** Run `flutter test test/health/health_summary_controller_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement. `build()`: if no flag → `HealthNotConnected(await reader.availability(), reader.platform)`; else read four metrics with `Future.wait` using `healthClockProvider()`; wrap each `read` in a catch-all mapping to `HealthReadFailed` (defence against a reader bug). `connect()` when available: `requestAccess()` then `repo.connect(owner, now)` (regardless of the bool), then `ref.invalidateSelf()`.
- [ ] **Step 4:** Run the test. Expected: PASS.
- [ ] **Step 5:** Commit `feat(health): health summary state and reader interface`.

---

### Task 4: Health tab UI and Today row

**Files:**
- Create: `apps/mobile/lib/features/health/widgets/health_metric_card.dart`
- Create: `apps/mobile/lib/features/health/widgets/health_connect_card.dart`
- Create: `apps/mobile/lib/features/health/widgets/today_health_row.dart`
- Create: `apps/mobile/lib/features/health/health_format.dart` (pure caption/value formatting)
- Modify: `apps/mobile/lib/features/health/health_page.dart` (full rewrite to `ConsumerWidget`)
- Modify: `apps/mobile/lib/features/today/today_page.dart:88-137` (replace hardcoded row with `TodayHealthRow`; delete "One useful context" insight; delete `_Metric` if unused)
- Test: `apps/mobile/test/health/health_format_test.dart`, `apps/mobile/test/health/health_page_test.dart`, `apps/mobile/test/today/today_health_row_test.dart`

**Interfaces:**
- Consumes: `healthSummaryProvider`, `HealthReading` types (Task 3).
- Produces: `String formatHealthValue(HealthMetric m, HealthReading r)`, `String formatHealthCaption(HealthMetric m, HealthReading r, HealthPlatformKind p, DateTime now)`, `class HealthMetricCard extends StatelessWidget { HealthMetricCard({required HealthMetric metric, required HealthReading reading, required HealthPlatformKind platform, required DateTime now, VoidCallback? onAction}); }`.

- [ ] **Step 1: Write failing format tests** (`now = DateTime(2026, 11, 24, 18, 20)`):
  - sleep `HealthMeasured(value: 378, measuredAt: 24 Nov 06:52, source: 'Apple Watch')` → value `6h 18m`, caption `Apple Watch · ended 6:52 AM`.
  - steps 6420 → `6,420`, caption `Apple Health · as of 6:20 PM` (Android: `Health Connect · as of 6:20 PM`).
  - resting HR 58 measured today 07:10 → `58 bpm`, `Apple Watch · today 7:10 AM`; measured 21 Nov → `… · 21 Nov`.
  - weight 74.2 → `74.2 kg`, `Withings · 22 Nov`.
  - `HealthNoData` → value `—`; captions `No sleep recorded last night` / `No steps yet today` / `None in the last 7 days` / `None in the last 30 days`.
  - `HealthNotAllowed` → `—`, `Not allowed · Manage`; `HealthReadFailed` → `Couldn't read · Try again`; `HealthUnsupported` → `Not available on this device`.
- [ ] **Step 2: Write failing widget tests** (override `healthSummaryProvider` with fixed states):
  - not connected → finds Connect body copy verbatim and a `Connect` action; no `FICTIONAL DEMO DATA`, no `Imported activities`.
  - not connected + `needsInstall` → action text `Get Health Connect`.
  - not connected + `unsupported` → `Health Connect isn't available on this phone` and no action.
  - connected mixed (sleep measured, steps no data, HR not allowed, weight failed) → four cards with expected texts; `0` appears nowhere as a value.
  - connected on `appleHealth` with any `HealthNoData` → iOS hint shown once; on `healthConnect` it is not.
  - `Disconnect` tap calls controller `disconnect` and the hint copy is shown beside it.
  - tablet width 900 → two columns; dark theme and `textScaler: TextScaler.linear(2)` render without overflow exceptions.
  - Today row: not connected → compact Connect card; connected → three cards (sleep, steps, resting HR), no weight; no "52 min shorter" insight.
- [ ] **Step 3:** Run `flutter test test/health test/today`. Expected: FAIL.
- [ ] **Step 4:** Implement. Cards reuse the existing `_Stat` look moved into `HealthMetricCard` (with `Semantics` label `"$name: $value. $caption"`); Connect card uses `InsightCard(actionLabel:, onAction:)`. "Not allowed · Manage" and "Try again" taps call `connect()` / `refresh()`. Pull-to-refresh via `RefreshIndicator` on the Health `ListView`. Refresh on resume with an `AppLifecycleListener` in `HealthPage` and `TodayHealthRow` calling `ref.invalidate(healthSummaryProvider)`. Drop the "FICTIONAL DEMO DATA" eyebrow: `PageHeader(title: 'Health')`.
- [ ] **Step 5:** Run `flutter test test/health test/today test/design_kit_guard_test.dart test/app_test.dart`. Expected: PASS (update any `app_test` expectations that asserted demo values).
- [ ] **Step 6:** Commit `feat(health): real daily summary UI with connect and empty states`.

---

### Task 5: `health` plugin reader and native setup

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (`health: 14.0.0`), `pubspec.lock`
- Create: `apps/mobile/lib/features/health/data/platform_health_reader.dart`
- Create: `apps/mobile/lib/features/health/data/sleep_merge.dart`
- Modify: `apps/mobile/lib/features/account/account_gate.dart:103` (add `healthReaderProvider.overrideWithValue(PlatformHealthReader(Health()))`)
- Modify: `apps/mobile/ios/Runner/Info.plist` (`NSHealthShareUsageDescription`), create/modify `apps/mobile/ios/Runner/Runner.entitlements` (`com.apple.developer.healthkit` = true, `com.apple.developer.healthkit.access` = empty array) and wire `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj` for all three configs
- Modify: `apps/mobile/android/app/build.gradle.kts:22` (`minSdk = 26`)
- Modify: `apps/mobile/android/app/src/main/kotlin/in/beyondrep/app/MainActivity.kt` (base class `FlutterFragmentActivity` only; no other line changes)
- Modify: `apps/mobile/android/app/src/main/AndroidManifest.xml` (`android.permission.health.READ_SLEEP`, `READ_STEPS`, `READ_RESTING_HEART_RATE`, `READ_WEIGHT`; `<queries><package android:name="com.google.android.apps.healthdata"/></queries>`; `ACTION_SHOW_PERMISSIONS_RATIONALE` intent filter on MainActivity; `ViewPermissionUsageActivity` `activity-alias` with `android.intent.action.VIEW_PERMISSION_USAGE` + `android.intent.category.HEALTH_PERMISSIONS`, targeting MainActivity)
- Test: `apps/mobile/test/health/platform_health_reader_test.dart`, `apps/mobile/test/health/sleep_merge_test.dart`, `apps/mobile/test/health/health_import_guard_test.dart`

**Interfaces:**
- Consumes: `HealthReader` and reading types (Task 3).
- Produces: `class PlatformHealthReader implements HealthReader { PlatformHealthReader(Health health, {HealthPlatformKind? platform}); }`; `int mergedSleepMinutes(List<({DateTime from, DateTime to})> segments)`; `String friendlySource(String sourceName, HealthPlatformKind p)`.

- [ ] **Step 1: Write failing tests.**
  - `sleep_merge_test`: overlapping `[23:00–03:00]` and `[02:00–06:30]` → `450`; identical duplicate segments → counted once; empty → `0`; segment crossing midnight on a DST-change date (use `DateTime.utc`) → correct minutes.
  - `platform_health_reader_test` with `class _FakeHealth extends Fake implements Health` (from `flutter_test`):
    - steps 6420 → `HealthMeasured(6420, measuredAt: now, source: 'Apple Health')`; steps `0` → `HealthNoData` on both platforms.
    - steps throws `HealthPlatformException` `permissionDenied` on `healthConnect` → `HealthNotAllowed`; same on `appleHealth` → `HealthNoData`.
    - Android `hasPermissions([type])` false for weight → `HealthNotAllowed` without calling `getHealthDataFromTypes`.
    - `notSupported` → `HealthUnsupported`; any other exception → `HealthReadFailed`.
    - windows: steps queried `[2026-11-24 00:00 local, now]`; sleep `[2026-11-23 18:00, now]` with types `SLEEP_ASLEEP, SLEEP_LIGHT, SLEEP_DEEP, SLEEP_REM`; resting HR `[now-7d, now]` `limit: 1`; weight `[now-30d, now]` `limit: 1`, newest by `dateTo`.
    - sleep with points → value from `mergedSleepMinutes`, `measuredAt` = latest `dateTo`, source = friendly names joined `', '`.
    - `availability()`: `sdkAvailable` → `available`; `sdkUnavailableProviderUpdateRequired` → `needsInstall`; `sdkUnavailable` → `unsupported`; iOS → `available`.
    - `friendlySource`: `com.google.android.apps.fitness` → `Fit`; unknown bundle/package → `Apple Health` / `Health Connect`; never returns a raw ID containing `.`.
  - `health_import_guard_test`: scanning `lib/`, only `lib/features/health/data/platform_health_reader.dart` and `lib/features/account/account_gate.dart` contain `package:health/`; no file under `lib/features/sync`, `lib/features/account` (except the gate's provider override import), `lib/core/storage` or `lib/features/workouts` imports `features/health/` except `account_gate.dart`.
- [ ] **Step 2:** Run `flutter test test/health`. Expected: new tests FAIL.
- [ ] **Step 3:** `flutter pub add health:14.0.0` (then confirm exact pin in `pubspec.yaml`), implement `sleep_merge.dart` (sort by start, merge overlapping/adjacent, sum minutes) and `PlatformHealthReader` (call `health.configure()` once lazily; on `healthConnect` check `hasPermissions([type])` before each read; map `HealthErrorCode` per tests; never log exception text).
- [ ] **Step 4:** Native setup per Files list. Privacy-policy target for the rationale intent: MainActivity receives it; until #52 ships, the app opens `https://beyondrep.in/privacy` — add a `// TODO(#52)` comment, no other behaviour.
- [ ] **Step 5:** Run `flutter test`, `flutter analyze`, `dart format --output=none --set-exit-if-changed lib test`, `flutter build apk --debug --no-pub`. Expected: all pass; APK builds.
- [ ] **Step 6:** Record in the PR body the manual device checks as run / not run: iPhone ± Apple Watch grant/deny/revoke; Android 14+ and Android 9–13 ± Health Connect app; partial grant; **Android workout JSON export still saves after `FlutterFragmentActivity`**; account A→sign out→account B shows Connect.
- [ ] **Step 7:** Commit `feat(health): read HealthKit and Health Connect via health 14.0.0`.

---

### Task 6: Status docs and release notes

**Files:**
- Modify: `CLAUDE.md` (move HealthKit/Health Connect *reads* from "Not implemented" to implemented-in-source, keep writes/Firebase/watch as not implemented), `docs/RELEASE.md` (Phase 3 release gates: #52 privacy policy live, App ID HealthKit capability enabled in Apple portal and profile regenerated, App Store privacy labels, Play Data Safety + Health Connect declaration, manual device matrix), `docs/implementation/README.md` + new `docs/implementation/phase-3/p3-01-daily-health-summary.md` (PR evidence, tests run, unrun checks).

- [ ] **Step 1:** Write the docs; state plainly which device checks were not run.
- [ ] **Step 2:** Run `python3 -m unittest discover -s tool -p 'test_*.py'` from repo root and full `flutter test`. Expected: OK / PASS.
- [ ] **Step 3:** Commit `docs: Phase 3 daily health summary status and release gates`.

## PR split

One PR per task in order (Task 1 and 6 may be combined with neighbours if small). Each PR: AI disclosure, checks actually run, device checks "not run" unless done. Agents open PRs; the owner merges.
