import XCTest
@testable import BeyondRepWatchCore

final class AckBuilderTests: XCTestCase {
    private typealias M = TestMessages

    func testAckJsonDecodesAsContractAck() throws {
        let acked = "77777777-3333-4333-8333-0000000000aa"
        let own = UUID()
        let json = AckBuilder.json(
            for: AckOutcome(messageId: acked, accountKey: M.keyA, result: "stored", reason: nil),
            messageId: own, now: M.date("2026-10-23T05:00:00Z"))
        let message = try WatchMessage(json: Data(json.utf8))
        XCTAssertEqual(message.type, "ack")
        XCTAssertEqual(message.accountKey, M.keyA)
        XCTAssertEqual(message.messageId, own.uuidString.lowercased())
        XCTAssertEqual(message.sentAtUtc, "2026-10-23T05:00:00Z")
        guard case .ack(let id, let result, let reason) = message.body else { return XCTFail("not an ack") }
        XCTAssertEqual(id, acked)
        XCTAssertEqual(result, "stored")
        XCTAssertNil(reason)
    }

    func testRejectedAckKeepsItsReason() throws {
        let json = AckBuilder.json(
            for: AckOutcome(
                messageId: "77777777-3333-4333-8333-0000000000bb", accountKey: M.keyB, result: "rejected",
                reason: "wrong_account"),
            messageId: UUID(), now: M.date("2026-10-23T05:00:00Z"))
        guard case .ack(_, let result, let reason) = try WatchMessage(json: Data(json.utf8)).body else {
            return XCTFail("not an ack")
        }
        XCTAssertEqual(result, "rejected")
        XCTAssertEqual(reason, "wrong_account")
    }

    func testAckCarriesNoHealthValues() throws {
        let json = AckBuilder.json(
            for: AckOutcome(messageId: M.id(), accountKey: M.keyA, result: "duplicate", reason: nil),
            messageId: UUID(), now: Date())
        for word in ["sleep", "hrv", "steps", "resting"] {
            XCTAssertFalse(json.lowercased().contains(word), word)
        }
    }
}
