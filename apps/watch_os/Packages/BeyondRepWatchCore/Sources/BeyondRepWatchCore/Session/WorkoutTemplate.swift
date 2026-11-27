import Foundation

public struct TemplateSet: Codable, Equatable {
    public var setId: String
    public var position: Int
    public var kind: String
    public var targetReps: Int?
    public var targetSeconds: Int?
    public var targetLoadGrams: Int?
    public var restSeconds: Int?

    public init(
        setId: String, position: Int, kind: String = "working", targetReps: Int? = nil,
        targetSeconds: Int? = nil, targetLoadGrams: Int? = nil, restSeconds: Int? = nil
    ) {
        self.setId = setId
        self.position = position
        self.kind = kind
        self.targetReps = targetReps
        self.targetSeconds = targetSeconds
        self.targetLoadGrams = targetLoadGrams
        self.restSeconds = restSeconds
    }
}

public struct TemplateExercise: Codable, Equatable {
    public var exerciseId: String
    public var name: String
    /// `reps` or `duration`.
    public var kind: String
    public var muscle: String?
    public var position: Int
    public var sets: [TemplateSet]

    public init(exerciseId: String, name: String, kind: String, muscle: String?, position: Int, sets: [TemplateSet]) {
        self.exerciseId = exerciseId
        self.name = name
        self.kind = kind
        self.muscle = muscle
        self.position = position
        self.sets = sets
    }
}

public struct ProgramDay: Codable, Equatable {
    public var planId: String
    public var programId: String
    public var localDate: String

    public init(planId: String, programId: String, localDate: String) {
        self.planId = planId
        self.programId = programId
        self.localDate = localDate
    }
}

/// The exercises and planned sets of one watch session. Every exercise and set
/// id is made fresh when the workout starts (never copied from a plan or the
/// catalogue), so two workouts from one plan never share an id on the phone.
public struct WorkoutTemplate: Codable, Equatable {
    public var name: String
    public var planId: String?
    public var programDay: ProgramDay?
    public var exercises: [TemplateExercise]

    public init(name: String, planId: String? = nil, programDay: ProgramDay? = nil, exercises: [TemplateExercise] = []) {
        self.name = name
        self.planId = planId
        self.programDay = programDay
        self.exercises = exercises
    }

    public static func quick(name: String = "Quick workout") -> WorkoutTemplate {
        WorkoutTemplate(name: name)
    }

    /// Builds the template of `planId` from a `plans_snapshot` body, or nil
    /// when the plan is not in it. Source exercise ids are not kept.
    public static func fromPlan(
        plansSnapshot raw: [String: Any], planId: String, makeId: () -> String
    ) -> WorkoutTemplate? {
        guard let plans = raw["plans"] as? [[String: Any]],
            let plan = plans.first(where: { $0["plan_id"] as? String == planId }),
            let name = plan["name"] as? String
        else { return nil }
        var exercises: [TemplateExercise] = []
        for (index, item) in ((plan["exercises"] as? [[String: Any]]) ?? []).enumerated() {
            guard let exerciseName = item["name"] as? String, let kind = item["kind"] as? String else { continue }
            let exerciseId = makeId()
            var sets: [TemplateSet] = []
            for entry in (item["sets"] as? [[String: Any]]) ?? [] {
                sets.append(
                    TemplateSet(
                        setId: makeId(), position: (entry["position"] as? Int) ?? sets.count,
                        kind: (entry["kind"] as? String) ?? "working",
                        targetReps: entry["target_reps"] as? Int, targetSeconds: entry["target_seconds"] as? Int,
                        targetLoadGrams: entry["target_load_grams"] as? Int, restSeconds: entry["rest_seconds"] as? Int))
            }
            sets.sort { $0.position < $1.position }
            exercises.append(
                TemplateExercise(
                    exerciseId: exerciseId, name: exerciseName, kind: kind, muscle: item["muscle"] as? String,
                    position: index, sets: sets))
        }
        return WorkoutTemplate(name: name, planId: planId, programDay: nil, exercises: exercises)
    }

    /// Today's program workout (`plans_snapshot.today`), carrying its program day.
    public static func today(plansSnapshot raw: [String: Any], makeId: () -> String) -> WorkoutTemplate? {
        guard let today = raw["today"] as? [String: Any], let planId = today["plan_id"] as? String,
            let programId = today["program_id"] as? String, let localDate = today["local_date"] as? String,
            var template = fromPlan(plansSnapshot: raw, planId: planId, makeId: makeId)
        else { return nil }
        template.programDay = ProgramDay(planId: planId, programId: programId, localDate: localDate)
        return template
    }

    /// Adds an exercise with one empty working set; returns the new exercise id.
    public mutating func addExercise(name: String, kind: String, muscle: String?, makeId: () -> String) -> String {
        let exerciseId = makeId()
        exercises.append(
            TemplateExercise(
                exerciseId: exerciseId, name: name, kind: kind, muscle: muscle, position: exercises.count,
                sets: [TemplateSet(setId: makeId(), position: 0, kind: "working")]))
        return exerciseId
    }

    /// Adds a working set that copies the last set's targets; returns its id.
    public mutating func addSet(exerciseId: String, makeId: () -> String) -> String {
        let setId = makeId()
        guard let index = exercises.firstIndex(where: { $0.exerciseId == exerciseId }) else { return setId }
        let last = exercises[index].sets.last
        exercises[index].sets.append(
            TemplateSet(
                setId: setId, position: (last?.position ?? -1) + 1, kind: "working",
                targetReps: last?.targetReps, targetSeconds: last?.targetSeconds,
                targetLoadGrams: last?.targetLoadGrams, restSeconds: last?.restSeconds))
        return setId
    }

    /// One `exercise_added` payload per exercise, in position order.
    public var exerciseAddedPayloads: [ExerciseAddedPayload] {
        exercises.sorted { $0.position < $1.position }.map {
            ExerciseAddedPayload(exerciseId: $0.exerciseId, name: $0.name, kind: $0.kind, position: $0.position)
        }
    }
}
