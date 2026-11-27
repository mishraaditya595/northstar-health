# Phase 4 stage 4c: watch workout heart rate and calories on the phone, watch cleanup, cross-phone test — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (Adi's choice: one Sonnet agent runs the whole plan, then an Opus review). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Close stage 4 with three pieces.

1. The phone's history detail for an Apple Watch workout shows that workout's average and maximum heart rate and its active energy. These are read fresh from Apple Health through the stored receipt and never stored.
2. The watch stops holding an account's plans and binding forever when the phone never comes back, and its clear-tombstones stay bounded.
3. A test proves that a watch workout re-imported on a second phone after deletion ends in a server conflict, never a silent resurrection.

**Architecture:**
- The phone reads through the existing `HealthReader`/`PlatformHealthReader` (`health` 14.0.0). The health layer gets the HKWorkout id from a provider overridden in the signed-in scope, the same way `ownPlatformWorkoutIdsProvider` works today, so health code never touches ObjectBox.
- The watch cleanup is one `WatchJournal` method, tested by `swift test` and called by the app.
- The cross-phone test uses the phone's real importer and upload coordinator with a fake RPC, plus one pgTAP case.

**Spec:** `docs/superpowers/specs/2026-11-26-phase-4-watch-and-tablet-design.md` §4.6 ("Heart rate and calories from that HKWorkout attach to the BeyondRep session through the receipt") and §5.4; ADR-0011; ADR-0012; `docs/ROADMAP.md` stage 4c.

## Global constraints

- **Public repository:** synthetic data only, no keys, refs or personal data. Read `AGENTS.md`, `apps/mobile/AGENTS.md` and `apps/watch_os/AGENTS.md` first.
- **Health values are read fresh and never stored:**
  - nothing in ObjectBox or SharedPreferences;
  - nothing in the outbox, the cloud payload, export or telemetry (AGENTS.md: "Platform health data can never flow into cloud workout backups").
  - A value that is missing is not shown. It is never shown as 0.
- **No new HealthKit or Health Connect permission.** Use the existing read types: `HEART_RATE`, `ACTIVE_ENERGY_BURNED` and `WORKOUT`. On Android, a watch workout cannot exist, so the section never shows.
- **The section shows only when all of these hold:**
  - the workout's origin is `beyondrep_watch`;
  - a receipt with an HKWorkout id exists;
  - Health is connected for the signed-in account (`HealthConnectionRepository.isConnected(owner)`);
  - the read returned at least one value.
- **UI:**
  - Use the existing design kit only (`apps/mobile/lib/core/design/`, catalog in `docs/DESIGN_SYSTEM.md`); `test/design_kit_guard_test.dart` must pass.
  - Section title "From Apple Health". Rows "Average heart rate" ("{n} bpm"), "Max heart rate" ("{n} bpm") and "Active energy" ("{n} kcal", rounded).
  - Show nothing while loading and nothing on failure: no spinner and no error text, because this is optional extra detail.
- **Watch cleanup rule:**
  - When the bound account's last stored phone data (`link_state.last_received_ms`) is more than **90 days** old and no workout is active or paused, the watch drops that account's plans, health and binding. It never drops unsent workouts (`clearAccount(key, wipeUnsent: false)`).
  - In the same transaction it records a clear tombstone for the key, with the binding's `sent_at_ms`. A replay of the old application context is then ignored.
  - Tombstones are capped at the **20** newest by `sent_at_ms`. They are never removed by age alone, because the watch replays the last application context on launch.
- **Out of scope:** live handoff, mirroring and phone commands (stage 5).

## Review focus

1. **A watch workout whose HKWorkout was deleted in the Health app.** The read finds nothing, the section is hidden, and nothing throws. *(Task 1: `returns null when the workout is not found`.)*
2. **Health was disconnected after the workout was imported.** The section is hidden, and the reader is never called. *(Task 1: `does not read when health is not connected`.)*
3. **Account switch while the detail page is open.** The provider is scoped to the signed-in owner, so it never shows another account's values. *(Task 1: `keyed by owner`.)*
4. **The binding is pruned during a workout.** Nothing is pruned while a session is active or paused. *(Task 2: `testNoPruneDuringActiveSession`.)*
5. **The old binding is replayed after pruning.** It is ignored because of the tombstone. *(Task 2: `testReplayAfterPruneIsIgnored`.)*

---

### Task 1: Phone shows heart rate and calories for an Apple Watch workout

**Files:**
- Modify:
  - `apps/mobile/lib/features/health/data/health_reader.dart`
  - `apps/mobile/lib/features/health/data/platform_health_reader.dart`
  - `apps/mobile/lib/features/health/application/health_overview.dart` (next to `ownPlatformWorkoutIdsProvider`), or a new `application/own_workout_health.dart`
  - `apps/mobile/lib/features/account/account_gate.dart` (override)
  - `apps/mobile/lib/features/progress/workout_history_detail_page.dart`
  - every `HealthReader` fake in `apps/mobile/test`
- Create:
  - `apps/mobile/lib/features/health/domain/own_workout_health.dart`
  - tests `apps/mobile/test/health/own_workout_health_test.dart` and `apps/mobile/test/progress/watch_workout_health_section_test.dart`

**Interfaces:**
- Domain:

  ```dart
  class OwnWorkoutHealth {
    const OwnWorkoutHealth({this.averageBpm, this.maxBpm, this.activeKcal});
    final int? averageBpm;
    final int? maxBpm;
    final double? activeKcal;
    bool get isEmpty => averageBpm == null && maxBpm == null && activeKcal == null;
  }
  ```

- Reader:
  - `Future<SeriesResult<OwnWorkoutHealth?>> readOwnWorkout(String platformWorkoutId, DateTime from, DateTime to)` on `HealthReader`.
  - The platform implementation reads `WORKOUT` points from `from - 5 min` to `to + 5 min` and picks the point whose `uuid` equals `platformWorkoutId`, ignoring case. When none matches, it returns `SeriesData(null)`.
  - `activeKcal` comes from `totalEnergyBurned`, converted the way `readWorkouts` already does it.
  - The heart rate reads the existing heart-rate series over that point's `dateFrom..dateTo`, giving the rounded average and maximum.
  - On Android it returns `SeriesUnsupported`.
  - Its permission checks match `readWorkouts` (`SeriesNotAllowed` when `WORKOUT` is not allowed).
- Providers:
  - `final watchWorkoutPlatformIdProvider = Provider.family<String?, String>((ref, workoutUuid) => null);`
    - It is overridden in `account_gate.dart` with a lookup of the `WatchWorkoutReceiptEntity` for that workout uuid in the signed-in ObjectBox, which returns its platform id.
    - The lookup is a plain read. Write a small query method on the existing watch receipt store in `features/watch/data/`, not in health code.
  - `final ownWorkoutHealthProvider = FutureProvider.autoDispose.family<OwnWorkoutHealth?, ({String workoutUuid, DateTime start, DateTime end})>`. It returns null when:
    - there is no platform id;
    - there is no owner, or the owner is not connected (the reader is not called);
    - the result is anything but `SeriesData`;
    - the value is null or `isEmpty`.

    It watches `healthOwnerIdProvider`, so an account switch rebuilds it.
- UI: in `WorkoutHistoryDetailPage`, when `session.origin == WorkoutOrigin.watch`, the page watches the provider. When the provider has a value, it adds a "From Apple Health" section with the rows from Global constraints, using only the rows that have a value.

- [ ] **Step 1: Write the failing tests.**
  - `own_workout_health_test.dart` (a fake `HealthReader`, a fake connection, provider overrides):
    - `returns values for a connected owner with a receipt`
    - `returns null without a receipt and never calls the reader`
    - `does not read when health is not connected`
    - `returns null when the workout is not found` (reader gives `SeriesData(null)`)
    - `returns null for SeriesNotAllowed, SeriesFailed and SeriesUnsupported`
    - `returns null when every value is missing`
    - `keyed by owner` (switching `healthOwnerIdProvider` re-reads for the new owner)
  - `watch_workout_health_section_test.dart`:
    - `shows average, max and kcal for an Apple Watch workout`
    - `hides rows that are missing`
    - `shows no section for a phone workout`
    - `shows no section while loading or when null`
    - `fits at text scale 2.0 and 320 dp wide` (no overflow)
  - Reader unit tests for `PlatformHealthReader.readOwnWorkout`, if the existing reader tests fake the `health` plugin: matching is case-insensitive, and points from other sources or with other uuids are ignored.
- [ ] **Step 2: Run** `cd apps/mobile && flutter test test/health/own_workout_health_test.dart test/progress/watch_workout_health_section_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Update every fake `HealthReader` in `test/` so it compiles: return `SeriesData(null)`.
- [ ] **Step 4: Run** the same tests (PASS), then `flutter analyze` and `test/design_kit_guard_test.dart` (PASS).
- [ ] **Step 5: Commit** `feat(health): show Apple Watch workout heart rate and calories read fresh from Apple Health`.

### Task 2: Watch drops a long-unused binding and caps tombstones

**Files:**
- Modify:
  - `apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Store/WatchJournal.swift`
  - `apps/watch_os/Sources/App/AppModel.swift`
- Test: `Tests/BeyondRepWatchCoreTests/WatchJournalTests.swift`

**Interfaces:**
- `public func pruneStale(nowMs: Int64, maxSilenceDays: Int = 90, maxTombstones: Int = 20) throws -> Bool` returns true when the binding was dropped. It runs in one transaction:
  1. If a binding exists, `last_received_ms` is non-null and older than `nowMs - maxSilenceDays·86_400_000`, and no session for the key has status `active` or `paused`, it records the tombstone `(key, binding.sent_at_ms)` and then `clearAccount(key, wipeUnsent: false)`.
  2. It deletes `cleared` rows beyond the newest `maxTombstones` by `sent_at_ms`.
- `AppModel` calls it on launch and when the app becomes active, before `refresh()`. It ignores errors.

- [ ] **Step 1: Write the failing tests:**
  - `testBindingSilentFor91DaysIsDropped` (plans, health and binding are gone; `pruneStale` returns true)
  - `testBindingSilentFor89DaysIsKept`
  - `testNoPruneWithoutLastReceived`
  - `testNoPruneDuringActiveSession`
  - `testUnsentWorkoutSurvivesPrune` (a queued `completed_workout` is still in `pendingCompleted`, and `waitingCounts(boundKey: nil)` is (0, 1))
  - `testReplayAfterPruneIsIgnored` (`PhoneInbox.receive(applicationContext:)` with the same binding message gives no binding, and `ignoredCount` goes up)
  - `testTombstonesCappedAtTwenty` (25 rows leave the 20 newest)
- [ ] **Step 2: Run** `swift test --filter WatchJournalTests` (macOS CI only; write the tests first and say so).
- [ ] **Step 3: Implement** the method and the `AppModel` call.
- [ ] **Step 4: CI** `watchos_smoke.yml` passes.
- [ ] **Step 5: Commit** `feat(watch-core): drop a binding the phone has not refreshed in 90 days`.

### Task 3: Cross-phone resurrection test

**Files:**
- Create: `apps/mobile/test/watch/cross_phone_resurrection_test.dart`
- Modify: `supabase/tests/workout_sync.test.sql` (one more assertion, with `plan(n)` raised by 1)

The scenario:
1. Phone A imported watch workout W and the user deleted it, so the server holds a tombstone for W.
2. Phone B is a fresh account-bound ObjectBox with no receipt and no session for W. The watch resends W to phone B.

- [ ] **Step 1: Write the Dart test** `watch workout resent to a second phone after deletion ends in a conflict`. Use the real `ObjectBoxWatchWorkoutImporter` and `WatchWorkoutInbox` on a temporary store, and the real upload coordinator with a fake RPC client. The fake answers `{"result": "conflict", ...}` in the shape that `workout_upload_coordinator.dart:273` handles for a tombstoned workout. Look up the exact response shape in the existing `workout_upload_coordinator_test.dart`. Assert:
  - the import result is `stored` and the watch gets a `stored` ack;
  - the upload sends expected revision 0;
  - after the conflict, the outbox entry is in the coordinator's conflict state, not acknowledged or removed;
  - the session is not marked synced.
- [ ] **Step 2: Write the pgTAP assertion** next to the existing "tombstoned workout cannot be silently resurrected" case: `sync_workout` for the tombstoned id with **expected revision 0**, the cross-phone case, returns `'conflict'`. Use the same fixture, with `origin` set to `beyondrep_watch` through `jsonb_set`.
- [ ] **Step 3: Run**:
  - `cd apps/mobile && flutter test test/watch/cross_phone_resurrection_test.dart`: expected PASS, because the behaviour exists already and this test pins it. If it fails, stop and report: that is a real bug, not a test to bend.
  - pgTAP runs on CI (`supabase_sql.yml`).
- [ ] **Step 4: Commit** `test(watch): a watch workout resent after deletion ends in a server conflict`.

### Task 4: Docs

- [ ] **ROADMAP:** stage 4c is "implemented in source, not released or device-verified".
- [ ] **RELEASE:** add device rows, each unticked:
  - "Apple Watch workout detail on iPhone shows average/max heart rate and kcal from Apple Health";
  - "delete that workout in the Health app: the section disappears";
  - "disconnect Health in BeyondRep: the section disappears".
- [ ] **HEALTH_DATA and ADR-0012:** add one line each saying that heart rate and energy for watch workouts are read fresh through the receipt and never stored or uploaded. HEALTH_DATA also gets the 90-day binding prune.
- [ ] **CLAUDE.md:** add a stage 4c line in the same style as 4b.
- [ ] **Run** `python3 -m unittest discover -s tool -p 'test_*.py'`.
- [ ] **Commit** `docs: phase 4 stage 4c`.

### Final verification

- [ ] From `apps/mobile`:
  - `dart format --output=none --set-exit-if-changed lib test`
  - `flutter analyze`
  - `flutter test`
- [ ] From the repository root: `python3 -m unittest discover -s tool -p 'test_*.py'`.
- [ ] Check `git status`, then push. `watchos_smoke.yml`, `supabase_sql.yml` and `mobile_ci.yml` must all be green.
- [ ] Report what ran locally, what ran only on CI, and that the device rows are "not run".
