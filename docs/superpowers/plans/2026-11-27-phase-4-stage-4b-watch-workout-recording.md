# Phase 4 stage 4b: record workouts on the Apple Watch — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (Adi's choice for this project: one Sonnet agent runs the whole plan, then an Opus review) to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person can start a plan, today's program workout or a quick workout on the Apple Watch, log sets with the Digital Crown, rest with a haptic, finish, and have the workout saved once to Apple Health and delivered to the iPhone (which stage 4a already imports and backs up).

**Architecture:** All rules live in the pure `BeyondRepWatchCore` package and are tested by `swift test`. That covers the workout template, the cursor, the rest deadline, the completed-workout builder, the journal's delivery state and the `WorkoutController` that commits one journal transaction per user action. The watch app (`apps/watch_os/Sources`) adds a thin HealthKit wrapper, the SwiftUI screens and the sending of queued workouts over WatchConnectivity. The phone does not change: stage 4a already imports `completed_workout` and acks it.

**Tech stack:** Swift 5.9, SwiftUI, HealthKit (`HKWorkoutSession`, `HKLiveWorkoutBuilder`), WatchConnectivity, SQLite (system `libsqlite3`), XCTest (`swift test`), Python contract tests, Dart contract tests.

**Spec:** `docs/superpowers/specs/2026-11-26-phase-4-watch-and-tablet-design.md` §4.2, §4.3, §4.6, §5.2–5.5 and §5.7, ADR-0012, and the workout mockups at claude.ai/artifact/5pDB7SGkMDBWDSHdoaPZB6. Adi picked **set screen Option A** on 2026-11-27: weight and reps side by side, the crown changes the box with the green outline, tap the other box to switch, then one "Log set" button.

## Global constraints

- The repository is public: synthetic data only (`@example.invalid`, fixture UUIDs), no keys, profiles, team ids or hosted refs.
- Read `AGENTS.md`, `apps/watch_os/AGENTS.md` and `docs/WEARABLES.md` first.
- **Core package rule:** `BeyondRepWatchCore` imports only Foundation and SQLite. HealthKit, WatchConnectivity, WatchKit and SwiftUI stay in `apps/watch_os/Sources`.
- **Commit before "saved":** every user action writes its event and the session state in one `WatchJournal` transaction before the UI shows it as done.
- **Fresh UUIDs per workout (ROADMAP 4b requirement a):** the exercise and set ids in a watch workout are new lowercase UUIDs made when the workout starts or a set or exercise is added. Never copy them from plan or catalogue ids such as `builtin.v1.*` or `plan-*`.
- **One HKWorkout per session:** the watch saves at most one `HKWorkout` per session. It carries the workout id in `HKMetadataKeyExternalUUID` so that recovery can find it instead of saving a second one.
- **HealthKit permissions on the watch (spec §4.6):**
  - share: `HKObjectType.workoutType()` only;
  - read: `heartRate` and `activeEnergyBurned` only.
  - If the person denies access, the workout still records, with no heart rate and no `healthkit_workout_uuid`.
- **Never send health values to the phone in the payload.** The `completed_workout` carries only the HKWorkout UUID. Heart rate and calories are read by the phone in stage 4c.
- **Units:** the binding `unit` (`kg` or `lb`) is the input unit.
  - Grams use 1000 per kg and 453.59237 per lb, rounded (the same as `apps/mobile/lib/core/units/load_units.dart`).
  - Crown steps: 2.5 kg or 5 lb for weight, 1 for reps, 5 s for timed sets.
  - Ranges: weight 0–500 kg or 0–1100 lb, reps 1–100, seconds 5–3600.
  - A weight of 0 or no weight is sent as no `load_grams`.
- **RPE:** 6, 7, 8, 9 or 10, optional. The sheet closes itself after 5 s with no RPE.
- **Default rest:** the plan set's `rest_seconds`, else 90 s. "+30 s" adds 30 s to what remains, capped at 3600 s.
- **Starting needs a binding** (spec §5.4). With none, Train shows "Open BeyondRep on your iPhone to sign in." and no Start button.
- Minimum watchOS is 10.0 (unchanged).
- **Copy (exact strings):**
  - set screen: "Log set", "Set {n} of {m}", "Turn the crown · tap the other box to switch"
  - RPE sheet: "How hard was it?", "RPE, optional", "Skip"
  - rest: "Rest", "+30 s", "Skip", "Next: {exercise} · set {n} of {m}"
  - overview: "Time", "Heart rate", "Sets", "Pause", "Resume", "End"
  - end: "End workout?", "Save workout", "Keep going", "Discard"
  - discard confirmation: "Discard this workout? It is deleted from your watch."
  - summary: "Done", "Saved on watch · sent to iPhone", "Saved on watch · waiting for iPhone", "Saved to iPhone"
  - Train: "+ Quick workout", "Start"
  - no sets: "No sets logged yet." (Save is disabled, Discard stays)
- Run `cd tool && bundle exec ruby embed_watch_target.rb` after adding or removing any watch Swift file, and commit the changed `Runner.xcodeproj`.
- **Out of scope (stage 4c):**
  - the phone reading heart rate and calories through the receipt;
  - pruning the watch's tombstones and binding when the phone never returns;
  - the cross-phone resurrection test (ROADMAP 4b requirement b).
- **Out of scope (stage 5):** live handoff, workout mirroring and phone commands.

## Review focus

1. **The app is killed after the HKWorkout is saved but before the journal queues the completed workout.** On relaunch the watch finds the saved HKWorkout by its external UUID and queues it. It never saves a second one. *(Task 6, `testFinishingSessionIsFoundAfterRestart` and `testQueueCompletedIsIdempotent`.)*
2. **A second workout from the same plan.** It gets entirely new exercise and set ids, and the phone does not reject it. *(Task 2, `testTwoSessionsFromOnePlanShareNoIds`.)*
3. **The phone acks a message the watch has already removed, or acks twice.** Nothing changes and nothing throws. *(Task 1, `testAckForUnknownMessageIsIgnored` and `testSecondAckChangesNothing`.)*
4. **A discarded workout.** Nothing from it is ever sent: no event messages and no completed workout. *(Task 1, `testAbandonDropsQueuedEventMessages`, and Task 6, `testDiscardQueuesNothing`.)*
5. **A workout recorded under account A while the phone is now signed in as B.** It stays queued and is counted as waiting, never sent as B's or deleted. *(Task 1, `testWaitingCountsSplitByAccount`.)*

---

## File structure

Core package (`apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/`):

- `Store/WatchJournal.swift` (modify): schema version 6, delivery state, a filtered outbox, the template column.
- `Session/WorkoutTemplate.swift` (create): the session's exercises and planned sets, with fresh ids, built from a plan or empty.
- `Session/WorkoutCursor.swift` (create): the current set, prefill, "Set n of m", and what comes next.
- `Session/RestClock.swift` (create): the rest deadline from events.
- `Session/CompletedWorkoutBuilder.swift` (create): events and template to a `completed_workout` message.
- `Session/WorkoutController.swift` (create): one object per session that runs `SessionMachine`, commits to the journal and restores after a relaunch.
- `Link/PhoneInbox.swift` (modify): handles `ack`.
- `Glance/SyncLine.swift` (modify): the waiting-workouts count.

Contracts:

- `contracts/watch_link/v1/cases/completed/*.json` (create): golden builder cases.
- `contracts/watch_link/v1/README.md` (modify).
- `tool/test_watch_link_contract.py` (modify): the schema check of the cases.
- `apps/mobile/test/watch/contract_fixtures_test.dart` (modify): Dart decode and `parseWorkout` of the cases.

Watch app (`apps/watch_os/`):

- `Sources/HealthKit/WorkoutRecorder.swift` (create): the HealthKit session wrapper.
- `Sources/App/AppModel.swift` (modify): the workout controller, sending queued workouts, acks.
- `Sources/Connectivity/PhoneLink.swift` (modify): `send(completed:)` and outstanding transfer ids.
- `Sources/Features/Train/TrainPage.swift` (modify): tappable cards and Quick workout.
- `Sources/Features/Workout/` (create):
  - `PlanPreviewView.swift`
  - `WorkoutView.swift` (pages)
  - `SetPage.swift`
  - `RpeSheet.swift`
  - `RestPage.swift`
  - `OverviewPage.swift`
  - `EndConfirmView.swift`
  - `SummaryView.swift`
  - `ExercisesSheet.swift`
- `Sources/Features/Root/RootView.swift` (modify): shows the workout while one is active.
- `Sources/Features/Sync/SyncView.swift` (modify): the waiting line.
- `BeyondRepWatch.entitlements` (create).
- `Sources/Resources/Info.plist` (create; partial Info.plist for `WKBackgroundModes`).
- `project.yml` (modify).
- Wiring for the embedded watch target:
  - `tool/embed_watch_target.rb` (modify): entitlements, Info.plist and HealthKit usage strings for the embedded target;
  - `tool/test_watch_embedding.py` (modify);
  - `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (regenerated).

Docs: `docs/ROADMAP.md`, `docs/RELEASE.md`, `docs/WEARABLES.md`, `docs/HEALTH_DATA.md`, `CLAUDE.md`, `docs/IOS_TESTFLIGHT_CODEMAGIC.md` (owner action).

---

### Task 1: Journal version 6 (delivery state and a filtered outbox)

**Files:**
- Modify: `Store/WatchJournal.swift`
- Test: `Tests/BeyondRepWatchCoreTests/WatchJournalTests.swift`

**Interfaces:**
- Produces:
  - `func queueCompleted(_ message: WatchMessage, sessionId: String) throws`: enqueues the message (type `completed_workout`) and sets the session's `delivery = 'queued'` in one transaction. A second call for the same message id changes nothing.
  - `func pendingCompleted(limit: Int) throws -> [WatchMessage]`: only `completed_workout` rows, oldest first.
  - `enum AckEffect: Equatable { case delivered(sessionId: String), rejected(sessionId: String) }`
  - `func applyAck(ackedMessageId: String, result: String) throws -> AckEffect?`:
    - `stored` or `duplicate`: deletes the completed message and every outbox row of that session, deletes the session's `events` and `applied_commands`, and sets `delivery = 'delivered'`.
    - `rejected`: the same deletes, with `delivery = 'rejected'`.
    - An unknown id returns nil.
    - One transaction. Case-insensitive ids.
  - `func sessionsAwaitingQueue(accountKey: String) throws -> [String]`: session ids with status `completed` and delivery NULL (finish was interrupted).
  - `func waitingCounts(boundKey: String?) throws -> (thisAccount: Int, otherAccounts: Int)`: queued completed messages split by whether `account_key == boundKey`.
  - `func saveTemplate(sessionId: String, json: String) throws` and `func template(sessionId: String) throws -> String?`.
  - `record(...)` gains `template: String? = nil`. It is written in the same transaction as the events.
  - When `sessionState.status == "abandoned"`, `record` also deletes that session's outbox rows.
  - `activeSession` also returns `sessionId`.

- [ ] **Step 1: Write the failing tests** in `WatchJournalTests.swift`:
  - `testVersion6AddsColumnsAndKeepsRows`: open a version-5 database built with the old statements, insert a binding and an outbox row, reopen, and assert `PRAGMA user_version == 6`. Assert the rows are still there, and that `outbox` has `type` and `session_id` and `sessions` has `delivery` and `template_json`.
  - `testPendingCompletedSkipsEventMessages`: record a start plus a set (2 event messages), queue a completed message, and assert `pendingCompleted(limit: 10).map(\.type) == ["completed_workout"]`.
  - `testStoredAckClearsSessionOutboxAndEvents`: after `applyAck(id, "stored")`, the effect is `.delivered(sessionId)`, `pendingOutbox(limit: 50)` is empty for that session, there are 0 `events` rows for it, and delivery is `delivered`.
  - `testDuplicateAckCountsAsDelivered`.
  - `testRejectedAckMarksRejected`.
  - `testAckForUnknownMessageIsIgnored`: returns nil and changes no row counts.
  - `testSecondAckChangesNothing`: the second call returns nil.
  - `testAbandonDropsQueuedEventMessages`: start, log, abandon (record with state status `abandoned`), and assert 0 outbox rows for the session.
  - `testQueueCompletedIsIdempotent`: calling it twice gives 1 outbox row.
  - `testWaitingCountsSplitByAccount`: queue one for key A and one for key B, and assert `waitingCounts(boundKey: A) == (1, 1)` and `waitingCounts(boundKey: nil) == (0, 2)`.
  - `testSessionsAwaitingQueue`: a session recorded with status `completed` and no queue call is listed; after `queueCompleted` it is not.
  - `testTemplateIsWrittenWithTheStartEvents`: `record(startEvents, template: "{...}")`, then `template(sessionId:)` returns it. With `failAt: .afterSessionUpsert` neither is written.
- [ ] **Step 2: Run** `cd apps/watch_os/Packages/BeyondRepWatchCore && swift test --filter WatchJournalTests`. Expected: the new tests fail. (This needs macOS. In the Linux container, write the tests and code, and rely on `watchos_smoke.yml`, saying so in the report.)
- [ ] **Step 3: Implement.**
  - Migration: version 6 adds the columns with `ALTER TABLE ... ADD COLUMN` only when absent, following the binding pattern.
    - `outbox.type TEXT NOT NULL DEFAULT ''`
    - `outbox.session_id TEXT NOT NULL DEFAULT ''`
    - `sessions.delivery TEXT`
    - `sessions.template_json TEXT`
  - `enqueue` fills `type` from `message.type`. It fills `session_id` from the event header, or from the `sessionId` argument for `queueCompleted`.
- [ ] **Step 4: Run the same command.** Expected: PASS, and the existing journal tests still pass.
- [ ] **Step 5: Commit** `feat(watch-core): journal v6 delivery state and completed-only outbox`.

### Task 2: Workout template and cursor

**Files:**
- Create: `Session/WorkoutTemplate.swift`, `Session/WorkoutCursor.swift`
- Test: `Tests/BeyondRepWatchCoreTests/WorkoutTemplateTests.swift`, `WorkoutCursorTests.swift`

**Interfaces:**
- Produces:
  - Template types:

    ```swift
    public struct TemplateSet: Codable, Equatable { public var setId: String; public var position: Int; public var kind: String; public var targetReps: Int?; public var targetSeconds: Int?; public var targetLoadGrams: Int?; public var restSeconds: Int? }
    public struct TemplateExercise: Codable, Equatable { public var exerciseId: String; public var name: String; public var kind: String /* reps|duration */; public var muscle: String?; public var position: Int; public var sets: [TemplateSet] }
    public struct WorkoutTemplate: Codable, Equatable {
      public var name: String; public var planId: String?; public var programDay: ProgramDay?; public var exercises: [TemplateExercise]
      public static func fromPlan(plansSnapshot raw: [String: Any], planId: String, makeId: () -> String) -> WorkoutTemplate?
      public static func today(plansSnapshot raw: [String: Any], makeId: () -> String) -> WorkoutTemplate?   // uses body.today
      public static func quick(name: String = "Quick workout") -> WorkoutTemplate
      public mutating func addExercise(name: String, kind: String, muscle: String?, makeId: () -> String) -> String  // returns new exerciseId, one empty set
      public mutating func addSet(exerciseId: String, makeId: () -> String) -> String  // copies the last set's targets
      public var exerciseAddedPayloads: [ExerciseAddedPayload] { get }
    }
    public struct ProgramDay: Codable, Equatable { public var planId: String; public var programId: String; public var localDate: String }
    ```

  - The cursor:

    ```swift
    public struct SetPosition: Equatable { public let exercise: TemplateExercise; public let set: TemplateSet; public let indexInExercise: Int; public let countInExercise: Int }
    public struct WorkoutCursor {
      public init(template: WorkoutTemplate, state: ReplayedWorkout, focusExerciseId: String? = nil)
      public var current: SetPosition? { get }      // first set (focused exercise first, then template order) with no completed/skipped state
      public func prefill(for position: SetPosition, unit: String) -> SetValues  // last completed set of the same exercise in this session, else targets
      public func next(after position: SetPosition) -> SetPosition?
      public var completedCount: Int { get }; public var plannedCount: Int { get }
    }
    ```

- [ ] **Step 1: Write the failing tests:**
  - `testFromPlanMakesFreshUuidsForExercisesAndSets`: use the `plans_snapshot.json` fixture. Every `exerciseId` and `setId` matches the lowercase UUID regex, none equals `builtin.v1.synthetic-move-1` or the fixture's exercise id, and the names, kinds, muscle, positions and targets are copied.
  - `testTwoSessionsFromOnePlanShareNoIds`: two templates from the same plan have disjoint id sets.
  - `testTodayCarriesProgramDay`: `programDay == ProgramDay(planId: "plan-synthetic-1", programId: "program-synthetic-1", localDate: "2026-10-23")`.
  - `testUnknownPlanIsNil`.
  - `testQuickHasNoExercises`.
  - `testAddSetCopiesLastTargets`.
  - `testAddExerciseHasOneSet`.
  - `testCurrentSkipsCompletedAndSkippedSets`.
  - `testCurrentIsNilWhenAllDone`.
  - `testPrefillUsesLastCompletedSetOfSameExercise`: after logging 60 kg × 8, the next set's prefill is 60 kg × 8 even though its target is 62.5 kg × 6.
  - `testPrefillFallsBackToTargets`.
  - `testPrefillDurationExerciseHasSecondsNotReps`.
  - `testPrefillUsesBindingUnit`: `inputUnit == "lb"` when the unit is lb.
  - `testNextMovesToNextExerciseAfterLastSet`.
  - `testFocusExerciseComesFirst`.
  - `testCountsExcludeWarmups`: `plannedCount` and `completedCount` count working sets only, the same rule as `ReplayedWorkout.completedSets`.
- [ ] **Step 2: Run** `swift test --filter 'WorkoutTemplateTests|WorkoutCursorTests'`. Expected: FAIL (types missing).
- [ ] **Step 3: Implement.**
  - The template reads the plan dictionary keys exactly as `plans_snapshot.json` uses them (`plan_id`, `exercises[].exercise_id|name|kind|muscle|sets[].position|kind|target_reps|target_seconds|target_load_grams|rest_seconds`).
  - The source `exercise_id` is not kept.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(watch-core): workout template with fresh ids and set cursor`.

### Task 3: Rest clock

**Files:**
- Create: `Session/RestClock.swift`
- Test: `Tests/BeyondRepWatchCoreTests/RestClockTests.swift`

**Interfaces:**
- Produces: `public enum RestClock { public static func deadline(events: [WorkoutEventV2]) -> Date?; public static func extendedSeconds(remaining: TimeInterval) -> Int }`.
  - `deadline` is the deadline of the highest-sequence `rest_started`, unless a later `rest_cleared`, `set_logged`, `workout_paused`, `workout_completed` or `workout_abandoned` follows it.
  - `extendedSeconds` is `min(3600, max(1, Int(remaining.rounded(.up)) + 30))`.
- [ ] **Step 1: Write the failing tests:**
  - `testDeadlineFromLastRestStarted`
  - `testClearedRestHasNoDeadline`
  - `testLoggedSetEndsRest`
  - `testPausedEndsRest`
  - `testExtendAddsThirtyAndCaps`: the expected values are 72 for 41.2 s, 3600 for 3590 s and 30 for 0 s.
- [ ] **Step 2: Run** `swift test --filter RestClockTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(watch-core): rest deadline from events`.

### Task 4: Completed-workout builder and golden contract cases

**Files:**
- Create: `Session/CompletedWorkoutBuilder.swift`
- Create: `contracts/watch_link/v1/cases/completed/plan_with_skip_and_timed.json`, `contracts/watch_link/v1/cases/completed/program_day_lb_no_healthkit.json`
- Modify: `contracts/watch_link/v1/README.md`, `tool/test_watch_link_contract.py`, `apps/mobile/test/watch/contract_fixtures_test.dart`
- Test: `Tests/BeyondRepWatchCoreTests/CompletedWorkoutBuilderTests.swift`

**Interfaces:**
- Produces:

  ```swift
  public enum CompletedWorkoutBuilder {
    public static func message(
      events: [WorkoutEventV2], template: WorkoutTemplate, unit: String, accountKey: String,
      healthkitWorkoutUuid: String?, messageId: String, sentAtUtc: String
    ) throws -> WatchMessage
  }
  ```

  The rules:
  - It throws `SessionError.invalidTransition` unless the replayed status is `completed` with at least one completed set.
  - Body: `last_sequence` is the max sequence, `healthkit_workout_uuid` is added only when non-nil, and `program_day` is added only when the template has one (`plan_id`, `program_id`, `local_date`).
  - `workout`:
    - `schema_version` 1, `workout_id` is the header workout id, `origin` is `beyondrep_watch` and `status` is `completed`;
    - `name` comes from `workout_started`;
    - `started_at_utc` and `completed_at_utc` are the `occurred_at_utc` of `workout_started` and `workout_completed`;
    - `original_offset_minutes` is the offset of the event `time_zone` at the start instant.
  - `exercises`: those from the template that have at least one completed or skipped set, in template position order. Each has `id`, `name`, `position`, plus `muscle` and `primary_muscles: [muscle]` when the muscle is non-nil.
  - `sets`: completed and skipped sets only, in position order.
    - A completed set has `id`, `position`, `kind`, `status`, `input_unit` (from the logged values), `reps` or `duration_seconds`, `load_grams` only when > 0, `rpe` when set, and `completed_at_utc` (the occurred time of the set's last event).
    - A skipped set has `id`, `position`, `kind`, `status: "skipped"` and `input_unit: unit`.
  - It decodes its own output with `WatchMessage(json:)` before returning, so a strict-codec failure throws.

The contract case format is `{"events": [...v2 envelopes...], "context": {"template": {...WorkoutTemplate JSON...}, "unit": "kg", "account_key": "...", "healthkit_workout_uuid": "...", "message_id": "...", "sent_at_utc": "..."}, "expected": {...full completed_workout message...}}`.

- [ ] **Step 1: Write the two cases by hand**, with synthetic ids and the `Asia/Kolkata` time zone (offset 330).
  - `plan_with_skip_and_timed`: 2 exercises; a set logged then corrected with an RPE; one skipped set; one timed set; and an exercise with no sets, which must be absent from `expected`.
  - `program_day_lb_no_healthkit`: `lb`, a `program_day`, no `healthkit_workout_uuid`, and a 0-weight set with no `load_grams`.
- [ ] **Step 2: Write the failing tests.**
  - Swift `CompletedWorkoutBuilderTests`:
    - `testGoldenCasesMatch`: for every file in `cases/completed`, the builder output's JSON object equals `expected`. Load it with `FixtureLoader`, the same way as the replay cases.
    - `testThrowsWhenNotCompleted`.
    - `testThrowsWhenNoCompletedSet`.
    - `testOutputDecodesWithStrictCodec`.
  - Python `test_completed_cases_validate_against_schema`: every `expected` validates against `message.schema.json`, and every event validates against `workout_sync/v2`.
  - Dart `completed cases decode and pass parseWorkout`: for each case, `WatchMessage.decode(expected)` is a `CompletedWorkout`, and `WorkoutRestorePage.parseWorkout(workout, workoutId: id, origins: {WorkoutOrigin.watch})` does not throw.
- [ ] **Step 3: Run**:
  - `python3 -m unittest tool.test_watch_link_contract`: the new test fails until the cases are valid; fix the cases, not the schema.
  - `cd apps/mobile && flutter test test/watch/contract_fixtures_test.dart`: PASS once the cases are right.
  - The Swift tests fail (builder missing).
- [ ] **Step 4: Implement the builder** and document the case format in the contracts README under "Completed cases".
- [ ] **Step 5: Run the Python and Dart tests again** (PASS). Swift runs on CI.
- [ ] **Step 6: Commit** `feat(watch-core): completed workout builder with shared golden cases`.

### Task 5: Ack handling and the waiting line

**Files:**
- Modify: `Link/PhoneInbox.swift`, `Glance/SyncLine.swift`
- Test: `PhoneInboxTests.swift`, `SyncLineTests.swift`

**Interfaces:**
- Consumes: `WatchJournal.applyAck` and `waitingCounts` (Task 1).
- Produces:
  - `PhoneInbox.receive(userInfo:)` handles `.ack`:
    - it calls `applyAck` only when the ack's `account_key` equals the key of the queued message's row;
    - it returns no outcome (an ack is never acked);
    - a mismatched key counts in `ignoredCount`.
  - `public private(set) var lastAckEffects: [AckEffect]` is appended per applied ack, for the app to refresh.
  - `SyncLine` gains `waiting: Int` and `waitingOtherAccount: Int`, from `waitingCounts`.
    - Line text: `"1 workout waiting for iPhone"` or `"{n} workouts waiting for iPhone"`.
    - When `waitingOtherAccount > 0`: `"{n} from another account waiting"`.
- [ ] **Step 1: Write the failing tests:**
  - `testStoredAckMarksDelivered`
  - `testRejectedAckMarksRejected`
  - `testAckWithOtherAccountKeyIsIgnored`
  - `testAckProducesNoOutcome`
  - `testSyncLineCountsWaitingWorkouts`
  - `testSyncLineShowsOtherAccountWaiting`
- [ ] **Step 2: Run** `swift test --filter 'PhoneInboxTests|SyncLineTests'`. Expected: FAIL.
- [ ] **Step 3: Implement.** The current `default:` branch, which rejects watch-bound types, keeps rejecting everything except `ack`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(watch-core): apply phone acks for completed workouts`.

### Task 6: Workout controller (one commit per action, restore, finish in two steps)

**Files:**
- Create: `Session/WorkoutController.swift`
- Test: `Tests/BeyondRepWatchCoreTests/WorkoutControllerTests.swift`

**Interfaces:**
- Consumes: `SessionMachine`, `WatchJournal` (Task 1), `WorkoutTemplate` and `WorkoutCursor` (Task 2), `RestClock` (Task 3), `CompletedWorkoutBuilder` (Task 4).
- Produces:

  ```swift
  public final class WorkoutController {
    public static func start(template: WorkoutTemplate, journal: WatchJournal, accountKey: String, unit: String, deviceId: String, clock: @escaping () -> Date, timeZone: String, makeId: @escaping () -> String) throws -> WorkoutController
    public static func restore(journal: WatchJournal, accountKey: String, unit: String, deviceId: String, clock: @escaping () -> Date, timeZone: String) throws -> WorkoutController?
    public var sessionId: String { get }; public var workoutId: String { get }
    public var template: WorkoutTemplate { get }; public var state: ReplayedWorkout { get }; public var status: String { get }
    public var cursor: WorkoutCursor { get }; public var restDeadline: Date? { get }; public var startedAt: Date { get }
    public func log(_ values: SetValues) throws            // log + startRest(rest_seconds ?? 90) committed together (one record call, two events)
    public func setRpe(setId: String, rpe: Double?) throws // set_corrected with the same values and the new rpe
    public func skip(setId: String) throws
    public func extendRest() throws; public func skipRest() throws
    public func pause() throws; public func resume() throws
    public func addSet(exerciseId: String) throws -> String
    public func addExercise(name: String, kind: String, muscle: String?) throws -> String  // exercise_added + template saved
    public func focus(exerciseId: String)
    public func markCompleted() throws                     // workout_completed recorded; NOT queued
    public func queueCompleted(healthkitWorkoutUuid: String?) throws  // builds + journal.queueCompleted; idempotent
    public func discard() throws                           // workout_abandoned
    public static func pendingFinish(journal: WatchJournal, accountKey: String) throws -> [String]  // = sessionsAwaitingQueue
    public static func queuePendingFinish(sessionId: String, journal: WatchJournal, unit: String, accountKey: String, healthkitWorkoutUuid: String?, makeId: () -> String, clock: () -> Date) throws
  }
  ```

  The template JSON is written with the start events (`record(template:)`). `restore` returns nil when there is no active or paused session for the key.

- [ ] **Step 1: Write the failing tests** (temporary-file journal, fixed clock and id makers):
  - `testStartCommitsStartedExercisesAndTemplate`: there are `1 + exercises.count` events and `template(sessionId:)` is non-nil.
  - `testLogStartsRestWithPlanSeconds`: `restDeadline == clock + 90`, or the set's `rest_seconds`.
  - `testSetRpeCorrectsTheSet`: the state's set has `rpe == 8` and history count 2.
  - `testRestoreAfterRelaunchKeepsCursorAndRest`: a new controller from `restore` has the same `cursor.current` set id, the same `restDeadline` and the same template.
  - `testRestoreIgnoresOtherAccount`.
  - `testMarkCompletedDoesNotQueue`: `pendingCompleted` is empty and `pendingFinish` contains the session.
  - `testQueueCompletedQueuesOnce`: called twice, there is 1 message, `pendingFinish` is empty, and the message's `healthkit_workout_uuid` is the one passed.
  - `testFinishingSessionIsFoundAfterRestart`: `markCompleted`, drop the controller, and `pendingFinish` lists the session. `queuePendingFinish(... healthkitWorkoutUuid: "1111...")` queues it with that UUID.
  - `testDiscardQueuesNothing`: after log and discard, `pendingOutbox(limit: 50)` has no row for the session.
  - `testAddExerciseInQuickWorkout`: a quick workout, then `addExercise`, `log` and `markCompleted`. `queueCompleted` produces a workout with that exercise.
  - `testCannotQueueWithoutCompletedSet`: throws.
  - `testFailedCommitLeavesStateUnchanged`: with the journal's `failAt: .afterSessionUpsert`, `log` throws and `state.completedSets` is unchanged. The controller recomputes from the journal (restore path) after a failed commit, so its in-memory machine never runs ahead of disk.
- [ ] **Step 2: Run** `swift test --filter WorkoutControllerTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Each mutating method builds the events on a copy of the machine, commits them, and only then replaces the machine.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(watch-core): workout controller with durable actions and two-step finish`.

### Task 7: HealthKit recorder, entitlements and Info.plist

**Files:**
- Create: `apps/watch_os/Sources/HealthKit/WorkoutRecorder.swift`
- Create: `apps/watch_os/BeyondRepWatch.entitlements` (`com.apple.developer.healthkit` true, `com.apple.developer.healthkit.access` an empty array, the same as `Runner.entitlements`)
- Create: `apps/watch_os/Sources/Resources/Info.plist` (only `WKBackgroundModes: [workout-processing]`)
- Modify: `apps/watch_os/project.yml`, `tool/embed_watch_target.rb`, `tool/test_watch_embedding.py`, `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (by the script)

**Interfaces:**
- Produces (watch app only, `@MainActor final class WorkoutRecorder: NSObject, ObservableObject`):
  - `@Published var heartRate: Int?`
  - `@Published var activeKilocalories: Double?`
  - `func requestAuthorization() async -> Bool`
  - `func begin(workoutId: String, at: Date) async throws`
  - `func pause()` and `func resume()`
  - `func finish(at: Date) async -> String?` (the saved HKWorkout UUID, lowercased, or nil when HealthKit is unavailable, denied or failed)
  - `func discard()` (`end` plus `builder.discardWorkout()`)
  - `func recover() async -> Bool` (`HKHealthStore.recoverActiveWorkoutSession`)
  - `func savedWorkoutUuid(workoutId: String) async -> String?` (an `HKSampleQuery` on `workoutType` with `HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [workoutId])`)

The HealthKit setup:
- configuration: `.traditionalStrengthTraining`, `.indoor`;
- `HKLiveWorkoutBuilder` with `HKLiveWorkoutDataSource`;
- `builder.addMetadata([HKMetadataKeyExternalUUID: workoutId])` before `finishWorkout`;
- the heart rate comes from `workoutBuilder(_:didCollectDataOf:)` (the most recent `heartRate` quantity, in count/min).

Build settings (`project.yml` and the embed script):
- `CODE_SIGN_ENTITLEMENTS = <path to BeyondRepWatch.entitlements>`
- `INFOPLIST_FILE = <path to Sources/Resources/Info.plist>` (merged with the generated plist)
- `INFOPLIST_KEY_NSHealthShareUsageDescription = "BeyondRep reads your heart rate and active energy during a workout on your watch."`
- `INFOPLIST_KEY_NSHealthUpdateUsageDescription = "BeyondRep saves each strength workout you finish on your watch to Apple Health."`

- [ ] **Step 1: Write the failing Python test** `test_watch_has_healthkit_entitlement_and_workout_background_mode` in `test_watch_embedding.py`.
  - The pbxproj watch configurations reference the entitlements file and the Info.plist.
  - Both usage-description keys are present.
  - The entitlements file contains only the two HealthKit keys.
  - The Info.plist contains `workout-processing`.
  - `project.yml` has the same settings.
- [ ] **Step 2: Run** `python3 -m unittest tool.test_watch_embedding`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Write the recorder, the entitlements, the Info.plist, `project.yml`, and the embed script settings.
  - Run `cd tool && bundle exec ruby embed_watch_target.rb`.
  - Check the script excludes the Info.plist from the watch target's resources: a plist in Resources breaks the build.
- [ ] **Step 4: Run** `python3 -m unittest discover -s tool -p 'test_*.py'`. Expected: all OK, including `test_script_is_idempotent` and the file-sync test.
- [ ] **Step 5: Commit** `feat(watch): HealthKit workout recorder, entitlement and workout background mode`.

### Task 8: Workout screens and app wiring

**Files:**
- Create: the files in `apps/watch_os/Sources/Features/Workout/` (listed under File structure)
- Modify: `TrainPage.swift`, `RootView.swift`, `AppModel.swift`, `PhoneLink.swift`, `SyncView.swift`, `Sources/Features/Preview/PreviewData.swift`
- Modify: the pbxproj (by the script)

**Interfaces:**
- Consumes: `WorkoutController` (Task 6), `WorkoutRecorder` (Task 7), `PhoneInbox` acks and `SyncLine` (Task 5).
- Produces, in `AppModel`:
  - `@Published var workout: WorkoutController?`
  - `func startWorkout(_ template: WorkoutTemplate) async`: needs a binding. It requests authorization, begins HealthKit (failures are ignored), then calls `WorkoutController.start`. If the start fails, it ends HealthKit.
  - `func finishWorkout() async`:
    1. `markCompleted`;
    2. `let uuid = await recorder.finish(at:)`;
    3. `queueCompleted(healthkitWorkoutUuid: uuid)`;
    4. `sendQueued()`;
    5. show the summary.
  - `func discardWorkout()`: `recorder.discard()` and `controller.discard()`.
  - `func sendQueued()`: `link.send(completed:)` for every `journal.pendingCompleted(limit: 20)` message whose id is not in `link.outstandingIds()`.
  - On launch, `restore` the controller and `recorder.recover()`.
  - For each id in `pendingFinish`, call `recorder.savedWorkoutUuid(workoutId:)` and then `queuePendingFinish`.
  - `sendQueued()` runs on launch, on activation, when the phone becomes reachable and after each ack.
- Produces, in `PhoneLink`:
  - `func send(completed: WatchMessage)` (`transferUserInfo(["json": ...])`)
  - `func outstandingIds() -> Set<String>` (message ids parsed from `WCSession.default.outstandingUserInfoTransfers` where `isTransferring`)

The screens (Palette colours, follow the mockups):
- **Train:** today's card and each plan card are buttons that open `PlanPreviewView` (exercise names with "sets × reps", then "Start"). "+ Quick workout" is at the bottom. With no binding, there is no Start button.
- **WorkoutView:** a horizontal `TabView` with `.page`. The pages are Set, Rest and Overview.
- **SetPage (Option A):**
  - the exercise name, and "Set n of m" from the cursor;
  - two boxes, weight and reps (or seconds for a duration exercise). The focused box has a green outline, and `.digitalCrownRotation` changes it with the global steps and ranges. Tapping the other box moves the focus;
  - the hint line, then "Log set";
  - live heart rate and elapsed time in the top row.
  - After all sets: "All planned sets done", "Add set" and "Exercises".
- **RpeSheet:** shown after Log. Its buttons are 6–10 and "Skip", and it auto-dismisses after 5 s. A choice calls `setRpe`.
- **RestPage:**
  - a ring counting down to `restDeadline` (`TimelineView(.periodic(from:by: 1))`);
  - "+30 s" calls `extendRest()` and "Skip" calls `skipRest()`;
  - "Next: …" comes from `cursor.next`.
  - At the deadline, `WKInterfaceDevice.current().play(.stop)` fires once per deadline. It is scheduled from `restDeadline`, so it also fires when the screen is off.
- **OverviewPage:**
  - Time (elapsed since start, excluding nothing; the pause shows "Paused"), Heart rate (or "—"), and Sets `completedCount / plannedCount`;
  - "Pause" or "Resume", and "End" (opens `EndConfirmView`);
  - an "Exercises" button opens `ExercisesSheet`. That lists each exercise with done/total; a tap calls `focus`, and "+ Add exercise" lists `recent_exercises` from the plans snapshot.
- **EndConfirmView:** "Save workout" (disabled with "No sets logged yet." when `completedSets == 0`), "Keep going" and "Discard". Discard asks a second time with the discard confirmation text.
- **SummaryView:** "Done", the name, Time, Sets, and the average heart rate if the recorder has one. The status line is:
  - "Saved to iPhone" after a delivered ack,
  - "Saved on watch · sent to iPhone" when reachable,
  - otherwise "Saved on watch · waiting for iPhone".
- **RootView:** shows `WorkoutView` while `model.workout?.status` is `active` or `paused`, and `SummaryView` until it is dismissed.
- **Accessibility:**
  - every number has a spoken label ("Weight 60 kilograms", "8 reps", "Heart rate 128");
  - buttons are at least 44 pt;
  - Dynamic Type works up to `.accessibility1`, with no truncated numbers (use `minimumScaleFactor(0.6)` on numerals only);
  - the always-on dimmed state hides seconds.

- [ ] **Step 1: Add SwiftUI previews** for every new screen with `PreviewData` (a mid-workout state, the rest state, the summary waiting state, and no sets logged).
- [ ] **Step 2: Implement** the screens and the `AppModel` and `PhoneLink` changes.
- [ ] **Step 3: Run** `cd tool && bundle exec ruby embed_watch_target.rb`, then `python3 -m unittest tool.test_watch_embedding` (PASS).
- [ ] **Step 4:** On macOS CI, `watchos_smoke.yml` builds the standalone watch target and `ios-with-watch`. Push and read the result; fix compile errors only in the files this task touched.
- [ ] **Step 5: Commit** `feat(watch): start, log, rest, finish and send workouts from the watch`.

### Task 9: Docs and owner actions

**Files:** `docs/ROADMAP.md`, `docs/RELEASE.md`, `docs/WEARABLES.md`, `docs/HEALTH_DATA.md`, `CLAUDE.md`, `docs/IOS_TESTFLIGHT_CODEMAGIC.md`

- [ ] **Step 1: ROADMAP.** Stage 4b becomes "implemented in source, not released or device-verified". Add stage 4c (not started) with the three items moved out of scope above.
- [ ] **Step 2: RELEASE.** Add the device rows. Each starts unticked:
  - a 45-minute workout with the phone left in another room;
  - screen off during rest (the haptic fires);
  - force-quit the watch app mid-workout (it restores to the same set);
  - force-quit right after Save (one HKWorkout in the Health app, and the workout appears on the phone);
  - deny the HealthKit prompt (it records without heart rate);
  - a second workout from the same plan imports on the phone;
  - discard (nothing on the phone);
  - sign in as another account with an unsent workout (it waits);
  - Dynamic Type on 41 mm.
- [ ] **Step 3: HEALTH_DATA, WEARABLES and CLAUDE.md.**
  - The watch writes one HKWorkout per session, with workout share and heart-rate and energy read permissions, and no health values leave the watch.
  - In CLAUDE.md, move "watch workout recording" and the watch's HealthKit workout write out of "Not implemented". Describe them as "implemented in source, not released or device-verified".
  - Keep phone HealthKit writes listed as not implemented.
- [ ] **Step 4: IOS_TESTFLIGHT_CODEMAGIC owner action.** Before the next TestFlight build:
  1. Enable HealthKit on the watch App ID `in.beyondrep.app.watchkitapp` in the Apple Developer portal.
  2. Regenerate the `beyondrep_watch_app_store` profile.
  3. Upload it to Codemagic under the same name.
- [ ] **Step 5: Run** `python3 -m unittest discover -s tool -p 'test_*.py'` (the docs guards).
- [ ] **Step 6: Commit** `docs: phase 4 stage 4b watch workout recording`.

### Final verification

- [ ] From `apps/mobile`, run:
  - `dart format --output=none --set-exit-if-changed lib test`
  - `flutter analyze`
  - `flutter test`
- [ ] From the repository root, run `python3 -m unittest discover -s tool -p 'test_*.py'`.
- [ ] Check `git status` for unexpected files, then push. `watchos_smoke.yml` runs `swift test` and both watch builds; all must be green.
- [ ] Report which checks ran locally, which ran only on CI, and that every device check is not run.
