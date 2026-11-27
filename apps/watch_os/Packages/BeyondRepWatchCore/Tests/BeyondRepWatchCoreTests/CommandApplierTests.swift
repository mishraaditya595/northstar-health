import XCTest
@testable import BeyondRepWatchCore

final class CommandApplierTests: XCTestCase {
    private let key = String(repeating: "0123456789abcdef", count: 4)
    private let otherKey = String(repeating: "fedcba9876543210", count: 4)
    private let base = Date(timeIntervalSince1970: 1_792_000_000)
    private var now = Date(timeIntervalSince1970: 1_792_000_000)
    private var dir: URL!
    private var journal: WatchJournal!
    private var commandCounter = 0

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        journal = try WatchJournal(url: dir.appendingPathComponent("journal.sqlite"), makeId: TemplateFixtures.counterIds(from: 5000))
        now = base
        commandCounter = 0
    }

    override func tearDownWithError() throws {
        journal = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func start() throws -> WorkoutController {
        try WorkoutController.start(
            template: try TemplateFixtures.template(), journal: journal, accountKey: key, unit: "kg",
            deviceId: "watch-installation-a", clock: { self.now }, timeZone: "Asia/Kolkata",
            makeId: TemplateFixtures.counterIds(from: 1000))
    }

    private func restore() throws -> WorkoutController {
        try XCTUnwrap(
            try WorkoutController.restore(
                journal: journal, accountKey: key, unit: "kg", deviceId: "watch-installation-a",
                clock: { self.now }, timeZone: "Asia/Kolkata"))
    }

    private func newCommandId() -> String {
        commandCounter += 1
        return String(format: "88888888-4444-4444-8444-%012d", commandCounter)
    }

    private func message(
        _ controller: WorkoutController, _ command: String, id: String? = nil, session: String? = nil,
        account: String? = nil, set: SetValues? = nil, restSeconds: Int? = nil, exerciseId: String? = nil
    ) -> WatchMessage {
        WatchMessage(
            messageId: String(format: "77777777-3333-4333-8333-%012d", commandCounter + 5000),
            sentAtUtc: "2026-10-23T11:00:00Z", accountKey: account ?? key,
            body: .sessionCommand(
                SessionCommand(
                    sessionId: session ?? controller.sessionId, commandId: id ?? newCommandId(), command: command,
                    set: set, restSeconds: restSeconds, exerciseId: exerciseId)))
    }

    /// Values for the n-th template set (0 = warm-up, 1 = working, 2 = plank).
    private func values(_ controller: WorkoutController, _ n: Int, reps: Int? = 8, seconds: Int? = nil, load: Int? = 60000) -> SetValues {
        let sets = controller.template.exercises.flatMap { exercise in exercise.sets.map { (exercise, $0) } }
        let (exercise, set) = sets[n]
        return SetValues(
            setId: set.setId, exerciseId: exercise.exerciseId, position: set.position, kind: set.kind,
            reps: reps, durationSeconds: seconds, loadGrams: load)
    }

    private func eventTypes(_ controller: WorkoutController) throws -> [String] {
        try journal.events(sessionId: controller.sessionId).map { event in
            switch event {
            case .workoutStarted: return "workout_started"
            case .exerciseAdded: return "exercise_added"
            case .setLogged: return "set_logged"
            case .setCorrected: return "set_corrected"
            case .setSkipped: return "set_skipped"
            case .restStarted: return "rest_started"
            case .restCleared: return "rest_cleared"
            case .workoutPaused: return "workout_paused"
            case .workoutResumed: return "workout_resumed"
            case .workoutCompleted: return "workout_completed"
            case .workoutAbandoned: return "workout_abandoned"
            case .platformWorkoutExported: return "platform_workout_exported"
            }
        }
    }

    private var startEvents: Int { 1 + 2 }

    func testLogThenCorrectGivesSetLoggedThenSetCorrected() throws {
        let c = try start()
        let first = try c.apply(message(c, "log_set", set: values(c, 1)))
        XCTAssertEqual(first, .applied)
        XCTAssertEqual(Array(try eventTypes(c).suffix(2)), ["set_logged", "rest_started"])
        let second = try c.apply(message(c, "correct_set", set: values(c, 1, reps: 9)))
        XCTAssertEqual(second, .applied)
        XCTAssertEqual(try eventTypes(c).last, "set_corrected")
        XCTAssertEqual(c.state.sets.first?.reps, 9)
    }

    func testCorrectSetOnANeverLoggedSetBecomesSetLoggedAndStartsRest() throws {
        let c = try start()
        XCTAssertEqual(try c.apply(message(c, "correct_set", set: values(c, 1))), .applied)
        XCTAssertEqual(Array(try eventTypes(c).suffix(2)), ["set_logged", "rest_started"])
        XCTAssertFalse(try eventTypes(c).contains("set_corrected"))
        XCTAssertNotNil(c.restDeadline)
    }

    func testOldDuplicateCommandIsStillListedInTheNextStateAfterTheWindowMoved() throws {
        let c = try start()
        let first = newCommandId()
        XCTAssertEqual(try c.apply(message(c, "pause", id: first)), .applied)
        for _ in 0..<24 {
            _ = try c.apply(message(c, "clear_rest"))
        }
        let early = try c.sessionState(messageId: "77777777-3333-4333-8333-0000000000f4", sentAtUtc: "2026-10-23T11:05:00Z")
        guard case .sessionState(_, let before) = early.body else { return XCTFail("not a session state") }
        XCTAssertFalse((before["applied_command_ids"] as? [String] ?? []).contains(first))
        XCTAssertEqual(try c.apply(message(c, "pause", id: first)), .duplicate)
        let state = try c.sessionState(messageId: "77777777-3333-4333-8333-0000000000f5", sentAtUtc: "2026-10-23T11:05:01Z")
        guard case .sessionState(_, let raw) = state.body else { return XCTFail("not a session state") }
        let listed = raw["applied_command_ids"] as? [String] ?? []
        XCTAssertLessThanOrEqual(listed.count, 20)
        XCTAssertTrue(listed.contains(first))
    }

    func testLogOnACompletedSetBecomesACorrection() throws {
        let c = try start()
        _ = try c.apply(message(c, "log_set", set: values(c, 1)))
        _ = try c.apply(message(c, "log_set", set: values(c, 1, reps: 10)))
        XCTAssertEqual(try eventTypes(c).filter { $0 == "set_logged" }.count, 1)
        XCTAssertEqual(try eventTypes(c).filter { $0 == "set_corrected" }.count, 1)
    }

    func testSkipSet() throws {
        let c = try start()
        XCTAssertEqual(try c.apply(message(c, "skip_set", set: values(c, 1))), .applied)
        XCTAssertEqual(c.state.sets.first?.status, "skipped")
    }

    func testStartAndClearRest() throws {
        let c = try start()
        XCTAssertEqual(try c.apply(message(c, "start_rest", restSeconds: 60)), .applied)
        XCTAssertEqual(c.restDeadline, base.addingTimeInterval(60))
        XCTAssertEqual(try c.apply(message(c, "clear_rest")), .applied)
        XCTAssertNil(c.restDeadline)
    }

    func testClearRestWithoutRestIsAppliedWithoutAnEvent() throws {
        let c = try start()
        let before = try eventTypes(c).count
        let id = newCommandId()
        XCTAssertEqual(try c.apply(message(c, "clear_rest", id: id)), .applied)
        XCTAssertEqual(try eventTypes(c).count, before)
        XCTAssertEqual(try c.apply(message(c, "clear_rest", id: id)), .duplicate)
    }

    func testPauseAndResumeShowInState() throws {
        let c = try start()
        now = base.addingTimeInterval(100)
        XCTAssertEqual(try c.apply(message(c, "pause")), .applied)
        XCTAssertEqual(c.status, "paused")
        now = base.addingTimeInterval(160)
        XCTAssertEqual(try c.apply(message(c, "resume")), .applied)
        let state = try c.sessionState(messageId: "77777777-3333-4333-8333-0000000000f2", sentAtUtc: "2026-10-23T11:05:00Z")
        guard case .sessionState(_, let raw) = state.body else { return XCTFail("not a session state") }
        XCTAssertEqual(raw["status"] as? String, "active")
        XCTAssertEqual(raw["paused_seconds"] as? Int, 60)
        XCTAssertNil(raw["paused_at_utc"])
    }

    func testPauseWhilePausedIsRejectedNotAllowed() throws {
        let c = try start()
        _ = try c.apply(message(c, "pause"))
        let before = try eventTypes(c).count
        XCTAssertEqual(try c.apply(message(c, "pause")), .rejected(.notAllowed))
        XCTAssertEqual(try eventTypes(c).count, before)
    }

    func testAddSetAddsATemplateSet() throws {
        let c = try start()
        let exerciseId = c.template.exercises[0].exerciseId
        let count = c.template.exercises[0].sets.count
        XCTAssertEqual(try c.apply(message(c, "add_set", exerciseId: exerciseId)), .applied)
        XCTAssertEqual(c.template.exercises[0].sets.count, count + 1)
        XCTAssertEqual(try restore().template.exercises[0].sets.count, count + 1)
    }

    func testAddSetTwiceWithOneCommandIdAddsOnce() throws {
        let c = try start()
        let exerciseId = c.template.exercises[0].exerciseId
        let count = c.template.exercises[0].sets.count
        let id = newCommandId()
        XCTAssertEqual(try c.apply(message(c, "add_set", id: id, exerciseId: exerciseId)), .applied)
        XCTAssertEqual(try c.apply(message(c, "add_set", id: id, exerciseId: exerciseId)), .duplicate)
        XCTAssertEqual(c.template.exercises[0].sets.count, count + 1)
    }

    func testAddSetForAnUnknownExerciseIsRejected() throws {
        let c = try start()
        XCTAssertEqual(
            try c.apply(message(c, "add_set", exerciseId: "builtin.v1.not-in-this-workout")), .rejected(.unknownSet))
    }

    func testFinishRecordsCompletionAndAsksTheAppToFinishHealthKit() throws {
        let c = try start()
        _ = try c.apply(message(c, "log_set", set: values(c, 1)))
        XCTAssertEqual(try c.apply(message(c, "finish")), .needsFinish)
        XCTAssertEqual(c.status, "completed")
        XCTAssertEqual(try eventTypes(c).filter { $0 == "workout_completed" }.count, 1)
    }

    func testFinishWithoutACompletedSetIsRejected() throws {
        let c = try start()
        XCTAssertEqual(try c.apply(message(c, "finish")), .rejected(.notAllowed))
        XCTAssertEqual(c.status, "active")
    }

    func testDuplicateFinishIsAppliedOnce() throws {
        let c = try start()
        _ = try c.apply(message(c, "log_set", set: values(c, 1)))
        let id = newCommandId()
        XCTAssertEqual(try c.apply(message(c, "finish", id: id)), .needsFinish)
        XCTAssertEqual(try c.apply(message(c, "finish", id: id)), .duplicate)
        XCTAssertEqual(try eventTypes(c).filter { $0 == "workout_completed" }.count, 1)
    }

    func testDiscard() throws {
        let c = try start()
        XCTAssertEqual(try c.apply(message(c, "discard")), .applied)
        XCTAssertEqual(c.status, "abandoned")
    }

    func testDuplicateCommandIdIsAppliedOnce() throws {
        let c = try start()
        let id = newCommandId()
        let command = message(c, "log_set", id: id, set: values(c, 1))
        XCTAssertEqual(try c.apply(command), .applied)
        let count = try eventTypes(c).count
        XCTAssertEqual(try c.apply(command), .duplicate)
        XCTAssertEqual(try c.apply(message(c, "log_set", id: id, set: values(c, 1, reps: 12))), .duplicate)
        XCTAssertEqual(try eventTypes(c).count, count)
        let state = try c.sessionState(messageId: "77777777-3333-4333-8333-0000000000f3", sentAtUtc: "2026-10-23T11:05:00Z")
        guard case .sessionState(_, let raw) = state.body else { return XCTFail("not a session state") }
        XCTAssertEqual(raw["applied_command_ids"] as? [String], [id])
    }

    func testCommandAfterRelaunchIsStillIdempotent() throws {
        let c = try start()
        let id = newCommandId()
        _ = try c.apply(message(c, "log_set", id: id, set: values(c, 1)))
        let count = try eventTypes(c).count
        let reopened = try WatchJournal(url: dir.appendingPathComponent("journal.sqlite"))
        let restored = try XCTUnwrap(
            try WorkoutController.restore(
                journal: reopened, accountKey: key, unit: "kg", deviceId: "watch-installation-a",
                clock: { self.now }, timeZone: "Asia/Kolkata"))
        XCTAssertEqual(try restored.apply(message(restored, "log_set", id: id, set: values(restored, 1))), .duplicate)
        XCTAssertEqual(try reopened.events(sessionId: restored.sessionId).count, count)
    }

    func testAnotherAccountKeyIsIgnoredAndWritesNothing() throws {
        let c = try start()
        let before = try eventTypes(c).count
        XCTAssertEqual(try c.apply(message(c, "pause", account: otherKey)), .ignored)
        XCTAssertEqual(try eventTypes(c).count, before)
        XCTAssertEqual(c.status, "active")
        XCTAssertTrue(try journal.commandLog(sessionId: c.sessionId).isEmpty)
    }

    func testAnotherSessionIdIsRejectedWithNoEvent() throws {
        let c = try start()
        let before = try eventTypes(c).count
        let outcome = try c.apply(message(c, "pause", session: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"))
        XCTAssertEqual(outcome, .rejected(.unknownSession))
        XCTAssertEqual(try eventTypes(c).count, before)
        XCTAssertEqual(c.status, "active")
    }

    func testUnknownSetIsRejectedAndListedInState() throws {
        let c = try start()
        var bogus = values(c, 1)
        bogus.setId = "dddddddd-dddd-4ddd-8ddd-ffffffffffff"
        let before = try eventTypes(c).count
        let id = newCommandId()
        XCTAssertEqual(try c.apply(message(c, "log_set", id: id, set: bogus)), .rejected(.unknownSet))
        XCTAssertEqual(try eventTypes(c).count, before)
        let state = try c.sessionState(messageId: "77777777-3333-4333-8333-0000000000f4", sentAtUtc: "2026-10-23T11:05:00Z")
        guard case .sessionState(_, let raw) = state.body else { return XCTFail("not a session state") }
        let rejected = try XCTUnwrap(raw["rejected_commands"] as? [[String: Any]])
        XCTAssertEqual(rejected.first?["command_id"] as? String, id)
        XCTAssertEqual(rejected.first?["reason"] as? String, "unknown_set")
        // A resend of a rejected command is a duplicate, not a second rejection.
        XCTAssertEqual(try c.apply(message(c, "log_set", id: id, set: bogus)), .duplicate)
    }

    func testSetOfAnotherExerciseIsRejectedAsUnknownSet() throws {
        let c = try start()
        var wrong = values(c, 1)
        wrong.exerciseId = c.template.exercises[1].exerciseId
        XCTAssertEqual(try c.apply(message(c, "log_set", set: wrong)), .rejected(.unknownSet))
    }

    func testInvalidValuesAreRejectedWithNoEvent() throws {
        let c = try start()
        let before = try eventTypes(c).count
        // Negative reps.
        XCTAssertEqual(try c.apply(message(c, "log_set", set: values(c, 1, reps: -1))), .rejected(.invalidValues))
        // A load on a duration exercise (the plank is the third set).
        XCTAssertEqual(
            try c.apply(message(c, "log_set", set: values(c, 2, reps: nil, seconds: 40, load: 20000))), .rejected(.invalidValues))
        // Reps on a duration exercise.
        XCTAssertEqual(try c.apply(message(c, "log_set", set: values(c, 2, reps: 5, load: nil))), .rejected(.invalidValues))
        // Seconds on a reps exercise.
        XCTAssertEqual(try c.apply(message(c, "log_set", set: values(c, 1, reps: nil, seconds: 30))), .rejected(.invalidValues))
        // Rest of 0 seconds.
        XCTAssertEqual(try c.apply(message(c, "start_rest", restSeconds: 0)), .rejected(.invalidValues))
        XCTAssertEqual(try c.apply(message(c, "start_rest")), .rejected(.invalidValues))
        XCTAssertEqual(try eventTypes(c).count, before)
    }

    func testLogWhilePausedIsNotAllowed() throws {
        let c = try start()
        _ = try c.apply(message(c, "pause"))
        XCTAssertEqual(try c.apply(message(c, "log_set", set: values(c, 1))), .rejected(.notAllowed))
    }
}
