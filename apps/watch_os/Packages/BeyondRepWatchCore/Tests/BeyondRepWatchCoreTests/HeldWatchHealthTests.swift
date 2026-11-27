import XCTest
@testable import BeyondRepWatchCore

final class HeldWatchHealthTests: XCTestCase {
    private let held = HeldWatchHealth(
        accountKey: TestMessages.keyA, health: WatchHealth(localDate: "2026-10-23", steps: 100))

    func testKeptForTheAccountItWasReadFor() {
        XCTAssertEqual(held.ifCurrent(boundKey: TestMessages.keyA), held.health)
    }

    func testDroppedAfterSignOutOrRebind() {
        XCTAssertNil(held.ifCurrent(boundKey: nil), "account_cleared or sign out removes the binding")
        XCTAssertNil(held.ifCurrent(boundKey: TestMessages.keyB), "another account never sees these values")
    }

    private let full = WatchHealth(localDate: "2026-10-23", asleepMinutes: 400, restingHrBpm: 55, hrvMs: 48, steps: 100)

    func testFailedFieldKeepsTheHeldValueForTheSameAccountAndDate() {
        let before = HeldWatchHealth(accountKey: TestMessages.keyA, health: full)
        let read = WatchHealth(localDate: "2026-10-23", asleepMinutes: nil, restingHrBpm: nil, hrvMs: 50, steps: 300)
        let after = before.updated(accountKey: TestMessages.keyA, read: read, failed: [.asleep, .hrv])
        XCTAssertEqual(after.health.asleepMinutes, 400, "failed query keeps the held value")
        XCTAssertNil(after.health.restingHrBpm, "no data (not an error) clears it")
        XCTAssertEqual(after.health.hrvMs, 50, "a failed field still takes the new value if one was derived")
        XCTAssertEqual(after.health.steps, 300)
    }

    func testFailedFieldIsNotKeptAcrossAccountOrDate() {
        let before = HeldWatchHealth(accountKey: TestMessages.keyA, health: full)
        let read = WatchHealth(localDate: "2026-10-24")
        XCTAssertEqual(before.updated(accountKey: TestMessages.keyA, read: read, failed: [.steps]).health, read)
        let sameDay = WatchHealth(localDate: "2026-10-23")
        XCTAssertEqual(before.updated(accountKey: TestMessages.keyB, read: sameDay, failed: [.steps]).health, sameDay)
    }
}
