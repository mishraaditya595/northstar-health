import XCTest
@testable import BeyondRepWatchCore

final class WorkoutControllerTests: XCTestCase {
    private let key = String(repeating: "0123456789abcdef", count: 4)
    private let otherKey = String(repeating: "fedcba9876543210", count: 4)
    private let base = Date(timeIntervalSince1970: 1_792_000_000)
    private var now = Date(timeIntervalSince1970: 1_792_000_000)
    private var dir: URL!
    private var journal: WatchJournal!
    private var ids: (() -> String)!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        journal = try WatchJournal(url: dir.appendingPathComponent("journal.sqlite"), makeId: TemplateFixtures.counterIds(from: 5000))
        now = base
        ids = TemplateFixtures.counterIds(from: 1000)
    }

    override func tearDownWithError() throws {
        journal = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func start(_ template: WorkoutTemplate) throws -> WorkoutController {
        try WorkoutController.start(
            template: template, journal: journal, accountKey: key, unit: "kg", deviceId: "watch-installation-a",
            clock: { self.now }, timeZone: "Asia/Kolkata", makeId: ids)
    }

    private func restore(account: String? = nil) throws -> WorkoutController? {
        try WorkoutController.restore(
            journal: journal, accountKey: account ?? key, unit: "kg", deviceId: "watch-installation-a",
            clock: { self.now }, timeZone: "Asia/Kolkata")
    }

    private func logCurrent(_ controller: WorkoutController) throws -> SetValues {
        let current = try XCTUnwrap(controller.cursor.current)
        let values = controller.cursor.prefill(for: current, unit: "kg")
        try controller.log(values)
        return values
    }

    func testStartCommitsStartedExercisesAndTemplate() throws {
        let template = try TemplateFixtures.template()
        let controller = try start(template)
        let active = try XCTUnwrap(journal.activeSession(accountKey: key))
        XCTAssertEqual(active.events.count, 1 + template.exercises.count)
        XCTAssertEqual(active.sessionId, controller.sessionId)
        XCTAssertNotNil(try journal.template(sessionId: controller.sessionId))
        XCTAssertEqual(controller.status, "active")
        XCTAssertEqual(controller.startedAt, base)
    }

    func testLogStartsRestWithPlanSeconds() throws {
        var template = try TemplateFixtures.template()
        let controller = try start(try TemplateFixtures.template())
        _ = try logCurrent(controller)
        XCTAssertEqual(controller.restDeadline, base.addingTimeInterval(90))
        XCTAssertEqual(try journal.activeSession(accountKey: key)?.events.count, 3 + 2)

        template.exercises[0].sets[0].restSeconds = 45
        let other = try WorkoutController.start(
            template: template, journal: try WatchJournal(url: dir.appendingPathComponent("b.sqlite")),
            accountKey: key, unit: "kg", deviceId: "watch-installation-a", clock: { self.now },
            timeZone: "Asia/Kolkata", makeId: TemplateFixtures.counterIds(from: 3000))
        _ = try logCurrent(other)
        XCTAssertEqual(other.restDeadline, base.addingTimeInterval(45))
    }

    func testSetRpeCorrectsTheSet() throws {
        let controller = try start(try TemplateFixtures.template())
        let values = try logCurrent(controller)
        try controller.setRpe(setId: values.setId, rpe: 8)
        let set = try XCTUnwrap(controller.state.sets.first { $0.setId == values.setId })
        XCTAssertEqual(set.rpe, 8)
        XCTAssertEqual(set.history.count, 2)
        XCTAssertEqual(set.reps, values.reps)
    }

    func testRestoreAfterRelaunchKeepsCursorAndRest() throws {
        let controller = try start(try TemplateFixtures.template())
        _ = try logCurrent(controller)
        let restored = try XCTUnwrap(try restore())
        XCTAssertEqual(restored.cursor.current?.set.setId, controller.cursor.current?.set.setId)
        XCTAssertEqual(restored.restDeadline, controller.restDeadline)
        XCTAssertEqual(restored.template, controller.template)
        XCTAssertEqual(restored.sessionId, controller.sessionId)
        XCTAssertEqual(restored.state, controller.state)
    }

    func testRestoreIgnoresOtherAccount() throws {
        _ = try start(try TemplateFixtures.template())
        XCTAssertNil(try restore(account: otherKey))
    }

    func testPauseAndResumeAreDurable() throws {
        let controller = try start(try TemplateFixtures.template())
        try controller.pause()
        XCTAssertEqual(try restore()?.status, "paused")
        try controller.resume()
        XCTAssertEqual(try restore()?.status, "active")
    }

    func testExtendAndSkipRest() throws {
        let controller = try start(try TemplateFixtures.template())
        _ = try logCurrent(controller)
        now = base.addingTimeInterval(50)  // 40 s remain
        try controller.extendRest()
        XCTAssertEqual(controller.restDeadline, base.addingTimeInterval(50 + 70))
        try controller.skipRest()
        XCTAssertNil(controller.restDeadline)
        XCTAssertNil(try restore()?.restDeadline)
    }

    func testSkipSetMovesTheCursorOn() throws {
        let controller = try start(try TemplateFixtures.template())
        let first = try XCTUnwrap(controller.cursor.current)
        try controller.skip(setId: first.set.setId)
        XCTAssertNotEqual(controller.cursor.current?.set.setId, first.set.setId)
    }

    func testMarkCompletedDoesNotQueue() throws {
        let controller = try start(try TemplateFixtures.template())
        _ = try logCurrent(controller)
        try controller.markCompleted()
        XCTAssertTrue(try journal.pendingCompleted(limit: 10).isEmpty)
        XCTAssertEqual(try WorkoutController.pendingFinish(journal: journal, accountKey: key), [controller.sessionId])
        XCTAssertNil(try restore())
    }

    func testQueueCompletedQueuesOnce() throws {
        let controller = try start(try TemplateFixtures.template())
        _ = try logCurrent(controller)  // the warm-up, not counted
        _ = try logCurrent(controller)  // the first working set
        try controller.markCompleted()
        let uuid = "11111111-2222-4333-8444-555555555555"
        try controller.queueCompleted(healthkitWorkoutUuid: uuid)
        try controller.queueCompleted(healthkitWorkoutUuid: uuid)
        let queued = try journal.pendingCompleted(limit: 10)
        XCTAssertEqual(queued.count, 1)
        XCTAssertTrue(try WorkoutController.pendingFinish(journal: journal, accountKey: key).isEmpty)
        guard case .completedWorkout(_, _, let hk, _) = queued[0].body else { return XCTFail("wrong body") }
        XCTAssertEqual(hk, uuid)
    }

    func testOnlyWarmupsCannotBeSaved() throws {
        let controller = try start(try TemplateFixtures.template())
        XCTAssertFalse(controller.canSave)
        _ = try logCurrent(controller)  // the warm-up
        XCTAssertFalse(controller.canSave)
        _ = try logCurrent(controller)  // the first working set
        XCTAssertTrue(controller.canSave)
    }

    func testFinishingSessionIsFoundAfterRestart() throws {
        var controller: WorkoutController? = try start(try TemplateFixtures.template())
        let sessionId = controller!.sessionId
        _ = try logCurrent(controller!)  // the warm-up, not counted
        _ = try logCurrent(controller!)  // the first working set
        try controller!.markCompleted()
        controller = nil
        let reopened = try WatchJournal(url: dir.appendingPathComponent("journal.sqlite"))
        XCTAssertEqual(try WorkoutController.pendingFinish(journal: reopened, accountKey: key), [sessionId])
        let uuid = "11111111-2222-4333-8444-555555555555"
        try WorkoutController.queuePendingFinish(
            sessionId: sessionId, journal: reopened, unit: "kg", accountKey: key, healthkitWorkoutUuid: uuid,
            makeId: ids, clock: { self.now })
        // A second recovery pass queues nothing more.
        try WorkoutController.queuePendingFinish(
            sessionId: sessionId, journal: reopened, unit: "kg", accountKey: key, healthkitWorkoutUuid: uuid,
            makeId: ids, clock: { self.now })
        let queued = try reopened.pendingCompleted(limit: 10)
        XCTAssertEqual(queued.count, 1)
        guard case .completedWorkout(_, _, let hk, _) = queued[0].body else { return XCTFail("wrong body") }
        XCTAssertEqual(hk, uuid)
        XCTAssertEqual(try reopened.delivery(sessionId: sessionId), "queued")
    }

    func testDiscardQueuesNothing() throws {
        let controller = try start(try TemplateFixtures.template())
        _ = try logCurrent(controller)
        try controller.discard()
        XCTAssertTrue(try journal.pendingOutbox(limit: 50).isEmpty)
        XCTAssertEqual(controller.status, "abandoned")
        XCTAssertNil(try restore())
    }

    func testAddExerciseInQuickWorkout() throws {
        let controller = try start(WorkoutTemplate.quick())
        let exerciseId = try controller.addExercise(name: "Synthetic curl", kind: "reps", muscle: "biceps")
        let set = try XCTUnwrap(controller.template.exercises.first?.sets.first)
        try controller.log(SetValues(setId: set.setId, exerciseId: exerciseId, position: 0, reps: 10, loadGrams: 15000))
        try controller.markCompleted()
        try controller.queueCompleted(healthkitWorkoutUuid: nil)
        let message = try XCTUnwrap(try journal.pendingCompleted(limit: 10).first)
        guard case .completedWorkout(_, _, _, let raw) = message.body,
            let workout = raw["workout"] as? [String: Any],
            let exercises = workout["exercises"] as? [[String: Any]]
        else { return XCTFail("wrong body") }
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0]["name"] as? String, "Synthetic curl")
        XCTAssertEqual(exercises[0]["id"] as? String, exerciseId)
        XCTAssertNil(try restore())
    }

    func testAddExerciseSurvivesRestore() throws {
        let controller = try start(WorkoutTemplate.quick())
        let exerciseId = try controller.addExercise(name: "Synthetic curl", kind: "reps", muscle: nil)
        XCTAssertEqual(try restore()?.template.exercises.map(\.exerciseId), [exerciseId])
    }

    func testAddSetIsStoredWithTheTemplate() throws {
        let controller = try start(try TemplateFixtures.template())
        let exerciseId = controller.template.exercises[0].exerciseId
        let setId = try controller.addSet(exerciseId: exerciseId)
        XCTAssertEqual(try restore()?.template.exercises[0].sets.last?.setId, setId)
    }

    func testCannotQueueWithoutCompletedSet() throws {
        let controller = try start(try TemplateFixtures.template())
        try controller.markCompleted()
        XCTAssertThrowsError(try controller.queueCompleted(healthkitWorkoutUuid: nil))
        XCTAssertTrue(try journal.pendingCompleted(limit: 10).isEmpty)
    }

    func testFailedCommitLeavesStateUnchanged() throws {
        let controller = try start(try TemplateFixtures.template())
        let before = controller.state
        let events = try XCTUnwrap(journal.activeSession(accountKey: key)).events.count
        journal.failAt = .afterSessionUpsert
        let current = try XCTUnwrap(controller.cursor.current)
        let values = controller.cursor.prefill(for: current, unit: "kg")
        XCTAssertThrowsError(try controller.log(values))
        XCTAssertEqual(controller.state, before)
        XCTAssertEqual(controller.state.completedSets, 0)
        XCTAssertEqual(try journal.activeSession(accountKey: key)?.events.count, events)
        // The sequence continues without a gap once the journal works again.
        journal.failAt = nil
        try controller.log(values)
        XCTAssertEqual(controller.state.gaps, [])
        XCTAssertEqual(try restore()?.state, controller.state)
    }
}
