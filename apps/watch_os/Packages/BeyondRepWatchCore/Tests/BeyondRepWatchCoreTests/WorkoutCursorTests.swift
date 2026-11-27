import XCTest
@testable import BeyondRepWatchCore

final class WorkoutCursorTests: XCTestCase {
    private func template() throws -> WorkoutTemplate { try TemplateFixtures.template() }

    private func state(_ sets: [ReplayedSet]) -> ReplayedWorkout {
        let done = sets.filter { $0.status == "completed" && $0.kind == "working" }.count
        return ReplayedWorkout(status: "active", sets: sets, volumeGrams: 0, completedSets: done, gaps: [])
    }

    private func completed(_ set: TemplateSet, reps: Int? = 8, seconds: Int? = nil, load: Int? = 60000) -> ReplayedSet {
        ReplayedSet(
            setId: set.setId, status: "completed", kind: set.kind, reps: reps, durationSeconds: seconds,
            loadGrams: load, rpe: nil, history: ["e"])
    }

    private func skipped(_ set: TemplateSet) -> ReplayedSet {
        ReplayedSet(setId: set.setId, status: "skipped", kind: set.kind, reps: nil, durationSeconds: nil, loadGrams: nil, rpe: nil, history: ["e"])
    }

    func testCurrentIsTheFirstSetWhenNothingIsDone() throws {
        let t = try template()
        let cursor = WorkoutCursor(template: t, state: state([]))
        XCTAssertEqual(cursor.current?.set.setId, t.exercises[0].sets[0].setId)
        XCTAssertEqual(cursor.current?.indexInExercise, 0)
        XCTAssertEqual(cursor.current?.countInExercise, 2)
    }

    func testCurrentSkipsCompletedAndSkippedSets() throws {
        let t = try template()
        let press = t.exercises[0]
        let cursor = WorkoutCursor(template: t, state: state([completed(press.sets[0]), skipped(press.sets[1])]))
        XCTAssertEqual(cursor.current?.set.setId, t.exercises[1].sets[0].setId)
        XCTAssertEqual(cursor.current?.exercise.name, "Synthetic plank")
    }

    func testCurrentIsNilWhenAllDone() throws {
        let t = try template()
        let all = t.exercises.flatMap { $0.sets }.map { completed($0) }
        XCTAssertNil(WorkoutCursor(template: t, state: state(all)).current)
    }

    func testPrefillUsesLastCompletedSetOfSameExercise() throws {
        var t = try template()
        // The next set targets 62.5 kg x 6, the logged one was 60 kg x 8.
        t.exercises[0].sets[1].targetLoadGrams = 62500
        t.exercises[0].sets[1].targetReps = 6
        let first = t.exercises[0].sets[0]
        let cursor = WorkoutCursor(template: t, state: state([completed(first, reps: 8, load: 60000)]))
        let current = try XCTUnwrap(cursor.current)
        XCTAssertEqual(current.set.setId, t.exercises[0].sets[1].setId)
        let values = cursor.prefill(for: current, unit: "kg")
        XCTAssertEqual(values.reps, 8)
        XCTAssertEqual(values.loadGrams, 60000)
        XCTAssertEqual(values.setId, current.set.setId)
        XCTAssertEqual(values.exerciseId, current.exercise.exerciseId)
        XCTAssertEqual(values.position, current.set.position)
        XCTAssertEqual(values.kind, "working")
    }

    func testPrefillFallsBackToTargets() throws {
        let t = try template()
        let cursor = WorkoutCursor(template: t, state: state([]))
        let first = try XCTUnwrap(cursor.current)
        let values = cursor.prefill(for: first, unit: "kg")
        XCTAssertEqual(values.reps, 10)
        XCTAssertEqual(values.loadGrams, 20000)
        XCTAssertEqual(values.kind, "warmup")
    }

    func testPrefillDurationExerciseHasSecondsNotReps() throws {
        let t = try template()
        let all = t.exercises[0].sets.map { completed($0) }
        let cursor = WorkoutCursor(template: t, state: state(all))
        let plank = try XCTUnwrap(cursor.current)
        let values = cursor.prefill(for: plank, unit: "kg")
        XCTAssertNil(values.reps)
        XCTAssertEqual(values.durationSeconds, 45)
        XCTAssertNil(values.loadGrams)
    }

    func testPrefillUsesBindingUnit() throws {
        let t = try template()
        let cursor = WorkoutCursor(template: t, state: state([]))
        XCTAssertEqual(cursor.prefill(for: try XCTUnwrap(cursor.current), unit: "lb").inputUnit, "lb")
    }

    func testNextMovesToNextExerciseAfterLastSet() throws {
        let t = try template()
        let cursor = WorkoutCursor(template: t, state: state([]))
        let last = SetPosition(exercise: t.exercises[0], set: t.exercises[0].sets[1], indexInExercise: 1, countInExercise: 2)
        XCTAssertEqual(cursor.next(after: last)?.exercise.name, "Synthetic plank")
        let plank = SetPosition(exercise: t.exercises[1], set: t.exercises[1].sets[0], indexInExercise: 0, countInExercise: 1)
        XCTAssertNil(cursor.next(after: plank))
    }

    func testFocusExerciseComesFirst() throws {
        let t = try template()
        let cursor = WorkoutCursor(template: t, state: state([]), focusExerciseId: t.exercises[1].exerciseId)
        XCTAssertEqual(cursor.current?.exercise.name, "Synthetic plank")
        XCTAssertEqual(cursor.next(after: try XCTUnwrap(cursor.current))?.exercise.name, "Synthetic press")
    }

    func testCountsExcludeWarmups() throws {
        let t = try template()
        let press = t.exercises[0]
        let cursor = WorkoutCursor(template: t, state: state([completed(press.sets[0]), completed(press.sets[1])]))
        XCTAssertEqual(cursor.plannedCount, 2)  // press working set and plank
        XCTAssertEqual(cursor.completedCount, 1)
    }
}
