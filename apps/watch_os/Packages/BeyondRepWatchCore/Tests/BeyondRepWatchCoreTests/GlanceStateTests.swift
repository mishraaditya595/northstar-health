import XCTest
@testable import BeyondRepWatchCore

final class GlanceStateTests: XCTestCase {
    private var dir: URL!
    private var journal: WatchJournal!
    private typealias M = TestMessages
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let locale = Locale(identifier: "en_US")

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        journal = try WatchJournal(url: dir.appendingPathComponent("journal.sqlite"))
    }

    override func tearDownWithError() throws {
        journal = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func make(now: String) throws -> GlanceState {
        try GlanceState.make(journal: journal, now: M.date(now), timeZone: kolkata, locale: locale)
    }

    private func ready(_ state: GlanceState) throws -> Glance {
        guard case .ready(let glance) = state else { throw XCTSkip("expected ready, got \(state)") }
        return glance
    }

    func testGlanceNotPairedWithoutBinding() throws {
        XCTAssertEqual(try make(now: "2026-10-23T05:00:00Z"), .notPaired)
    }

    func testGlanceShowsReadinessAndTilesForToday() throws {
        try journal.saveBinding(M.binding())
        try journal.saveHealth(M.health())
        try journal.savePlans(M.plans(names: ["Push", "Pull"], today: ("plan-1", "Pull day", "2026-10-23")))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertEqual(g.readiness, ReadinessLine(score: 72, band: "good", headline: "Ready to train"))
        XCTAssertEqual(g.tiles.map { $0.label }, ["Sleep", "Resting HR", "HRV", "Steps"])
        XCTAssertEqual(g.tiles[0], GlanceTile(label: "Sleep", value: "7h 12m", unit: "score 81"))
        XCTAssertEqual(g.tiles[1], GlanceTile(label: "Resting HR", value: "54", unit: "bpm"))
        XCTAssertEqual(g.tiles[2], GlanceTile(label: "HRV", value: "62", unit: "ms"))
        XCTAssertEqual(g.tiles[3], GlanceTile(label: "Steps", value: "1,200", unit: nil))
        XCTAssertTrue(g.caption.hasPrefix("as of "), g.caption)
        XCTAssertTrue(g.caption.contains("7:10"), g.caption)
        XCTAssertEqual(g.plans.map { $0.name }, ["Push", "Pull"])
        XCTAssertEqual(g.today, PlanRow(id: "plan-1", name: "Pull day"))
    }

    func testGlanceAfterMidnightShowsTheRefreshCaptionAndDashes() throws {
        try journal.saveBinding(M.binding())
        // 23:50 local on 2026-10-22, viewed at 00:05 on 2026-10-23.
        try journal.saveHealth(M.health(localDate: "2026-10-22", asOf: "2026-10-22T18:20:00Z"))
        let g = try ready(try make(now: "2026-10-22T18:35:00Z"))
        XCTAssertEqual(g.caption, "Open BeyondRep on your iPhone to refresh")
        XCTAssertNil(g.readiness)
        XCTAssertEqual(g.tiles.map { $0.value }, ["—", "—", "—", "—"])
    }

    func testGlanceBeforeAnyHealthArrivesShowsTheRefreshCaption() throws {
        try journal.saveBinding(M.binding())
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertEqual(g.caption, "Open BeyondRep on your iPhone to refresh")
        XCTAssertEqual(g.tiles.map { $0.value }, ["—", "—", "—", "—"])
    }

    func testMissingStepsShowsADashNotZero() throws {
        try journal.saveBinding(M.binding())
        var raw: [String: Any] = [
            "local_date": "2026-10-23", "as_of_utc": "2026-10-23T01:40:00Z", "resting_hr_bpm": 54,
        ]
        raw["hrv_ms"] = nil
        try journal.saveHealth(
            WatchMessage(
                messageId: M.id(), sentAtUtc: "2026-10-23T01:45:00Z", accountKey: M.keyA,
                body: .healthSnapshot(localDate: "2026-10-23", raw: raw)))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertNil(g.readiness)
        XCTAssertEqual(g.tiles[0], GlanceTile(label: "Sleep", value: "—", unit: nil))
        XCTAssertEqual(g.tiles[1].value, "54")
        XCTAssertEqual(g.tiles[2], GlanceTile(label: "HRV", value: "—", unit: nil))
        XCTAssertEqual(g.tiles[3], GlanceTile(label: "Steps", value: "—", unit: nil))
    }

    func testSleepUnderAnHourAndZeroStepsAreShownAsReported() throws {
        try journal.saveBinding(M.binding())
        try journal.saveHealth(M.health(extra: ["sleep": ["asleep_minutes": 45], "steps": 0]))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertEqual(g.tiles[0], GlanceTile(label: "Sleep", value: "45m", unit: nil))
        XCTAssertEqual(g.tiles[3].value, "0")  // a reported zero is real; only missing is a dash
    }

    func testTodaysProgramIsHiddenWhenItsDateIsNotToday() throws {
        try journal.saveBinding(M.binding())
        try journal.savePlans(M.plans(today: ("plan-0", "Old day", "2026-10-22")))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertNil(g.today)
        XCTAssertEqual(g.plans.count, 1)
    }

    func testAnotherAccountsHealthIsNeverShown() throws {
        try journal.saveBinding(M.binding(M.keyB))
        try journal.saveHealth(M.health(M.keyA))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertNil(g.readiness)
        XCTAssertEqual(g.tiles.map { $0.value }, ["—", "—", "—", "—"])
    }
}
