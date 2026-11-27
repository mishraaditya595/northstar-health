import Foundation

/// Validated `session_command` body.
public struct SessionCommand: Equatable {
    public var sessionId: String
    public var commandId: String
    public var command: String
    public var set: SetValues?
    public var restSeconds: Int?

    public init(
        sessionId: String, commandId: String, command: String, set: SetValues? = nil,
        restSeconds: Int? = nil
    ) {
        self.sessionId = sessionId
        self.commandId = commandId
        self.command = command
        self.set = set
        self.restSeconds = restSeconds
    }
}

/// A validated message body. Nested lists and objects are checked strictly and
/// kept as plain JSON (`raw`); typed access is added where a stage needs it.
public enum WatchMessageBody {
    case accountBinding(unit: String)
    case accountCleared(wipeUnsent: Bool)
    case plansSnapshot(raw: [String: Any])
    case healthSnapshot(localDate: String, raw: [String: Any])
    case workoutEvent(WorkoutEventV2)
    case sessionState(sessionId: String, raw: [String: Any])
    case sessionCommand(SessionCommand)
    case completedWorkout(workoutId: String, lastSequence: Int, healthkitWorkoutUuid: String?, raw: [String: Any])
    case ack(ackedMessageId: String, result: String, reason: String?)
}

/// One `watch_link/v1` message.
public struct WatchMessage {
    public var messageId: String
    public var sentAtUtc: String
    public var accountKey: String
    public var body: WatchMessageBody

    public init(messageId: String, sentAtUtc: String, accountKey: String, body: WatchMessageBody) {
        self.messageId = messageId
        self.sentAtUtc = sentAtUtc
        self.accountKey = accountKey
        self.body = body
    }

    public var type: String {
        switch body {
        case .accountBinding: return "account_binding"
        case .accountCleared: return "account_cleared"
        case .plansSnapshot: return "plans_snapshot"
        case .healthSnapshot: return "health_snapshot"
        case .workoutEvent: return "workout_event"
        case .sessionState: return "session_state"
        case .sessionCommand: return "session_command"
        case .completedWorkout: return "completed_workout"
        case .ack: return "ack"
        }
    }

    private static let types: Set<String> = [
        "account_binding", "account_cleared", "plans_snapshot", "health_snapshot",
        "workout_event", "session_state", "session_command", "completed_workout", "ack",
    ]

    public init(json data: Data) throws {
        let o = try StrictObject(
            StrictObject.parse(data),
            required: ["schema_version", "message_id", "type", "sent_at_utc", "account_key", "body"])
        guard let version = o.dict["schema_version"] as? NSNumber, !StrictObject.isBool(version) else {
            throw ContractError("invalid_value")
        }
        if version.doubleValue != 1 { throw ContractError("unsupported_version") }
        guard let type = o.dict["type"] as? String, Self.types.contains(type) else {
            throw ContractError("unknown_type")
        }
        messageId = try o.uuid("message_id")
        sentAtUtc = try o.dateTime("sent_at_utc")
        accountKey = try o.accountKey()
        let raw = o.dict["body"]
        func body(_ required: Set<String>, _ optional: Set<String> = []) throws -> StrictObject {
            try StrictObject(raw, required: required, optional: optional)
        }
        switch type {
        case "account_binding":
            self.body = .accountBinding(unit: try body(["unit"]).oneOf("unit", ["kg", "lb"]))
        case "account_cleared":
            self.body = .accountCleared(wipeUnsent: try body(["wipe_unsent"]).bool("wipe_unsent"))
        case "plans_snapshot":
            let b = try body(["generated_at_utc", "plans", "recent_exercises"], ["today"])
            _ = try b.dateTime("generated_at_utc")
            for plan in try b.array("plans", max: 100) { try Self.checkPlan(plan) }
            for item in try b.array("recent_exercises", max: 30) {
                let r = try StrictObject(item, required: ["exercise_id", "name", "kind"])
                _ = try r.string("exercise_id", max: 128)
                _ = try r.string("name", max: 120)
                _ = try r.oneOf("kind", ["reps", "duration"])
            }
            if b.has("today") {
                let t = try b.object("today", required: ["plan_id", "program_id", "local_date", "label"])
                _ = try t.string("plan_id", max: 128)
                _ = try t.string("program_id", max: 128)
                _ = try t.localDate("local_date")
                _ = try t.string("label", max: 120)
            }
            self.body = .plansSnapshot(raw: b.dict)
        case "health_snapshot":
            let b = try body(
                ["local_date", "as_of_utc"],
                [
                    "readiness", "sleep", "resting_hr_bpm", "hrv_ms", "hrv_kind", "steps", "active_energy_kcal",
                    "resting_hr_usual_bpm", "hrv_usual_ms", "week",
                ])
            let date = try b.localDate("local_date")
            _ = try b.dateTime("as_of_utc")
            if b.has("readiness") {
                let r = try b.object(
                    "readiness", required: ["score", "band", "headline", "reason"], optional: ["factors"])
                _ = try r.int("score", max: 100)
                _ = try r.oneOf("band", ["good", "fair", "low"])
                _ = try r.string("headline", max: 60)
                _ = try r.string("reason", max: 140)
                if r.has("factors") {
                    var inputs = Set<String>()
                    for item in try r.array("factors", max: 4) {
                        let f = try StrictObject(item, required: ["input", "status", "tone"])
                        let input = try f.oneOf("input", ["sleep", "hrv", "resting_hr", "training_load"])
                        // Each input appears once; JSON Schema cannot say so.
                        guard inputs.insert(input).inserted else { throw ContractError("invalid_value") }
                        _ = try f.string("status", max: 24)
                        _ = try f.oneOf("tone", ["good", "neutral", "caution"])
                    }
                }
            }
            if b.has("sleep") {
                let s = try b.object(
                    "sleep", required: [],
                    optional: ["score", "asleep_minutes", "deep_minutes", "rem_minutes", "core_minutes", "awake_minutes"])
                _ = try s.optionalInt("score", max: 100)
                _ = try s.optionalInt("asleep_minutes")
                _ = try s.optionalInt("deep_minutes")
                _ = try s.optionalInt("rem_minutes")
                _ = try s.optionalInt("core_minutes")
                _ = try s.optionalInt("awake_minutes")
            }
            if b.has("week") {
                let week = try b.array("week", max: 7)
                if week.isEmpty { throw ContractError("invalid_value") }
                var previous: String?
                for item in week {
                    let d = try StrictObject(
                        item, required: ["local_date"],
                        optional: ["asleep_minutes", "sleep_score", "resting_hr_bpm", "hrv_ms", "steps"])
                    let dayDate = try d.localDate("local_date")
                    // Dates are zero-padded, so string order is date order.
                    if let previous, dayDate <= previous { throw ContractError("invalid_value") }
                    if dayDate > date { throw ContractError("invalid_value") }
                    previous = dayDate
                    _ = try d.optionalInt("asleep_minutes")
                    _ = try d.optionalInt("sleep_score", max: 100)
                    _ = try d.optionalInt("resting_hr_bpm")
                    _ = try d.optionalInt("hrv_ms")
                    _ = try d.optionalInt("steps")
                }
            }
            _ = try b.optionalInt("resting_hr_usual_bpm")
            _ = try b.optionalInt("hrv_usual_ms")
            _ = try b.optionalInt("resting_hr_bpm")
            _ = try b.optionalInt("hrv_ms")
            if b.has("hrv_kind") { _ = try b.oneOf("hrv_kind", ["sdnn", "rmssd"]) }
            _ = try b.optionalInt("steps")
            _ = try b.optionalInt("active_energy_kcal")
            self.body = .healthSnapshot(localDate: date, raw: b.dict)
        case "workout_event":
            let b = try body(["event"])
            self.body = .workoutEvent(try WorkoutEventV2(object: b.dict["event"]))
        case "session_state":
            let b = try body(
                ["session_id", "owner", "status", "name", "started_at_utc", "last_sequence", "exercises"],
                ["current_set_id", "rest_deadline_utc"])
            let sessionId = try b.uuid("session_id")
            _ = try b.oneOf("owner", ["watch", "phone"])
            _ = try b.oneOf("status", ["active", "paused"])
            _ = try b.string("name", max: 120)
            _ = try b.dateTime("started_at_utc")
            _ = try b.int("last_sequence")
            if b.has("current_set_id") { _ = try b.uuid("current_set_id") }
            if b.has("rest_deadline_utc") { _ = try b.dateTime("rest_deadline_utc") }
            for item in try b.array("exercises", max: 120) {
                let x = try StrictObject(item, required: ["exercise_id", "name", "kind", "sets"])
                _ = try x.string("exercise_id", max: 128)
                _ = try x.string("name", max: 120)
                _ = try x.oneOf("kind", ["reps", "duration"])
                for entry in try x.array("sets", max: 300) {
                    let s = try StrictObject(
                        entry, required: ["set_id", "position", "kind", "status"],
                        optional: Set(["input_unit"]).union(SetValues.optionalKeys))
                    _ = try s.uuid("set_id")
                    _ = try s.int("position")
                    _ = try s.oneOf("kind", ["working", "warmup"])
                    _ = try s.oneOf("status", ["planned", "completed", "skipped"])
                    if s.has("input_unit") { _ = try s.oneOf("input_unit", ["kg", "lb"]) }
                    _ = try s.optionalInt("reps")
                    _ = try s.optionalInt("duration_seconds", min: 1)
                    _ = try s.optionalInt("load_grams")
                    _ = try s.optionalRpe("rpe")
                }
            }
            self.body = .sessionState(sessionId: sessionId, raw: b.dict)
        case "session_command":
            let b = try body(["session_id", "command_id", "command"], ["set", "rest_seconds"])
            var set: SetValues?
            if b.has("set") {
                let s = try b.object("set", required: SetValues.requiredKeys, optional: SetValues.optionalKeys)
                set = try SetValues.read(s, requireRepsOrSeconds: false)
            }
            self.body = .sessionCommand(
                SessionCommand(
                    sessionId: try b.uuid("session_id"), commandId: try b.uuid("command_id"),
                    command: try b.oneOf(
                        "command",
                        ["log_set", "correct_set", "skip_set", "start_rest", "clear_rest", "pause", "resume", "finish", "discard"]),
                    set: set, restSeconds: try b.optionalInt("rest_seconds", min: 1, max: 3600)))
        case "completed_workout":
            let b = try body(["workout", "last_sequence"], ["healthkit_workout_uuid", "program_day"])
            guard let workout = b.dict["workout"] as? [String: Any],
                workout["origin"] as? String == "beyondrep_watch",
                let workoutId = workout["workout_id"] as? String
            else { throw ContractError("invalid_value") }
            let lastSequence = try b.int("last_sequence")
            let healthkitUuid = try b.has("healthkit_workout_uuid") ? b.uuid("healthkit_workout_uuid") : nil
            if b.has("program_day") {
                let d = try b.object("program_day", required: ["plan_id", "program_id", "local_date"])
                _ = try d.string("plan_id", max: 128)
                _ = try d.string("program_id", max: 128)
                _ = try d.localDate("local_date")
            }
            self.body = .completedWorkout(
                workoutId: workoutId, lastSequence: lastSequence, healthkitWorkoutUuid: healthkitUuid, raw: b.dict)
        default:
            let b = try body(["acked_message_id", "result"], ["reason"])
            let acked = try b.uuid("acked_message_id")
            let result = try b.oneOf("result", ["stored", "duplicate", "rejected"])
            let reason = try b.has("reason") ? b.oneOf("reason", ["wrong_account", "invalid", "unsupported_version"]) : nil
            self.body = .ack(ackedMessageId: acked, result: result, reason: reason)
        }
    }

    private static func checkPlan(_ raw: Any) throws {
        let p = try StrictObject(raw, required: ["plan_id", "name", "exercises"])
        _ = try p.string("plan_id", max: 128)
        _ = try p.string("name", max: 120)
        for item in try p.array("exercises", max: 40) {
            let x = try StrictObject(item, required: ["exercise_id", "name", "kind", "sets"], optional: ["muscle"])
            _ = try x.string("exercise_id", max: 128)
            _ = try x.string("name", max: 120)
            _ = try x.oneOf("kind", ["reps", "duration"])
            _ = try x.optionalString("muscle", max: 60)
            for entry in try x.array("sets", max: 30) {
                let s = try StrictObject(
                    entry, required: ["position", "kind"],
                    optional: ["target_reps", "target_seconds", "target_load_grams", "rest_seconds"])
                _ = try s.int("position")
                _ = try s.oneOf("kind", ["working", "warmup"])
                _ = try s.optionalInt("target_reps")
                _ = try s.optionalInt("target_seconds", min: 1)
                _ = try s.optionalInt("target_load_grams")
                _ = try s.optionalInt("rest_seconds", max: 3600)
            }
        }
    }

    var bodyObject: [String: Any] {
        switch body {
        case .accountBinding(let unit): return ["unit": unit]
        case .accountCleared(let wipe): return ["wipe_unsent": wipe]
        case .plansSnapshot(let raw), .healthSnapshot(_, let raw), .sessionState(_, let raw),
            .completedWorkout(_, _, _, let raw):
            return raw
        case .workoutEvent(let event): return ["event": event.jsonObject]
        case .sessionCommand(let c):
            var out: [String: Any] = ["session_id": c.sessionId, "command_id": c.commandId, "command": c.command]
            if let set = c.set { out["set"] = set.jsonObject }
            if let seconds = c.restSeconds { out["rest_seconds"] = seconds }
            return out
        case .ack(let id, let result, let reason):
            var out: [String: Any] = ["acked_message_id": id, "result": result]
            if let reason { out["reason"] = reason }
            return out
        }
    }

    public func jsonData() throws -> Data {
        try StrictObject.data([
            "schema_version": 1, "message_id": messageId, "type": type,
            "sent_at_utc": sentAtUtc, "account_key": accountKey, "body": bodyObject,
        ])
    }
}
