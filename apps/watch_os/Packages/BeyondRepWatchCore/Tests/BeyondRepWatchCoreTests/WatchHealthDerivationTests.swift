import XCTest
@testable import BeyondRepWatchCore

final class WatchHealthDerivationTests: XCTestCase {
    private func sleep(_ items: [[String: Any]]) -> [SleepSample] {
        items.compactMap { item in
            guard let from = (item["from"] as? String).flatMap(WatchTimestamp.date),
                let to = (item["to"] as? String).flatMap(WatchTimestamp.date),
                let stage = (item["stage"] as? String).flatMap(SleepStage.init(rawValue:)),
                let source = item["source_key"] as? String
            else { return nil }
            return SleepSample(from: from, to: to, stage: stage, sourceKey: source)
        }
    }

    private func values(_ items: [[String: Any]]) -> [ValueSample] {
        items.compactMap { item in
            guard let from = (item["from"] as? String).flatMap(WatchTimestamp.date),
                let to = (item["to"] as? String).flatMap(WatchTimestamp.date),
                let value = (item["value"] as? NSNumber)?.doubleValue
            else { return nil }
            return ValueSample(from: from, to: to, value: value)
        }
    }

    /// Every golden case the Dart test runs against the phone's code gives
    /// the same numbers here.
    func testEveryGoldenCaseGivesTheExpectedValues() throws {
        let files = try FixtureLoader.files(in: "contracts/watch_link/v1/cases/health")
        XCTAssertGreaterThanOrEqual(files.count, 8)
        for file in files {
            let name = file.lastPathComponent
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            let c = try XCTUnwrap(object, name)
            let offset = try XCTUnwrap((c["utc_offset_minutes"] as? NSNumber)?.intValue, name)
            let zone = try XCTUnwrap(TimeZone(secondsFromGMT: offset * 60), name)
            let now = try XCTUnwrap((c["now"] as? String).flatMap(WatchTimestamp.date), name)
            let result = WatchHealthDerivation.today(
                sleep: sleep(c["sleep"] as? [[String: Any]] ?? []),
                hrv: values(c["hrv"] as? [[String: Any]] ?? []),
                restingHr: values(c["resting_hr"] as? [[String: Any]] ?? []),
                steps: nil, now: now, timeZone: zone)
            var got: [String: Any] = [:]
            if let v = result.asleepMinutes { got["asleep_minutes"] = v }
            if let v = result.hrvMs { got["hrv_ms"] = v }
            if let v = result.restingHrBpm { got["resting_hr_bpm"] = v }
            XCTAssertEqual(NSDictionary(dictionary: got), c["expected"] as? NSDictionary, name)
            XCTAssertNil(result.steps, name)
        }
    }

    func testLocalDateIsTheDateOfNowInTheGivenZone() {
        // 20:00 UTC on 2026-11-20 is 01:30 on 2026-11-21 in Asia/Kolkata.
        let now = TestMessages.date("2026-11-20T20:00:00Z")
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        XCTAssertEqual(
            WatchHealthDerivation.today(sleep: [], hrv: [], restingHr: [], steps: nil, now: now, timeZone: kolkata)
                .localDate, "2026-11-21")
        XCTAssertEqual(
            WatchHealthDerivation.today(
                sleep: [], hrv: [], restingHr: [], steps: nil, now: now, timeZone: TimeZone(secondsFromGMT: 0)!
            ).localDate, "2026-11-20")
    }

    func testNightIsDatedByItsLocalEndDate() {
        // 23:00 to 06:30 UTC. At UTC-8 it ends at 22:30 on 2026-11-19, so it is
        // not the night of 2026-11-20 there.
        let night = [
            SleepSample(
                from: TestMessages.date("2026-11-19T23:00:00Z"), to: TestMessages.date("2026-11-20T06:30:00Z"),
                stage: .asleepUnspecified, sourceKey: "com.example.watch")
        ]
        let west = TimeZone(secondsFromGMT: -8 * 3600)!
        let now = TestMessages.date("2026-11-20T18:00:00Z")  // 10:00 on 2026-11-20 at UTC-8
        let result = WatchHealthDerivation.today(sleep: night, hrv: [], restingHr: [], steps: nil, now: now, timeZone: west)
        XCTAssertNil(result.asleepMinutes)
    }

    func testStepsZeroIsMissingAndOthersAreRounded() {
        let now = TestMessages.date("2026-11-20T09:30:00Z")
        let utc = TimeZone(secondsFromGMT: 0)!
        func steps(_ value: Double?) -> Int? {
            WatchHealthDerivation.today(sleep: [], hrv: [], restingHr: [], steps: value, now: now, timeZone: utc).steps
        }
        XCTAssertNil(steps(nil))
        XCTAssertNil(steps(0))
        XCTAssertNil(steps(0.4), "rounds to 0, which is missing")
        XCTAssertEqual(steps(9450.4), 9450)
        XCTAssertEqual(steps(9450.5), 9451)
    }

    func testZeroMinuteNightIsMissingOnTheWatch() {
        // 30 s asleep ending after 03:00: the phone shows 0 min, the watch has no night value.
        let night = [
            SleepSample(
                from: TestMessages.date("2026-11-20T06:29:30Z"), to: TestMessages.date("2026-11-20T06:30:00Z"),
                stage: .asleepUnspecified, sourceKey: "com.example.watch")
        ]
        let now = TestMessages.date("2026-11-20T09:30:00Z")
        let result = WatchHealthDerivation.today(
            sleep: night, hrv: [], restingHr: [], steps: nil, now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertNil(result.asleepMinutes)
    }
}
