import XCTest
@testable import BeyondRepWatchCore

/// Shared helpers for the template, cursor and controller tests.
enum TemplateFixtures {
    static func counterIds(from start: Int = 1) -> () -> String {
        var n = start - 1
        return {
            n += 1
            return String(format: "00000000-0000-4000-8000-%012d", n)
        }
    }

    static func planRaw() throws -> [String: Any] {
        let message = try WatchMessage(json: FixtureLoader.json("contracts/watch_link/v1/fixtures/valid/plans_snapshot.json"))
        guard case .plansSnapshot(let raw) = message.body else { throw ContractError("invalid_value") }
        return raw
    }

    static func template() throws -> WorkoutTemplate {
        try XCTUnwrap(WorkoutTemplate.fromPlan(plansSnapshot: planRaw(), planId: "plan-synthetic-1", makeId: counterIds()))
    }
}

final class WorkoutTemplateTests: XCTestCase {
    private let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

    private func ids(_ template: WorkoutTemplate) -> Set<String> {
        var out = Set<String>()
        for exercise in template.exercises {
            out.insert(exercise.exerciseId)
            for set in exercise.sets { out.insert(set.setId) }
        }
        return out
    }

    func testFromPlanMakesFreshUuidsForExercisesAndSets() throws {
        let template = try TemplateFixtures.template()
        XCTAssertEqual(template.name, "Synthetic push day")
        XCTAssertEqual(template.planId, "plan-synthetic-1")
        XCTAssertNil(template.programDay)
        XCTAssertEqual(template.exercises.count, 2)
        for id in ids(template) {
            XCTAssertNotNil(id.range(of: uuidPattern, options: .regularExpression), id)
        }
        let source: Set<String> = ["builtin.v1.synthetic-move-1", "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"]
        XCTAssertTrue(ids(template).isDisjoint(with: source))
        let press = template.exercises[0]
        XCTAssertEqual(press.name, "Synthetic press")
        XCTAssertEqual(press.kind, "reps")
        XCTAssertEqual(press.muscle, "chest")
        XCTAssertEqual(press.position, 0)
        XCTAssertEqual(press.sets.map(\.kind), ["warmup", "working"])
        XCTAssertEqual(press.sets.map(\.position), [0, 1])
        XCTAssertEqual(press.sets[1].targetReps, 8)
        XCTAssertEqual(press.sets[1].targetLoadGrams, 60000)
        XCTAssertEqual(press.sets[1].restSeconds, 90)
        let plank = template.exercises[1]
        XCTAssertEqual(plank.kind, "duration")
        XCTAssertNil(plank.muscle)
        XCTAssertEqual(plank.position, 1)
        XCTAssertEqual(plank.sets[0].targetSeconds, 45)
        XCTAssertNil(plank.sets[0].targetReps)
    }

    func testTwoSessionsFromOnePlanShareNoIds() throws {
        let raw = try TemplateFixtures.planRaw()
        let a = try XCTUnwrap(WorkoutTemplate.fromPlan(plansSnapshot: raw, planId: "plan-synthetic-1", makeId: { UUID().uuidString.lowercased() }))
        let b = try XCTUnwrap(WorkoutTemplate.fromPlan(plansSnapshot: raw, planId: "plan-synthetic-1", makeId: { UUID().uuidString.lowercased() }))
        XCTAssertTrue(ids(a).isDisjoint(with: ids(b)))
    }

    func testTodayCarriesProgramDay() throws {
        let template = try XCTUnwrap(WorkoutTemplate.today(plansSnapshot: TemplateFixtures.planRaw(), makeId: TemplateFixtures.counterIds()))
        XCTAssertEqual(
            template.programDay,
            ProgramDay(planId: "plan-synthetic-1", programId: "program-synthetic-1", localDate: "2026-10-23"))
        XCTAssertEqual(template.planId, "plan-synthetic-1")
        XCTAssertEqual(template.exercises.count, 2)
    }

    func testTodayIsNilWithoutTodayOrPlan() throws {
        var raw = try TemplateFixtures.planRaw()
        raw["today"] = ["plan_id": "missing", "program_id": "p", "local_date": "2026-10-23", "label": "x"]
        XCTAssertNil(WorkoutTemplate.today(plansSnapshot: raw, makeId: TemplateFixtures.counterIds()))
        raw.removeValue(forKey: "today")
        XCTAssertNil(WorkoutTemplate.today(plansSnapshot: raw, makeId: TemplateFixtures.counterIds()))
    }

    func testUnknownPlanIsNil() throws {
        XCTAssertNil(WorkoutTemplate.fromPlan(plansSnapshot: try TemplateFixtures.planRaw(), planId: "nope", makeId: TemplateFixtures.counterIds()))
    }

    func testQuickHasNoExercises() {
        let quick = WorkoutTemplate.quick()
        XCTAssertEqual(quick.name, "Quick workout")
        XCTAssertTrue(quick.exercises.isEmpty)
        XCTAssertNil(quick.planId)
        XCTAssertNil(quick.programDay)
    }

    func testAddSetCopiesLastTargets() throws {
        var template = try TemplateFixtures.template()
        let exerciseId = template.exercises[0].exerciseId
        let setId = template.addSet(exerciseId: exerciseId, makeId: TemplateFixtures.counterIds(from: 500))
        let added = try XCTUnwrap(template.exercises[0].sets.last)
        XCTAssertEqual(added.setId, setId)
        XCTAssertEqual(added.position, 2)
        XCTAssertEqual(added.kind, "working")
        XCTAssertEqual(added.targetReps, 8)
        XCTAssertEqual(added.targetLoadGrams, 60000)
        XCTAssertEqual(added.restSeconds, 90)
    }

    func testAddExerciseHasOneSet() {
        var template = WorkoutTemplate.quick()
        let id = template.addExercise(name: "Synthetic curl", kind: "reps", muscle: "biceps", makeId: TemplateFixtures.counterIds())
        XCTAssertEqual(template.exercises.count, 1)
        let exercise = template.exercises[0]
        XCTAssertEqual(exercise.exerciseId, id)
        XCTAssertEqual(exercise.position, 0)
        XCTAssertEqual(exercise.sets.count, 1)
        XCTAssertEqual(exercise.sets[0].kind, "working")
        XCTAssertEqual(template.exerciseAddedPayloads, [
            ExerciseAddedPayload(exerciseId: id, name: "Synthetic curl", kind: "reps", position: 0)
        ])
    }

    func testTemplateRoundTripsThroughJson() throws {
        let template = try TemplateFixtures.template()
        let data = try JSONEncoder().encode(template)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutTemplate.self, from: data), template)
    }
}
