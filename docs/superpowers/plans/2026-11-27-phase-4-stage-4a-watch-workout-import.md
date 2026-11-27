# Phase 4 stage 4a: phone import of watch workouts and the `beyondrep_watch` cloud origin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The phone durably imports a `completed_workout` message from the Apple Watch (validate, then workout + inbox receipt + cloud outbox entry in one ObjectBox transaction, then `ack`), backs it up with cloud origin `beyondrep_watch`, keeps that origin through history, restore and export, hides the watch's own HealthKit workout from "outside workouts", and retries the account-deletion wipe until the watch confirms it.

**Architecture:**
- Server: one migration redefines `northstar_private.validate_workout_v1` to accept `origin` `northstar_phone` or `beyondrep_watch`; nothing else in the payload changes.
- Phone domain: a `WorkoutOrigin` enum replaces every hard-coded `'northstar_phone'`. The restore parser's private payload validator becomes the public `WorkoutRestorePage.parseWorkout`, used by both restore and the watch import. The restore importer's `_materialize` moves unchanged into a shared `writeCompletedSnapshot`, used by both.
- Watch import: `WatchSyncController` already listens to `WatchLink.messages`; it routes `CompletedWorkout` messages to a new `WatchWorkoutInbox` (application), which checks the account key, validates, calls `ObjectBoxWatchWorkoutImporter` (data, one write transaction) and only then sends an `ack` by `WatchLink.transfer`.
- Deletion wipe (deferred M6 from stage 3): the wipe message is persisted in `SharedPreferences` (outside the account store, which is deleted) before it is sent, and a process-wide `WatchWipeRetrier` resends it until the watch acks it.

**Tech Stack:** Flutter 3.47.7, Dart, Riverpod 3, ObjectBox 5 (+ `build_runner` codegen), shared_preferences, PostgreSQL/pgTAP (Supabase CLI 2.81.3 in CI), Python `jsonschema` contract tests, Swift (`BeyondRepWatchCore`, CI only).

**Spec:** `docs/superpowers/specs/2026-11-26-phase-4-watch-and-tablet-design.md` §4.6, §5.3, §5.4, §5.5 (steps 5–7 and the cloud backup part), §6 stage 4, §9; `docs/adr/0012-apple-watch-companion.md`; `docs/adr/0011-read-workouts-from-health-platforms.md`; `docs/SYNC_PROTOCOL.md`; `contracts/watch_link/v1/README.md`. Read them first.

**Split:** stage 4 is 4a (this plan: everything testable without the watch UI) and 4b (watch HealthKit session, logging screens, rest timer, the watch sending `completed_workout` and resending until `ack`). Nothing in 4a sends a completed workout from the watch; phone tests use synthetic messages.

## Global Constraints

- **Public repo.** Synthetic data only (`@example.invalid`, the fixture UUIDs). No keys, no project ref/URL, no real emails or health exports. Check `git status` before each commit.
- **Origins:** exactly `northstar_phone` and `beyondrep_watch`, case sensitive. Everything else stays rejected (server `22023`, restore `invalid_workout_origin`, export `invalid_payload`, upload validity `false`). `schema_version` stays 1.
- **Order on import (spec 5.5 step 6):** strict decode → account key equals `watchAccountKey(signedInUserId)` (else ignore: no write, no ack) → `WorkoutRestorePage.parseWorkout(..., origins: {WorkoutOrigin.watch})` (reps-or-duration rule included) → **one** ObjectBox write transaction: session + exercises + sets, `WatchWorkoutReceiptEntity`, `WorkoutSyncOutboxEntity` (`pending`) → commit → `ack`. Nothing is written for an invalid payload. An ack is never sent before the commit returns.
- **Ack results (contract `body_ack`):** `stored` (new import), `duplicate` (already imported or locally deleted; no writes), `rejected` with `reason: "invalid"` (validation or collision; no writes). The ack's `account_key` is the signed-in account's key; `acked_message_id` is the completed message's `message_id`.
- **ObjectBox:** never change existing entity/property/index UIDs; commit `lib/objectbox-model.json` and `lib/objectbox.g.dart` together; old-database upgrade test with a frozen pre-change model (docs/OBJECTBOX.md).
- **Health data:** the HKWorkout UUID is a platform record reference, not a measurement; it stays in the local receipt, never in the cloud payload, the export, logs or telemetry. `lib/features/health/application` and `domain` still never import ObjectBox (`test/health/health_import_guard_test.dart`).
- **UI:** design kit only (`NsTag`); `test/design_kit_guard_test.dart` passes. Exact copy: tag **"Apple Watch"**.
- **Deploy order:** the migration must be applied (Codemagic `supabase-database` job) to a project **before** any build that uploads `beyondrep_watch`, and every install updated first, because older builds reject the origin when restoring.
- **Checks before each commit** (from `apps/mobile/`, with `export PATH=/root/sdk/flutter/bin:$PATH`): `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, the touched tests; the full `flutter test` before the last commit. Contract: `python3 -m unittest tool.test_watch_link_contract` (repo root), full `python3 -m unittest discover -s tool -p 'test_*.py'` at the end.
- **SQL:** pgTAP cannot run in this container (no Docker daemon, no Supabase CLI, no pgTAP extension; `psql` 16 client only). Try `docker ps && supabase --version`; if either fails, push and use the `Supabase SQL and RLS` check (`.github/workflows/supabase_sql.yml`) as the result and say so in the PR. Never claim pgTAP passed locally.
- **Swift:** no Swift toolchain here. Swift edits are verified by `swift test` in `watchos_smoke.yml` and the `ios-with-watch` job on the PR; write them so they compile by inspection.
- **Commits:** end every commit message with the attribution lines the session gives you. Do not merge.

## Review Focus

1. **Ack lost, watch resends the same workout under a new `message_id`:** the phone answers `duplicate`, writes nothing, and the outbox still has exactly one entry for it. Test in Task 7 (`redelivery with a new message id is a duplicate`).
2. **User deletes the imported watch workout on the phone, then the watch redelivers it:** it does not come back; `duplicate`, the tombstone and its delete operation stay. Test in Task 7 (`a locally deleted workout is not resurrected`).
3. **Account switch while a completed workout is in flight:** a message for account A arriving while B is signed in is ignored with no ack (the watch keeps it); an account change during the transaction rolls it back. Tests in Task 7 (`account changed inside the transaction rolls back`) and Task 8 (`another account's workout is ignored without an ack`).
4. **Process killed after commit, before the ack:** on relaunch the same message is answered `duplicate`, never stored twice. Test in Task 7 (`after reopening the store a redelivery is a duplicate`).
5. **Account deleted while the watch is out of range and the app is then killed:** next launch with the watch reachable sends the same wipe; it is dropped from the queue only on the watch's ack. Test in Task 10 (`a persisted wipe is resent on the next launch and removed on ack`).

---

### Task 1: Server accepts `beyondrep_watch`

**Files:**
- Create: `supabase/migrations/20261127090000_workout_origin_beyondrep_watch.sql`, `supabase/tests/workout_watch_origin.test.sql`

**Interfaces:**
- Produces: `northstar_private.validate_workout_v1(uuid, jsonb)` redefined with `CREATE OR REPLACE` from its **latest** body, `20261126020000_workout_set_duration.sql` (confirm with `grep -l validate_workout_v1 supabase/migrations/*` that nothing later redefines it). The only change: `p_payload->>'origin' is distinct from 'northstar_phone'` becomes `p_payload->>'origin' not in ('northstar_phone','beyondrep_watch')` (the `jsonb_typeof(...) <> 'string'` guard before it stays, so null/number origins still fail). Header comment: what changed and "Deploy before any app build that uploads beyondrep_watch." Re-issue the trailing `revoke all on function ... from public,anon,authenticated;` exactly as the previous migration. No other SQL pins the origin (checked: `sync_workout_internal`, `get_workout_changes`, `get_workout_progress`, `get_workout_for_resolution` do not).

- [ ] **Step 1: Write the failing pgTAP file** in the style of `supabase/tests/workout_timed_sets.test.sql` (`begin; create extension if not exists pgtap ...; select plan(N);` synthetic `auth.users` row `northstar-watch-origin@example.invalid`, `pg_temp.doc(wid, origin jsonb)` building one completed rep set, `pg_temp.try_sync` returning result or sqlstate, `set local role authenticated` with JWT claims, `finish(); rollback;`). Cases:
  - `origin "beyondrep_watch"` → `'applied'`; stored `payload->>'origin'` = `'beyondrep_watch'`.
  - `origin "northstar_phone"` → `'applied'` (regression).
  - `22023` for `"beyondrep_wear"`, `"BEYONDREP_WATCH"`, `""`, `1` (number), JSON `null`, and the key missing.
  - `get_workout_changes(0,100,null)->'changes'` contains the watch workout with `payload->>'origin'` = `'beyondrep_watch'`.
  - `get_workout_progress(day, day)->'totals'->>'workouts'` counts the watch workout (1 phone + 1 watch on the same day → `2`).
- [ ] **Step 2: Run** `supabase db reset && supabase test db` if available, else push and read the CI check. Expected: the watch cases FAIL (`22023` for `beyondrep_watch`).
- [ ] **Step 3: Write the migration.**
- [ ] **Step 4: Run** again. Expected: every pgTAP file PASSES (including `workout_sync`, `workout_restore_feed`, `workout_timed_sets`, `workout_muscles`). Run `python3 -m unittest tool.test_supabase_migration_reconciliation tool.test_codemagic_supabase` — PASS.
- [ ] **Step 5: Commit** `feat(supabase): accept the beyondrep_watch workout origin`

---

### Task 2: Contract — optional `program_day` on `completed_workout`

`completed_workout` already carries `healthkit_workout_uuid` (the platform-export receipt, spec 4.6), so that needs no contract change. It has no place for today's program day, which the phone must record (spec 5.5 "Program day"). *(My call: add an optional `body.program_day` object, copied by the watch from `plans_snapshot.today` in 4b.)*

**Files:**
- Modify: `contracts/watch_link/v1/message.schema.json` (`$defs.body_completed_workout.properties.program_day`), `contracts/watch_link/v1/README.md` (one paragraph under the `completed_workout` sentence: `program_day` and that the phone records it only when the plan exists locally and belongs to that program; `healthkit_workout_uuid` is the receipt the phone stores to hide the watch's own HealthKit workout)
- Create: `contracts/watch_link/v1/fixtures/valid/completed_workout_program_day.json` (copy of `completed_workout.json` with `program_day`, new `message_id`), `fixtures/invalid/completed_workout_program_day_bad_date.json` (`local_date` `"2026-10-23\n"`), `fixtures/invalid/completed_workout_program_day_extra_field.json` (extra `"label"`)
- Modify: `apps/mobile/lib/features/watch/domain/watch_message.dart` (`completed_workout` branch, `CompletedWorkout`), `apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Contracts/WatchMessage.swift` (`completed_workout` case)
- Test: `tool/test_watch_link_contract.py`, `apps/mobile/test/watch/contract_fixtures_test.dart`, Swift `ContractFixtureTests.swift` (all iterate the fixture folders, so the new files are covered)

**Interfaces:**
- Schema: `program_day: {type: object, required: [plan_id, program_id, local_date], additionalProperties: false, properties: plan_id/program_id string 1–128, local_date pattern ^[0-9]{4}-[0-9]{2}-[0-9]{2}$}` (same rules as `plans_snapshot.today`).
- Dart: `CompletedWorkout.programDay` of type `({String planId, String programId, String localDate})?`, decoded strictly with `StrictObject` (`string(max: 128)`, the existing local-date check), written back by `bodyJson` only when present.
- Swift: `body(["workout","last_sequence"], ["healthkit_workout_uuid","program_day"])` and a strict check of `program_day` with the existing `StrictJSON` helpers. The enum case `completedWorkout(...)` keeps its associated values; `program_day` stays in `raw` (nothing on the watch reads it in 4a).

- [ ] **Step 1: Add the three fixtures.** Add Dart test `completed_workout program_day round-trips` (decode the valid fixture, `programDay!.programId` equals the fixture's, `toJson()` equals the file) and Swift test `testCompletedWorkoutProgramDayIsChecked` (valid decodes, the two invalid throw).
- [ ] **Step 2: Run** `python3 -m unittest tool.test_watch_link_contract` and `flutter test test/watch/contract_fixtures_test.dart` — FAIL (valid fixture rejected for the unknown key).
- [ ] **Step 3: Implement** schema, README, Dart, Swift.
- [ ] **Step 4: Run** both — PASS. Swift: push and read `watchos_smoke.yml`.
- [ ] **Step 5: Commit** `feat(contracts): optional program day on completed watch workouts`

---

### Task 3: `WorkoutOrigin`, public payload validator, restore keeps the origin

**Files:**
- Modify: `apps/mobile/lib/features/workouts/domain/workout_models.dart` (enum, `WorkoutSessionRecord.origin`)
- Modify: `apps/mobile/lib/features/sync/workout_restore_feed.dart` (`_workout` → public `parseWorkout`, `RemoteWorkoutSnapshot.origin`)
- Create: `apps/mobile/lib/features/sync/completed_snapshot_writer.dart` (body of `ObjectBoxWorkoutRestoreImporter._materialize`, moved)
- Modify: `apps/mobile/lib/features/sync/objectbox_workout_restore_importer.dart` (lines ~476, ~698, ~812 origin checks; `_materialize` delegates)
- Test: `apps/mobile/test/sync/workout_restore_feed_test.dart`, `apps/mobile/test/sync/objectbox_workout_restore_importer_test.dart`, `apps/mobile/test/sync/workout_conflict_resolution_test.dart`

**Interfaces:**
- Produces:
  - `enum WorkoutOrigin { phone('northstar_phone'), watch('beyondrep_watch'); const WorkoutOrigin(this.wire); final String wire; static WorkoutOrigin? fromWire(Object? value); }` — `fromWire` returns null for anything else.
  - `WorkoutSessionRecord({..., this.origin = WorkoutOrigin.phone})`, `final WorkoutOrigin origin`.
  - `RemoteWorkoutSnapshot.origin` (`WorkoutOrigin`, required).
  - `static RemoteWorkoutSnapshot WorkoutRestorePage.parseWorkout(Object? raw, {required String workoutId, Set<WorkoutOrigin> origins = const {WorkoutOrigin.phone, WorkoutOrigin.watch}})` — the existing `_workout` body; the origin check becomes `WorkoutOrigin.fromWire(data['origin'])` in `origins`, else `invalid_workout_origin`. `workoutId` must already be lowercase canonical. Pure, mutates nothing.
  - `int writeCompletedSnapshot(Store store, RemoteWorkoutSnapshot snapshot, WorkoutSessionEntity? existing, {required int nowMs})` — must run inside a write transaction; same collision checks and `RestoreImportException('exercise_uuid_collision' | 'set_uuid_collision')` as today; sets `session.origin = snapshot.origin.wire`; returns the session revision. Does not touch `programUuid`, `programDayLocalDate` or `planUuid` beyond what `_materialize` did (it nulls `planUuid`).
  - Restore importer: every `local.origin != 'northstar_phone'` becomes `WorkoutOrigin.fromWire(local.origin) == null`.

- [ ] **Step 1: Write the failing tests:**
  - feed: `a beyondrep_watch payload decodes with origin watch`; `an unknown origin is still invalid_workout_origin` (`beyondrep_wear`); `parseWorkout with origins {watch} rejects northstar_phone`; `parseWorkout rejects a completed set with neither reps nor seconds` (`invalid_set_completion`).
  - importer: `restoring a watch workout keeps origin beyondrep_watch` (entity `origin` and a second restore page updating it keep it); `a local watch workout is not a local_workout_conflict`.
  - conflict resolution: `retryLocal works for a watch-origin workout`.
- [ ] **Step 2: Run** `flutter test test/sync` — FAIL.
- [ ] **Step 3: Implement.** The move of `_materialize` is verbatim apart from `store.box<...>()` lookups and the origin line.
- [ ] **Step 4: Run** `flutter test test/sync test/progress` — PASS (all existing restore tests unchanged).
- [ ] **Step 5: Commit** `feat(sync): restore keeps the beyondrep_watch origin`

---

### Task 4: Outbox, upload and export accept both origins

**Files:**
- Modify: `apps/mobile/lib/features/workouts/data/objectbox_workout_outbox.dart` (lines ~147, ~223, ~421, ~576)
- Modify: `apps/mobile/lib/features/sync/workout_upload_coordinator.dart` (`_isValidUploadOperation`, ~476)
- Modify: `apps/mobile/lib/features/account/workout_history_export.dart` (~178)
- Test: `apps/mobile/test/workouts/objectbox_workout_outbox_test.dart`, `apps/mobile/test/sync/workout_upload_coordinator_test.dart`, `apps/mobile/test/account/workout_history_export_test.dart`

**Interfaces:**
- Consumes: `WorkoutOrigin` (Task 3).
- Produces:
  - `void enqueueCompletedInTransaction(String workoutUuid, {bool requireValid = false})`: accepts sessions whose origin is a `WorkoutOrigin`; the payload's `origin` is the session's own `origin` string. With `requireValid: true`, a snapshot that would be `blocked` throws `InvalidCloudSnapshot(code)` (new `class InvalidCloudSnapshot implements Exception { final String code; }`, codes `invalid_snapshot` | `payload_too_large`) instead of writing a blocked row, so the caller's transaction rolls back.
  - `deleteCompletedWorkout` and `backfillCompleted` accept both origins.
  - Upload validity and export row checks: `WorkoutOrigin.fromWire(payload['origin']) != null`.

- [ ] **Step 1: Write the failing tests:** outbox `a completed watch-origin session queues a payload with origin beyondrep_watch`; `requireValid throws InvalidCloudSnapshot and writes no row` (a completed set with no reps and no seconds); `a watch-origin workout can be deleted with a delete operation`; `an unknown origin still cannot be queued`; coordinator `a beyondrep_watch upsert is a valid upload`; export `a beyondrep_watch row is exported unchanged` and the existing `health_connect` corruption test still fails with `invalid_payload`.
- [ ] **Step 2: Run** the three files — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS, plus `test/workouts/fixtures/rep_workout_payload.json` comparison tests unchanged (phone payloads byte-identical).
- [ ] **Step 5: Commit** `feat(sync): back up and export watch-origin workouts`

---

### Task 5: History shows watch workouts

**Files:**
- Modify: `apps/mobile/lib/features/progress/data/objectbox_workout_history_repository.dart` (query ~80, record mapping)
- Modify: `apps/mobile/lib/features/progress/progress_page.dart` (history row `Wrap`, ~747), `apps/mobile/lib/features/progress/workout_history_detail_page.dart` (tag `Wrap`, ~121)
- Test: `apps/mobile/test/progress/objectbox_workout_history_repository_test.dart`, `apps/mobile/test/progress/progress_page_widget_test.dart`

**Interfaces:**
- Query: `WorkoutSessionEntity_.origin.oneOf([for (final o in WorkoutOrigin.values) o.wire])`; the record gets `origin: WorkoutOrigin.fromWire(s.origin)!`.
- UI: `if (session.origin == WorkoutOrigin.watch) const NsTag('Apple Watch')` before the sync tag in both places. Nothing else changes (counts, volume, recovery and program status already read every completed session).

- [ ] **Step 1: Write the failing tests:** repository `completed watch workouts are in history with origin watch` (and the existing `health_connect_import` exclusion test still passes); widget `a watch workout row and detail show the Apple Watch tag`, `a phone workout shows no Apple Watch tag`, and the watch row at `textScaler 2.0` on a 320-wide surface has no overflow.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** `flutter test test/progress test/design_kit_guard_test.dart` — PASS.
- [ ] **Step 5: Commit** `feat(progress): show Apple Watch workouts in history`

---

### Task 6: `WatchWorkoutReceiptEntity` and model upgrade

**Files:**
- Create: `apps/mobile/lib/features/watch/data/watch_workout_receipt_entity.dart`
- Create: `apps/mobile/test/workouts/fixtures/objectbox_pre_watch_receipts.g.dart` — copy of the current `lib/objectbox.g.dart` **before** codegen, with the header `// FROZEN FROM main AT <sha>, BEFORE watch workout receipts. Do not regenerate.`
- Regenerate: `apps/mobile/lib/objectbox-model.json`, `apps/mobile/lib/objectbox.g.dart` (`dart run build_runner build --delete-conflicting-outputs`)
- Create test: `apps/mobile/test/watch/objectbox_watch_receipt_migration_test.dart`
- Modify: `docs/OBJECTBOX.md` (one table row)

**Interfaces:**
- Produces:
```dart
@Entity()
class WatchWorkoutReceiptEntity {
  @Id() int id = 0;
  @Unique() String workoutUuid;        // lowercase
  @Unique() String messageId;          // lowercase, the delivery that stored it
  String? platformWorkoutUuid;         // lowercase HKWorkout UUID, from healthkit_workout_uuid
  int receivedAtMs;
}
```
  *(My call: one receipt holds both the inbox dedup and the platform-export reference; no separate `HealthExportReceipt` entity until phone write-back needs one. Receipts are not pruned in 4a.)*
- OBJECTBOX.md row: `WatchWorkoutReceipt` | until the account store is deleted | Never — local dedup and platform record reference only.

- [ ] **Step 1: Copy the frozen fixture**, then write the failing test `pre-receipt database upgrades and keeps sessions` (open a store with the frozen model, put a session, close; reopen with `getObjectBoxModel()`: session intact, `WatchWorkoutReceiptEntity` box empty and writable).
- [ ] **Step 2: Run** — FAIL (entity does not exist). **Step 3: Add the entity and run codegen.** Diff `objectbox-model.json`: only a new entity and its index ids are added; no existing UID changed.
- [ ] **Step 4: Run** the new test and `flutter test test/workouts test/progress/objectbox_workout_history_repository_test.dart` (all older upgrade tests) — PASS.
- [ ] **Step 5: Commit** `feat(watch): ObjectBox receipt for imported watch workouts`

---

### Task 7: Atomic watch workout import

**Files:**
- Create: `apps/mobile/lib/features/watch/data/objectbox_watch_workout_importer.dart`
- Test: `apps/mobile/test/watch/objectbox_watch_workout_importer_test.dart`

**Interfaces:**
- Consumes: `RemoteWorkoutSnapshot`, `writeCompletedSnapshot` (Task 3), `ObjectBoxWorkoutOutbox.enqueueCompletedInTransaction(requireValid: true)`, `InvalidCloudSnapshot` (Task 4), `WatchWorkoutReceiptEntity` (Task 6), `WorkoutPlanEntity.programUuid`.
- Produces:
  - `enum WatchImportResult { stored, duplicate, invalid }`
  - `class ObjectBoxWatchWorkoutImporter { ObjectBoxWatchWorkoutImporter(Store store, {required String accountId, required String? Function() activeAccountId, ObjectBoxWorkoutOutbox? outbox, DateTime Function()? clock}); WatchImportResult importCompleted({required String messageId, required RemoteWorkoutSnapshot snapshot, String? platformWorkoutUuid, ({String planId, String programId, String localDate})? programDay}); Set<String> platformWorkoutUuids(); }`
  - `final watchWorkoutImporterProvider = Provider<ObjectBoxWatchWorkoutImporter Function(String accountId, String? Function() active)>` built from `objectBoxStoreProvider` (same pattern as `workoutRestoreImporterProvider`).
- Rules, all inside one `TxMode.write` transaction:
  1. Receipt with this `workoutUuid` or this `messageId` exists → `duplicate`, no writes. *(My call: a receipt for the same message but a different workout is `invalid`.)*
  2. A session with this UUID exists: deleted (`deletedAtMs != null`) or a completed `beyondrep_watch` session (for example restored from the cloud on a reinstalled phone) → `duplicate`, no writes, never resurrected *(my call)*; any other session → `invalid`.
  3. `writeCompletedSnapshot`; collisions (`RestoreImportException`) → `invalid` (transaction rolled back).
  4. Program day: when the plan `programDay.planId` exists and its `programUuid == programDay.programId`, set `planUuid`, `programUuid`, `programDayLocalDate` on the session; otherwise import without them, never `invalid` *(my call)*.
  5. Put the receipt (`platformWorkoutUuid?.toLowerCase()`), then `enqueueCompletedInTransaction(uuid, requireValid: true)`; `InvalidCloudSnapshot` → `invalid` (rolled back).
  6. `activeAccountId() != accountId` checked before the transaction and as its last statement; a mismatch throws `StateError('account_changed')` so the transaction rolls back (same as the restore importer's `_checkAccount`).

- [ ] **Step 1: Write the failing tests** (temp-dir `Store`, synthetic snapshot built with `WorkoutRestorePage.parseWorkout` from the `completed_workout.json` fixture's `workout`):
  - `stores session, receipt and one pending outbox entry with origin beyondrep_watch` (session `status` completed, revision 1; outbox payload origin `beyondrep_watch`; receipt has the lowercase HKWorkout UUID).
  - `same message twice is a duplicate with no writes` (row counts unchanged).
  - `redelivery with a new message id is a duplicate` (Review Focus 1).
  - `a locally deleted workout is not resurrected` (delete via `deleteCompletedWorkout`, redeliver → `duplicate`, still a tombstone, delete op still queued) (Review Focus 2).
  - `a restored watch workout is a duplicate`; `a phone session with the same uuid is invalid`.
  - `a set uuid used by another workout is invalid and writes nothing`.
  - `an outbox-invalid snapshot writes nothing` (force `payload_too_large` with 120 exercises × long names).
  - `account changed inside the transaction rolls back` (`activeAccountId` flips after the first call; no session, receipt or outbox row) (Review Focus 3).
  - `after reopening the store a redelivery is a duplicate` (close and reopen the `Store` between import and redelivery) (Review Focus 4).
  - `program day is recorded when the plan belongs to the program`; `an unknown plan imports without a program day`.
  - `platformWorkoutUuids returns the stored HKWorkout ids lowercase`.
- [ ] **Step 2: Run** `flutter test test/watch/objectbox_watch_workout_importer_test.dart` — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat(watch): import completed watch workouts atomically into the outbox`

---

### Task 8: Inbox, ack and controller routing

**Files:**
- Create: `apps/mobile/lib/features/watch/application/watch_workout_inbox.dart`
- Modify: `apps/mobile/lib/features/watch/application/watch_snapshots.dart` (ack builder), `apps/mobile/lib/features/watch/application/watch_sync_controller.dart` (`_onMessage`)
- Test: `apps/mobile/test/watch/watch_workout_inbox_test.dart`, extend `apps/mobile/test/watch/watch_sync_controller_test.dart`

**Interfaces:**
- Consumes: Task 7 importer, `WorkoutRestorePage.parseWorkout`, `CompletedWorkout`, `watchAccountKey`, `watchLinkProvider`, `watchMessageIdsProvider`, `wallClockProvider`.
- Produces:
  - `Ack buildAck({required String accountKey, required String ackedMessageId, required String result, String? reason, required String messageId, required DateTime nowUtc})` in `watch_snapshots.dart`.
  - `class WatchWorkoutInbox { WatchWorkoutInbox({required WatchLink link, required ObjectBoxWatchWorkoutImporter Function(String accountId) importer, required String? Function() signedInUserId, required UuidFactory ids, required DateTime Function() clock, required void Function() onStored}); Future<WatchImportResult?> handle(CompletedWorkout message); }` — returns null when ignored. Order per Global Constraints. Parse failure (`RestoreContractException`) → `invalid`. Sends `buildAck(...)` JSON by `link.transfer` after the importer returns; `stored` calls `onStored()` first. Wrong account, signed out, or a `StateError('account_changed')` → null, nothing sent. *(My call: wrong account gets no ack at all, so the watch keeps the workout "waiting for the account it was recorded under", spec 5.4; the contract's `wrong_account` reason stays the watch's answer to phone messages.)*
  - `final watchWorkoutInboxProvider = Provider<WatchWorkoutInbox>` whose `onStored` invalidates `completedWorkoutHistoryProvider`, `programWeekProvider`, `blockedWorkoutCountProvider`, `workoutSyncFlagsProvider` and calls `ref.read(workoutUploadKickProvider)?.call()`.
  - `WatchSyncController._onMessage`: a decoded `CompletedWorkout` goes to `ref.read(watchWorkoutInboxProvider).handle(...)` (unawaited); `Ack` handling is unchanged. Undecodable JSON (including `unsupported_version`) is still dropped without an ack *(my call)*. `last_sequence` is not used by the phone *(my call)*.
  - *(My call, for 4b:* the phone does not buffer watch messages that arrive before the controller listens (cold launch, signed out). The watch must keep resending an unacked completed workout, at least whenever it receives a binding or context from the phone, which the controller sends after every launch.*)*

- [ ] **Step 1: Write the failing tests** (fake `WatchLink` recording `transfer`, real temp `Store`, fixture-based messages):
  - inbox `stores and acks stored with the signed-in key and the message id`; `ack is sent only after the import returned` (importer fake records order); `a duplicate acks duplicate`; `an invalid payload acks rejected invalid and stores nothing` (fixture with a completed set lacking reps and seconds); `another account's workout is ignored without an ack` (Review Focus 3); `signed out ignores the message`; `onStored runs only for stored`.
  - controller `a completed_workout from the watch is imported and acked` (push the JSON on `_FakeLink.messages`, pump, expect one `transfer` with an `Ack` `stored`); `an ack message is still handled as before`.
- [ ] **Step 2: Run** `flutter test test/watch` — FAIL. **Step 3: Implement.** **Step 4: Run** `flutter test test/watch test/account` — PASS.
- [ ] **Step 5: Commit** `feat(watch): acknowledge imported watch workouts after the local commit`

---

### Task 9: Outside workouts drop the watch's own HealthKit workout

**Files:**
- Modify: `apps/mobile/lib/features/health/data/platform_health_reader.dart` (`_ownAppId` filter ~312)
- Modify: `apps/mobile/lib/features/health/application/health_overview.dart` (`_read` workouts, new provider)
- Modify: `apps/mobile/lib/features/account/account_gate.dart` (override, next to `healthReaderProvider`)
- Modify: `docs/adr/0011-read-workouts-from-health-platforms.md` (rule 3)
- Test: `apps/mobile/test/health/platform_health_reader_test.dart`, `apps/mobile/test/health/health_overview_test.dart`

**Interfaces:**
- Reader: a workout is dropped when `sourceId` or `sourceName` **starts with** `in.beyondrep.app` (covers `in.beyondrep.app.watchkitapp`).
- `final ownPlatformWorkoutIdsProvider = Provider<Set<String>>((ref) => const {})` in `health_overview.dart`; `_read` takes `Set<String> ownWorkoutIds` (read once per overview read) and drops every `OutsideWorkout` whose `id.toLowerCase()` is in it, before the workouts section and the training load are built.
- `account_gate.dart` overrides it with `ref.watch(watchWorkoutImporterProvider)(owner, () => auth?.userId).platformWorkoutUuids()` (empty when signed out). Health application/domain still import no ObjectBox.
- *(My call: spec 4.6's "heart rate and calories from that HKWorkout attach to the BeyondRep session through the receipt" moves to 4b, when a real watch HKWorkout exists to test it; in 4a the receipt only hides it.)*
- ADR-0011 rule 3 new text: "**Our own writes are dropped.** Any workout whose `sourceId` or `sourceName` starts with `in.beyondrep.app` (the iPhone app and its watch app `in.beyondrep.app.watchkitapp`) is ignored, and so is any workout whose platform UUID is in a stored watch workout receipt (ADR-0012). *Amended 2026-11-27 for Phase 4 stage 4.*"

- [ ] **Step 1: Write the failing tests:** reader `a workout from in.beyondrep.app.watchkitapp is dropped`, `a source merely containing beyondrep elsewhere is kept` (`com.example.beyondrep`); overview `a workout whose uuid is a stored receipt is not an outside workout and adds no load` (override the provider with the fake reader's workout id in upper case).
- [ ] **Step 2: Run** `flutter test test/health` — FAIL. **Step 3: Implement** and amend the ADR. **Step 4: Run** `flutter test test/health` (includes `health_import_guard_test.dart`) — PASS.
- [ ] **Step 5: Commit** `feat(health): hide BeyondRep watch workouts from outside workouts`

---

### Task 10: Deletion wipe persisted and retried (stage 3 deferred M6)

**Files:**
- Create: `apps/mobile/lib/features/watch/data/watch_wipe_queue.dart`, `apps/mobile/lib/features/watch/application/watch_wipe_retrier.dart`
- Modify: `apps/mobile/lib/features/watch/data/watch_link.dart` (`MethodChannelWatchLink.shared`, `watchLinkProvider`), `apps/mobile/lib/features/watch/application/watch_sync_controller.dart` (`announceWatchAccountDeleted`, `accountDeleted`), `apps/mobile/lib/main.dart` (`_AuthBootstrapState`)
- Test: `apps/mobile/test/watch/watch_wipe_retrier_test.dart`, extend `apps/mobile/test/watch/watch_link_test.dart` and `watch_sync_controller_test.dart`

**Interfaces:**
- `class PendingWatchWipe { const PendingWatchWipe({required this.messageId, required this.json}); final String messageId; final String json; }`
- `class WatchWipeQueue { WatchWipeQueue(SharedPreferences prefs); static Future<WatchWipeQueue> open(); List<PendingWatchWipe> pending(); Future<void> add(PendingWatchWipe wipe); Future<void> remove(String messageId); }` — key `watch_link.pending_wipes`, a JSON list; keeps the newest 10 *(my call)*; holds only the account key HMAC inside the message, never the user id. Not cleared by `WatchStatusStore.clear()` and outside the account store (which deletion removes).
- `final watchWipeQueueProvider = Provider<Future<WatchWipeQueue>>((ref) => WatchWipeQueue.open())`.
- `announceWatchAccountDeleted({required WatchLink link, required String userId, required UuidFactory ids, required DateTime nowUtc, required Future<WatchWipeQueue> queue})`: build the wipe, `queue.add` **first**, then, if `isReachableForUpdates()`, `transfer` and `updateContext({'account_cleared': json})` as today. A queue failure never stops the immediate send.
- `class WatchWipeRetrier { WatchWipeRetrier({required WatchLink link, required Future<WatchWipeQueue> queue}); void start(); Future<void> retry(); void dispose(); }` — `start` listens to `link.messages`, `link.watchStateChanges` and `AppLifecycleListener(onResume:)`, then calls `retry()`. `retry` transfers (user info only, never the context, since another account may be bound by then *(my call)*) each pending wipe not yet sent since `start` or the last `watchStateChanges`, only when `isReachableForUpdates()`. An `Ack` with result `stored` or `duplicate` whose `ackedMessageId` matches a pending wipe removes it *(my call: removal on the watch's ack, not on "reachable", which only means paired and installed)*.
- `static final MethodChannelWatchLink shared` and `watchLinkProvider` returns it on iOS: two instances would fight over the one platform handler (`_handling`), and the retrier must hear acks while the signed-in controller also listens *(my call)*. `main.dart` passes `MethodChannelWatchLink.shared` to `announceWatchAccountDeleted` and, on iOS only, starts one `WatchWipeRetrier` after `controller.restore()`, disposed in `dispose()`.

- [ ] **Step 1: Write the failing tests:** queue `add, pending and remove round-trip`, `keeps the newest 10`; announce `the wipe is persisted even when no watch is reachable`; retrier `a persisted wipe is resent on the next launch and removed on ack` (new queue instance over the same mocked prefs, fake link reachable, ack JSON pushed on `messages`) (Review Focus 5); `not reachable sends nothing and keeps the wipe`; `a watch state change sends it again`; `an ack for another message id removes nothing`; `rejected ack removes nothing`; link `watchLinkProvider on iOS returns the shared instance` (`debugDefaultTargetPlatformOverride`).
- [ ] **Step 2: Run** `flutter test test/watch` — FAIL. **Step 3: Implement.** **Step 4: Run** `flutter test test/watch test/account test/app_test.dart` — PASS.
- [ ] **Step 5: Commit** `fix(watch): retry the account deletion wipe until the watch confirms it`

---

### Task 11: Docs and status

**Files:**
- Modify: `docs/adr/0012-apple-watch-companion.md` (Consequences), `docs/SYNC_PROTOCOL.md`, `docs/ROADMAP.md`, `docs/RELEASE.md`, `CLAUDE.md`, `docs/HEALTH_DATA.md` (line 51), `docs/WEARABLES.md` only if it states watch workouts are not backed up (grep first)

**Content (exact facts; wording follows each file's style):**
- ADR-0012 Consequences, add: the migration `20261127090000_workout_origin_beyondrep_watch.sql` lets the server accept `beyondrep_watch`; the phone imports `completed_workout` atomically (workout, receipt, outbox) and acks only after commit; wrong-account workouts get no ack; the `completed_workout` body gained optional `program_day`; ADR-0011 rule 3 amended; the deletion wipe is persisted and retried until acked. Keep "Nothing here is released or device-verified."
- SYNC_PROTOCOL: "Cloud workout payload" `origin` becomes (`northstar_phone` or `beyondrep_watch`); add a deploy-order bullet for the new migration in the style of the `duration_seconds` one ("Older app builds reject the unknown origin when restoring (`invalid_workout_origin`, the whole page is refused), so update every install"); rule 5 says the import is "one ObjectBox transaction with the inbox receipt and outbox entry, then the `ack`"; rule 8 says the receipt travels as `healthkit_workout_uuid` on `completed_workout`.
- ROADMAP Phase 4: replace "Stage 4 notes (not started)" with "Stage 4a (phone import and `beyondrep_watch` origin, implemented in source, not released or device-verified)" summarising Tasks 1–10, and "Stage 4b (not started)": watch HealthKit session, logging screens, rest timer, sending and resending completed workouts, attaching HKWorkout heart rate and kcal through the receipt, and the watch dropping tombstones/binding if the phone never returns (unchanged open item).
- RELEASE: new section "Phase 4 stage 4a: watch workout import and `beyondrep_watch` origin (owner actions, none done)" with rows, all `not run`: deploy order — the `supabase-database` job has applied `20261127090000_workout_origin_beyondrep_watch.sql` to the project under test **before** any build that uploads watch workouts; every install on every phone of the test account updated before the first watch workout is uploaded; a restored watch workout on a second phone shows the Apple Watch tag; deleting the account with the watch out of range, then bringing it in range: the watch drops that account's unsent workouts. Note that 4a cannot be device-tested end to end until 4b sends workouts.
- CLAUDE.md "Project state": one bullet "Phase 4 stage 4a ... (implemented in source, not released or device-verified)"; keep "watch workout recording" under **Not implemented** and do not mention a deployed migration.
- HEALTH_DATA.md: `beyondrep_apple_watch` → `beyondrep_watch` *(my call: one origin name everywhere)*.

- [ ] **Step 1: Edit the docs.**
- [ ] **Step 2: Run** `python3 -m unittest discover -s tool -p 'test_*.py'` (repo layout and README checks) — PASS; then from `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test` — PASS.
- [ ] **Step 3: Commit** `docs: phase 4 stage 4a watch workout import`

---

## Checks this plan cannot run here

- pgTAP (Task 1): CI `supabase_sql.yml` only.
- Swift (Task 2): CI `watchos_smoke.yml` and `ios-with-watch` only.
- Any device behaviour (WatchConnectivity delivery, acks across a real watch, account deletion with the watch away): owner rows in `docs/RELEASE.md`; end-to-end needs stage 4b.
- Hosted migration: owner runs the Codemagic `supabase-database` job; never claim it ran.
