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
        XCTAssertEqual(
            g.tiles[0],
            GlanceTile(label: "Sleep", value: "7h 12m", unit: nil, status: "Score 81", tone: .neutral, metric: .sleep))
        XCTAssertEqual(
            g.tiles[1],
            GlanceTile(label: "Resting HR", value: "54", unit: "bpm", status: nil, tone: .neutral, metric: .restingHr))
        XCTAssertEqual(
            g.tiles[2], GlanceTile(label: "HRV", value: "62", unit: "ms", status: nil, tone: .neutral, metric: .hrv))
        XCTAssertEqual(
            g.tiles[3],
            GlanceTile(label: "Steps", value: "1,200", unit: nil, status: "today", tone: .neutral, metric: .steps))
        XCTAssertEqual(g.readinessReason, "Synthetic reason.")
        XCTAssertTrue(g.caption.hasPrefix("as of "), g.caption)
        XCTAssertTrue(g.caption.contains("7:10"), g.caption)
        XCTAssertEqual(g.plans.map { $0.name }, ["Push"], "today's plan is not listed twice")
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
        XCTAssertEqual(
            g.tiles[0], GlanceTile(label: "Sleep", value: "—", unit: nil, status: nil, tone: .neutral, metric: .sleep))
        XCTAssertEqual(g.tiles[1].value, "54")
        XCTAssertEqual(
            g.tiles[2], GlanceTile(label: "HRV", value: "—", unit: nil, status: nil, tone: .neutral, metric: .hrv))
        XCTAssertEqual(
            g.tiles[3], GlanceTile(label: "Steps", value: "—", unit: nil, status: nil, tone: .neutral, metric: .steps))
    }

    func testSleepUnderAnHourAndZeroStepsAreShownAsReported() throws {
        try journal.saveBinding(M.binding())
        try journal.saveHealth(M.health(extra: ["sleep": ["asleep_minutes": 45], "steps": 0]))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertEqual(g.tiles[0].value, "45m")
        XCTAssertNil(g.tiles[0].status, "no score, no status")
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

    func testHealthRowsFromAnotherDayAreDeletedEvenWithoutABinding() throws {
        try journal.saveHealth(M.health(localDate: "2026-10-22", asOf: "2026-10-22T18:20:00Z"))
        XCTAssertEqual(try make(now: "2026-10-23T05:00:00Z"), .notPaired)
        let check = try SQLiteDatabase(url: dir.appendingPathComponent("journal.sqlite"))
        XCTAssertEqual(try check.query("SELECT COUNT(*) FROM health").first?.first, .int(0))
    }

    func testCaptionParsesTheTimestampFormatDartSends() throws {
        try journal.saveBinding(M.binding())
        // Whole milliseconds, as the phone builds them.
        try journal.saveHealth(M.health(asOf: "2026-10-23T01:40:00.123Z"))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertTrue(g.caption.contains("7:10"), g.caption)
    }

    // MARK: Tile status, factors and plan rows

    private func tiles(_ extra: [String: Any]) throws -> [GlanceTile] {
        try journal.saveBinding(M.binding())
        try journal.saveHealth(M.health(extra: extra))
        return try ready(try make(now: "2026-10-23T05:00:00Z")).tiles
    }

    func testTileStatusLinesFromUsual() throws {
        // Resting HR 54 against 56 and HRV 62 against 56: both better.
        let better = try tiles(["resting_hr_usual_bpm": 56, "hrv_usual_ms": 56])
        XCTAssertEqual(better[1].status, "\u{2212}2 vs usual")
        XCTAssertEqual(better[1].tone, .good)
        XCTAssertEqual(better[2].status, "+6 vs usual")
        XCTAssertEqual(better[2].tone, .good)
        XCTAssertEqual(better[0].status, "Score 81")
        XCTAssertEqual(better[0].tone, .neutral)  // sleep is never coloured as good or bad
        XCTAssertEqual(better[3].status, "today")
        XCTAssertEqual(better[3].tone, .neutral)

        // Resting HR above and HRV below the usual: neutral, not an alarm.
        let worse = try tiles(["resting_hr_usual_bpm": 50, "hrv_usual_ms": 70])
        XCTAssertEqual(worse[1].status, "+4 vs usual")
        XCTAssertEqual(worse[1].tone, .neutral)
        XCTAssertEqual(worse[2].status, "\u{2212}8 vs usual")
        XCTAssertEqual(worse[2].tone, .neutral)
    }

    func testMissingUsualGivesNoStatus() throws {
        let t = try tiles([:])
        XCTAssertNil(t[1].status)
        XCTAssertNil(t[2].status)
        XCTAssertEqual(t[1].tone, .neutral)
    }

    func testMissingValueIsDashNeverZero() throws {
        try journal.saveBinding(M.binding())
        let raw: [String: Any] = [
            "local_date": "2026-10-23", "as_of_utc": "2026-10-23T01:40:00Z",
            "resting_hr_usual_bpm": 56, "hrv_usual_ms": 56,
        ]
        try journal.saveHealth(
            WatchMessage(
                messageId: M.id(), sentAtUtc: "2026-10-23T01:45:00Z", accountKey: M.keyA,
                body: .healthSnapshot(localDate: "2026-10-23", raw: raw)))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertEqual(g.tiles.map { $0.value }, ["—", "—", "—", "—"])
        XCTAssertEqual(g.tiles.map { $0.status }, [nil, nil, nil, nil], "a usual without a value gives no status")
        XCTAssertEqual(g.tiles.map { $0.unit }, [nil, nil, nil, nil])
    }

    func testFactorsInPhoneOrder() throws {
        try journal.saveBinding(M.binding())
        let readiness: [String: Any] = [
            "score": 72, "band": "good", "headline": "Ready to train", "reason": "Synthetic reason.",
            "factors": [
                ["input": "resting_hr", "status": "Below usual", "tone": "good"],
                ["input": "sleep", "status": "Slept 7h 12m", "tone": "good"],
                ["input": "training_load", "status": "Above usual", "tone": "caution"],
            ],
        ]
        try journal.saveHealth(M.health(extra: ["readiness": readiness]))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertEqual(
            g.factors,
            [
                Glance.Factor(input: "resting_hr", status: "Below usual", tone: .good),
                Glance.Factor(input: "sleep", status: "Slept 7h 12m", tone: .good),
                Glance.Factor(input: "training_load", status: "Above usual", tone: .caution),
            ])
        XCTAssertEqual(g.readinessReason, "Synthetic reason.")
    }

    func testNoFactorsWithoutThemInTheSnapshot() throws {
        try journal.saveBinding(M.binding())
        try journal.saveHealth(M.health())
        XCTAssertEqual(try ready(try make(now: "2026-10-23T05:00:00Z")).factors, [])
    }

    func testPlanRowsCarryExerciseCountAndTodaySubtitle() throws {
        try journal.saveBinding(M.binding())
        try journal.savePlans(
            M.plans(names: ["Push", "Pull"], today: ("plan-1", "Pull day", "2026-10-23"), exerciseCount: 6))
        let g = try ready(try make(now: "2026-10-23T05:00:00Z"))
        XCTAssertEqual(g.today, PlanRow(id: "plan-1", name: "Pull day", subtitle: "6 exercises", exerciseCount: 6))
        XCTAssertEqual(g.plans, [PlanRow(id: "plan-0", name: "Push", subtitle: nil, exerciseCount: 6)])
    }

    func testTodaySubtitleIsSingularForOneExerciseAndAbsentForNone() throws {
        try journal.saveBinding(M.binding())
        try journal.savePlans(M.plans(names: ["Push"], today: ("plan-0", "Push day", "2026-10-23"), exerciseCount: 1))
        XCTAssertEqual(try ready(try make(now: "2026-10-23T05:00:00Z")).today?.subtitle, "1 exercise")
        try journal.savePlans(M.plans(names: ["Push"], today: ("plan-0", "Push day", "2026-10-23"), exerciseCount: 0))
        XCTAssertNil(try ready(try make(now: "2026-10-23T05:00:00Z")).today?.subtitle)
    }
}
