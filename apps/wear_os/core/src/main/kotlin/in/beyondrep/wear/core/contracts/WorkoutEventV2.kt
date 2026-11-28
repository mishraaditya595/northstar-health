package `in`.beyondrep.wear.core.contracts

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

data class EventHeader(
    val eventId: String,
    val workoutId: String,
    val sessionId: String,
    val originDeviceId: String,
    val sequence: Int,
    val occurredAtUtc: String,
    val recordedAtUtc: String,
    val timeZone: String,
)

/** The values of one logged set (`set_logged`, `set_corrected`, commands). */
data class SetValues(
    val setId: String,
    val exerciseId: String,
    val position: Int,
    val kind: String = "working",
    val inputUnit: String = "kg",
    val reps: Int? = null,
    val durationSeconds: Int? = null,
    val loadGrams: Int? = null,
    val rpe: Double? = null,
) {
    internal fun toJson(): JsonObject {
        val out = linkedMapOf<String, JsonElement>(
            "set_id" to JsonPrimitive(setId), "exercise_id" to JsonPrimitive(exerciseId),
            "position" to StrictObject.number(position), "kind" to JsonPrimitive(kind),
            "input_unit" to JsonPrimitive(inputUnit),
        )
        reps?.let { out["reps"] = StrictObject.number(it) }
        durationSeconds?.let { out["duration_seconds"] = StrictObject.number(it) }
        loadGrams?.let { out["load_grams"] = StrictObject.number(it) }
        rpe?.let { out["rpe"] = StrictObject.number(it) }
        return JsonObject(out)
    }

    internal companion object {
        val requiredKeys = setOf("set_id", "exercise_id", "position", "kind", "input_unit")
        val optionalKeys = setOf("reps", "duration_seconds", "load_grams", "rpe")

        fun read(o: StrictObject, requireRepsOrSeconds: Boolean = true): SetValues {
            val values = SetValues(
                setId = o.uuid("set_id"),
                exerciseId = o.string("exercise_id", max = 128),
                position = o.int("position"),
                kind = o.oneOf("kind", setOf("working", "warmup")),
                inputUnit = o.oneOf("input_unit", setOf("kg", "lb")),
                reps = o.optionalInt("reps"),
                durationSeconds = o.optionalInt("duration_seconds", min = 1),
                loadGrams = o.optionalInt("load_grams"),
                rpe = o.optionalRpe("rpe"),
            )
            if (requireRepsOrSeconds && values.reps == null && values.durationSeconds == null) {
                throw ContractException("missing_field")
            }
            return values
        }
    }
}

data class WorkoutStartedPayload(
    val activityType: String = "traditional_strength_training",
    val name: String,
    val owner: String,
    val accountKey: String,
    val planId: String? = null,
    val programId: String? = null,
    val programLocalDate: String? = null,
)

data class ExerciseAddedPayload(
    val exerciseId: String,
    val name: String,
    val kind: String,
    val position: Int,
)

/** One `workout_sync/v2` event (port of WorkoutEventV2.swift). */
sealed interface WorkoutEventV2 {
    val header: EventHeader
    val type: String

    data class WorkoutStarted(override val header: EventHeader, val payload: WorkoutStartedPayload) : WorkoutEventV2 {
        override val type get() = "workout_started"
    }

    data class ExerciseAdded(override val header: EventHeader, val payload: ExerciseAddedPayload) : WorkoutEventV2 {
        override val type get() = "exercise_added"
    }

    data class SetLogged(override val header: EventHeader, val values: SetValues) : WorkoutEventV2 {
        override val type get() = "set_logged"
    }

    data class SetCorrected(
        override val header: EventHeader, val values: SetValues, val supersedesEventId: String,
    ) : WorkoutEventV2 {
        override val type get() = "set_corrected"
    }

    data class SetSkipped(override val header: EventHeader, val setId: String) : WorkoutEventV2 {
        override val type get() = "set_skipped"
    }

    data class RestStarted(override val header: EventHeader, val seconds: Int, val deadlineUtc: String) : WorkoutEventV2 {
        override val type get() = "rest_started"
    }

    data class RestCleared(override val header: EventHeader) : WorkoutEventV2 {
        override val type get() = "rest_cleared"
    }

    data class WorkoutPaused(override val header: EventHeader) : WorkoutEventV2 {
        override val type get() = "workout_paused"
    }

    data class WorkoutResumed(override val header: EventHeader) : WorkoutEventV2 {
        override val type get() = "workout_resumed"
    }

    data class WorkoutCompleted(override val header: EventHeader) : WorkoutEventV2 {
        override val type get() = "workout_completed"
    }

    data class WorkoutAbandoned(override val header: EventHeader) : WorkoutEventV2 {
        override val type get() = "workout_abandoned"
    }

    data class PlatformWorkoutExported(
        override val header: EventHeader, val platform: String, val externalRecordId: String,
    ) : WorkoutEventV2 {
        override val type get() = "platform_workout_exported"
    }

    fun encode(): String = StrictObject.encode(toJson())

    fun toJson(): JsonObject {
        val h = header
        return JsonObject(
            mapOf(
                "schema_version" to JsonPrimitive(2), "event_id" to JsonPrimitive(h.eventId),
                "workout_id" to JsonPrimitive(h.workoutId), "session_id" to JsonPrimitive(h.sessionId),
                "origin_device_id" to JsonPrimitive(h.originDeviceId),
                "sequence" to StrictObject.number(h.sequence), "type" to JsonPrimitive(type),
                "occurred_at_utc" to JsonPrimitive(h.occurredAtUtc),
                "recorded_at_utc" to JsonPrimitive(h.recordedAtUtc), "time_zone" to JsonPrimitive(h.timeZone),
                "payload" to payloadObject(),
            ),
        )
    }

    private fun payloadObject(): JsonObject = when (this) {
        is WorkoutStarted -> {
            val out = linkedMapOf<String, JsonElement>(
                "activity_type" to JsonPrimitive(payload.activityType), "name" to JsonPrimitive(payload.name),
                "owner" to JsonPrimitive(payload.owner), "account_key" to JsonPrimitive(payload.accountKey),
            )
            payload.planId?.let { out["plan_id"] = JsonPrimitive(it) }
            val program = payload.programId
            val date = payload.programLocalDate
            if (program != null && date != null) {
                out["program_day"] = JsonObject(
                    mapOf("program_id" to JsonPrimitive(program), "local_date" to JsonPrimitive(date)))
            }
            JsonObject(out)
        }
        is ExerciseAdded -> JsonObject(
            mapOf(
                "exercise_id" to JsonPrimitive(payload.exerciseId), "name" to JsonPrimitive(payload.name),
                "kind" to JsonPrimitive(payload.kind), "position" to StrictObject.number(payload.position),
            ),
        )
        is SetLogged -> values.toJson()
        is SetCorrected -> JsonObject(values.toJson() + ("supersedes_event_id" to JsonPrimitive(supersedesEventId)))
        is SetSkipped -> JsonObject(mapOf("set_id" to JsonPrimitive(setId)))
        is RestStarted -> JsonObject(
            mapOf("seconds" to StrictObject.number(seconds), "deadline_utc" to JsonPrimitive(deadlineUtc)))
        is PlatformWorkoutExported -> JsonObject(
            mapOf("platform" to JsonPrimitive(platform), "external_record_id" to JsonPrimitive(externalRecordId)))
        is RestCleared, is WorkoutPaused, is WorkoutResumed, is WorkoutCompleted, is WorkoutAbandoned ->
            JsonObject(emptyMap())
    }

    companion object {
        private val types = setOf(
            "workout_started", "exercise_added", "set_logged", "set_corrected", "set_skipped",
            "rest_started", "rest_cleared", "workout_paused", "workout_resumed",
            "workout_completed", "workout_abandoned", "platform_workout_exported",
        )

        fun decode(json: String): WorkoutEventV2 = fromElement(StrictObject.parse(json))

        fun fromElement(raw: JsonElement?): WorkoutEventV2 {
            val o = StrictObject(
                raw,
                required = setOf(
                    "schema_version", "event_id", "workout_id", "session_id", "origin_device_id",
                    "sequence", "type", "occurred_at_utc", "recorded_at_utc", "time_zone", "payload",
                ),
            )
            val version = StrictObject.numberOf(o.dict["schema_version"])
            if (version != 2.0) throw ContractException("unsupported_version")
            val typePrimitive = o.dict["type"] as? JsonPrimitive
            val type = typePrimitive?.takeIf { it.isString && it.content in types }?.content
                ?: throw ContractException("unknown_type")
            val header = EventHeader(
                eventId = o.uuid("event_id"),
                workoutId = o.uuid("workout_id"),
                sessionId = o.uuid("session_id"),
                originDeviceId = o.string("origin_device_id", max = 128),
                sequence = o.int("sequence"),
                occurredAtUtc = o.dateTime("occurred_at_utc"),
                recordedAtUtc = o.dateTime("recorded_at_utc"),
                timeZone = o.string("time_zone", max = 100),
            )
            val p = o.dict["payload"]
            return when (type) {
                "workout_started" -> {
                    val s = StrictObject(
                        p, setOf("activity_type", "name", "owner", "account_key"), setOf("plan_id", "program_day"))
                    var programId: String? = null
                    var programDate: String? = null
                    if (s.has("program_day")) {
                        val day = s.obj("program_day", setOf("program_id", "local_date"))
                        programId = day.string("program_id", max = 128)
                        programDate = day.localDate("local_date")
                    }
                    WorkoutStarted(
                        header,
                        WorkoutStartedPayload(
                            activityType = s.string("activity_type", max = 80),
                            name = s.string("name", max = 120),
                            owner = s.oneOf("owner", setOf("watch", "phone")),
                            accountKey = s.accountKey(),
                            planId = s.optionalString("plan_id", max = 128),
                            programId = programId, programLocalDate = programDate,
                        ),
                    )
                }
                "exercise_added" -> {
                    val s = StrictObject(p, setOf("exercise_id", "name", "kind", "position"))
                    ExerciseAdded(
                        header,
                        ExerciseAddedPayload(
                            exerciseId = s.string("exercise_id", max = 128),
                            name = s.string("name", max = 120),
                            kind = s.oneOf("kind", setOf("reps", "duration")),
                            position = s.int("position"),
                        ),
                    )
                }
                "set_logged" -> {
                    val s = StrictObject(p, SetValues.requiredKeys, SetValues.optionalKeys)
                    SetLogged(header, SetValues.read(s))
                }
                "set_corrected" -> {
                    val s = StrictObject(p, SetValues.requiredKeys + "supersedes_event_id", SetValues.optionalKeys)
                    SetCorrected(header, SetValues.read(s), s.uuid("supersedes_event_id"))
                }
                "set_skipped" -> SetSkipped(header, StrictObject(p, setOf("set_id")).uuid("set_id"))
                "rest_started" -> {
                    val s = StrictObject(p, setOf("seconds", "deadline_utc"))
                    RestStarted(header, s.int("seconds", min = 1, max = 3600), s.dateTime("deadline_utc"))
                }
                "platform_workout_exported" -> {
                    val s = StrictObject(p, setOf("platform", "external_record_id"))
                    PlatformWorkoutExported(
                        header, s.oneOf("platform", setOf("healthkit", "health_connect")),
                        s.string("external_record_id", max = 256))
                }
                else -> {
                    StrictObject(p, emptySet())
                    when (type) {
                        "rest_cleared" -> RestCleared(header)
                        "workout_paused" -> WorkoutPaused(header)
                        "workout_resumed" -> WorkoutResumed(header)
                        "workout_completed" -> WorkoutCompleted(header)
                        else -> WorkoutAbandoned(header)
                    }
                }
            }
        }
    }
}

