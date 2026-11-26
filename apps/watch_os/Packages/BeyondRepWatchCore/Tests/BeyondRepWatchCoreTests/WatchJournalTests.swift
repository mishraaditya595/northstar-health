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
        if sets > 0 { for n in 1...sets { events.append(try m.log(set: set(n))) } }
        var replayed: [WorkoutEventV2] = []
        for event in events {
            replayed.append(event)
            try journal.record(event, sessionState: replay(replayed))
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
        journal.failAfterEventInsert = true
        XCTAssertThrowsError(try journal.record(event, sessionState: m.state))
        let reopened = try WatchJournal(url: url)
        XCTAssertEqual(try reopened.pendingOutbox(limit: 100).count, before)
        XCTAssertEqual(try reopened.activeSession()?.events.count, 1)
    }

    func testReopenRestoresTheActiveSessionAndItsReplayedState() throws {
        var journal: WatchJournal? = try WatchJournal(url: url)
        let events = try recordSession(journal!, sets: 2)
        journal = nil
        let reopened = try WatchJournal(url: url)
        let restored = try XCTUnwrap(reopened.activeSession())
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
        XCTAssertEqual(try journal.activeSession()?.events.count, events.count)
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
        XCTAssertNotNil(try journal.activeSession())
    }

    func testClearAccountWithWipeRemovesIt() throws {
        let journal = try WatchJournal(url: url)
        try recordSession(journal, sets: 1)
        try journal.clearAccount(key, wipeUnsent: true)
        XCTAssertTrue(try journal.pendingOutbox(limit: 100).isEmpty)
        XCTAssertNil(try journal.activeSession())
    }

    func testOutboxSurvivesReopen() throws {
        var journal: WatchJournal? = try WatchJournal(url: url)
        try recordSession(journal!, sets: 1)
        try journal!.saveCompleted(fixture("completed_workout"))
        journal = nil
        let reopened = try WatchJournal(url: url)
        XCTAssertEqual(try reopened.pendingOutbox(limit: 100).count, 3)
    }
}
