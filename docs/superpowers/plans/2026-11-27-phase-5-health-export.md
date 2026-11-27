# Phase 5: Save Phone Workouts to Apple Health / Health Connect — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in, per-account switch that saves every completed phone workout (past and new) to Apple Health / Health Connect exactly once, with durable local receipts, retry, delete-follows, and no duplicate of any Apple Watch `HKWorkout`.

**Architecture:** A pure planner compares this account's completed phone workouts with export receipts and watch receipts and returns actions (write, adopt, skip, delete, supersede). An exporter runs one serialized pass of those actions against a `HealthWorkoutWriter` (over the `health` 14.0.0 plugin), committing a receipt before and after each platform call. Kicks come from finish, delete, watch link/import, switch-on, resume and sign-in. The finish/delete transactions and the cloud outbox are not changed.

**Tech Stack:** Flutter 3.47.7, Riverpod, ObjectBox 5.3.2 (`build_runner` codegen), `health` 14.0.0 (no new dependency).

**Spec:** `docs/superpowers/specs/2026-11-27-phase-5-health-export-design.md` (approved by Adi 2026-11-27). Read it first; this plan does not repeat its reasoning.

## Global Constraints

- Only workouts with `status == 'completed'`, `completedAtMs != null`, `deletedAtMs == null`, `origin == 'northstar_phone'` are ever written. Never `beyondrep_watch`, never outside workouts.
- The record: iOS `HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING`, Android `HealthWorkoutActivityType.STRENGTH_TRAINING`; start `startedAtMs`, end `completedAtMs`; Android `title` = workout name, zone offsets = `originalOffsetMinutes`; iOS `WorkoutMetadata(workoutBrandName: 'BeyondRep', indoorWorkout: true, syncIdentifier: uuid, syncVersion: version)`; Android `clientRecordId: uuid`, `clientRecordVersion: version.toDouble()`. `uuid` is the lowercase workout uuid, `version` is the workout's `updatedAtMs`. No energy, no distance, no HR.
- Platform ids, receipts and the switch are local ObjectBox only. Never in the outbox, Supabase, the JSON export, logs or analytics.
- No write when signed out, when the switch row is absent, or when the store is unavailable. Switch off ⇒ no writes and no deletes.
- At most 50 platform writes per pass, oldest `completedAtMs` first.
- iOS with a paired Apple Watch that has the app installed: a workout is not written until 10 minutes after `completedAtMs`.
- New permissions: iOS `HealthDataType.WORKOUT` with `HealthDataAccess.READ_WRITE`; Android manifest `android.permission.health.WRITE_EXERCISE`. Nothing else (Wear OS thread adds HR/calories writes later).
- `NSHealthUpdateUsageDescription` = `BeyondRep writes the workouts you finish on this phone to Apple Health when you turn on saving in the Health tab.`
- UI uses only the component kit (`NsListCard`, `showNsSheet`, `showNsConfirm`, `NsStatusLine`, `showNsMessage`); `test/design_kit_guard_test.dart` must pass. No new kit component.
- ObjectBox: new entities get stable UIDs; commit `lib/objectbox.g.dart` and `lib/objectbox-model.json`; old-database migration test.
- Keep edits to shared health files (`platform_health_reader.dart`, `health_reader.dart`, `health_page.dart`, `AndroidManifest.xml`, `Info.plist`) small and additive: an energy-score thread and a Wear OS thread work on health code in parallel.
- Checks from `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`; from repo root `python3 -m unittest discover -s tool -p 'test_*.py'`.

## Review Focus

1. **Crash between platform write and `confirmed`** (receipt left `writing`): the next pass must not create a second entry. Test in Task 4 (`resumes a writing receipt by adopting the own copy on iOS` and `rewrites with the same id on Android`).
2. **`workout_link` arrives after the phone saved:** our copy is deleted and the receipt is `supersededByWatch`; a later pass never rewrites it. Test in Task 4.
3. **Account switch or sign-out mid-pass:** a pass started for account A writes no receipt into B's store and stops before the next platform call. Test in Task 4 (`stops when the account changes mid-pass`).
4. **Permission revoked after confirm:** a later delete or rewrite gets `permissionDenied` ⇒ `blocked`, the row says "Allow access in Settings", and the pass after access returns retries. Tests in Task 4 and Task 6.
5. **Our written workout read back as an outside workout** (double training load): `_isOwnSource` drops source `in.beyondrep.app`. Test in Task 3 (`own written workout is not an outside workout`).

---

### Task 1: Export setting and receipt storage

**Files:**
- Create: `lib/features/health/data/health_export_entities.dart` (`HealthExportSettingEntity`, `HealthExportReceiptEntity`)
- Create: `lib/features/health/data/health_export_repository.dart`
- Create: `test/workouts/fixtures/objectbox_pre_health_export.g.dart` (copy of the current generated model before the change, the same way `objectbox_pre_watch_receipts.g.dart` was made)
- Modify (generated): `lib/objectbox.g.dart`, `lib/objectbox-model.json`
- Test: `test/health/health_export_repository_test.dart`, `test/health/objectbox_health_export_migration_test.dart`

**Interfaces:**
- Produces:
  - `enum HealthExportState { writing, confirmed, failedRetryable, blocked, skippedWatch, supersededByWatch, deleting }` with `String wire` (camelCase names as wire) and `static HealthExportState? fromWire(String)`.
  - `HealthExportSettingEntity { int id; @Unique String ownerAccountId; int enabledAtMs; }`
  - `HealthExportReceiptEntity { int id; @Unique String workoutUuid; String platform /* 'healthkit' | 'health_connect' */; String state; int exportedVersion /* 0 = none */; String? platformRecordId; int attempts; int lastAttemptAtMs; int updatedAtMs; }`
  - `abstract interface class HealthExportRepository { bool isEnabled(String owner); void enable(String owner, DateTime at); void disable(String owner); HealthExportReceiptEntity? receipt(String workoutUuid); List<HealthExportReceiptEntity> allReceipts(); void putReceipt(HealthExportReceiptEntity r); void removeReceipt(String workoutUuid); }`
  - `class ObjectBoxHealthExportRepository implements HealthExportRepository` taking `Store`.
  - `final healthExportRepositoryProvider = Provider<HealthExportRepository>((ref) => ObjectBoxHealthExportRepository(ref.watch(objectBoxStoreProvider)));`

- [x] **Step 1: Write the failing tests**
  - `enable then isEnabled is true; disable removes the row; enable twice keeps one row`.
  - `putReceipt upserts by workoutUuid (second put with same uuid replaces, one row)`; `removeReceipt deletes`; `receipt returns null for unknown`; workout uuid stored lowercase (`putReceipt` with `'AB…'` → `receipt('ab…')` finds it).
  - Migration: open a store with `legacy.getObjectBoxModel()` from the new fixture, put one `WorkoutSessionEntity`, close; open with `getObjectBoxModel()`; the session is there, both new boxes are empty and accept a row.
- [x] **Step 2: Run** `flutter test test/health/health_export_repository_test.dart test/health/objectbox_health_export_migration_test.dart` — expected FAIL (missing files).
- [x] **Step 3: Create the fixture first** (copy `lib/objectbox.g.dart` to the fixture path, rename as the existing pre-* fixtures do), then add the entities and the repository, then run `dart run build_runner build --delete-conflicting-outputs`.
- [x] **Step 4: Run the two test files** — expected PASS. Also run `flutter test test/watch/objectbox_watch_receipt_migration_test.dart` (older migrations still open).
- [x] **Step 5: Commit** `feat(health): add health export setting and receipt entities`.

### Task 2: Pure export planner

**Files:**
- Create: `lib/features/health/domain/workout_health_export.dart`
- Test: `test/health/domain/workout_health_export_test.dart`

**Interfaces:**
- Consumes: `HealthExportState` (Task 1). No ObjectBox or Flutter imports (keeps `health_import_guard_test.dart` green).
- Produces:
  - `class ExportCandidate { final String uuid; final String name; final String origin; final String status; final DateTime startedAt; final DateTime? completedAt; final bool deleted; final int version; final int offsetMinutes; }`
  - `class ExportReceiptView { final String workoutUuid; final HealthExportState state; final int exportedVersion; final String? platformRecordId; final int attempts; final DateTime lastAttemptAt; }`
  - `sealed class ExportAction` with `WriteWorkout(ExportCandidate c, {required bool resumeUncertain})`, `DeleteOwnCopy(String workoutUuid, String? platformRecordId)`, `SupersedeByWatch(String workoutUuid, String? platformRecordId)`, `LookupDeletedCopy(ExportCandidate c)` (iOS only: deleted workout with no receipt).
  - `List<ExportAction> planHealthExport({required List<ExportCandidate> workouts, required Map<String, ExportReceiptView> receipts, required Set<String> watchLinkedWorkoutUuids, required bool watchPaired, required bool isIos, required DateTime now, int maxWrites = 50})`

Rules (in this order per workout):
1. Origin ≠ `northstar_phone`, or not completed: nothing.
2. In `watchLinkedWorkoutUuids`: if receipt is `confirmed` or `writing` ⇒ `SupersedeByWatch`; else nothing.
3. Deleted: receipt `confirmed`/`writing`/`deleting` ⇒ `DeleteOwnCopy`; no receipt and `isIos` ⇒ `LookupDeletedCopy`; else nothing.
4. Receipt `skippedWatch` or `supersededByWatch`: nothing, ever.
5. Receipt `confirmed` with `exportedVersion >= version`: nothing.
6. Receipt `failedRetryable`: only when `now - lastAttemptAt >= min(2^(attempts-1) minutes, 60 minutes)`.
7. Receipt `blocked`: write (the exporter checks access first; see Task 4).
8. `isIos && watchPaired && now - completedAt < 10 minutes`: nothing yet.
9. Otherwise ⇒ `WriteWorkout(resumeUncertain: receipt?.state == writing)`.
Writes are sorted by `completedAt` ascending and cut at `maxWrites`; deletes and supersedes are not capped and come first.

- [x] **Step 1: Write failing tests**, one per rule above plus: `orders writes oldest first and caps at 50 (60 eligible → 50, the 50 oldest)`; `deletes and supersedes come before writes and are not capped`; `version bump on a confirmed workout rewrites`; `watch-origin workout is never written even with no receipts`; `Android deleted workout without receipt plans nothing`; `failedRetryable with attempts 3 waits 4 minutes, attempts 10 waits 60`.
- [x] **Step 2: Run** `flutter test test/health/domain/workout_health_export_test.dart` — expected FAIL.
- [x] **Step 3: Implement** `planHealthExport` and the value types.
- [x] **Step 4: Run** — expected PASS.
- [x] **Step 5: Commit** `feat(health): plan which workouts to save to the health store`.

### Task 3: Platform workout writer and native declarations

**Files:**
- Create: `lib/features/health/data/health_workout_writer.dart`
- Create: `test/support/fake_health_workout_writer.dart`
- Modify: `ios/Runner/Info.plist` (`NSHealthUpdateUsageDescription`, exact text in Global Constraints)
- Modify: `android/app/src/main/AndroidManifest.xml` (add `WRITE_EXERCISE` next to `READ_EXERCISE`)
- Modify: `tool/test_ios_privacy_strings.py` only if needed (current check `"write" in value.lower()` already fits the new text; add an assertion that the value does not contain `does not write`)
- Test: `test/health/health_workout_writer_test.dart`, add one case to `test/health/platform_health_reader_test.dart`

**Interfaces:**
- Produces:
  - `class HealthWorkoutRecord { final String workoutUuid; final String name; final DateTime start; final DateTime end; final int offsetMinutes; final int version; }` (Wear OS stage extends it later with optional HR samples and calories; do not add them now).
  - `sealed class HealthWriteResult`: `HealthWriteOk(String platformRecordId)`, `HealthWriteDenied()`, `HealthWriteFailed()`, `HealthWriteUnavailable()`.
  - `class OwnStoredWorkout { final String platformRecordId; final String sourceId; final DateTime start; final DateTime end; }`
  - `abstract interface class HealthWorkoutWriter { String get platform; /* 'healthkit' | 'health_connect' */ bool get isIos; Future<bool> isAvailable(); Future<bool> requestAccess(); Future<bool> hasWriteAccess(); Future<HealthWriteResult> write(HealthWorkoutRecord r); Future<HealthWriteResult> delete(String workoutUuid, String? platformRecordId); Future<List<OwnStoredWorkout>?> beyondRepWorkoutsIn(DateTime start, DateTime end); }` — `beyondRepWorkoutsIn` returns workouts whose source is `in.beyondrep.app` or starts with `in.beyondrep.app.`, null on read failure.
  - `class PlatformHealthWorkoutWriter implements HealthWorkoutWriter` taking a `Health` instance (and an `isIos` flag for tests, defaulting to `Platform.isIOS`).
  - `final healthWorkoutWriterProvider = Provider<HealthWorkoutWriter>((ref) => PlatformHealthWorkoutWriter(Health()));` (tests and `account_gate.dart` overrides follow the `healthReaderProvider` pattern).
  - `FakeHealthWorkoutWriter` records calls, scripted results, and an in-memory store list for `beyondRepWorkoutsIn`.

Mapping: `write` calls `writeWorkoutDataUUID` with the Global Constraints values; non-empty uuid ⇒ `HealthWriteOk` (Android: use `clientRecordId` = workout uuid as the record id when the returned string is empty but the call returned without error). `HealthException` with `HealthErrorCode.permissionDenied` ⇒ `HealthWriteDenied`; Health Connect unavailable ⇒ `HealthWriteUnavailable`; any other exception or empty result ⇒ `HealthWriteFailed`. `delete`: iOS `deleteByUUID(uuid: platformRecordId, type: HealthDataType.WORKOUT)`, Android `deleteByClientRecordId(dataTypeKey: HealthDataType.WORKOUT, clientRecordId: workoutUuid)`; a record already gone counts as Ok. `requestAccess`: `requestAuthorization([HealthDataType.WORKOUT], permissions: [HealthDataAccess.READ_WRITE])`. `hasWriteAccess`: `hasPermissions([WORKOUT], permissions: [READ_WRITE])` on Android; on iOS `hasPermissions` with `WRITE` (HealthKit reports write status truthfully). Never log values or exception text.

- [x] **Step 1: Write failing tests** with a mocked method channel (as `platform_health_reader_test.dart` does): `write sends strength training, brand BeyondRep, syncIdentifier and syncVersion on iOS`; `write sends clientRecordId, clientRecordVersion, title and zone offsets on Android`; `no energy or distance argument is sent`; `permission error maps to HealthWriteDenied`; `delete uses deleteByUUID with WORKOUT on iOS and deleteByClientRecordId on Android`; `beyondRepWorkoutsIn keeps in.beyondrep.app and in.beyondrep.app.watchkitapp, drops in.beyondrep.apple and other apps`. In the reader test: `own written workout is not an outside workout` (source `in.beyondrep.app`).
- [x] **Step 2: Run** those files — expected FAIL.
- [x] **Step 3: Implement** the writer, the fake, and the native declarations.
- [x] **Step 4: Run** the files plus `python3 -m unittest tool.test_ios_privacy_strings` from the repo root — expected PASS.
- [x] **Step 5: Commit** `feat(health): add a workout writer for Apple Health and Health Connect`.

### Task 4: Exporter pass (state machine)

**Files:**
- Create: `lib/features/health/application/workout_health_exporter.dart`
- Test: `test/health/workout_health_exporter_test.dart` (real ObjectBox store in a temp dir, `FakeHealthWorkoutWriter`)

**Interfaces:**
- Consumes: Task 1 repository, Task 2 `planHealthExport`, Task 3 writer.
- Produces:
  - `class WorkoutHealthExporter { WorkoutHealthExporter({required Store store, required String accountId, required HealthExportRepository repository, required HealthWorkoutWriter writer, required bool Function() stillCurrent, required bool Function() watchPaired, required DateTime Function() clock}); Future<ExportPassResult> runPass(); }`
  - `class ExportPassResult { final int saved; final int waiting; final bool blocked; }` — `saved` = receipts `confirmed`; `waiting` = wanted workouts not confirmed (excluding skipped/superseded); `blocked` = any receipt `blocked`.

Behaviour:
- Read sessions (`WorkoutSessionEntity`), receipts, and `WatchWorkoutReceiptEntity` rows with a non-null `platformWorkoutUuid` from `store`; build the planner inputs; return early (zeros) when `!repository.isEnabled(accountId)` or `!await writer.isAvailable()`.
- If any planned action exists and `!await writer.hasWriteAccess()`: mark every receipt the pass would touch `blocked` (create it if missing), return.
- Before **every** platform call and every receipt write, check `stillCurrent()`; stop when false.
- `WriteWorkout`: on iOS without a `confirmed` receipt, call `beyondRepWorkoutsIn(start - 1 min, end + 1 min)`:
  - a result from a source other than exactly `in.beyondrep.app` overlapping by the 50% rule (make the private `_sameRange` in `lib/features/health/domain/outside_workouts.dart` public as `overlapsByHalf(aStart, aEnd, bStart, bEnd)` and reuse it; existing callers keep working) ⇒ receipt `skippedWatch`, no write;
  - a result from `in.beyondrep.app` whose start and end equal the workout's to the second ⇒ adopt its id: receipt `confirmed`, `exportedVersion = version`, no write;
  - null (read failed) or nothing matching ⇒ continue.
  Then put receipt `writing` (attempts+1, lastAttempt = now), call `write`, then `Ok` ⇒ `confirmed` with id and version; `Denied` ⇒ `blocked`; `Failed`/`Unavailable` ⇒ `failedRetryable`.
- `DeleteOwnCopy`: put `deleting`, call `delete`, `Ok` ⇒ `removeReceipt`; `Denied` ⇒ `blocked` (kept, retried later); other ⇒ stays `deleting`.
- `LookupDeletedCopy` (iOS): `beyondRepWorkoutsIn` window; an exact `in.beyondrep.app` match ⇒ `delete`; no receipt is kept either way.
- `SupersedeByWatch`: `delete` our copy (when we have an id), then receipt `supersededByWatch`.
- One pass at a time per exporter instance: a second `runPass` while running sets a rerun flag and returns the running pass's future.

- [x] **Step 1: Write failing tests:** `saves a completed phone workout and confirms the receipt`; `saves all past workouts in two passes when there are 60` (50 then 10); `does nothing when the switch is off`; `marks blocked without write access and writes after access is granted`; `resumes a writing receipt by adopting the own copy on iOS` (fake store holds a matching `in.beyondrep.app` workout: no `write` call, receipt `confirmed`); `rewrites with the same id on Android after a crash` (receipt `writing` → one `write` with the same `clientRecordId`, then `confirmed`); `skips when the watch already saved an overlapping workout`; `link after confirm deletes our copy and marks supersededByWatch, and a later pass writes nothing`; `deleting a confirmed workout deletes the platform copy and removes the receipt`; `delete denied keeps the receipt blocked`; `iOS restored tombstone with an own copy deletes it`; `failure marks failedRetryable and the next pass within the backoff writes nothing`; `stops when the account changes mid-pass` (`stillCurrent` flips after the first write: one write, no further receipts); `waits 10 minutes on iOS with a paired watch`; `revision bump (updatedAtMs) on a confirmed workout writes again with the new version`.
- [x] **Step 2: Run** `flutter test test/health/workout_health_exporter_test.dart` — expected FAIL.
- [x] **Step 3: Implement** `WorkoutHealthExporter`.
- [x] **Step 4: Run** — expected PASS.
- [x] **Step 5: Commit** `feat(health): save workouts to the health store with receipts and retry`.

### Task 5: Controller, kicks and the host

**Files:**
- Create: `lib/features/health/application/workout_health_export_controller.dart`
- Create: `lib/features/health/application/health_export_host.dart`
- Modify: `lib/features/account/account_gate.dart` (wrap `CatalogRefreshHost(child: BeyondRepApp())` with `HealthExportHost`; add `healthWorkoutWriterProvider` override where `healthReaderProvider` is overridden, if the gate overrides it for tests)
- Modify: `lib/features/train/active_workout_page.dart` (after the existing `workoutUploadKickProvider` call)
- Modify: `lib/features/progress/workout_history_detail_page.dart` (after a successful delete)
- Modify: `lib/features/watch/application/watch_workout_inbox.dart` (`onLinked` and `onStored` also kick)
- Test: `test/health/workout_health_export_controller_test.dart`, `test/health/health_export_host_test.dart`

**Interfaces:**
- Consumes: Tasks 1, 3, 4; `healthOwnerIdProvider`, `objectBoxStoreProvider`, `watchStatusProvider` (paired + app installed ⇒ `watchPaired`), `accountAuthControllerProvider`.
- Produces:
  - `sealed class HealthExportStatus`: `HealthExportUnavailable()`, `HealthExportOff()`, `HealthExportOn({required int saved, required int waiting, required bool needsAccess})`.
  - `final healthExportControllerProvider = AsyncNotifierProvider<HealthExportController, HealthExportStatus>(...)` with methods `Future<void> turnOn()` (enable row, `requestAccess`, run a pass), `Future<void> turnOff()` (disable row), `Future<void> runPass()` (rebuilds state from `ExportPassResult`), `Future<void> openSettings()` (delegates to `healthReaderProvider.openSettings()`).
  - `final healthExportKickProvider = Provider<void Function()>((ref) => () => unawaited(ref.read(healthExportControllerProvider.notifier).runPass()));`
  - `HealthExportHost` (`ConsumerStatefulWidget`, `WidgetsBindingObserver`): kick after first frame, on `AppLifecycleState.resumed`, and when the signed-in user id changes to non-null. Mirrors `CatalogRefreshHost`.
- `stillCurrent` for the exporter = the signed-in user id still equals the pass's account id.

- [x] **Step 1: Write failing tests:** controller `is Off by default, On after turnOn with saved count`; `turnOn requests access once and runs a pass`; `turnOff stops later passes writing`; `Unavailable when the store is unavailable`; `needsAccess true after a denied pass`; host `kicks on resume and on sign-in`; inbox `onLinked calls the export kick` (extend `test/watch/watch_workout_inbox_test.dart` or the provider test that builds the inbox).
- [x] **Step 2: Run** those tests — expected FAIL.
- [x] **Step 3: Implement** the controller, kick provider, host and the four call sites (each call site is one line).
- [x] **Step 4: Run** the new tests plus `flutter test test/train test/progress test/watch` — expected PASS.
- [x] **Step 5: Commit** `feat(health): run health export on finish, delete, watch link and resume`.

### Task 6: Health tab row and first-use sheet

**Files:**
- Create: `lib/features/health/widgets/health_export_row.dart`
- Modify: `lib/features/health/health_page.dart` (place the row in the settings area next to Disconnect; it shows whether or not health reads are connected, and not at all for `HealthExportUnavailable`)
- Test: `test/health/health_export_row_test.dart`, one case in `test/health/health_page_test.dart`

**Interfaces:**
- Consumes: `healthExportControllerProvider` (Task 5), platform kind (`HealthPlatformKind`) for "Apple Health" vs "Health Connect".

Copy (iOS shown; Android replaces "Apple Health" with "Health Connect"):
- Row (`NsListCard`): title `Save workouts to Apple Health`; subtitle `Off` | `On · 42 saved` | `On · 42 saved, 3 waiting` | `Allow access in Settings`. Tap when Off ⇒ sheet; tap when On and `needsAccess` ⇒ `openSettings`; tap when On otherwise ⇒ `showNsConfirm(title: 'Stop saving workouts?', message: 'New workouts will no longer be saved to Apple Health. Workouts already saved stay there.', confirmLabel: 'Stop saving')` ⇒ `turnOff`.
- Sheet (`showNsSheet`): heading `Save workouts to Apple Health`; body `BeyondRep will save each workout you finish on this phone to Apple Health as Strength training, with its name, start and end. Your past workouts here are saved too. Heart rate and calories are not included. Apple Watch workouts are already in Apple Health and are not saved twice.`; primary `Turn on` ⇒ `turnOn`; secondary `Not now`.

- [ ] **Step 1: Write failing widget tests:** `shows Off and opens the sheet`; `Turn on calls turnOn`; `On shows saved and waiting counts`; `needsAccess shows Allow access in Settings and opens settings`; `Stop saving asks before turning off`; `Health Connect wording on Android`; `hidden when unavailable`; light and dark at text scale 2.0 without overflow; health page shows the row while not connected for reads.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the row, the sheet and the page placement.
- [ ] **Step 4: Run** the tests plus `flutter test test/design_kit_guard_test.dart test/health` — expected PASS.
- [ ] **Step 5: Commit** `feat(health): add the save-to-Apple-Health switch to the Health tab`.

### Task 7: ADR-0014, docs and full checks

**Files:**
- Create: `docs/adr/0014-save-workouts-to-health-platforms.md` (context, decision = the Global Constraints and the spec's 5.3/5.4 rules, the accepted risk of a phone restored from the cloud with Workout read denied, consequences, the Wear OS thread extending the writer later)
- Create: `docs/implementation/phase-5/p5-01-workout-health-export.md` (what changed, tests run, unrun device checks)
- Modify: `docs/HEALTH_DATA.md` (export section: states actually used), `docs/OBJECTBOX.md` (receipt row), `docs/PRIVACY_POLICY_INPUTS.md` (new write permission and plist text), `docs/RELEASE.md` (Phase 5 device rows: first-use prompt iPhone and Android, backfill of a real history, delete removes the entry, 5b with the watch joined leaves one entry, Health Connect not installed, revoke write access then resume), `docs/ROADMAP.md` (Phase 5 "implemented in source, not released or device-verified"), `CLAUDE.md` (Project state line; remove "phone HealthKit/Health Connect writes" from Not implemented, keep "exports" wording accurate), `docs/implementation/README.md` index.
- Test: none new.

- [ ] **Step 1:** Write the ADR and docs above.
- [ ] **Step 2: Run all checks** from `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`; from repo root `python3 -m unittest discover -s tool -p 'test_*.py'`. Expected: all pass, no analyzer issues.
- [ ] **Step 3: Commit** `docs(phase-5): ADR-0014 and release gates for saving workouts to health`.
