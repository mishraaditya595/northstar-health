# Wear OS stage 3b: watch workout heart rate and calories to Health Connect — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (one Sonnet agent, strict TDD, then an Opus review). Steps use checkbox (`- [ ]`) syntax. Builds on stage 3a in the same branch and PR (#108); Adi asked for one PR for stage 3.

**Goal:** After the phone has imported a Wear workout, the watch sends its per-minute heart rate and total calories in a new `workout_health` message; the Android phone writes the workout, its heart rate and calories to Health Connect (if the account turned on "save workouts" and the permissions are granted), keeps only the record id, acks, and the history detail reads them back fresh.

**Architecture:** Additive contract change (`workout_health` type, ack reason `not_written`). The watch keeps the series in its journal next to the session (retention below) and puts it after the `completed_workout` is acked. The phone handles it in a new `WatchWorkoutHealthInbox`, writes through the Phase 5 `HealthWorkoutWriter` (extended with optional heart rate and calories), and records a `HealthExportReceiptEntity` for the watch workout so delete-follows and the read-back reuse Phase 5. Values live only in memory on the phone.

**Tech Stack:** JSON Schema + Python contract tests, Kotlin `:core` and `:app`, Dart/Riverpod/ObjectBox, `health` 14.0.0 (Android Health Connect), Swift codec in `BeyondRepWatchCore` (decode only).

**Spec:** `docs/superpowers/specs/2026-11-27-wear-os-companion-design.md` section 4.3 (Adi chose C). Phase 5 docs: `docs/adr/0014-save-workouts-to-health-platforms.md`, `docs/implementation/phase-5/p5-01-workout-health-export.md`.

## Global Constraints

- `schema_version` stays 1; changes are additive. New fixtures go through `tool/test_watch_link_contract.py`, the Kotlin `ContractFixtureTest`, the Dart `contract_fixtures_test.dart` and the Swift package tests (CI only).
- `workout_health` is the second message (after `health_snapshot`) allowed to carry health values; extend the "no health values elsewhere" check to allow exactly these two.
- Body: `workout_id` (uuid), `start_utc`, `end_utc` (WatchTimestamp format, end > start), `heart_rate` (array, 0 to 600 items, each `{ "at_utc": <ts within start..end>, "bpm": <int 25..250> }`, strictly increasing `at_utc`), `total_kcal` (optional number, > 0, at most 10000). Missing values are left out, never 0. No other fields.
- Heart rate is reduced on the watch to one average per started minute of the workout (`at_utc` = the minute's start, bpm rounded half up); minutes without a valid sample are left out.
- Ack: `result` `stored` (written), `duplicate` (already written), `rejected` with new reason `not_written` (switch off, permission missing, Health Connect missing or not Android). A write failure sends no ack; the watch resends.
- Watch retention: the series sits in the journal only with its session; deleted on any ack of the `workout_health`, on the wipe, on `account_cleared`, when the binding is dropped, and 7 days after the workout ended, whichever comes first. Never logged.
- Phone: values only in memory for the write. Never ObjectBox, outbox, Supabase, JSON export, logs or crash text. ObjectBox stores only the receipt (record id, state, version).
- Health Connect: session via `writeWorkoutDataUUID` with `totalEnergyBurned` (kcal, rounded) and `clientRecordId` = workout uuid; heart rate via `writeHealthData(type: HEART_RATE, clientRecordId: '<uuid>-hr-<index>', clientRecordVersion: version)` one record per minute. Android permissions added: `WRITE_HEART_RATE`, `READ_TOTAL_CALORIES_BURNED`, `WRITE_TOTAL_CALORIES_BURNED`.
- Phone workouts keep needing only the exercise permission; only `workout_health` writes need heart rate and total calories write too.
- Only `in.beyondrep.app` records count as ours (`_isOwnSource`); outside-workout reads keep hiding them.
- Copy (history detail on Android): rows `Average heart rate`, `Max heart rate`, `Calories` (total), same widgets as the Apple Watch rows. Export row extra action on Android when a Wear watch is paired and heart rate write is missing: `Allow heart rate and calories` (kit button), which calls `requestAccess()`.
- Public repo, synthetic data only. Android code compiles and tests only on GitHub CI; Swift tests run on CI only.

## Review Focus

1. **The phone gets `workout_health` before the workout is imported** (reordered Data Layer delivery). Expect: no ack, nothing written; the watch resends and it lands after the import. Test in Task 4.
2. **Switch off, or heart rate permission missing, or Health Connect not installed.** Expect: `rejected`/`not_written`, the watch deletes the series, history shows no heart rate rows, nothing written. Tests in Tasks 4 and 5.
3. **The same `workout_health` arrives twice, or after a phone reinstall restored the workout.** Expect: one Health Connect session (client record id upsert), ack `duplicate` when a receipt already says exported. Test in Task 4.
4. **The workout is deleted on the phone after the write.** Expect: the Health Connect session, its heart rate records and calories are deleted (our own records in the window only), the receipt says deleted. Test in Task 5.
5. **The watch is away for more than 7 days, or the account is cleared before the phone acks.** Expect: the series is gone from the watch journal; nothing is ever sent for another account. Test in Task 2.

---

### Task 1: Contract — `workout_health` and `not_written`

**Files:** `contracts/watch_link/v1/message.schema.json`, `contracts/watch_link/v1/README.md`, new `fixtures/valid/workout_health.json`, `fixtures/valid/workout_health_minimal.json` (no heart rate, no kcal), `fixtures/valid/ack_not_written.json`, new invalid fixtures `workout_health_bpm_zero.json`, `workout_health_sample_outside.json`, `workout_health_unsorted.json`, `workout_health_extra_field.json`, `ack_not_written_stored.json` (reason `not_written` with result `stored`); `tool/test_watch_link_contract.py`.

- [ ] **Step 1: Failing test:** extend the Python test so the new valid fixtures validate, the invalid ones fail with the expected reason, the health-values check allows `health_snapshot` and `workout_health` only, and `not_written` is allowed only with `rejected`.
- [ ] **Step 2:** `python3 -m unittest tool.test_watch_link_contract` → FAIL. **Step 3:** schema `body_workout_health`, type enum, the if/then, ack reason enum + rule; README section. **Step 4:** PASS. **Step 5:** Commit `feat(contracts): workout_health message and not_written ack reason`.

### Task 2: `:core` — codec, journal storage, retention, outbox

**Files:** `apps/wear_os/core/.../contracts/WatchMessage.kt` (body `WorkoutHealthBody`, ack reason), `.../session/HeartRateTracker.kt` (minute series), `.../store/WatchJournal.kt` (schema version +1, table `session_health(session_id PK, account_key, message_json, ended_at_ms)`), `.../link/PhoneInbox.kt` (ack of a `workout_health` deletes its row), `.../link/OutboxSender.kt` unchanged; tests in the matching test files and `ContractFixtureTest` (picks up the new fixtures).

**Interfaces:**
- `HeartRateTracker.minuteSeries(start: Instant): List<Pair<Instant, Int>>` (one average per started minute since `start`, in order).
- `WatchJournal.saveWorkoutHealth(sessionId: String, accountKey: String, message: WatchMessage, endedAtMs: Long)`; `pendingWorkoutHealth(accountKey: String, limit: Int): List<WatchMessage>` returning only rows whose session `delivery == 'delivered'`; `clearAccount` and the binding drop delete the account's rows; `pruneStale(nowMs)` also deletes rows with `ended_at_ms` older than 7 days; `applyAck` deletes the `workout_health` row for any result.
- Migration from the stage-3a schema version keeps every existing row (test with a journal file created at the old version).

- [ ] **Step 1: Failing tests:** codec round-trip of both valid fixtures, rejection of the invalid ones; `minuteSeriesAveragesPerMinuteAndSkipsEmptyMinutes`; `workoutHealthWaitsForTheCompletedWorkoutAck`; `anyAckDeletesTheSeries` (`stored`, `duplicate`, `rejected`); `clearAccountDeletesTheSeries`; `pruneStaleDropsSeriesAfterSevenDays` (6d23h kept, 7d1h dropped); `aSeriesOfAnotherAccountIsNeverPending`; `migrationFromStage3aKeepsRows`.
- [ ] **Step 2:** `cd apps/wear_os && ./gradlew :core:test -Pbeyondrep.coreOnly=true` → FAIL. **Step 3:** Implement. **Step 4:** PASS. **Step 5:** Commit `feat(wear-core): workout_health codec, journal retention and outbox`.

### Task 3: Watch app — build, keep and send the series

**Files:** `apps/wear_os/app/.../workout/WorkoutRunner.kt` (at `finish`, after `queueCompleted`, save the `workout_health` built from `minuteSeries` and the last total calories, in the same journal-dispatcher block), `.../link/OutboxFlusher.kt` (also put `pendingWorkoutHealth`), `.../app/WatchGraph.kt` (call `pruneStale` on start if not already), tests `WorkoutRunnerTest`, `OutboxFlusherTest`.

- Process death mid-workout loses the in-memory series before restore; the message then carries only what was measured after the restore (documented, not fixed).
- A finish with no heart rate and no calories saves no `workout_health` at all.

- [ ] **Step 1: Failing tests:** `finishSavesTheSeriesWithTheWorkout` (fake readings 70,72 in minute 0 and 80 in minute 2 → two points 71 and 80, kcal 987); `finishWithoutReadingsSavesNoSeries`; `theSeriesIsPutOnlyAfterTheWorkoutAck`; `aNotWrittenAckDeletesTheSeries`; update `healthValuesNeverReachTheJournalOrTheDataLayer` → now asserts the sentinels appear only in the `session_health` row and only in the `workout_health` put.
- [ ] **Step 2:** push → CI FAIL. **Step 3:** Implement. **Step 4:** CI PASS. **Step 5:** Commit `feat(wear): send workout heart rate and calories after the phone imports the workout`.

### Task 4: Phone — codec and `WatchWorkoutHealthInbox`

**Files:** `apps/mobile/lib/features/watch/domain/watch_message.dart` (`WorkoutHealth` message, `not_written` reason), new `apps/mobile/lib/features/watch/application/watch_workout_health_inbox.dart`, `.../application/watch_sync_controller.dart` (dispatch), `apps/mobile/lib/features/health/data/health_workout_writer.dart` (record fields), `apps/mobile/lib/features/health/data/health_export_repository.dart` (receipt upsert for a watch workout); tests `test/watch/watch_workout_health_inbox_test.dart`, `test/watch/contract_fixtures_test.dart`.

**Interfaces:**
- `HealthWorkoutRecord` gains `final double? totalKcal;` and `final List<HeartRateMinute> heartRate;` (`class HeartRateMinute { final DateTime at; final int bpm; }`), both defaulting to none; phone records leave them empty.
- `HealthWorkoutWriter` gains `Future<bool> hasWatchHealthWriteAccess()` (exercise + heart rate + total calories write on Android; false on iOS).
- `class WatchWorkoutHealthInbox { Future<WatchLinkResult?> handle(WorkoutHealth message) }` returning the ack to send or null for no ack:
  - wrong account → `rejected`/`wrong_account`; workout unknown or not completed or not `beyondrep_watch` → null;
  - not Android, Health Connect unavailable, export switch off for the account, or `hasWatchHealthWriteAccess()` false → `rejected`/`not_written`;
  - receipt for the workout already `exported` at the workout's version → `duplicate`;
  - write → `HealthWriteOk` → upsert receipt (`health_connect`, `exported`, record id, version) then `stored`; any failure → null.

- [ ] **Step 1: Failing tests** (fake writer, in-memory ObjectBox as the Phase 5 tests do): one per branch above, plus `theValuesAreNeverStored` (sentinels 173 and 987 appear in no ObjectBox entity after a write; scan the store's boxes the way existing privacy tests do) and fixture decode tests.
- [ ] **Step 2:** `flutter test test/watch/watch_workout_health_inbox_test.dart` → FAIL. **Step 3:** Implement. **Step 4:** PASS. **Step 5:** Commit `feat(watch): write watch workout heart rate and calories to Health Connect`.

### Task 5: Phone — Health Connect writes, delete-follows and read-back

**Files:** `apps/mobile/lib/features/health/data/health_workout_writer.dart` (Android write of kcal and heart rate; delete also removes our `HEART_RATE` and `TOTAL_CALORIES_BURNED` in the workout window), `apps/mobile/lib/features/health/domain/workout_health_export.dart` (`planHealthExport`: a `beyondrep_watch` workout with a receipt gets delete-follows; it is never written by the exporter itself), `apps/mobile/lib/features/health/data/platform_health_reader.dart` (`readOwnWorkout` on Android: match the session by record id, heart rate and total calories from our source in its window), `apps/mobile/lib/features/account/account_gate.dart` (on Android `watchWorkoutPlatformIdProvider` reads the exported receipt's record id), `apps/mobile/lib/features/progress/workout_history_detail_page.dart` only if the rows need the total-calories label, `apps/mobile/lib/features/health/...` export row action, `apps/mobile/android/app/src/main/AndroidManifest.xml` (three permissions); tests in the existing Phase 5 test files and a history detail test.

- [ ] **Step 1: Failing tests:** `androidWriteSendsCaloriesAndOneHeartRateRecordPerMinute` (fake `Health` records calls: `totalEnergyBurned: 987`, two `writeHealthData` calls with ids `<uuid>-hr-0`, `<uuid>-hr-1`); `aFailedHeartRateWriteIsAFailedWrite`; `deletingAWatchWorkoutDeletesItsHealthConnectCopy`; `theExporterNeverWritesAWatchWorkout`; `readOwnWorkoutOnAndroidReturnsAverageMaxAndCalories`; `readOwnWorkoutIgnoresHeartRateFromOtherApps`; `historyDetailShowsWatchHeartRateOnAndroid`; `exportRowOffersHeartRateAccessWhenAWearWatchIsPaired`; manifest check in the existing Android permission test if there is one (`grep -rn READ_EXERCISE apps/mobile/test tool`).
- [ ] **Step 2:** run those files → FAIL. **Step 3:** Implement. **Step 4:** PASS, then `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`. **Step 5:** Commit `feat(health): Health Connect heart rate and calories for watch workouts`.

### Task 6: Swift codec

**Files:** `apps/watch_os/Packages/BeyondRepWatchCore/Sources/.../` message codec (decode `workout_health` and the `not_written` reason so the shared fixtures pass; the Apple Watch never sends it), its fixture test.

- [ ] **Step 1:** add the new fixtures to the Swift fixture test list if it is explicit. **Step 2:** implement decode. **Step 3:** push; `watchos_smoke.yml` on CI is the check. **Step 4:** Commit `feat(watch-core): decode workout_health`.

### Task 7: Docs

`docs/adr/0015-wear-os-companion.md` (stage 3b amendment: message, retention, permissions, total not active calories), `docs/adr/0012-*` decision 4 note or a pointer from ADR-0015 (health values in transit watch → phone → Health Connect), `docs/HEALTH_DATA.md`, `docs/adr/0014-save-workouts-to-health-platforms.md` (one line: watch workouts on Android are written by the watch inbox, not the exporter), `docs/RELEASE.md` rows (all `not run`: switch on and heart rate allowed → history shows avg/max/calories and Health Connect has one session with heart rate; switch off → no rows, nothing in Health Connect; permission missing → the row action asks and the next workout is written; delete on phone → gone from Health Connect; watch 8 days away → series dropped; Samsung Health shows its own copy or not), `docs/ROADMAP.md`, `CLAUDE.md` (replace the 3a bullet with one stage-3 bullet; "Not implemented" line now also excepts watch workout heart rate and calories on Android).

- [ ] Write; `python3 -m unittest discover -s tool -p 'test_*.py'` → OK; commit `docs(wear): stage 3b heart rate and calories to Health Connect`.

### Finish

- [ ] `:core:test`, Flutter format/analyze/test, Python suite locally; push; CI green on `wear_os`, `mobile`, `ios-with-watch`/`watch`.
