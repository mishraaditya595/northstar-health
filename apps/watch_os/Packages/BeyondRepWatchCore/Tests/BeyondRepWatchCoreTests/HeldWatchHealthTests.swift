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
}
