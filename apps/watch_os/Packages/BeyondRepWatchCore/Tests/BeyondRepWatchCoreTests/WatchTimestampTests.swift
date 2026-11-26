import XCTest
@testable import BeyondRepWatchCore

final class WatchTimestampTests: XCTestCase {
    func testWholeSecondsAndMillisecondsFromDart() {
        XCTAssertEqual(WatchTimestamp.milliseconds("2026-11-24T02:30:01Z"), 1_795_487_401_000)
        XCTAssertEqual(WatchTimestamp.milliseconds("2026-11-24T02:30:01.123Z"), 1_795_487_401_123)
        XCTAssertEqual(WatchTimestamp.milliseconds("2026-11-24T02:30:01.000Z"), 1_795_487_401_000)
    }

    func testMoreFractionalDigitsAreTruncatedNotRejected() {
        XCTAssertEqual(WatchTimestamp.milliseconds("2026-11-24T02:30:01.123456Z"), 1_795_487_401_123)
    }

    func testOffsetsAreHonoured() {
        XCTAssertEqual(
            WatchTimestamp.milliseconds("2026-11-24T08:00:01.500+05:30"), 1_795_487_401_500)
    }

    func testGarbageIsNil() {
        XCTAssertNil(WatchTimestamp.milliseconds("yesterday"))
        XCTAssertNil(WatchTimestamp.milliseconds("2026-11-24T02:30:01."))
    }

    func testAMessageWithMillisecondsDecodesAndRoundTrips() throws {
        let message = WatchMessage(
            messageId: TestMessages.id(), sentAtUtc: "2026-11-24T02:30:01.123Z",
            accountKey: TestMessages.keyA, body: .accountBinding(unit: "kg"))
        let again = try WatchMessage(json: message.jsonData())
        XCTAssertEqual(again.sentAtUtc, "2026-11-24T02:30:01.123Z")
    }
}
