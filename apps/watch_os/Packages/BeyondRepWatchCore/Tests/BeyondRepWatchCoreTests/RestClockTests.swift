import XCTest
@testable import BeyondRepWatchCore

final class RestClockTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_792_000_000)
    private var now = Date(timeIntervalSince1970: 1_792_000_000)

    private func machine() -> SessionMachine {
        now = base
        return SessionMachine(
            sessionId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", owner: "watch", accountKey: String(repeating: "a", count: 64),
            deviceId: "watch-installation-a", clock: { self.now }, timeZone: "Asia/Kolkata",
            makeId: TemplateFixtures.counterIds(from: 900))
    }

    private func set(_ n: Int) -> SetValues {
        SetValues(setId: "dddddddd-dddd-4ddd-8ddd-00000000000\(n)", exerciseId: "x", position: n, reps: 8)
    }

    func testDeadlineFromLastRestStarted() throws {
        var m = machine()
        _ = try m.start(name: "x")
        _ = try m.startRest(seconds: 60)
        now = base.addingTimeInterval(10)
        _ = try m.startRest(seconds: 90)
        XCTAssertEqual(RestClock.deadline(events: m.events), base.addingTimeInterval(100))
    }

    func testDeadlineIsNilWithoutRest() throws {
        var m = machine()
        _ = try m.start(name: "x")
        XCTAssertNil(RestClock.deadline(events: m.events))
    }

    func testClearedRestHasNoDeadline() throws {
        var m = machine()
        _ = try m.start(name: "x")
        _ = try m.startRest(seconds: 60)
        _ = try m.clearRest()
        XCTAssertNil(RestClock.deadline(events: m.events))
    }

    func testLoggedSetEndsRest() throws {
        var m = machine()
        _ = try m.start(name: "x")
        _ = try m.startRest(seconds: 60)
        _ = try m.log(set: set(1))
        XCTAssertNil(RestClock.deadline(events: m.events))
    }

    func testPausedEndsRest() throws {
        var m = machine()
        _ = try m.start(name: "x")
        _ = try m.startRest(seconds: 60)
        _ = try m.pause()
        XCTAssertNil(RestClock.deadline(events: m.events))
    }

    func testCompletedAndAbandonedEndRest() throws {
        var a = machine()
        _ = try a.start(name: "x")
        _ = try a.startRest(seconds: 60)
        _ = try a.complete()
        XCTAssertNil(RestClock.deadline(events: a.events))
        var b = machine()
        _ = try b.start(name: "x")
        _ = try b.startRest(seconds: 60)
        _ = try b.abandon()
        XCTAssertNil(RestClock.deadline(events: b.events))
    }

    func testRestStartedAfterALoggedSetCounts() throws {
        var m = machine()
        _ = try m.start(name: "x")
        _ = try m.log(set: set(1))
        _ = try m.startRest(seconds: 45)
        XCTAssertEqual(RestClock.deadline(events: m.events), base.addingTimeInterval(45))
    }

    func testExtendAddsThirtyAndCaps() {
        XCTAssertEqual(RestClock.extendedSeconds(remaining: 41.2), 72)
        XCTAssertEqual(RestClock.extendedSeconds(remaining: 3590), 3600)
        XCTAssertEqual(RestClock.extendedSeconds(remaining: 0), 30)
    }
}
