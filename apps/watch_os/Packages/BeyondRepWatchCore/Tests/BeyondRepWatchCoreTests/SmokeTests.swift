import XCTest
@testable import BeyondRepWatchCore

final class SmokeTests: XCTestCase {
    func testFindsContracts() throws {
        let files = try FixtureLoader.files(in: "contracts/watch_link/v1/fixtures/valid")
        XCTAssertFalse(files.isEmpty)
    }

    func testSchemaVersionsMatchContracts() {
        XCTAssertEqual(BeyondRepWatchCore.workoutSyncSchemaVersion, 2)
        XCTAssertEqual(BeyondRepWatchCore.watchLinkSchemaVersion, 1)
    }
}
