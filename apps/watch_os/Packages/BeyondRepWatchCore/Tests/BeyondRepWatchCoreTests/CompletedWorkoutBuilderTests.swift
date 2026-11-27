import XCTest
@testable import BeyondRepWatchCore

final class CompletedWorkoutBuilderTests: XCTestCase {
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testGoldenCasesMatch() throws {
        let files = try FixtureLoader.files(in: "contracts/watch_link/v1/cases/completed")
        XCTAssertGreaterThanOrEqual(files.count, 2)
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
            let message = try CompletedWorkoutBuilder.message(
                events: events, template: template, unit: try XCTUnwrap(context["unit"] as? String),
                accountKey: try XCTUnwrap(context["account_key"] as? String),
                healthkitWorkoutUuid: context["healthkit_workout_uuid"] as? String,
                messageId: try XCTUnwrap(context["message_id"] as? String),
                sentAtUtc: try XCTUnwrap(context["sent_at_utc"] as? String))
            let actual = try object(message.jsonData())
            let expected = try XCTUnwrap(root["expected"] as? [String: Any])
            XCTAssertEqual(actual as NSDictionary, expected as NSDictionary, name)
        }
    }

    // MARK: Built with the session machine

    private let key = String(repeating: "0123456789abcdef", count: 4)
    private var now = Date(timeIntervalSince1970: 1_792_000_000)

    private func machine() -> SessionMachine {
        SessionMachine(
            sessionId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", workoutId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            owner: "watch", accountKey: key, deviceId: "watch-installation-a",
            clock: { self.now }, timeZone: "Asia/Kolkata", makeId: TemplateFixtures.counterIds(from: 700))
    }

    private func build(_ events: [WorkoutEventV2], template: WorkoutTemplate) throws -> WatchMessage {
        try CompletedWorkoutBuilder.message(
            events: events, template: template, unit: "kg", accountKey: key, healthkitWorkoutUuid: nil,
            messageId: "77777777-3333-4333-8333-0000000000b1", sentAtUtc: "2026-10-23T11:40:05Z")
    }

    private func values(_ template: WorkoutTemplate) -> SetValues {
        SetValues(
            setId: template.exercises[0].sets[0].setId, exerciseId: template.exercises[0].exerciseId,
            position: 0, reps: 8, loadGrams: 60000)
    }

    func testThrowsWhenNotCompleted() throws {
        let template = try TemplateFixtures.template()
        var m = machine()
        var events = try m.start(name: template.name, exercises: template.exerciseAddedPayloads)
        events.append(try m.log(set: values(template)))
        XCTAssertThrowsError(try build(events, template: template)) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
    }

    func testThrowsWhenNoCompletedSet() throws {
        let template = try TemplateFixtures.template()
        var m = machine()
        var events = try m.start(name: template.name, exercises: template.exerciseAddedPayloads)
        events.append(try m.complete())
        XCTAssertThrowsError(try build(events, template: template)) {
            XCTAssertEqual($0 as? SessionError, .invalidTransition)
        }
    }

    func testOutputDecodesWithStrictCodec() throws {
        let template = try TemplateFixtures.template()
        var m = machine()
        var events = try m.start(name: template.name, exercises: template.exerciseAddedPayloads)
        events.append(try m.log(set: values(template)))
        events.append(try m.complete())
        let message = try build(events, template: template)
        let decoded = try WatchMessage(json: message.jsonData())
        guard case .completedWorkout(let id, let last, let uuid, _) = decoded.body else {
            return XCTFail("not a completed workout")
        }
        XCTAssertEqual(id, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(last, 4)
        XCTAssertNil(uuid)
    }

    func testUnknownMuscleKeepsMuscleButOmitsPrimaryMuscles() throws {
        var template = try TemplateFixtures.template()
        template.exercises[0].muscle = "Synthetic muscle"
        var m = machine()
        var events = try m.start(name: template.name, exercises: template.exerciseAddedPayloads)
        events.append(try m.log(set: values(template)))
        events.append(try m.complete())
        let body = try object(build(events, template: template).jsonData())["body"] as? [String: Any]
        let workout = try XCTUnwrap(body?["workout"] as? [String: Any])
        let exercise = try XCTUnwrap((workout["exercises"] as? [[String: Any]])?.first)
        XCTAssertEqual(exercise["muscle"] as? String, "Synthetic muscle")
        XCTAssertNil(exercise["primary_muscles"])
    }
}
