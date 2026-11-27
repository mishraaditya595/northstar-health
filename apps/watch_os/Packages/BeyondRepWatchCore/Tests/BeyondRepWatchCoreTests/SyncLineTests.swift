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
}
