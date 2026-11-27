import XCTest
@testable import BeyondRepWatchCore

final class OrphanSessionPolicyTests: XCTestCase {
    func testAnOrphanWithNothingToRestoreOrFinishIsDiscarded() {
        XCTAssertTrue(OrphanSessionPolicy.shouldDiscard(restoredSession: false, unresolvedPendingFinish: false))
    }

    func testARestoredSessionOwnsTheHealthKitSession() {
        XCTAssertFalse(OrphanSessionPolicy.shouldDiscard(restoredSession: true, unresolvedPendingFinish: false))
    }

    func testAnUnresolvedPendingFinishKeepsTheHealthKitSession() {
        XCTAssertFalse(OrphanSessionPolicy.shouldDiscard(restoredSession: false, unresolvedPendingFinish: true))
    }
}
