import XCTest
@testable import BeyondRepWatchCore

final class DetailModelTests: XCTestCase {
    private var dir: URL!
    private var journal: WatchJournal!
    private typealias M = TestMessages
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    private let locale = Locale(identifier: "en_US")
    private let now = "2026-10-23T05:00:00Z"  // 10:30 on 2026-10-23 in Asia/Kolkata

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        journal = try WatchJournal(url: dir.appendingPathComponent("journal.sqlite"))
        try journal.saveBinding(M.binding())
    }

    override func tearDownWithError() throws {
        journal = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func detail(_ metric: Metric, at: String? = nil) throws -> DetailModel? {
        try DetailModel.make(
            metric: metric, journal: journal, now: M.date(at ?? now), timeZone: kolkata, locale: locale)
    }

    private func localDates(_ model: DetailModel) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kolkata
        return model.week.map { point in
            let c = calendar.dateComponents([.year, .month, .day], from: point.date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
    }

    func testDetailWeekHasSevenDaysEndingTodayWithGaps() throws {
        // Five days sent, one of them without HRV; the two oldest days were never sent.
        let week: [[String: Any]] = [
            ["local_date": "2026-10-19", "hrv_ms": 40],
            ["local_date": "2026-10-20", "hrv_ms": 44],
            ["local_date": "2026-10-21", "steps": 5000],
            ["local_date": "2026-10-22", "hrv_ms": 50],
            ["local_date": "2026-10-23", "hrv_ms": 62],
        ]
        try journal.saveHealth(M.health(extra: ["week": week, "hrv_usual_ms": 56]))
        let model = try XCTUnwrap(try detail(.hrv))
        XCTAssertEqual(model.week.count, 7)
        XCTAssertEqual(
            localDates(model),
            ["2026-10-17", "2026-10-18", "2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23"])
        XCTAssertEqual(model.week.map { $0.value }, [nil, nil, 40, 44, nil, 50, 62])
        XCTAssertEqual(model.week.map { $0.isToday }, [false, false, false, false, false, false, true])
        XCTAssertEqual(model.week.map { $0.label }, ["S", "S", "M", "T", "W", "T", "F"])
        XCTAssertEqual(model.title, "HRV")
        XCTAssertEqual(model.value, "62")
        XCTAssertEqual(model.unit, "ms")
        XCTAssertEqual(model.usual, 56)
        XCTAssertEqual(model.weekAverage, 49)  // (40 + 44 + 50 + 62) / 4: the gap is not a zero
        XCTAssertNil(model.stages)
    }

    func testTodayComesFromTheSnapshotWhenThePhoneSentNoWeek() throws {
        try journal.saveHealth(M.health())
        let model = try XCTUnwrap(try detail(.steps))
        XCTAssertEqual(model.week.count, 7)
        XCTAssertEqual(model.week.map { $0.value }, [nil, nil, nil, nil, nil, nil, 1200])
        XCTAssertEqual(model.value, "1,200")
        XCTAssertEqual(model.title, "Steps")
        XCTAssertEqual(model.weekAverage, 1200)
        XCTAssertNil(model.usual)
    }

    func testMissingValueIsDashNeverZero() throws {
        let raw: [String: Any] = ["local_date": "2026-10-23", "as_of_utc": "2026-10-23T01:40:00Z"]
        try journal.saveHealth(
            WatchMessage(
                messageId: M.id(), sentAtUtc: "2026-10-23T01:45:00Z", accountKey: M.keyA,
                body: .healthSnapshot(localDate: "2026-10-23", raw: raw)))
        for metric in [Metric.sleep, .restingHr, .hrv, .steps] {
            let model = try XCTUnwrap(try detail(metric))
            XCTAssertEqual(model.value, "—", "\(metric)")
            XCTAssertEqual(model.week.map { $0.value }, [nil, nil, nil, nil, nil, nil, nil], "\(metric)")
            XCTAssertNil(model.weekAverage, "\(metric)")
        }
    }

    func testStagesOnlyWhenAllFourPresent() throws {
        let full: [String: Any] = [
            "score": 81, "asleep_minutes": 432, "deep_minutes": 80, "core_minutes": 220, "rem_minutes": 95,
            "awake_minutes": 18,
        ]
        try journal.saveHealth(M.health(extra: ["sleep": full]))
        let withStages = try XCTUnwrap(try detail(.sleep))
        XCTAssertEqual(withStages.stages, SleepStages(deep: 80, core: 220, rem: 95, awake: 18))
        XCTAssertEqual(withStages.value, "7h 12m")
        XCTAssertEqual(withStages.caption, "Score 81")

        let partial: [String: Any] = ["asleep_minutes": 432, "deep_minutes": 80, "rem_minutes": 95]
        try journal.saveHealth(M.health(extra: ["sleep": partial]))
        let without = try XCTUnwrap(try detail(.sleep))
        XCTAssertNil(without.stages)
        XCTAssertNil(without.caption)
    }

    func testSleepWeekIsMinutesAndAverageIsInMinutes() throws {
        let week: [[String: Any]] = [
            ["local_date": "2026-10-22", "asleep_minutes": 400],
            ["local_date": "2026-10-23", "asleep_minutes": 432],
        ]
        try journal.saveHealth(M.health(extra: ["week": week]))
        let model = try XCTUnwrap(try detail(.sleep))
        XCTAssertEqual(model.week.suffix(2).map { $0.value }, [400, 432])
        XCTAssertEqual(model.weekAverage, 416)
    }

    func testYesterdaysSnapshotGivesNoDetail() throws {
        let week: [[String: Any]] = [["local_date": "2026-10-22", "hrv_ms": 50]]
        try journal.saveHealth(
            M.health(localDate: "2026-10-22", asOf: "2026-10-22T18:20:00Z", extra: ["week": week]))
        // 00:05 on 2026-10-23 local.
        XCTAssertNil(try detail(.hrv, at: "2026-10-22T18:35:00Z"))
        XCTAssertNil(try detail(.steps, at: "2026-10-22T18:35:00Z"))
    }

    func testNoDetailWithoutABindingOrHealth() throws {
        XCTAssertNil(try detail(.hrv))
        try journal.clearAccount(M.keyA, wipeUnsent: false)
        try journal.saveHealth(M.health())
        XCTAssertNil(try detail(.hrv))
    }
}
