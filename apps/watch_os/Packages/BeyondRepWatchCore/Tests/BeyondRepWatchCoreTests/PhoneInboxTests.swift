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

    // MARK: Ack outcomes

    private func message(_ m: WatchMessage) -> String { m.messageId.lowercased() }

    func testStoredAckForEachAppliedContextMessage() throws {
        let binding = M.binding(M.keyA), plans = M.plans(M.keyA), health = M.health(M.keyA)
        let outcomes = try inbox.receive(applicationContext: context(health, plans, binding), now: M.date(M.t0))
        XCTAssertEqual(
            outcomes,
            [
                AckOutcome(messageId: message(binding), accountKey: M.keyA, result: "stored", reason: nil),
                AckOutcome(messageId: message(plans), accountKey: M.keyA, result: "stored", reason: nil),
                AckOutcome(messageId: message(health), accountKey: M.keyA, result: "stored", reason: nil),
            ])
    }

    func testSameHealthTwiceIsDuplicate() throws {
        let binding = M.binding(M.keyA), health = M.health(M.keyA)
        _ = try inbox.receive(applicationContext: context(binding, health), now: M.date(M.t0))
        let again = try inbox.receive(applicationContext: context(binding, health), now: M.date(M.t0))
        XCTAssertEqual(
            again,
            [
                AckOutcome(messageId: message(binding), accountKey: M.keyA, result: "duplicate", reason: nil),
                AckOutcome(messageId: message(health), accountKey: M.keyA, result: "duplicate", reason: nil),
            ])
        let plans = M.plans(M.keyA)
        XCTAssertEqual(try inbox.receive(applicationContext: context(plans)).first?.result, "stored")
        XCTAssertEqual(try inbox.receive(applicationContext: context(plans)).first?.result, "duplicate")
    }

    func testPlansForAnotherBoundAccountAreRejectedWrongAccount() throws {
        _ = try inbox.receive(applicationContext: context(M.binding(M.keyA)))
        let plans = M.plans(M.keyB), health = M.health(M.keyB)
        let outcomes = try inbox.receive(applicationContext: context(plans, health))
        XCTAssertEqual(
            outcomes,
            [
                AckOutcome(messageId: message(plans), accountKey: M.keyB, result: "rejected", reason: "wrong_account"),
                AckOutcome(messageId: message(health), accountKey: M.keyB, result: "rejected", reason: "wrong_account"),
            ])
        XCTAssertNil(try journal.plans(accountKey: M.keyB))
    }

    func testNoAckWithoutBinding() throws {
        let outcomes = try inbox.receive(applicationContext: context(M.plans(M.keyA), M.health(M.keyA)))
        XCTAssertEqual(outcomes, [])
        XCTAssertEqual(try inbox.receive(userInfo: ["json": "not json"]), [])
        XCTAssertEqual(try inbox.receive(userInfo: [:]), [])
    }

    func testClearedGivesAStoredAckAndDropsTheReceivedTime() throws {
        _ = try inbox.receive(applicationContext: context(M.binding(M.keyA)))
        let cleared = M.cleared(M.keyA)
        let outcomes = try inbox.receive(userInfo: ["json": try M.json(cleared)])
        XCTAssertEqual(
            outcomes, [AckOutcome(messageId: message(cleared), accountKey: M.keyA, result: "stored", reason: nil)])
    }

    func testReceivedTimeRecordedAndClearedWithAccount() throws {
        XCTAssertNil(try journal.lastReceivedMs())
        let now = M.date("2026-10-23T05:00:00Z")
        _ = try inbox.receive(applicationContext: context(M.binding(M.keyA), M.health(M.keyA)), now: now)
        XCTAssertEqual(try journal.lastReceivedMs(), 1_792_731_600_000)

        // A rejected message does not count as received.
        let later = M.date("2026-10-23T06:00:00Z")
        _ = try inbox.receive(applicationContext: context(M.plans(M.keyB)), now: later)
        XCTAssertEqual(try journal.lastReceivedMs(), 1_792_731_600_000)

        _ = try inbox.receive(userInfo: ["json": try M.json(M.cleared(M.keyA))], now: later)
        XCTAssertNil(try journal.lastReceivedMs())
    }

    func testReplayedDuplicatesDoNotMoveTheReceivedTime() throws {
        let first = M.date("2026-10-23T05:00:00Z")
        let ctx = try context(M.binding(M.keyA), M.plans(M.keyA), M.health(M.keyA))
        _ = try inbox.receive(applicationContext: ctx, now: first)
        XCTAssertEqual(try journal.lastReceivedMs(), 1_792_731_600_000)

        // The same context again at launch, days later: all duplicates.
        let later = M.date("2026-10-26T09:00:00Z")
        let outcomes = try inbox.receive(applicationContext: ctx, now: later)
        XCTAssertEqual(outcomes.map(\.result), ["duplicate", "duplicate", "duplicate"])
        XCTAssertEqual(try journal.lastReceivedMs(), 1_792_731_600_000)
    }

    // MARK: Acks for completed workouts

    private let ackSession = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

    private func queuedCompleted(key: String = M.keyA) throws -> WatchMessage {
        let base = try WatchMessage(
            json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/completed_workout.json"))
        let message = WatchMessage(messageId: M.id(), sentAtUtc: base.sentAtUtc, accountKey: key, body: base.body)
        try journal.queueCompleted(message, sessionId: ackSession)
        return message
    }

    private func ack(_ message: WatchMessage, result: String, key: String? = nil) throws -> [String: Any] {
        let reason: String? = result == "rejected" ? "invalid" : nil
        let ack = WatchMessage(
            messageId: M.id(), sentAtUtc: "2026-10-23T11:41:00Z", accountKey: key ?? message.accountKey,
            body: .ack(ackedMessageId: message.messageId, result: result, reason: reason))
        return ["json": try M.json(ack)]
    }

    func testStoredAckMarksDelivered() throws {
        let queued = try queuedCompleted()
        try inbox.receive(userInfo: ack(queued, result: "stored"))
        XCTAssertTrue(try journal.pendingCompleted(limit: 10).isEmpty)
        XCTAssertEqual(inbox.lastAckEffects, [.delivered(sessionId: ackSession)])
    }

    func testRejectedAckMarksRejected() throws {
        let queued = try queuedCompleted()
        try inbox.receive(userInfo: ack(queued, result: "rejected"))
        XCTAssertTrue(try journal.pendingCompleted(limit: 10).isEmpty)
        XCTAssertEqual(inbox.lastAckEffects, [.rejected(sessionId: ackSession)])
    }

    func testAckWithOtherAccountKeyIsIgnored() throws {
        let queued = try queuedCompleted()
        try inbox.receive(userInfo: ack(queued, result: "stored", key: M.keyB))
        XCTAssertEqual(try journal.pendingCompleted(limit: 10).count, 1)
        XCTAssertTrue(inbox.lastAckEffects.isEmpty)
        XCTAssertEqual(inbox.ignoredCount, 1)
    }

    func testAckProducesNoOutcome() throws {
        let queued = try queuedCompleted()
        let outcomes = try inbox.receive(userInfo: ack(queued, result: "stored"))
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertEqual(inbox.rejectedCount, 0)
    }

    func testAckForUnknownMessageChangesNothingAndThrowsNothing() throws {
        let unknown = WatchMessage(
            messageId: M.id(), sentAtUtc: "2026-10-23T11:41:00Z", accountKey: M.keyA,
            body: .completedWorkout(workoutId: "x", lastSequence: 0, healthkitWorkoutUuid: nil, raw: [:]))
        let outcomes = try inbox.receive(userInfo: ack(unknown, result: "stored"))
        XCTAssertTrue(outcomes.isEmpty)
        XCTAssertTrue(inbox.lastAckEffects.isEmpty)
    }

    // MARK: Acks for workout links (stage 5b)

    private func queuedLink(key: String = M.keyA) throws -> WatchMessage {
        let message = WatchMessage(
            messageId: M.id(), sentAtUtc: "2026-10-23T11:00:00Z", accountKey: key,
            body: .workoutLink(workoutId: ackSession, healthkitWorkoutUuid: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"))
        XCTAssertTrue(try journal.queueWorkoutLink(message))
        return message
    }

    func testStoredAckSettlesAWorkoutLink() throws {
        let queued = try queuedLink()
        try inbox.receive(userInfo: ack(queued, result: "stored"))
        XCTAssertTrue(try journal.pendingLinks(limit: 10).isEmpty)
        XCTAssertEqual(inbox.lastAckEffects, [.linked(workoutId: ackSession)])
    }

    func testLinkAckWithOtherAccountKeyIsIgnored() throws {
        let queued = try queuedLink()
        try inbox.receive(userInfo: ack(queued, result: "stored", key: M.keyB))
        XCTAssertEqual(try journal.pendingLinks(limit: 10).count, 1)
        XCTAssertTrue(inbox.lastAckEffects.isEmpty)
        XCTAssertEqual(inbox.ignoredCount, 1)
    }
}
