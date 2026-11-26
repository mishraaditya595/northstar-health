import XCTest
@testable import BeyondRepWatchCore

final class PhoneInboxTests: XCTestCase {
    private var dir: URL!
    private var journal: WatchJournal!
    private var inbox: PhoneInbox!
    private typealias M = TestMessages

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        journal = try WatchJournal(url: dir.appendingPathComponent("journal.sqlite"))
        inbox = PhoneInbox(journal: journal)
    }

    override func tearDownWithError() throws {
        inbox = nil
        journal = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func context(_ messages: WatchMessage...) throws -> [String: Any] {
        var out: [String: Any] = [:]
        for m in messages { out[m.type] = try M.json(m) }
        return out
    }

    func testBindingReplacesAndClearsThePreviousAccountsPlansAndHealth() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyA), M.plans(M.keyA), M.health(M.keyA)))
        XCTAssertNotNil(try journal.plans(accountKey: M.keyA))
        XCTAssertNotNil(try journal.health(accountKey: M.keyA, forLocalDate: "2026-10-23"))

        try inbox.receive(applicationContext: context(M.binding(M.keyB)))
        XCTAssertNil(try journal.plans(accountKey: M.keyA))
        XCTAssertNil(try journal.health(accountKey: M.keyA, forLocalDate: "2026-10-23"))
        XCTAssertEqual(try journal.binding()?.accountKey, M.keyB)
    }

    func testBindingWithTheSameKeyKeepsPlansAndUpdatesTheUnit() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyA), M.plans(M.keyA)))
        try inbox.receive(applicationContext: context(M.binding(M.keyA, unit: "lb")))
        XCTAssertNotNil(try journal.plans(accountKey: M.keyA))
        XCTAssertEqual(try journal.binding()?.unit, "lb")
    }

    func testBindingInTheSameContextIsAppliedBeforePlansAndHealth() throws {
        // Dictionary order is arbitrary; binding must still go first.
        try inbox.receive(applicationContext: context(M.plans(M.keyB), M.health(M.keyB), M.binding(M.keyB)))
        XCTAssertNotNil(try journal.plans(accountKey: M.keyB))
        XCTAssertNotNil(try journal.health(accountKey: M.keyB, forLocalDate: "2026-10-23"))
    }

    func testPlansForAnotherAccountAreDropped() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyA)))
        try inbox.receive(applicationContext: context(M.plans(M.keyB), M.health(M.keyB)))
        XCTAssertNil(try journal.plans(accountKey: M.keyB))
        XCTAssertNil(try journal.plans(accountKey: M.keyA))
        XCTAssertNil(try journal.health(accountKey: M.keyB, forLocalDate: "2026-10-23"))
    }

    func testPlansWithoutAnyBindingAreDropped() throws {
        try inbox.receive(applicationContext: context(M.plans(M.keyA)))
        XCTAssertNil(try journal.plans(accountKey: M.keyA))
    }

    func testAccountClearedWithoutWipeKeepsTheOutbox() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyA), M.plans(M.keyA)))
        let completed = try WatchMessage(
            json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/completed_workout.json"))
        XCTAssertEqual(completed.accountKey, M.keyA)
        try journal.saveCompleted(completed)

        try inbox.receive(userInfo: ["json": M.json(M.cleared(M.keyA, wipe: false))])
        XCTAssertNil(try journal.binding())
        XCTAssertNil(try journal.plans(accountKey: M.keyA))
        XCTAssertEqual(try journal.pendingOutbox(limit: 10).count, 1)
    }

    func testAccountClearedWithWipeRemovesTheOutbox() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyA)))
        let completed = try WatchMessage(
            json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/completed_workout.json"))
        try journal.saveCompleted(completed)
        try inbox.receive(userInfo: ["json": M.json(M.cleared(M.keyA, wipe: true))])
        XCTAssertTrue(try journal.pendingOutbox(limit: 10).isEmpty)
    }

    func testAccountClearedForAnotherKeyKeepsTheCurrentBinding() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyB), M.plans(M.keyB)))
        try inbox.receive(userInfo: ["json": M.json(M.cleared(M.keyA, wipe: false))])
        XCTAssertEqual(try journal.binding()?.accountKey, M.keyB)
        XCTAssertNotNil(try journal.plans(accountKey: M.keyB))
    }

    func testBadJSONEntryIsSkippedAndCounted() throws {
        var ctx = try context(M.binding(M.keyA))
        ctx["plans_snapshot"] = "{not json"
        ctx["health_snapshot"] = 42
        try inbox.receive(applicationContext: ctx)
        XCTAssertEqual(try journal.binding()?.accountKey, M.keyA)
        XCTAssertEqual(inbox.rejectedCount, 2)

        try inbox.receive(userInfo: ["json": "nope"])
        try inbox.receive(userInfo: ["other": "x"])
        XCTAssertEqual(inbox.rejectedCount, 4)
    }

    func testEntryWhoseTypeDoesNotMatchItsKeyIsRejected() throws {
        try inbox.receive(applicationContext: ["plans_snapshot": M.json(M.binding(M.keyA))])
        XCTAssertNil(try journal.binding())
        XCTAssertEqual(inbox.rejectedCount, 1)
    }

    func testClearedThenAReplayedOlderBindingIsRejected() throws {
        let old = M.binding(M.keyA, at: "2026-10-23T01:00:00Z")
        try inbox.receive(applicationContext: context(old, M.plans(M.keyA)))
        try inbox.receive(userInfo: ["json": M.json(M.cleared(M.keyA, at: "2026-10-23T02:00:00Z"))])
        XCTAssertNil(try journal.binding())

        // The watch relaunches and replays the context it received before the clear.
        try inbox.receive(applicationContext: context(old, M.plans(M.keyA)))
        XCTAssertNil(try journal.binding())
        XCTAssertNil(try journal.plans(accountKey: M.keyA))
        XCTAssertEqual(inbox.rejectedCount, 0, "a stale replay is ignored, not malformed")
    }

    func testBindingNewerThanTheClearIsAppliedAfterIt() throws {
        try inbox.receive(userInfo: ["json": M.json(M.cleared(M.keyA, at: "2026-10-23T02:00:00Z"))])
        try inbox.receive(applicationContext: context(M.binding(M.keyA, at: "2026-10-23T03:00:00Z")))
        XCTAssertEqual(try journal.binding()?.accountKey, M.keyA)
    }

    func testANewerBindingThenALateOlderClearIsIgnored() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyA, at: "2026-10-23T01:00:00Z")))
        try inbox.receive(applicationContext: context(M.binding(M.keyA, at: "2026-10-23T03:00:00Z"), M.plans(M.keyA)))
        try inbox.receive(userInfo: ["json": M.json(M.cleared(M.keyA, at: "2026-10-23T02:00:00Z"))])
        XCTAssertEqual(try journal.binding()?.accountKey, M.keyA)
        XCTAssertNotNil(try journal.plans(accountKey: M.keyA))
    }

    func testAnOlderBindingDoesNotReplaceANewerOne() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyA, unit: "lb", at: "2026-10-23T03:00:00Z")))
        try inbox.receive(applicationContext: context(M.binding(M.keyA, unit: "kg", at: "2026-10-23T01:00:00Z")))
        XCTAssertEqual(try journal.binding()?.unit, "lb")
    }

    func testReplayingTheSameBindingMessageChangesNothing() throws {
        let binding = M.binding(M.keyA, unit: "lb")
        try inbox.receive(applicationContext: context(binding, M.plans(M.keyA)))
        try inbox.receive(applicationContext: context(binding))
        XCTAssertEqual(try journal.binding()?.unit, "lb")
        XCTAssertNotNil(try journal.plans(accountKey: M.keyA))
        XCTAssertEqual(inbox.rejectedCount, 0)
    }

    func testClearedInTheContextIsAppliedLikeOneSentByTransfer() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyA, at: "2026-10-23T01:00:00Z")))
        try inbox.receive(applicationContext: context(M.cleared(M.keyA, at: "2026-10-23T02:00:00Z")))
        XCTAssertNil(try journal.binding())
    }

    func testAccountDeletionWipesEvenWhenANewerBindingIsStored() throws {
        try inbox.receive(applicationContext: context(M.binding(M.keyA, at: "2026-10-23T03:00:00Z")))
        let completed = try WatchMessage(
            json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/completed_workout.json"))
        try journal.saveCompleted(completed)
        try inbox.receive(userInfo: ["json": M.json(M.cleared(M.keyA, wipe: true, at: "2026-10-23T02:00:00Z"))])
        XCTAssertNil(try journal.binding())
        XCTAssertTrue(try journal.pendingOutbox(limit: 10).isEmpty)
    }
}
