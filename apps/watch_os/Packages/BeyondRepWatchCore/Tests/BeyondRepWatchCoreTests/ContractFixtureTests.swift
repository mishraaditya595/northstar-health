import XCTest
@testable import BeyondRepWatchCore

final class ContractFixtureTests: XCTestCase {
    private func roundTrips<T>(
        _ dir: String,
        minimum: Int,
        decode: (Data) throws -> T,
        encode: (T) throws -> Data
    ) throws {
        let files = try FixtureLoader.files(in: dir)
        XCTAssertGreaterThanOrEqual(files.count, minimum, dir)
        for file in files {
            let original = try Data(contentsOf: file)
            let value = try decode(original)
            let again = try encode(value)
            let a = try JSONSerialization.jsonObject(with: original) as? NSDictionary
            let b = try JSONSerialization.jsonObject(with: again) as? NSDictionary
            XCTAssertEqual(a, b, file.lastPathComponent)
        }
    }

    private func rejects(_ dir: String, minimum: Int, decode: (Data) throws -> Void) throws {
        let files = try FixtureLoader.files(in: dir)
        XCTAssertGreaterThanOrEqual(files.count, minimum, dir)
        for file in files {
            XCTAssertThrowsError(try decode(Data(contentsOf: file)), file.lastPathComponent) { error in
                XCTAssertTrue(error is ContractError, "\(file.lastPathComponent): \(error)")
            }
        }
    }

    func testWorkoutSyncV2ValidFixturesRoundTrip() throws {
        try roundTrips(
            "contracts/workout_sync/v2/fixtures/valid", minimum: 15,
            decode: { try WorkoutEventV2(json: $0) }, encode: { try $0.jsonData() })
    }

    func testWorkoutSyncV2InvalidFixturesAreRejected() throws {
        try rejects("contracts/workout_sync/v2/fixtures/invalid", minimum: 14) { _ = try WorkoutEventV2(json: $0) }
    }

    func testV1EnvelopeIsUnsupportedVersion() throws {
        let data = try FixtureLoader.json("contracts/workout_sync/v1/fixtures/valid/set_logged.json")
        XCTAssertThrowsError(try WorkoutEventV2(json: data)) { error in
            XCTAssertEqual((error as? ContractError)?.code, "unsupported_version")
        }
    }

    func testWatchLinkValidFixturesRoundTrip() throws {
        try roundTrips(
            "contracts/watch_link/v1/fixtures/valid", minimum: 20,
            decode: { try WatchMessage(json: $0) }, encode: { try $0.jsonData() })
    }

    func testWatchLinkInvalidFixturesAreRejected() throws {
        try rejects("contracts/watch_link/v1/fixtures/invalid", minimum: 25) { _ = try WatchMessage(json: $0) }
    }

    func testWorkoutLinkAndJoinDecodeIntoTypedBodies() throws {
        let link = try WatchMessage(
            json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/workout_link.json"))
        guard case .workoutLink(let workoutId, let hkUuid) = link.body else { return XCTFail("not a workout_link") }
        XCTAssertEqual(workoutId, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        XCTAssertEqual(hkUuid, "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
        XCTAssertEqual(link.type, "workout_link")
        let join = try WatchMessage(json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/join.json"))
        guard case .join(let sessionId) = join.body else { return XCTFail("not a join") }
        XCTAssertEqual(sessionId, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        let any = try WatchMessage(json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/join_any.json"))
        guard case .join(let anySession) = any.body else { return XCTFail("not a join") }
        XCTAssertNil(anySession)
        let phone = try WatchMessage(
            json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/session_state_phone.json"))
        guard case .sessionState = phone.body else { return XCTFail("not a session_state") }
    }

    func testCompletedWorkoutProgramDayIsChecked() throws {
        let valid = try FixtureLoader.json(
            "contracts/watch_link/v1/fixtures/valid/completed_workout_program_day.json")
        _ = try WatchMessage(json: valid)
        for name in ["completed_workout_program_day_bad_date", "completed_workout_program_day_extra_field"] {
            let data = try FixtureLoader.json("contracts/watch_link/v1/fixtures/invalid/\(name).json")
            XCTAssertThrowsError(try WatchMessage(json: data), name) { error in
                XCTAssertTrue(error is ContractError, "\(name): \(error)")
            }
        }
    }

    func testWorkoutHealthDecodesAndKeepsItsBody() throws {
        let data = try FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/workout_health.json")
        let message = try WatchMessage(json: data)
        XCTAssertEqual(message.type, "workout_health")
        guard case .workoutHealth(let workoutId, let raw) = message.body else { return XCTFail("wrong body") }
        XCTAssertEqual(workoutId, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual((raw["heart_rate"] as? [Any])?.count, 3)
        XCTAssertEqual((raw["total_kcal"] as? NSNumber)?.doubleValue, 312.5)
    }

    func testNotWrittenAckDecodesOnlyWithRejected() throws {
        let valid = try FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/ack_not_written.json")
        guard case .ack(_, let result, let reason) = try WatchMessage(json: valid).body else {
            return XCTFail("wrong body")
        }
        XCTAssertEqual(result, "rejected")
        XCTAssertEqual(reason, "not_written")
        let invalid = try FixtureLoader.json("contracts/watch_link/v1/fixtures/invalid/ack_not_written_stored.json")
        XCTAssertThrowsError(try WatchMessage(json: invalid))
    }

    func testHealthSnapshotStillRejectsUnknownKey() throws {
        let data = try FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/health_snapshot_full.json")
        var message = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var body = try XCTUnwrap(message["body"] as? [String: Any])
        body["bedtime"] = "23:40"
        message["body"] = body
        let changed = try JSONSerialization.data(withJSONObject: message)
        XCTAssertThrowsError(try WatchMessage(json: changed)) { error in
            XCTAssertEqual((error as? ContractError)?.code, "unknown_key")
        }
    }

    func testReplayCaseEventsDecode() throws {
        for file in try FixtureLoader.files(in: "contracts/watch_link/v1/cases/replay") {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
            for event in object?["events"] as? [[String: Any]] ?? [] {
                _ = try WorkoutEventV2(json: JSONSerialization.data(withJSONObject: event))
            }
        }
    }
}
