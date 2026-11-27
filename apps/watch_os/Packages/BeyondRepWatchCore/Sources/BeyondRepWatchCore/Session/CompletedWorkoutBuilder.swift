import Foundation

/// Builds the `completed_workout` message for a finished watch session from its
/// events and template. The message holds no health values: only the optional
/// HealthKit workout UUID travels with it.
public enum CompletedWorkoutBuilder {
    /// The muscle names the cloud workout payload accepts in `primary_muscles`.
    private static let knownMuscles: Set<String> = [
        "chest", "shoulders", "biceps", "forearms", "abs", "obliques", "quads", "calves", "traps",
        "lats", "lowerBack", "triceps", "glutes", "hamstrings",
    ]

    public static func message(
        events: [WorkoutEventV2], template: WorkoutTemplate, unit: String, accountKey: String,
        healthkitWorkoutUuid: String?, messageId: String, sentAtUtc: String
    ) throws -> WatchMessage {
        let state = replay(events)
        guard state.status == "completed", state.completedSets >= 1 else { throw SessionError.invalidTransition }

        var seen = Set<String>()
        let ordered = events.filter { seen.insert($0.header.eventId).inserted }
            .sorted { $0.header.sequence < $1.header.sequence }
        var startedName: String?
        var startedAt: String?
        var startedHeader: EventHeader?
        var completedAt: String?
        var lastOccurred: [String: String] = [:]
        var lastUnit: [String: String] = [:]
        for event in ordered {
            let header = event.header
            switch event {
            case .workoutStarted(_, let payload):
                if startedName == nil {
                    startedName = payload.name
                    startedAt = header.occurredAtUtc
                    startedHeader = header
                }
            case .workoutCompleted:
                completedAt = header.occurredAtUtc
            case .setLogged(_, let values), .setCorrected(_, let values, _):
                lastOccurred[values.setId] = header.occurredAtUtc
                lastUnit[values.setId] = values.inputUnit
            case .setSkipped(_, let setId):
                lastOccurred[setId] = header.occurredAtUtc
            default:
                break
            }
        }
        guard let name = startedName, let startedAt, let completedAt, let startedHeader else {
            throw SessionError.invalidTransition
        }

        let startInstant = WatchTimestamp.date(startedAt) ?? Date(timeIntervalSince1970: 0)
        let zone = TimeZone(identifier: startedHeader.timeZone) ?? TimeZone(secondsFromGMT: 0)!
        let offsetMinutes = zone.secondsFromGMT(for: startInstant) / 60

        var replayed: [String: ReplayedSet] = [:]
        for set in state.sets { replayed[set.setId] = set }

        var exercises: [[String: Any]] = []
        for exercise in template.exercises.sorted(by: { $0.position < $1.position }) {
            var sets: [[String: Any]] = []
            for set in exercise.sets.sorted(by: { $0.position < $1.position }) {
                guard let done = replayed[set.setId] else { continue }
                // A skipped set has no logged kind, so it takes the template's.
                let kind = done.status == "skipped" ? set.kind : done.kind
                var item: [String: Any] = ["id": set.setId, "position": set.position, "kind": kind]
                if done.status == "skipped" {
                    item["status"] = "skipped"
                    item["input_unit"] = unit
                } else {
                    item["status"] = "completed"
                    item["input_unit"] = lastUnit[set.setId] ?? unit
                    if let reps = done.reps { item["reps"] = reps }
                    if let seconds = done.durationSeconds { item["duration_seconds"] = seconds }
                    if let load = done.loadGrams, load > 0 { item["load_grams"] = load }
                    if let rpe = done.rpe { item["rpe"] = rpe }
                    item["completed_at_utc"] = lastOccurred[set.setId] ?? completedAt
                }
                sets.append(item)
            }
            if sets.isEmpty { continue }
            var item: [String: Any] = [
                "id": exercise.exerciseId, "name": exercise.name, "position": exercise.position, "sets": sets,
            ]
            if let muscle = exercise.muscle {
                item["muscle"] = muscle
                if knownMuscles.contains(muscle) { item["primary_muscles"] = [muscle] }
            }
            exercises.append(item)
        }

        let workout: [String: Any] = [
            "schema_version": 1, "workout_id": startedHeader.workoutId, "origin": "beyondrep_watch",
            "status": "completed", "name": name, "started_at_utc": startedAt, "completed_at_utc": completedAt,
            "original_offset_minutes": offsetMinutes, "exercises": exercises,
        ]
        let lastSequence = ordered.map { $0.header.sequence }.max() ?? 0
        var body: [String: Any] = ["workout": workout, "last_sequence": lastSequence]
        if let healthkitWorkoutUuid { body["healthkit_workout_uuid"] = healthkitWorkoutUuid }
        if let day = template.programDay {
            body["program_day"] = ["plan_id": day.planId, "program_id": day.programId, "local_date": day.localDate]
        }
        let message = WatchMessage(
            messageId: messageId, sentAtUtc: sentAtUtc, accountKey: accountKey,
            body: .completedWorkout(
                workoutId: startedHeader.workoutId, lastSequence: lastSequence,
                healthkitWorkoutUuid: healthkitWorkoutUuid, raw: body))
        // A strict-codec failure throws here rather than at the phone.
        _ = try WatchMessage(json: message.jsonData())
        return message
    }
}
