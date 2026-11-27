import XCTest
@testable import BeyondRepWatchCore

final class SessionStateBuilderTests: XCTestCase {
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testGoldenCasesMatch() throws {
        let files = try FixtureLoader.files(in: "contracts/watch_link/v1/cases/session_state")
        XCTAssertGreaterThanOrEqual(files.count, 4)
        for file in files {
            let name = file.lastPathComponent
            let root = try object(Data(contentsOf: file))
            let events = try (try XCTUnwrap(root["events"] as? [Any])).map {
                try WorkoutEventV2(json: JSONSerialization.data(withJSONObject: $0))
            }
            let context = try XCTUnwrap(root["context"] as? [String: Any])
            let template = try JSONDecoder().decode(
                WorkoutTemplate.self,
                from: JSONSerialization.data(withJSONObject: try XCTUnwrap(context["template"])))
            let rejected = (context["rejected_commands"] as? [[String: Any]] ?? []).map {
                SessionStateBuilder.Rejection(
                    commandId: $0["command_id"] as? String ?? "", reason: $0["reason"] as? String ?? "")
            }
            let message = try SessionStateBuilder.message(
                events: events, template: template, unit: try XCTUnwrap(context["unit"] as? String),
                accountKey: try XCTUnwrap(context["account_key"] as? String),
                messageId: try XCTUnwrap(context["message_id"] as? String),
                sentAtUtc: try XCTUnwrap(context["sent_at_utc"] as? String),
                appliedCommandIds: context["applied_command_ids"] as? [String] ?? [], rejectedCommands: rejected)
            let actual = try object(message.jsonData())
            let expected = try XCTUnwrap(root["expected"] as? [String: Any])
            XCTAssertEqual(actual as NSDictionary, expected as NSDictionary, name)
        }
    }

    func testOnlyTheNewestTwentyCommandIdsAreKept() throws {
        let template = try TemplateFixtures.template()
        var m = SessionMachine(
            sessionId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", owner: "watch", accountKey: String(repeating: "0123456789abcdef", count: 4),
            deviceId: "watch-installation-a", clock: { Date(timeIntervalSince1970: 1_792_000_000) }, timeZone: "Asia/Kolkata",
            makeId: TemplateFixtures.counterIds(from: 900))
        let events = try m.start(name: template.name, exercises: template.exerciseAddedPayloads)
        let ids = (1...25).map { String(format: "88888888-4444-4444-8444-%012d", $0) }
        let message = try SessionStateBuilder.message(
            events: events, template: template, unit: "kg", accountKey: String(repeating: "0123456789abcdef", count: 4),
            messageId: "77777777-3333-4333-8333-0000000000f1", sentAtUtc: "2026-10-23T11:00:00Z", appliedCommandIds: ids)
        guard case .sessionState(_, let raw) = message.body else { return XCTFail("not a session state") }
        XCTAssertEqual(raw["applied_command_ids"] as? [String], Array(ids.suffix(20)))
    }
}
