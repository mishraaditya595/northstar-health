import XCTest
@testable import BeyondRepWatchCore

final class WatchJournalTests: XCTestCase {
    private let key = String(repeating: "0123456789abcdef", count: 4)
    private let session = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var url: URL { dir.appendingPathComponent("journal.sqlite") }

    private func machine() -> SessionMachine {
        var tick = 0
        let base = Date(timeIntervalSince1970: 1_792_000_000)
        return SessionMachine(
            sessionId: session, owner: "watch", accountKey: key, deviceId: "watch-installation-a",
            clock: { tick += 1; return base.addingTimeInterval(TimeInterval(tick)) }, timeZone: "Asia/Kolkata")
    }

    private func set(_ n: Int) -> SetValues {
        SetValues(
            setId: "dddddddd-dddd-4ddd-8ddd-00000000000\(n)", exerciseId: "builtin.v1.synthetic-move-1",
            position: n, reps: 8, loadGrams: 60000)
    }

    /// Records a started session with `sets` logged sets; returns the events.
    @discardableResult
    private func recordSession(_ journal: WatchJournal, sets: Int) throws -> [WorkoutEventV2] {
        var m = machine()
        var events = try m.start(name: "Synthetic push day")
        try journal.record(events, sessionState: replay(events))
        if sets > 0 {
            for n in 1...sets {
                let event = try m.log(set: set(n))
                events.append(event)
                try journal.record(event, sessionState: replay(events))
            }
        }
        return events
    }

    private func fixture(_ name: String) throws -> WatchMessage {
        try WatchMessage(json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/\(name).json"))
    }

    func testRecordIsAtomic() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 0)
        let before = try journal.pendingOutbox(limit: 100).count
        var m = machine()
        _ = try m.start(name: "x")
        let event = try m.log(set: set(1))
        journal.failAt = .afterEventInsert(index: 0)
        XCTAssertThrowsError(try journal.record(event, sessionState: m.state))
        let reopened = try WatchJournal(url: url)
        XCTAssertEqual(try reopened.pendingOutbox(limit: 100).count, before)
        XCTAssertEqual(try reopened.activeSession(accountKey: key)?.events.count, 1)
    }

    func testRecordRollsBackWhenItFailsAfterTheStateUpsertOrTheCompletedInsert() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 0)
        let before = try journal.pendingOutbox(limit: 100).count
        var m = machine()
        _ = try m.start(name: "x")
        let event = try m.log(set: set(1))
        let completed = try fixture("completed_workout")
        for point in [WatchJournal.FailurePoint.afterSessionUpsert, .afterCompletedEnqueue] {
            journal.failAt = point
            XCTAssertThrowsError(
                try journal.record(event, sessionState: m.state, completed: completed, commandId: "88888888-4444-4444-8444-00000000000c"))
            let reopened = try WatchJournal(url: url)
            XCTAssertEqual(try reopened.pendingOutbox(limit: 100).count, before, "\(point)")
            let active = try XCTUnwrap(reopened.activeSession(accountKey: key))
            XCTAssertEqual(active.events.count, 1, "\(point)")
            XCTAssertEqual(active.state.completedSets, 0, "\(point)")
            XCTAssertTrue(active.commandIds.isEmpty, "\(point)")
        }
    }

    func testMultiEventRecordIsAtomic() throws {
        let journal = try WatchJournal(url: url)
        var m = machine()
        let events = try m.start(
            name: "x",
            exercises: [ExerciseAddedPayload(exerciseId: "builtin.v1.synthetic-move-1", name: "Move", kind: "reps", position: 0)])
        XCTAssertEqual(events.count, 2)
        journal.failAt = .afterEventInsert(index: 0)
        XCTAssertThrowsError(try journal.record(events, sessionState: m.state))
        journal.failAt = nil
        let reopened = try WatchJournal(url: url)
        XCTAssertNil(try reopened.activeSession(accountKey: key))
        XCTAssertTrue(try reopened.pendingOutbox(limit: 100).isEmpty)
        try reopened.record(events, sessionState: m.state)
        XCTAssertEqual(try reopened.activeSession(accountKey: key)?.events.count, 2)
        XCTAssertEqual(try reopened.pendingOutbox(limit: 100).count, 2)
    }

    func testActiveSessionIsPerAccount() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        let other = String(repeating: "f", count: 64)
        XCTAssertNil(try journal.activeSession(accountKey: other))
        XCTAssertNotNil(try journal.activeSession(accountKey: key))
    }

    func testRestoredMachineContinuesTheSequenceWithoutReuse() throws {
        var journal: WatchJournal? = try WatchJournal(url: url)
        try recordSession(journal!, sets: 1)
        journal = nil
        let reopened = try WatchJournal(url: url)
        let active = try XCTUnwrap(reopened.activeSession(accountKey: key))
        var tick = 100
        var m = try SessionMachine(
            restoring: active.events, owner: "watch", accountKey: key, deviceId: "watch-installation-a",
            clock: { tick += 1; return Date(timeIntervalSince1970: 1_792_100_000 + TimeInterval(tick)) },
            timeZone: "Asia/Kolkata", appliedCommandIds: active.commandIds)
        XCTAssertEqual(m.status, "active")
        let next = try m.log(set: set(2))
        XCTAssertEqual(next.header.sequence, 2)
        XCTAssertEqual(Set(m.events.map { $0.header.sequence }).count, 3)
        XCTAssertEqual(next.header.sessionId, session)
        try reopened.record(next, sessionState: m.state)
        XCTAssertEqual(try reopened.activeSession(accountKey: key)?.state.completedSets, 2)
    }

    func testDuplicateLogAfterCorrectIsIgnoredAcrossReopen() throws {
        var journal: WatchJournal? = try WatchJournal(url: url)
        var m = machine()
        let start = try m.start(name: "x")
        try journal!.record(start, sessionState: m.state)
        let logId = "88888888-4444-4444-8444-00000000000a"
        let log = SessionCommand(sessionId: session, commandId: logId, command: "log_set", set: set(1))
        let e1 = try XCTUnwrap(m.apply(command: log))
        try journal!.record(e1, sessionState: m.state, commandId: logId)
        let fixId = "88888888-4444-4444-8444-00000000000b"
        let e2 = try XCTUnwrap(m.apply(
            command: SessionCommand(sessionId: session, commandId: fixId, command: "correct_set", set: SetValues(
                setId: set(1).setId, exerciseId: "builtin.v1.synthetic-move-1", position: 1, reps: 9, loadGrams: 60000))))
        try journal!.record(e2, sessionState: m.state, commandId: fixId)
        journal = nil

        let reopened = try WatchJournal(url: url)
        let active = try XCTUnwrap(reopened.activeSession(accountKey: key))
        XCTAssertEqual(active.commandIds, [logId, fixId])
        var restored = try SessionMachine(
            restoring: active.events, owner: "watch", accountKey: key, deviceId: "watch-installation-a",
            clock: { Date(timeIntervalSince1970: 1_792_100_000) }, timeZone: "Asia/Kolkata",
            appliedCommandIds: active.commandIds)
        XCTAssertNil(try restored.apply(command: log))
        XCTAssertEqual(restored.state.sets.first?.reps, 9)
        XCTAssertEqual(restored.events.count, 3)
    }

    func testReopenRestoresTheActiveSessionAndItsReplayedState() throws {
        var journal: WatchJournal? = try WatchJournal(url: url)
        let events = try recordSession(journal!, sets: 2)
        journal = nil
        let reopened = try WatchJournal(url: url)
        let restored = try XCTUnwrap(reopened.activeSession(accountKey: key))
        XCTAssertEqual(restored.events, events)
        XCTAssertEqual(restored.state, replay(events))
        XCTAssertEqual(restored.state.completedSets, 2)
    }

    func testDuplicateEventIdIsIgnored() throws {
        let journal = try WatchJournal(url: url)
        let events = try recordSession(journal, sets: 1)
        let count = try journal.pendingOutbox(limit: 100).count
        try journal.record(events[1], sessionState: replay(events))
        XCTAssertEqual(try journal.pendingOutbox(limit: 100).count, count)
        XCTAssertEqual(try journal.activeSession(accountKey: key)?.events.count, events.count)
    }

    func testAcknowledgeRemovesOnlyThatMessageAndIsIdempotent() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 2)
        let pending = try journal.pendingOutbox(limit: 100)
        XCTAssertEqual(pending.count, 3)
        let id = try XCTUnwrap(UUID(uuidString: pending[0].messageId))
        try journal.acknowledge(messageId: id)
        try journal.acknowledge(messageId: id)
        let left = try journal.pendingOutbox(limit: 100)
        XCTAssertEqual(left.map { $0.messageId }, pending.dropFirst().map { $0.messageId })
    }

    func testHealthForAnotherDateIsNil() throws {
        let journal = try WatchJournal(url: url)
        let snapshot = try fixture("health_snapshot")
        try journal.saveHealth(snapshot)
        XCTAssertNotNil(try journal.health(accountKey: key, forLocalDate: "2026-10-23"))
        XCTAssertNil(try journal.health(accountKey: key, forLocalDate: "2026-10-24"))
        // Reading another date deleted the stale row (cleared at local midnight).
        XCTAssertNil(try journal.health(accountKey: key, forLocalDate: "2026-10-23"))
    }

    func testSavingTodaysHealthDeletesOlderDates() throws {
        let journal = try WatchJournal(url: url)
        let old = try fixture("health_snapshot")
        try journal.saveHealth(old)
        guard case .healthSnapshot(_, let raw) = old.body else { return XCTFail("fixture") }
        var next = raw
        next["local_date"] = "2026-10-24"
        let newer = WatchMessage(
            messageId: UUID().uuidString.lowercased(), sentAtUtc: old.sentAtUtc, accountKey: key,
            body: .healthSnapshot(localDate: "2026-10-24", raw: next))
        try journal.saveHealth(newer)
        XCTAssertNotNil(try journal.health(accountKey: key, forLocalDate: "2026-10-24"))
        XCTAssertNil(try journal.health(accountKey: key, forLocalDate: "2026-10-23"))
    }

    func testClearAccountWithoutWipeKeepsUnsentOutbox() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        try journal.savePlans(fixture("plans_snapshot"))
        try journal.saveHealth(fixture("health_snapshot"))
        try journal.clearAccount(key, wipeUnsent: false)
        XCTAssertNil(try journal.plans(accountKey: key))
        XCTAssertNil(try journal.health(accountKey: key, forLocalDate: "2026-10-23"))
        XCTAssertEqual(try journal.pendingOutbox(limit: 100).count, 2)
        XCTAssertNotNil(try journal.activeSession(accountKey: key))
    }

    func testClearAccountWithWipeRemovesIt() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        try journal.clearAccount(key, wipeUnsent: true)
        XCTAssertTrue(try journal.pendingOutbox(limit: 100).isEmpty)
        XCTAssertNil(try journal.activeSession(accountKey: key))
    }

    func testOutboxSurvivesReopen() throws {
        var journal: WatchJournal? = try WatchJournal(url: url)
        try recordSession(journal!, sets: 1)
        try journal!.saveCompleted(fixture("completed_workout"))
        journal = nil
        let reopened = try WatchJournal(url: url)
        XCTAssertEqual(try reopened.pendingOutbox(limit: 100).count, 3)
    }

    func testBindingRoundTripsAndClearAccountRemovesItOnlyForItsKey() throws {
        let journal = try WatchJournal(url: url)
        XCTAssertNil(try journal.binding())
        try journal.saveBinding(TestMessages.binding(TestMessages.keyA, unit: "lb"))
        XCTAssertEqual(try journal.binding()?.accountKey, TestMessages.keyA)
        XCTAssertEqual(try journal.binding()?.unit, "lb")
        try journal.clearAccount(TestMessages.keyB, wipeUnsent: false)
        XCTAssertNotNil(try journal.binding())
        try journal.clearAccount(TestMessages.keyA, wipeUnsent: false)
        XCTAssertNil(try journal.binding())
    }

    func testJournalMigratesUserVersion2To3KeepingOutboxRows() throws {
        // A database written before the binding table existed.
        let old = try SQLiteDatabase(url: url)
        try old.execute("CREATE TABLE outbox(message_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, json TEXT NOT NULL, created_at TEXT NOT NULL)")
        let message = try fixture("completed_workout")
        try old.execute(
            "INSERT INTO outbox(message_id, account_key, json, created_at) VALUES(?,?,?,?)",
            [.text(message.messageId.lowercased()), .text(message.accountKey),
             .text(String(decoding: try message.jsonData(), as: UTF8.self)), .text("2026-10-23T00:00:00Z")])
        try old.setUserVersion(2)

        let journal = try WatchJournal(url: url)
        XCTAssertEqual(try journal.pendingOutbox(limit: 10).count, 1)
        XCTAssertNil(try journal.binding())
        try journal.saveBinding(TestMessages.binding())
        XCTAssertEqual(try journal.binding()?.accountKey, TestMessages.keyA)
        let check = try SQLiteDatabase(url: url)
        XCTAssertEqual(try check.query("PRAGMA user_version").first?.first, .int(3))
    }
}
