package `in`.beyondrep.wear.core.contracts

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Validated `session_command` body. */
data class SessionCommand(
    val sessionId: String,
    val commandId: String,
    val command: String,
    val set: SetValues? = null,
    val restSeconds: Int? = null,
    /** Only for `add_set`. */
    val exerciseId: String? = null,
)

/** One per-minute heart rate average of `workout_health`; `bpm` is a whole number from 25 to 250. */
data class HeartRatePoint(val atUtc: String, val bpm: Int)

/**
 * A validated message body. Nested lists and objects are checked strictly and kept as plain
 * JSON (`raw`); typed access is added where a stage needs it.
 */
sealed interface WatchMessageBody {
    data class AccountBinding(val unit: String) : WatchMessageBody
    data class AccountCleared(val wipeUnsent: Boolean) : WatchMessageBody
    data class PlansSnapshot(val raw: JsonObject) : WatchMessageBody
    data class HealthSnapshot(val localDate: String, val raw: JsonObject) : WatchMessageBody
    data class WorkoutEvent(val event: WorkoutEventV2) : WatchMessageBody
    data class SessionState(val sessionId: String, val raw: JsonObject) : WatchMessageBody
    data class SessionCommandBody(val command: SessionCommand) : WatchMessageBody
    data class CompletedWorkout(
        val workoutId: String,
        val lastSequence: Int,
        val healthkitWorkoutUuid: String?,
        val raw: JsonObject,
    ) : WatchMessageBody

    data class Ack(val ackedMessageId: String, val result: String, val reason: String?) : WatchMessageBody

    /**
     * The heart rate and total calories of one finished workout (stage 3b). With `health_snapshot`
     * the only message that carries health values; missing values are left out, never 0.
     */
    data class WorkoutHealth(
        val workoutId: String,
        val startUtc: String,
        val endUtc: String,
        val heartRate: List<HeartRatePoint>,
        val totalKcal: Double?,
    ) : WatchMessageBody

    /** Not sent by Wear (spec 4.5) but still decoded and encoded. */
    data class WorkoutLink(val workoutId: String, val healthkitWorkoutUuid: String) : WatchMessageBody

    /** A follower is attached; `sessionId` is null while the watch does not know the phone's session yet. */
    data class Join(val sessionId: String?) : WatchMessageBody
}

/** One `watch_link/v1` message (port of WatchMessage.swift). */
data class WatchMessage(
    val messageId: String,
    val sentAtUtc: String,
    val accountKey: String,
    val body: WatchMessageBody,
) {
    val type: String
        get() = when (body) {
            is WatchMessageBody.AccountBinding -> "account_binding"
            is WatchMessageBody.AccountCleared -> "account_cleared"
            is WatchMessageBody.PlansSnapshot -> "plans_snapshot"
            is WatchMessageBody.HealthSnapshot -> "health_snapshot"
            is WatchMessageBody.WorkoutEvent -> "workout_event"
            is WatchMessageBody.SessionState -> "session_state"
            is WatchMessageBody.SessionCommandBody -> "session_command"
            is WatchMessageBody.CompletedWorkout -> "completed_workout"
            is WatchMessageBody.Ack -> "ack"
            is WatchMessageBody.WorkoutLink -> "workout_link"
            is WatchMessageBody.Join -> "join"
            is WatchMessageBody.WorkoutHealth -> "workout_health"
        }

    private fun bodyObject(): JsonObject = when (val b = body) {
        is WatchMessageBody.AccountBinding -> JsonObject(mapOf("unit" to JsonPrimitive(b.unit)))
        is WatchMessageBody.AccountCleared -> JsonObject(mapOf("wipe_unsent" to JsonPrimitive(b.wipeUnsent)))
        is WatchMessageBody.PlansSnapshot -> b.raw
        is WatchMessageBody.HealthSnapshot -> b.raw
        is WatchMessageBody.SessionState -> b.raw
        is WatchMessageBody.CompletedWorkout -> b.raw
        is WatchMessageBody.WorkoutEvent -> JsonObject(mapOf("event" to b.event.toJson()))
        is WatchMessageBody.SessionCommandBody -> {
            val c = b.command
            val out = linkedMapOf<String, JsonElement>(
                "session_id" to JsonPrimitive(c.sessionId), "command_id" to JsonPrimitive(c.commandId),
                "command" to JsonPrimitive(c.command),
            )
            c.set?.let { out["set"] = it.toJson() }
            c.restSeconds?.let { out["rest_seconds"] = StrictObject.number(it) }
            c.exerciseId?.let { out["exercise_id"] = JsonPrimitive(it) }
            JsonObject(out)
        }
        is WatchMessageBody.WorkoutLink -> JsonObject(
            mapOf(
                "workout_id" to JsonPrimitive(b.workoutId),
                "healthkit_workout_uuid" to JsonPrimitive(b.healthkitWorkoutUuid),
            ),
        )
        is WatchMessageBody.Join -> JsonObject(
            b.sessionId?.let { mapOf("session_id" to JsonPrimitive(it)) } ?: emptyMap())
        is WatchMessageBody.WorkoutHealth -> {
            val out = linkedMapOf<String, JsonElement>(
                "workout_id" to JsonPrimitive(b.workoutId), "start_utc" to JsonPrimitive(b.startUtc),
                "end_utc" to JsonPrimitive(b.endUtc),
                "heart_rate" to JsonArray(
                    b.heartRate.map {
                        JsonObject(mapOf("at_utc" to JsonPrimitive(it.atUtc), "bpm" to StrictObject.number(it.bpm)))
                    }),
            )
            b.totalKcal?.let { out["total_kcal"] = StrictObject.number(it) }
            JsonObject(out)
        }
        is WatchMessageBody.Ack -> {
            val out = linkedMapOf<String, JsonElement>(
                "acked_message_id" to JsonPrimitive(b.ackedMessageId), "result" to JsonPrimitive(b.result))
            b.reason?.let { out["reason"] = JsonPrimitive(it) }
            JsonObject(out)
        }
    }

    fun toJson(): JsonObject = JsonObject(
        mapOf(
            "schema_version" to JsonPrimitive(1), "message_id" to JsonPrimitive(messageId),
            "type" to JsonPrimitive(type), "sent_at_utc" to JsonPrimitive(sentAtUtc),
            "account_key" to JsonPrimitive(accountKey), "body" to bodyObject(),
        ),
    )

    fun encode(): String = StrictObject.encode(toJson())

    companion object {
        private val types = setOf(
            "account_binding", "account_cleared", "plans_snapshot", "health_snapshot",
            "workout_event", "session_state", "session_command", "completed_workout", "ack",
            "workout_link", "join", "workout_health",
        )

        fun decode(json: String): WatchMessage {
            val o = StrictObject(
                StrictObject.parse(json),
                required = setOf("schema_version", "message_id", "type", "sent_at_utc", "account_key", "body"),
            )
            val version = StrictObject.numberOf(o.dict["schema_version"])
            if (version != 1.0) throw ContractException("unsupported_version")
            val typePrimitive = o.dict["type"] as? JsonPrimitive
            val type = typePrimitive?.takeIf { it.isString && it.content in types }?.content
                ?: throw ContractException("unknown_type")
            val messageId = o.uuid("message_id")
            val sentAtUtc = o.dateTime("sent_at_utc")
            val accountKey = o.accountKey()
            val raw = o.dict["body"]
            fun body(required: Set<String>, optional: Set<String> = emptySet()) = StrictObject(raw, required, optional)
            val parsed: WatchMessageBody = when (type) {
                "account_binding" ->
                    WatchMessageBody.AccountBinding(body(setOf("unit")).oneOf("unit", setOf("kg", "lb")))
                "account_cleared" ->
                    WatchMessageBody.AccountCleared(body(setOf("wipe_unsent")).bool("wipe_unsent"))
                "plans_snapshot" -> {
                    val b = body(setOf("generated_at_utc", "plans", "recent_exercises"), setOf("today"))
                    b.dateTime("generated_at_utc")
                    for (plan in b.array("plans", max = 100)) checkPlan(plan)
                    for (item in b.array("recent_exercises", max = 30)) {
                        val r = StrictObject(item, setOf("exercise_id", "name", "kind"))
                        r.string("exercise_id", max = 128)
                        r.string("name", max = 120)
                        r.oneOf("kind", setOf("reps", "duration"))
                    }
                    if (b.has("today")) {
                        val t = b.obj("today", setOf("plan_id", "program_id", "local_date", "label"))
                        t.string("plan_id", max = 128)
                        t.string("program_id", max = 128)
                        t.localDate("local_date")
                        t.string("label", max = 120)
                    }
                    WatchMessageBody.PlansSnapshot(b.dict)
                }
                "health_snapshot" -> {
                    val b = body(
                        setOf("local_date", "as_of_utc"),
                        setOf(
                            "readiness", "sleep", "resting_hr_bpm", "hrv_ms", "hrv_kind", "steps",
                            "active_energy_kcal", "resting_hr_usual_bpm", "hrv_usual_ms", "week",
                        ),
                    )
                    val date = b.localDate("local_date")
                    b.dateTime("as_of_utc")
                    if (b.has("readiness")) {
                        val r = b.obj("readiness", setOf("score", "band", "headline", "reason"), setOf("factors"))
                        r.int("score", max = 100)
                        r.oneOf("band", setOf("good", "fair", "low"))
                        r.string("headline", max = 60)
                        r.string("reason", max = 140)
                        if (r.has("factors")) {
                            val inputs = mutableSetOf<String>()
                            for (item in r.array("factors", max = 4)) {
                                val f = StrictObject(item, setOf("input", "status", "tone"))
                                val input = f.oneOf("input", setOf("sleep", "hrv", "resting_hr", "training_load"))
                                // Each input appears once; JSON Schema cannot say so.
                                if (!inputs.add(input)) throw ContractException("invalid_value")
                                f.string("status", max = 24)
                                f.oneOf("tone", setOf("good", "neutral", "caution"))
                            }
                        }
                    }
                    if (b.has("sleep")) {
                        val s = b.obj(
                            "sleep", emptySet(),
                            setOf("score", "asleep_minutes", "deep_minutes", "rem_minutes", "core_minutes", "awake_minutes"))
                        s.optionalInt("score", max = 100)
                        s.optionalInt("asleep_minutes")
                        s.optionalInt("deep_minutes")
                        s.optionalInt("rem_minutes")
                        s.optionalInt("core_minutes")
                        s.optionalInt("awake_minutes")
                    }
                    if (b.has("week")) {
                        val week = b.array("week", max = 7)
                        if (week.isEmpty()) throw ContractException("invalid_value")
                        var previous: String? = null
                        for (item in week) {
                            val d = StrictObject(
                                item, setOf("local_date"),
                                setOf("asleep_minutes", "sleep_score", "resting_hr_bpm", "hrv_ms", "steps"))
                            val dayDate = d.localDate("local_date")
                            // Dates are zero-padded, so string order is date order.
                            if (previous != null && dayDate <= previous) throw ContractException("invalid_value")
                            if (dayDate > date) throw ContractException("invalid_value")
                            previous = dayDate
                            d.optionalInt("asleep_minutes")
                            d.optionalInt("sleep_score", max = 100)
                            d.optionalInt("resting_hr_bpm")
                            d.optionalInt("hrv_ms")
                            d.optionalInt("steps")
                        }
                    }
                    b.optionalInt("resting_hr_usual_bpm")
                    b.optionalInt("hrv_usual_ms")
                    b.optionalInt("resting_hr_bpm")
                    b.optionalInt("hrv_ms")
                    if (b.has("hrv_kind")) b.oneOf("hrv_kind", setOf("sdnn", "rmssd"))
                    b.optionalInt("steps")
                    b.optionalInt("active_energy_kcal")
                    WatchMessageBody.HealthSnapshot(date, b.dict)
                }
                "workout_event" -> {
                    val b = body(setOf("event"))
                    WatchMessageBody.WorkoutEvent(WorkoutEventV2.fromElement(b.dict["event"]))
                }
                "session_state" -> checkSessionState(
                    body(
                        setOf("session_id", "owner", "status", "name", "started_at_utc", "last_sequence", "exercises"),
                        setOf(
                            "current_set_id", "rest_deadline_utc", "end_reason", "paused_at_utc", "paused_seconds",
                            "applied_command_ids", "rejected_commands",
                        ),
                    ),
                )
                "session_command" -> {
                    val b = body(setOf("session_id", "command_id", "command"), setOf("set", "rest_seconds", "exercise_id"))
                    val command = b.oneOf(
                        "command",
                        setOf(
                            "log_set", "correct_set", "skip_set", "add_set", "start_rest", "clear_rest", "pause",
                            "resume", "finish", "discard",
                        ),
                    )
                    // The schema requires `set` for these and `exercise_id` for add_set only.
                    if (command in setOf("log_set", "correct_set", "skip_set") && !b.has("set")) {
                        throw ContractException("missing_field")
                    }
                    if (b.has("exercise_id") != (command == "add_set")) {
                        throw ContractException(if (command == "add_set") "missing_field" else "unknown_key")
                    }
                    val exerciseId = b.optionalString("exercise_id", max = 128)
                    var set: SetValues? = null
                    if (b.has("set")) {
                        val s = b.obj("set", SetValues.requiredKeys, SetValues.optionalKeys)
                        set = SetValues.read(s, requireRepsOrSeconds = false)
                    }
                    WatchMessageBody.SessionCommandBody(
                        SessionCommand(
                            sessionId = b.uuid("session_id"), commandId = b.uuid("command_id"),
                            command = command, set = set,
                            restSeconds = b.optionalInt("rest_seconds", min = 1, max = 3600),
                            exerciseId = exerciseId,
                        ),
                    )
                }
                "completed_workout" -> {
                    val b = body(setOf("workout", "last_sequence"), setOf("healthkit_workout_uuid", "program_day"))
                    val workout = b.dict["workout"] as? JsonObject ?: throw ContractException("invalid_value")
                    val origin = (workout["origin"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                    val workoutId = (workout["workout_id"] as? JsonPrimitive)?.takeIf { it.isString }?.content
                    if (origin != "beyondrep_watch" || workoutId == null) throw ContractException("invalid_value")
                    val lastSequence = b.int("last_sequence")
                    val healthkitUuid = if (b.has("healthkit_workout_uuid")) b.uuid("healthkit_workout_uuid") else null
                    if (b.has("program_day")) {
                        val d = b.obj("program_day", setOf("plan_id", "program_id", "local_date"))
                        d.string("plan_id", max = 128)
                        d.string("program_id", max = 128)
                        d.localDate("local_date")
                    }
                    WatchMessageBody.CompletedWorkout(workoutId, lastSequence, healthkitUuid, b.dict)
                }
                "workout_link" -> {
                    val b = body(setOf("workout_id", "healthkit_workout_uuid"))
                    WatchMessageBody.WorkoutLink(b.uuid("workout_id"), b.uuid("healthkit_workout_uuid"))
                }
                "workout_health" -> {
                    val b = body(setOf("workout_id", "start_utc", "end_utc", "heart_rate"), setOf("total_kcal"))
                    val workoutId = b.uuid("workout_id")
                    val startText = b.dateTime("start_utc")
                    val endText = b.dateTime("end_utc")
                    val start = WatchTimestamp.milliseconds(startText) ?: throw ContractException("invalid_value")
                    val end = WatchTimestamp.milliseconds(endText) ?: throw ContractException("invalid_value")
                    if (end <= start) throw ContractException("invalid_value")
                    var previous = Long.MIN_VALUE
                    val points = b.array("heart_rate", max = 600).map { item ->
                        val p = StrictObject(item, setOf("at_utc", "bpm"))
                        val at = p.dateTime("at_utc")
                        val atMs = WatchTimestamp.milliseconds(at) ?: throw ContractException("invalid_value")
                        // Inside the workout and strictly increasing; JSON Schema cannot say so.
                        if (atMs < start || atMs > end || atMs <= previous) throw ContractException("invalid_value")
                        previous = atMs
                        HeartRatePoint(at, p.int("bpm", min = 25, max = 250))
                    }
                    var kcal: Double? = null
                    if (b.has("total_kcal")) {
                        kcal = StrictObject.numberOf(b.dict["total_kcal"])
                        if (!(kcal > 0 && kcal <= 10_000)) throw ContractException("invalid_value")
                    }
                    WatchMessageBody.WorkoutHealth(workoutId, startText, endText, points, kcal)
                }
                "join" -> {
                    val b = body(emptySet(), setOf("session_id"))
                    WatchMessageBody.Join(if (b.has("session_id")) b.uuid("session_id") else null)
                }
                else -> {
                    val b = body(setOf("acked_message_id", "result"), setOf("reason"))
                    val acked = b.uuid("acked_message_id")
                    val result = b.oneOf("result", setOf("stored", "duplicate", "rejected"))
                    val reason = if (b.has("reason")) {
                        b.oneOf("reason", setOf("wrong_account", "invalid", "unsupported_version", "not_written"))
                    } else {
                        null
                    }
                    // `not_written` goes with `rejected` only.
                    if (reason == "not_written" && result != "rejected") throw ContractException("invalid_value")
                    WatchMessageBody.Ack(acked, result, reason)
                }
            }
            return WatchMessage(messageId, sentAtUtc, accountKey, parsed)
        }

        private fun checkSessionState(b: StrictObject): WatchMessageBody {
            val sessionId = b.uuid("session_id")
            b.oneOf("owner", setOf("watch", "phone"))
            val status = b.oneOf("status", setOf("active", "paused", "ended"))
            // `end_reason` goes with `ended` and `paused_at_utc` with `paused`.
            if (b.has("end_reason") != (status == "ended") || (b.has("paused_at_utc") && status != "paused")) {
                throw ContractException("invalid_value")
            }
            if (b.has("end_reason")) b.oneOf("end_reason", setOf("completed", "discarded"))
            if (b.has("paused_at_utc")) b.dateTime("paused_at_utc")
            b.optionalInt("paused_seconds")
            if (b.has("applied_command_ids")) {
                for (item in b.array("applied_command_ids", max = 20)) {
                    StrictObject(JsonObject(mapOf("id" to item)), setOf("id")).uuid("id")
                }
            }
            if (b.has("rejected_commands")) {
                for (item in b.array("rejected_commands", max = 20)) {
                    val r = StrictObject(item, setOf("command_id", "reason"))
                    r.uuid("command_id")
                    r.oneOf("reason", setOf("unknown_session", "unknown_set", "invalid_values", "not_allowed"))
                }
            }
            b.string("name", max = 120)
            b.dateTime("started_at_utc")
            b.int("last_sequence")
            if (b.has("current_set_id")) b.uuid("current_set_id")
            if (b.has("rest_deadline_utc")) b.dateTime("rest_deadline_utc")
            for (item in b.array("exercises", max = 120)) {
                val x = StrictObject(item, setOf("exercise_id", "name", "kind", "sets"))
                x.string("exercise_id", max = 128)
                x.string("name", max = 120)
                x.oneOf("kind", setOf("reps", "duration"))
                for (entry in x.array("sets", max = 300)) {
                    val s = StrictObject(
                        entry, setOf("set_id", "position", "kind", "status"),
                        setOf("input_unit", "rest_seconds") + SetValues.optionalKeys)
                    s.uuid("set_id")
                    s.int("position")
                    s.oneOf("kind", setOf("working", "warmup"))
                    s.oneOf("status", setOf("planned", "completed", "skipped"))
                    if (s.has("input_unit")) s.oneOf("input_unit", setOf("kg", "lb"))
                    s.optionalInt("rest_seconds", min = 1, max = 3600)
                    s.optionalInt("reps")
                    s.optionalInt("duration_seconds", min = 1)
                    s.optionalInt("load_grams")
                    s.optionalRpe("rpe")
                }
            }
            return WatchMessageBody.SessionState(sessionId, b.dict)
        }

        private fun checkPlan(raw: JsonElement) {
            val p = StrictObject(raw, setOf("plan_id", "name", "exercises"))
            p.string("plan_id", max = 128)
            p.string("name", max = 120)
            for (item in p.array("exercises", max = 40)) {
                val x = StrictObject(item, setOf("exercise_id", "name", "kind", "sets"), setOf("muscle"))
                x.string("exercise_id", max = 128)
                x.string("name", max = 120)
                x.oneOf("kind", setOf("reps", "duration"))
                x.optionalString("muscle", max = 60)
                for (entry in x.array("sets", max = 30)) {
                    val s = StrictObject(
                        entry, setOf("position", "kind"),
                        setOf("target_reps", "target_seconds", "target_load_grams", "rest_seconds"))
                    s.int("position")
                    s.oneOf("kind", setOf("working", "warmup"))
                    s.optionalInt("target_reps")
                    s.optionalInt("target_seconds", min = 1)
                    s.optionalInt("target_load_grams")
                    s.optionalInt("rest_seconds", max = 3600)
                }
            }
        }
    }
}
