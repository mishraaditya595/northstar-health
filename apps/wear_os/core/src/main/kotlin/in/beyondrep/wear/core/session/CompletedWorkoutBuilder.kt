package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.EventHeader
import `in`.beyondrep.wear.core.contracts.StrictObject
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.DateTimeException
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Builds the `completed_workout` message for a finished watch session from its events and template
 * (port of CompletedWorkoutBuilder.swift). The message holds no health values: only the optional
 * HealthKit workout UUID travels with it (Wear passes null).
 */
object CompletedWorkoutBuilder {
    /** The muscle names the cloud workout payload accepts in `primary_muscles`. */
    private val knownMuscles = setOf(
        "chest", "shoulders", "biceps", "forearms", "abs", "obliques", "quads", "calves", "traps",
        "lats", "lowerBack", "triceps", "glutes", "hamstrings",
    )

    fun message(
        events: List<WorkoutEventV2>,
        template: WorkoutTemplate,
        unit: String,
        accountKey: String,
        healthkitWorkoutUuid: String?,
        messageId: String,
        sentAtUtc: String,
    ): WatchMessage {
        val state = WorkoutReplay.replay(events)
        if (state.status != "completed" || state.completedSets < 1) throw SessionException(SessionError.INVALID_TRANSITION)

        val seen = mutableSetOf<String>()
        val ordered = events.filter { seen.add(it.header.eventId) }.sortedBy { it.header.sequence }
        var startedName: String? = null
        var startedAt: String? = null
        var startedHeader: EventHeader? = null
        var completedAt: String? = null
        val lastOccurred = mutableMapOf<String, String>()
        val lastUnit = mutableMapOf<String, String>()
        for (event in ordered) {
            val header = event.header
            when (event) {
                is WorkoutEventV2.WorkoutStarted -> if (startedName == null) {
                    startedName = event.payload.name
                    startedAt = header.occurredAtUtc
                    startedHeader = header
                }
                is WorkoutEventV2.WorkoutCompleted -> completedAt = header.occurredAtUtc
                is WorkoutEventV2.SetLogged -> {
                    lastOccurred[event.values.setId] = header.occurredAtUtc
                    lastUnit[event.values.setId] = event.values.inputUnit
                }
                is WorkoutEventV2.SetCorrected -> {
                    lastOccurred[event.values.setId] = header.occurredAtUtc
                    lastUnit[event.values.setId] = event.values.inputUnit
                }
                is WorkoutEventV2.SetSkipped -> lastOccurred[event.setId] = header.occurredAtUtc
                else -> Unit
            }
        }
        val name = startedName
        val started = startedAt
        val completed = completedAt
        val firstHeader = startedHeader
        if (name == null || started == null || completed == null || firstHeader == null) {
            throw SessionException(SessionError.INVALID_TRANSITION)
        }

        val startInstant = WatchTimestamp.instant(started) ?: Instant.EPOCH
        // The offset of the event time zone at the start instant (not "now"), so a session that
        // started just before a daylight-saving change keeps the offset it began in.
        val zone = try {
            ZoneId.of(firstHeader.timeZone)
        } catch (_: DateTimeException) {
            ZoneOffset.UTC
        }
        val offsetMinutes = zone.rules.getOffset(startInstant).totalSeconds / 60

        val replayed = state.sets.associateBy { it.setId }
        val exercises = mutableListOf<JsonElement>()
        for (exercise in template.exercises.sortedBy { it.position }) {
            val sets = mutableListOf<JsonElement>()
            for (set in exercise.sets.sortedBy { it.position }) {
                val done = replayed[set.setId] ?: continue
                // A skipped set has no logged kind, so it takes the template's.
                val kind = if (done.status == "skipped") set.kind else done.kind
                val item = linkedMapOf<String, JsonElement>(
                    "id" to JsonPrimitive(set.setId), "position" to JsonPrimitive(set.position), "kind" to JsonPrimitive(kind))
                if (done.status == "skipped") {
                    item["status"] = JsonPrimitive("skipped")
                    item["input_unit"] = JsonPrimitive(unit)
                } else {
                    item["status"] = JsonPrimitive("completed")
                    item["input_unit"] = JsonPrimitive(lastUnit[set.setId] ?: unit)
                    done.reps?.let { item["reps"] = JsonPrimitive(it) }
                    done.durationSeconds?.let { item["duration_seconds"] = JsonPrimitive(it) }
                    done.loadGrams?.takeIf { it > 0 }?.let { item["load_grams"] = JsonPrimitive(it) }
                    done.rpe?.let { item["rpe"] = StrictObject.number(it) }
                    item["completed_at_utc"] = JsonPrimitive(lastOccurred[set.setId] ?: completed)
                }
                sets.add(JsonObject(item))
            }
            if (sets.isEmpty()) continue
            val item = linkedMapOf<String, JsonElement>(
                "id" to JsonPrimitive(exercise.exerciseId), "name" to JsonPrimitive(exercise.name),
                "position" to JsonPrimitive(exercise.position), "sets" to JsonArray(sets))
            exercise.muscle?.let {
                item["muscle"] = JsonPrimitive(it)
                if (it in knownMuscles) item["primary_muscles"] = JsonArray(listOf(JsonPrimitive(it)))
            }
            exercises.add(JsonObject(item))
        }

        val workout = JsonObject(
            mapOf(
                "schema_version" to JsonPrimitive(1), "workout_id" to JsonPrimitive(firstHeader.workoutId),
                "origin" to JsonPrimitive("beyondrep_watch"), "status" to JsonPrimitive("completed"),
                "name" to JsonPrimitive(name), "started_at_utc" to JsonPrimitive(started),
                "completed_at_utc" to JsonPrimitive(completed),
                "original_offset_minutes" to JsonPrimitive(offsetMinutes), "exercises" to JsonArray(exercises),
            ),
        )
        val lastSequence = ordered.maxOfOrNull { it.header.sequence } ?: 0
        val body = linkedMapOf<String, JsonElement>("workout" to workout, "last_sequence" to JsonPrimitive(lastSequence))
        healthkitWorkoutUuid?.let { body["healthkit_workout_uuid"] = JsonPrimitive(it) }
        template.programDay?.let {
            body["program_day"] = JsonObject(
                mapOf(
                    "plan_id" to JsonPrimitive(it.planId), "program_id" to JsonPrimitive(it.programId),
                    "local_date" to JsonPrimitive(it.localDate),
                ),
            )
        }
        val message = WatchMessage(
            messageId, sentAtUtc, accountKey,
            WatchMessageBody.CompletedWorkout(firstHeader.workoutId, lastSequence, healthkitWorkoutUuid, JsonObject(body)))
        // A strict-codec failure throws here rather than at the phone.
        WatchMessage.decode(message.encode())
        return message
    }
}
