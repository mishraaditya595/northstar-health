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

    func testJournalMigratesUserVersion2To6KeepingOutboxRows() throws {
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
        XCTAssertEqual(try check.query("PRAGMA user_version").first?.first, .int(6))
    }

    func testJournalMigratesAVersion3BindingTableKeepingItsRow() throws {
        let old = try SQLiteDatabase(url: url)
        try old.execute("CREATE TABLE binding(slot INTEGER PRIMARY KEY CHECK(slot = 1), account_key TEXT NOT NULL, unit TEXT NOT NULL)")
        try old.execute("INSERT INTO binding(slot, account_key, unit) VALUES(1,?,?)", [.text(TestMessages.keyA), .text("lb")])
        try old.setUserVersion(3)

        let journal = try WatchJournal(url: url)
        XCTAssertEqual(try journal.binding()?.accountKey, TestMessages.keyA)
        XCTAssertEqual(try journal.binding()?.unit, "lb")
        XCTAssertEqual(try journal.bindingState()?.sentAtMs, 0)
        try journal.saveBinding(TestMessages.binding(TestMessages.keyA, unit: "kg", at: "2026-10-23T01:00:00.250Z"))
        XCTAssertEqual(try journal.bindingState()?.sentAtMs, 1_792_717_200_250)
    }

    func testClearedTombstoneKeepsTheNewestTimeAndSurvivesReopen() throws {
        var journal: WatchJournal? = try WatchJournal(url: url)
        XCTAssertNil(try journal!.clearedAt(TestMessages.keyA))
        try journal!.recordCleared(TestMessages.keyA, sentAtMs: 2_000)
        try journal!.recordCleared(TestMessages.keyA, sentAtMs: 1_000)
        journal = nil
        let reopened = try WatchJournal(url: url)
        XCTAssertEqual(try reopened.clearedAt(TestMessages.keyA), 2_000)
        XCTAssertNil(try reopened.clearedAt(TestMessages.keyB))
    }

    func testMigrationFromVersion4KeepsData() throws {
        let old = try SQLiteDatabase(url: url)
        try old.execute("CREATE TABLE binding(slot INTEGER PRIMARY KEY CHECK(slot = 1), account_key TEXT NOT NULL, unit TEXT NOT NULL, message_id TEXT NOT NULL DEFAULT '', sent_at_ms INTEGER NOT NULL DEFAULT 0)")
        try old.execute(
            "INSERT INTO binding(slot, account_key, unit, message_id, sent_at_ms) VALUES(1,?,?,?,?)",
            [.text(TestMessages.keyA), .text("lb"), .text("77777777-3333-4333-8333-000000000001"), .int(5)])
        try old.setUserVersion(4)

        let journal = try WatchJournal(url: url)
        XCTAssertEqual(try journal.binding()?.accountKey, TestMessages.keyA)
        XCTAssertEqual(try journal.bindingState()?.sentAtMs, 5)
        XCTAssertNil(try journal.lastReceivedMs())
        try journal.recordReceived(atMs: 1_234)
        XCTAssertEqual(try journal.lastReceivedMs(), 1_234)
        let check = try SQLiteDatabase(url: url)
        XCTAssertEqual(try check.query("PRAGMA user_version").first?.first, .int(6))
    }

    func testRecordedReceivedTimeKeepsTheLatestAndSurvivesReopen() throws {
        var journal: WatchJournal? = try WatchJournal(url: url)
        try journal!.recordReceived(atMs: 1_000)
        try journal!.recordReceived(atMs: 2_000)
        journal = nil
        let reopened = try WatchJournal(url: url)
        XCTAssertEqual(try reopened.lastReceivedMs(), 2_000)
    }

    func testClearAccountDeletesTheReceivedTimeOnlyForTheBoundKey() throws {
        let journal = try WatchJournal(url: url)
        try journal.saveBinding(TestMessages.binding(TestMessages.keyA))
        try journal.recordReceived(atMs: 1_000)
        try journal.clearAccount(TestMessages.keyB, wipeUnsent: false)
        XCTAssertEqual(try journal.lastReceivedMs(), 1_000)
        try journal.clearAccount(TestMessages.keyA, wipeUnsent: false)
        XCTAssertNil(try journal.lastReceivedMs())
    }

    // MARK: Version 6 (delivery state and a filtered outbox)

    private func completedMessage(key: String? = nil, id: String = UUID().uuidString.lowercased()) throws -> WatchMessage {
        let base = try fixture("completed_workout")
        return WatchMessage(messageId: id, sentAtUtc: base.sentAtUtc, accountKey: key ?? self.key, body: base.body)
    }

    private func count(_ table: String, session: String? = nil) throws -> Int {
        let check = try SQLiteDatabase(url: url)
        let rows: [[SQLValue]]
        if let session {
            rows = try check.query("SELECT COUNT(*) FROM \(table) WHERE session_id = ?", [.text(session)])
        } else {
            rows = try check.query("SELECT COUNT(*) FROM \(table)")
        }
        guard case .int(let n)? = rows.first?.first else { return -1 }
        return Int(n)
    }

    private func delivery(_ sessionId: String) throws -> String? {
        let check = try SQLiteDatabase(url: url)
        let rows = try check.query("SELECT delivery FROM sessions WHERE session_id = ?", [.text(sessionId)])
        guard case .text(let text)? = rows.first?.first else { return nil }
        return text
    }

    private func columns(_ table: String) throws -> [String] {
        try SQLiteDatabase(url: url).query("PRAGMA table_info(\(table))").compactMap { row in
            guard row.count > 1, case .text(let name) = row[1] else { return nil }
            return name
        }
    }

    /// A finished session (completed, not queued) with one logged set.
    private func recordFinishedSession(_ journal: WatchJournal) throws {
        var m = machine()
        var events = try m.start(name: "Synthetic push day")
        events.append(try m.log(set: set(1)))
        events.append(try m.complete())
        try journal.record(events, sessionState: replay(events))
    }

    func testVersion6AddsColumnsAndKeepsRows() throws {
        let old = try SQLiteDatabase(url: url)
        try old.execute("CREATE TABLE outbox(message_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, json TEXT NOT NULL, created_at TEXT NOT NULL)")
        try old.execute("CREATE TABLE sessions(session_id TEXT PRIMARY KEY, account_key TEXT NOT NULL, status TEXT NOT NULL, state_json TEXT NOT NULL)")
        try old.execute("CREATE TABLE binding(slot INTEGER PRIMARY KEY CHECK(slot = 1), account_key TEXT NOT NULL, unit TEXT NOT NULL, message_id TEXT NOT NULL DEFAULT '', sent_at_ms INTEGER NOT NULL DEFAULT 0)")
        try old.execute(
            "INSERT INTO binding(slot, account_key, unit, message_id, sent_at_ms) VALUES(1,?,?,?,?)",
            [.text(TestMessages.keyA), .text("kg"), .text("77777777-3333-4333-8333-000000000001"), .int(5)])
        let message = try completedMessage()
        try old.execute(
            "INSERT INTO outbox(message_id, account_key, json, created_at) VALUES(?,?,?,?)",
            [.text(message.messageId), .text(message.accountKey),
             .text(String(decoding: try message.jsonData(), as: UTF8.self)), .text("2026-10-23T00:00:00Z")])
        try old.setUserVersion(5)

        let journal = try WatchJournal(url: url)
        XCTAssertEqual(try journal.binding()?.accountKey, TestMessages.keyA)
        XCTAssertEqual(try journal.pendingOutbox(limit: 10).count, 1)
        // The old row's type is filled in, so it counts as a queued completed workout.
        XCTAssertEqual(try journal.pendingCompleted(limit: 10).count, 1)
        let check = try SQLiteDatabase(url: url)
        XCTAssertEqual(try check.query("PRAGMA user_version").first?.first, .int(6))
        XCTAssertTrue(try columns("outbox").contains("type"))
        XCTAssertTrue(try columns("outbox").contains("session_id"))
        XCTAssertTrue(try columns("sessions").contains("delivery"))
        XCTAssertTrue(try columns("sessions").contains("template_json"))
    }

    func testPendingCompletedSkipsEventMessages() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        XCTAssertEqual(try journal.pendingOutbox(limit: 10).count, 2)
        try journal.queueCompleted(try completedMessage(), sessionId: session)
        XCTAssertEqual(try journal.pendingCompleted(limit: 10).map(\.type), ["completed_workout"])
    }

    func testStoredAckClearsSessionOutboxAndEvents() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        let message = try completedMessage()
        try journal.queueCompleted(message, sessionId: session)
        let effect = try journal.applyAck(ackedMessageId: message.messageId.uppercased(), result: "stored")
        XCTAssertEqual(effect, .delivered(sessionId: session))
        XCTAssertTrue(try journal.pendingOutbox(limit: 50).isEmpty)
        XCTAssertEqual(try count("events", session: session), 0)
        XCTAssertEqual(try delivery(session), "delivered")
    }

    func testDuplicateAckCountsAsDelivered() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        let message = try completedMessage()
        try journal.queueCompleted(message, sessionId: session)
        XCTAssertEqual(try journal.applyAck(ackedMessageId: message.messageId, result: "duplicate"), .delivered(sessionId: session))
        XCTAssertEqual(try delivery(session), "delivered")
    }

    func testRejectedAckMarksRejected() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        let message = try completedMessage()
        try journal.queueCompleted(message, sessionId: session)
        XCTAssertEqual(try journal.applyAck(ackedMessageId: message.messageId, result: "rejected"), .rejected(sessionId: session))
        XCTAssertEqual(try delivery(session), "rejected")
        XCTAssertTrue(try journal.pendingOutbox(limit: 50).isEmpty)
        XCTAssertEqual(try count("events", session: session), 0)
    }

    func testAckForUnknownMessageIsIgnored() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        let outboxBefore = try count("outbox")
        let eventsBefore = try count("events")
        XCTAssertNil(try journal.applyAck(ackedMessageId: "77777777-3333-4333-8333-0000000000ff", result: "stored"))
        XCTAssertEqual(try count("outbox"), outboxBefore)
        XCTAssertEqual(try count("events"), eventsBefore)
    }

    func testSecondAckChangesNothing() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        let message = try completedMessage()
        try journal.queueCompleted(message, sessionId: session)
        XCTAssertNotNil(try journal.applyAck(ackedMessageId: message.messageId, result: "stored"))
        XCTAssertNil(try journal.applyAck(ackedMessageId: message.messageId, result: "stored"))
        XCTAssertEqual(try delivery(session), "delivered")
    }

    func testAbandonDropsQueuedEventMessages() throws {
        let journal = try WatchJournal(url: url)
        var m = machine()
        var events = try m.start(name: "x")
        try journal.record(events, sessionState: replay(events))
        let log = try m.log(set: set(1))
        events.append(log)
        try journal.record(log, sessionState: replay(events))
        XCTAssertGreaterThan(try count("outbox", session: session), 0)
        let abandon = try m.abandon()
        events.append(abandon)
        try journal.record(abandon, sessionState: replay(events))
        XCTAssertEqual(try count("outbox", session: session), 0)
    }

    func testQueueCompletedIsIdempotent() throws {
        let journal = try WatchJournal(url: url)
        try recordFinishedSession(journal)
        let message = try completedMessage()
        try journal.queueCompleted(message, sessionId: session)
        try journal.queueCompleted(message, sessionId: session)
        XCTAssertEqual(try journal.pendingCompleted(limit: 10).count, 1)
        XCTAssertEqual(try delivery(session), "queued")
    }

    func testQueueCompletedAfterDeliveryDoesNotRequeueTheState() throws {
        let journal = try WatchJournal(url: url)
        try recordFinishedSession(journal)
        let message = try completedMessage()
        try journal.queueCompleted(message, sessionId: session)
        _ = try journal.applyAck(ackedMessageId: message.messageId, result: "stored")
        try journal.queueCompleted(message, sessionId: session)
        XCTAssertEqual(try delivery(session), "delivered")
    }

    func testWaitingCountsSplitByAccount() throws {
        let journal = try WatchJournal(url: url)
        try journal.queueCompleted(try completedMessage(key: TestMessages.keyA), sessionId: session)
        try journal.queueCompleted(try completedMessage(key: TestMessages.keyB), sessionId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2")
        let split = try journal.waitingCounts(boundKey: TestMessages.keyA)
        XCTAssertEqual(split.thisAccount, 1)
        XCTAssertEqual(split.otherAccounts, 1)
        let none = try journal.waitingCounts(boundKey: nil)
        XCTAssertEqual(none.thisAccount, 0)
        XCTAssertEqual(none.otherAccounts, 2)
    }

    func testSessionsAwaitingQueue() throws {
        let journal = try WatchJournal(url: url)
        try recordFinishedSession(journal)
        XCTAssertEqual(try journal.sessionsAwaitingQueue(accountKey: key), [session])
        XCTAssertEqual(try journal.sessionsAwaitingQueue(accountKey: TestMessages.keyB), [])
        try journal.queueCompleted(try completedMessage(), sessionId: session)
        XCTAssertEqual(try journal.sessionsAwaitingQueue(accountKey: key), [])
    }

    func testTemplateIsWrittenWithTheStartEvents() throws {
        let journal = try WatchJournal(url: url)
        var m = machine()
        let events = try m.start(name: "x")
        try journal.record(events, sessionState: replay(events), template: "{\"name\":\"x\"}")
        XCTAssertEqual(try journal.template(sessionId: session), "{\"name\":\"x\"}")
        XCTAssertEqual(try journal.activeSession(accountKey: key)?.sessionId, session)

        let otherDir = dir.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        let failing = try WatchJournal(url: otherDir.appendingPathComponent("j.sqlite"))
        failing.failAt = .afterSessionUpsert
        XCTAssertThrowsError(try failing.record(events, sessionState: replay(events), template: "{}"))
        XCTAssertNil(try failing.template(sessionId: session))
    }

    func testSaveTemplateReplacesTheStoredTemplate() throws {
        let journal = try WatchJournal(url: url)
        var m = machine()
        let events = try m.start(name: "x")
        try journal.record(events, sessionState: replay(events), template: "{\"a\":1}")
        try journal.saveTemplate(sessionId: session, json: "{\"a\":2}")
        XCTAssertEqual(try journal.template(sessionId: session), "{\"a\":2}")
    }
}
