import Foundation

public struct SetPosition: Equatable {
    public let exercise: TemplateExercise
    public let set: TemplateSet
    public let indexInExercise: Int
    public let countInExercise: Int
}

/// Where the person is in the template, given what the session has logged.
public struct WorkoutCursor {
    public let template: WorkoutTemplate
    public let state: ReplayedWorkout
    private let ordered: [SetPosition]

    public init(template: WorkoutTemplate, state: ReplayedWorkout, focusExerciseId: String? = nil) {
        self.template = template
        self.state = state
        var exercises = template.exercises.sorted { $0.position < $1.position }
        if let focusExerciseId, let index = exercises.firstIndex(where: { $0.exerciseId == focusExerciseId }) {
            exercises.insert(exercises.remove(at: index), at: 0)
        }
        ordered = exercises.flatMap { exercise -> [SetPosition] in
            let sets = exercise.sets.sorted { $0.position < $1.position }
            return sets.enumerated().map {
                SetPosition(exercise: exercise, set: $0.element, indexInExercise: $0.offset, countInExercise: sets.count)
            }
        }
    }

    private func isDone(_ position: SetPosition) -> Bool {
        state.sets.contains { $0.setId == position.set.setId }
    }

    /// The first set, focused exercise first, that is not completed or skipped.
    public var current: SetPosition? { ordered.first { !isDone($0) } }

    /// The first undone set after `position` in the same order.
    public func next(after position: SetPosition) -> SetPosition? {
        guard let index = ordered.firstIndex(where: { $0.set.setId == position.set.setId }) else { return nil }
        return ordered[(index + 1)...].first { !isDone($0) }
    }

    /// Starting values for the set screen: the last completed set of the same
    /// exercise and kind in this session (a warm-up never fills a working set), else the set's targets, else a plain default
    /// (10 reps or 30 s, no weight) the crown then adjusts.
    public func prefill(for position: SetPosition, unit: String) -> SetValues {
        let ids = Set(position.exercise.sets.map(\.setId))
        let last = state.sets.last {
            $0.status == "completed" && $0.kind == position.set.kind && ids.contains($0.setId)
        }
        let timed = position.exercise.kind == "duration"
        var values = SetValues(
            setId: position.set.setId, exerciseId: position.exercise.exerciseId,
            position: position.set.position, kind: position.set.kind, inputUnit: unit)
        if timed {
            values.durationSeconds = last?.durationSeconds ?? position.set.targetSeconds ?? 30
        } else {
            values.reps = last?.reps ?? position.set.targetReps ?? 10
            let load = last?.loadGrams ?? position.set.targetLoadGrams
            if let load, load > 0 { values.loadGrams = load }
        }
        return values
    }

    /// Working sets in the template (warm-ups are not counted).
    public var plannedCount: Int {
        template.exercises.reduce(0) { $0 + $1.sets.filter { $0.kind == "working" }.count }
    }

    /// Completed working sets, the same rule as `ReplayedWorkout.completedSets`.
    public var completedCount: Int { state.completedSets }
}
