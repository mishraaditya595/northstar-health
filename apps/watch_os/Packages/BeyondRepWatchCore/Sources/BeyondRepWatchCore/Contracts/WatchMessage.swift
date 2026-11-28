import Foundation

/// Validated `session_command` body.
public struct SessionCommand: Equatable {
    public var sessionId: String
    public var commandId: String
    public var command: String
    public var set: SetValues?
    public var restSeconds: Int?
    /// Only for `add_set`.
    public var exerciseId: String?

    public init(
        sessionId: String, commandId: String, command: String, set: SetValues? = nil,
        restSeconds: Int? = nil, exerciseId: String? = nil
    ) {
        self.exerciseId = exerciseId
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
    /// The watch's receipt for the one `HKWorkout` it saved for a phone workout.
    case workoutLink(workoutId: String, healthkitWorkoutUuid: String)
    /// A follower is attached; `sessionId` is nil while the watch does not know
    /// the phone's session yet.
    case join(sessionId: String?)
    /// Heart rate and calories of a finished Wear OS workout. The Apple Watch
    /// never sends it; it is decoded so the shared fixtures stay valid here.
    case workoutHealth(workoutId: String, raw: [String: Any])
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
        case .workoutLink: return "workout_link"
        case .join: return "join"
        case .workoutHealth: return "workout_health"
        }
    }

    private static let types: Set<String> = [
        "account_binding", "account_cleared", "plans_snapshot", "health_snapshot",
        "workout_event", "session_state", "session_command", "completed_workout", "ack",
        "workout_link", "join", "workout_health",
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
                [
                    "current_set_id", "rest_deadline_utc", "end_reason", "paused_at_utc", "paused_seconds",
                    "applied_command_ids", "rejected_commands",
                ])
            let sessionId = try b.uuid("session_id")
            _ = try b.oneOf("owner", ["watch", "phone"])
            let status = try b.oneOf("status", ["active", "paused", "ended"])
            // `end_reason` goes with `ended` and `paused_at_utc` with `paused`.
            if b.has("end_reason") != (status == "ended") || (b.has("paused_at_utc") && status != "paused") {
                throw ContractError("invalid_value")
            }
            if b.has("end_reason") { _ = try b.oneOf("end_reason", ["completed", "discarded"]) }
            if b.has("paused_at_utc") { _ = try b.dateTime("paused_at_utc") }
            _ = try b.optionalInt("paused_seconds")
            if b.has("applied_command_ids") {
                for item in try b.array("applied_command_ids", max: 20) {
                    _ = try StrictObject(["id": item], required: ["id"]).uuid("id")
                }
            }
            if b.has("rejected_commands") {
                for item in try b.array("rejected_commands", max: 20) {
                    let r = try StrictObject(item, required: ["command_id", "reason"])
                    _ = try r.uuid("command_id")
                    _ = try r.oneOf("reason", ["unknown_session", "unknown_set", "invalid_values", "not_allowed"])
                }
            }
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
                        optional: Set(["input_unit", "rest_seconds"]).union(SetValues.optionalKeys))
                    _ = try s.uuid("set_id")
                    _ = try s.int("position")
                    _ = try s.oneOf("kind", ["working", "warmup"])
                    _ = try s.oneOf("status", ["planned", "completed", "skipped"])
                    if s.has("input_unit") { _ = try s.oneOf("input_unit", ["kg", "lb"]) }
                    _ = try s.optionalInt("rest_seconds", min: 1, max: 3600)
                    _ = try s.optionalInt("reps")
                    _ = try s.optionalInt("duration_seconds", min: 1)
                    _ = try s.optionalInt("load_grams")
                    _ = try s.optionalRpe("rpe")
                }
            }
            self.body = .sessionState(sessionId: sessionId, raw: b.dict)
        case "session_command":
            let b = try body(["session_id", "command_id", "command"], ["set", "rest_seconds", "exercise_id"])
            let command = try b.oneOf(
                "command",
                [
                    "log_set", "correct_set", "skip_set", "add_set", "start_rest", "clear_rest", "pause", "resume",
                    "finish", "discard",
                ])
            // The schema requires `set` for these and `exercise_id` for add_set only.
            if ["log_set", "correct_set", "skip_set"].contains(command) && !b.has("set") {
                throw ContractError("missing_field")
            }
            if b.has("exercise_id") != (command == "add_set") {
                throw ContractError(command == "add_set" ? "missing_field" : "unknown_key")
            }
            let exerciseId = try b.optionalString("exercise_id", max: 128)
            var set: SetValues?
            if b.has("set") {
                let s = try b.object("set", required: SetValues.requiredKeys, optional: SetValues.optionalKeys)
                set = try SetValues.read(s, requireRepsOrSeconds: false)
            }
            self.body = .sessionCommand(
                SessionCommand(
                    sessionId: try b.uuid("session_id"), commandId: try b.uuid("command_id"),
                    command: command, set: set,
                    restSeconds: try b.optionalInt("rest_seconds", min: 1, max: 3600), exerciseId: exerciseId))
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
        case "workout_link":
            let b = try body(["workout_id", "healthkit_workout_uuid"])
            self.body = .workoutLink(
                workoutId: try b.uuid("workout_id"), healthkitWorkoutUuid: try b.uuid("healthkit_workout_uuid"))
        case "join":
            let b = try body([], ["session_id"])
            self.body = .join(sessionId: try b.has("session_id") ? b.uuid("session_id") : nil)
        case "workout_health":
            let b = try body(["workout_id", "start_utc", "end_utc", "heart_rate"], ["total_kcal"])
            let workoutId = try b.uuid("workout_id")
            let start = try b.dateTime("start_utc")
            let end = try b.dateTime("end_utc")
            guard let startMs = WatchTimestamp.milliseconds(start), let endMs = WatchTimestamp.milliseconds(end),
                endMs > startMs
            else { throw ContractError("invalid_value") }
            var previous: Int64?
            for item in try b.array("heart_rate", max: 600) {
                let point = try StrictObject(item, required: ["at_utc", "bpm"])
                let at = try point.dateTime("at_utc")
                _ = try point.int("bpm", min: 25, max: 250)
                guard let atMs = WatchTimestamp.milliseconds(at), atMs >= startMs, atMs <= endMs else {
                    throw ContractError("invalid_value")
                }
                if let previous, atMs <= previous { throw ContractError("invalid_value") }
                previous = atMs
            }
            if b.has("total_kcal") {
                guard let kcal = b.dict["total_kcal"] as? NSNumber, !StrictObject.isBool(kcal),
                    kcal.doubleValue > 0, kcal.doubleValue <= 10000
                else { throw ContractError("invalid_value") }
            }
            self.body = .workoutHealth(workoutId: workoutId, raw: b.dict)
        default:
            let b = try body(["acked_message_id", "result"], ["reason"])
            let acked = try b.uuid("acked_message_id")
            let result = try b.oneOf("result", ["stored", "duplicate", "rejected"])
            let reason =
                try b.has("reason")
                ? b.oneOf("reason", ["wrong_account", "invalid", "unsupported_version", "not_written"]) : nil
            // not_written only ever comes with a rejection.
            if reason == "not_written", result != "rejected" { throw ContractError("invalid_value") }
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
            .completedWorkout(_, _, _, let raw), .workoutHealth(_, let raw):
            return raw
        case .workoutEvent(let event): return ["event": event.jsonObject]
        case .sessionCommand(let c):
            var out: [String: Any] = ["session_id": c.sessionId, "command_id": c.commandId, "command": c.command]
            if let set = c.set { out["set"] = set.jsonObject }
            if let seconds = c.restSeconds { out["rest_seconds"] = seconds }
            if let exerciseId = c.exerciseId { out["exercise_id"] = exerciseId }
            return out
        case .workoutLink(let workoutId, let hkUuid):
            return ["workout_id": workoutId, "healthkit_workout_uuid": hkUuid]
        case .join(let sessionId): return sessionId.map { ["session_id": $0] } ?? [:]
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
