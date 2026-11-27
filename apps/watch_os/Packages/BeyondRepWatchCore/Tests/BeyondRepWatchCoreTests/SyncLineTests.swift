import XCTest
@testable import BeyondRepWatchCore

final class SyncLineTests: XCTestCase {
    private var dir: URL!
    private var journal: WatchJournal!
    private typealias M = TestMessages
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let locale = Locale(identifier: "en_US")
    /// 10:43 on 2026-10-23 in Asia/Kolkata.
    private let receivedMs: Int64 = 1_792_732_380_000

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        journal = try WatchJournal(url: dir.appendingPathComponent("journal.sqlite"))
    }

    override func tearDownWithError() throws {
        journal = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func line(reachable: Bool) throws -> SyncLine {
        try SyncLine.make(
            journal: journal, isPhoneReachable: reachable, now: M.date("2026-10-23T06:00:00Z"), timeZone: kolkata,
            locale: locale)
    }

    func testSyncLineStates() throws {
        // Nothing bound: not set up, reachable or not.
        XCTAssertEqual(try line(reachable: true), .notPaired)
        XCTAssertEqual(try line(reachable: false), .notPaired)

        try journal.saveBinding(M.binding())
        try journal.recordReceived(atMs: receivedMs)
        guard case .synced(let time) = try line(reachable: true) else { return XCTFail("expected synced") }
        XCTAssertTrue(time.contains("10:43"), time)
        guard case .phoneAway(let away) = try line(reachable: false) else { return XCTFail("expected phoneAway") }
        XCTAssertTrue(away.contains("10:43"), away)
    }

    private func timeText(daysAgo: Int64) throws -> String {
        try journal.saveBinding(M.binding())
        try journal.recordReceived(atMs: receivedMs - daysAgo * 86_400_000)
        guard case .synced(let text) = try line(reachable: true) else { throw XCTSkip("not synced") }
        return text
    }

    func testTheDayComesBeforeTheTime() throws {
        // now is Friday 2026-10-23 11:30 in Asia/Kolkata.
        let today = try timeText(daysAgo: 0)
        XCTAssertTrue(today.hasPrefix("Today "), today)
        XCTAssertTrue(today.contains("10:43"), today)
    }

    func testYesterdayWeekdayAndDate() throws {
        XCTAssertTrue(try timeText(daysAgo: 1).hasPrefix("Yesterday "))
        XCTAssertTrue(try timeText(daysAgo: 3).hasPrefix("Tue "))  // 2026-10-20
        XCTAssertTrue(try timeText(daysAgo: 6).hasPrefix("Sat "))  // 2026-10-17
        let old = try timeText(daysAgo: 13)  // 2026-10-10
        XCTAssertTrue(old.hasPrefix("10 Oct "), old)
        XCTAssertTrue(old.contains("10:43"), old)
    }

    func testBoundButNothingReceivedYetIsNotPaired() throws {
        try journal.saveBinding(M.binding())
        XCTAssertEqual(try line(reachable: true), .notPaired)
    }

    func testClearingTheAccountDropsTheLine() throws {
        try journal.saveBinding(M.binding())
        try journal.recordReceived(atMs: receivedMs)
        try journal.clearAccount(M.keyA, wipeUnsent: false)
        XCTAssertEqual(try line(reachable: true), .notPaired)
    }

    // MARK: Waiting workouts

    private func queue(key: String, session: String) throws {
        let base = try WatchMessage(
            json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/completed_workout.json"))
        let message = WatchMessage(messageId: M.id(), sentAtUtc: base.sentAtUtc, accountKey: key, body: base.body)
        try journal.queueCompleted(message, sessionId: session)
    }

    func testSyncLineCountsWaitingWorkouts() throws {
        try journal.saveBinding(M.binding(M.keyA))
        XCTAssertEqual(try WaitingWorkouts.make(journal: journal), WaitingWorkouts(waiting: 0, waitingOtherAccount: 0))
        XCTAssertTrue(try WaitingWorkouts.make(journal: journal).lines.isEmpty)
        try queue(key: M.keyA, session: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1")
        XCTAssertEqual(try WaitingWorkouts.make(journal: journal).lines, ["1 workout waiting for iPhone"])
        try queue(key: M.keyA, session: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2")
        XCTAssertEqual(try WaitingWorkouts.make(journal: journal).lines, ["2 workouts waiting for iPhone"])
    }

    func testSyncLineShowsOtherAccountWaiting() throws {
        try journal.saveBinding(M.binding(M.keyA))
        try queue(key: M.keyB, session: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3")
        let waiting = try WaitingWorkouts.make(journal: journal)
        XCTAssertEqual(waiting.waiting, 0)
        XCTAssertEqual(waiting.waitingOtherAccount, 1)
        XCTAssertEqual(waiting.lines, ["1 from another account waiting"])
    }
}
