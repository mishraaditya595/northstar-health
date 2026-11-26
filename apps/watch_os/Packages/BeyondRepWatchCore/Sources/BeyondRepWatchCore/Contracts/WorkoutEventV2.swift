import Foundation

public struct EventHeader: Equatable {
    public var eventId: String
    public var workoutId: String
    public var sessionId: String
    public var originDeviceId: String
    public var sequence: Int
    public var occurredAtUtc: String
    public var recordedAtUtc: String
    public var timeZone: String

    public init(
        eventId: String, workoutId: String, sessionId: String, originDeviceId: String,
        sequence: Int, occurredAtUtc: String, recordedAtUtc: String, timeZone: String
    ) {
        self.eventId = eventId
        self.workoutId = workoutId
        self.sessionId = sessionId
        self.originDeviceId = originDeviceId
        self.sequence = sequence
        self.occurredAtUtc = occurredAtUtc
        self.recordedAtUtc = recordedAtUtc
        self.timeZone = timeZone
    }
}

/// The values of one logged set (`set_logged`, `set_corrected`, commands).
public struct SetValues: Equatable {
    public var setId: String
    public var exerciseId: String
    public var position: Int
    public var kind: String
    public var inputUnit: String
    public var reps: Int?
    public var durationSeconds: Int?
    public var loadGrams: Int?
    public var rpe: Double?

    public init(
        setId: String, exerciseId: String, position: Int, kind: String = "working",
        inputUnit: String = "kg", reps: Int? = nil, durationSeconds: Int? = nil,
        loadGrams: Int? = nil, rpe: Double? = nil
    ) {
        self.setId = setId
        self.exerciseId = exerciseId
        self.position = position
        self.kind = kind
        self.inputUnit = inputUnit
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.loadGrams = loadGrams
        self.rpe = rpe
    }

    static let requiredKeys: Set<String> = ["set_id", "exercise_id", "position", "kind", "input_unit"]
    static let optionalKeys: Set<String> = ["reps", "duration_seconds", "load_grams", "rpe"]

    static func read(_ o: StrictObject, requireRepsOrSeconds: Bool = true) throws -> SetValues {
        let values = SetValues(
            setId: try o.uuid("set_id"),
            exerciseId: try o.string("exercise_id", max: 128),
            position: try o.int("position"),
            kind: try o.oneOf("kind", ["working", "warmup"]),
            inputUnit: try o.oneOf("input_unit", ["kg", "lb"]),
            reps: try o.optionalInt("reps"),
            durationSeconds: try o.optionalInt("duration_seconds", min: 1),
            loadGrams: try o.optionalInt("load_grams"),
            rpe: try o.optionalRpe("rpe"))
        if requireRepsOrSeconds && values.reps == nil && values.durationSeconds == nil {
            throw ContractError("missing_field")
        }
        return values
    }

    var jsonObject: [String: Any] {
        var out: [String: Any] = [
            "set_id": setId, "exercise_id": exerciseId, "position": position,
            "kind": kind, "input_unit": inputUnit,
        ]
        if let reps { out["reps"] = reps }
        if let durationSeconds { out["duration_seconds"] = durationSeconds }
        if let loadGrams { out["load_grams"] = loadGrams }
        if let rpe { out["rpe"] = rpe }
        return out
    }
}

public struct WorkoutStartedPayload: Equatable {
    public var activityType: String
    public var name: String
    public var owner: String
    public var accountKey: String
    public var planId: String?
    public var programId: String?
    public var programLocalDate: String?

    public init(
        activityType: String = "traditional_strength_training", name: String, owner: String,
        accountKey: String, planId: String? = nil, programId: String? = nil,
        programLocalDate: String? = nil
    ) {
        self.activityType = activityType
        self.name = name
        self.owner = owner
        self.accountKey = accountKey
        self.planId = planId
        self.programId = programId
        self.programLocalDate = programLocalDate
    }
}

public struct ExerciseAddedPayload: Equatable {
    public var exerciseId: String
    public var name: String
    public var kind: String
    public var position: Int

    public init(exerciseId: String, name: String, kind: String, position: Int) {
        self.exerciseId = exerciseId
        self.name = name
        self.kind = kind
        self.position = position
    }
}

/// One `workout_sync/v2` event.
public enum WorkoutEventV2: Equatable {
    case workoutStarted(EventHeader, WorkoutStartedPayload)
    case exerciseAdded(EventHeader, ExerciseAddedPayload)
    case setLogged(EventHeader, SetValues)
    case setCorrected(EventHeader, SetValues, supersedesEventId: String)
    case setSkipped(EventHeader, setId: String)
    case restStarted(EventHeader, seconds: Int, deadlineUtc: String)
    case restCleared(EventHeader)
    case workoutPaused(EventHeader)
    case workoutResumed(EventHeader)
    case workoutCompleted(EventHeader)
    case workoutAbandoned(EventHeader)
    case platformWorkoutExported(EventHeader, platform: String, externalRecordId: String)

    public var header: EventHeader {
        switch self {
        case .workoutStarted(let h, _), .exerciseAdded(let h, _), .setLogged(let h, _),
            .setCorrected(let h, _, _), .setSkipped(let h, _), .restStarted(let h, _, _),
            .restCleared(let h), .workoutPaused(let h), .workoutResumed(let h),
            .workoutCompleted(let h), .workoutAbandoned(let h),
            .platformWorkoutExported(let h, _, _):
            return h
        }
    }

    public var type: String {
        switch self {
        case .workoutStarted: return "workout_started"
        case .exerciseAdded: return "exercise_added"
        case .setLogged: return "set_logged"
        case .setCorrected: return "set_corrected"
        case .setSkipped: return "set_skipped"
        case .restStarted: return "rest_started"
        case .restCleared: return "rest_cleared"
        case .workoutPaused: return "workout_paused"
        case .workoutResumed: return "workout_resumed"
        case .workoutCompleted: return "workout_completed"
        case .workoutAbandoned: return "workout_abandoned"
        case .platformWorkoutExported: return "platform_workout_exported"
        }
    }

    public init(json data: Data) throws {
        try self.init(object: StrictObject.parse(data))
    }

    init(object raw: Any?) throws {
        let o = try StrictObject(
            raw,
            required: [
                "schema_version", "event_id", "workout_id", "session_id", "origin_device_id",
                "sequence", "type", "occurred_at_utc", "recorded_at_utc", "time_zone", "payload",
            ])
        guard let version = o.dict["schema_version"] as? NSNumber, !StrictObject.isBool(version) else {
            throw ContractError("invalid_value")
        }
        if version.doubleValue != 2 { throw ContractError("unsupported_version") }
        guard let type = o.dict["type"] as? String, Self.types.contains(type) else {
            throw ContractError("unknown_type")
        }
        let header = EventHeader(
            eventId: try o.uuid("event_id"),
            workoutId: try o.uuid("workout_id"),
            sessionId: try o.uuid("session_id"),
            originDeviceId: try o.string("origin_device_id", max: 128),
            sequence: try o.int("sequence"),
            occurredAtUtc: try o.dateTime("occurred_at_utc"),
            recordedAtUtc: try o.dateTime("recorded_at_utc"),
            timeZone: try o.string("time_zone", max: 100))
        let p = o.dict["payload"]
        switch type {
        case "workout_started":
            let s = try StrictObject(
                p, required: ["activity_type", "name", "owner", "account_key"],
                optional: ["plan_id", "program_day"])
            var programId: String?
            var programDate: String?
            if s.has("program_day") {
                let day = try s.object("program_day", required: ["program_id", "local_date"])
                programId = try day.string("program_id", max: 128)
                programDate = try day.localDate("local_date")
            }
            self = .workoutStarted(
                header,
                WorkoutStartedPayload(
                    activityType: try s.string("activity_type", max: 80),
                    name: try s.string("name", max: 120),
                    owner: try s.oneOf("owner", ["watch", "phone"]),
                    accountKey: try s.accountKey(),
                    planId: try s.optionalString("plan_id", max: 128),
                    programId: programId, programLocalDate: programDate))
        case "exercise_added":
            let s = try StrictObject(p, required: ["exercise_id", "name", "kind", "position"])
            self = .exerciseAdded(
                header,
                ExerciseAddedPayload(
                    exerciseId: try s.string("exercise_id", max: 128),
                    name: try s.string("name", max: 120),
                    kind: try s.oneOf("kind", ["reps", "duration"]),
                    position: try s.int("position")))
        case "set_logged":
            let s = try StrictObject(p, required: SetValues.requiredKeys, optional: SetValues.optionalKeys)
            self = .setLogged(header, try SetValues.read(s))
        case "set_corrected":
            let s = try StrictObject(
                p, required: SetValues.requiredKeys.union(["supersedes_event_id"]),
                optional: SetValues.optionalKeys)
            self = .setCorrected(
                header, try SetValues.read(s), supersedesEventId: try s.uuid("supersedes_event_id"))
        case "set_skipped":
            let s = try StrictObject(p, required: ["set_id"])
            self = .setSkipped(header, setId: try s.uuid("set_id"))
        case "rest_started":
            let s = try StrictObject(p, required: ["seconds", "deadline_utc"])
            self = .restStarted(
                header, seconds: try s.int("seconds", min: 1, max: 3600),
                deadlineUtc: try s.dateTime("deadline_utc"))
        case "platform_workout_exported":
            let s = try StrictObject(p, required: ["platform", "external_record_id"])
            self = .platformWorkoutExported(
                header, platform: try s.oneOf("platform", ["healthkit", "health_connect"]),
                externalRecordId: try s.string("external_record_id", max: 256))
        default:
            _ = try StrictObject(p, required: [])
            switch type {
            case "rest_cleared": self = .restCleared(header)
            case "workout_paused": self = .workoutPaused(header)
            case "workout_resumed": self = .workoutResumed(header)
            case "workout_completed": self = .workoutCompleted(header)
            default: self = .workoutAbandoned(header)
            }
        }
    }

    private static let types: Set<String> = [
        "workout_started", "exercise_added", "set_logged", "set_corrected", "set_skipped",
        "rest_started", "rest_cleared", "workout_paused", "workout_resumed",
        "workout_completed", "workout_abandoned", "platform_workout_exported",
    ]

    var payloadObject: [String: Any] {
        switch self {
        case .workoutStarted(_, let p):
            var out: [String: Any] = [
                "activity_type": p.activityType, "name": p.name, "owner": p.owner,
                "account_key": p.accountKey,
            ]
            if let id = p.planId { out["plan_id"] = id }
            if let program = p.programId, let date = p.programLocalDate {
                out["program_day"] = ["program_id": program, "local_date": date]
            }
            return out
        case .exerciseAdded(_, let p):
            return ["exercise_id": p.exerciseId, "name": p.name, "kind": p.kind, "position": p.position]
        case .setLogged(_, let values):
            return values.jsonObject
        case .setCorrected(_, let values, let supersedes):
            var out = values.jsonObject
            out["supersedes_event_id"] = supersedes
            return out
        case .setSkipped(_, let id):
            return ["set_id": id]
        case .restStarted(_, let seconds, let deadline):
            return ["seconds": seconds, "deadline_utc": deadline]
        case .platformWorkoutExported(_, let platform, let id):
            return ["platform": platform, "external_record_id": id]
        case .restCleared, .workoutPaused, .workoutResumed, .workoutCompleted, .workoutAbandoned:
            return [:]
        }
    }

    var jsonObject: [String: Any] {
        let h = header
        return [
            "schema_version": 2, "event_id": h.eventId, "workout_id": h.workoutId,
            "session_id": h.sessionId, "origin_device_id": h.originDeviceId,
            "sequence": h.sequence, "type": type, "occurred_at_utc": h.occurredAtUtc,
            "recorded_at_utc": h.recordedAtUtc, "time_zone": h.timeZone,
            "payload": payloadObject,
        ]
    }

    public func jsonData() throws -> Data {
        try StrictObject.data(jsonObject)
    }
}
