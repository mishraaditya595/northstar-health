package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.contracts.EventHeader
import `in`.beyondrep.wear.core.contracts.StrictObject
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import `in`.beyondrep.wear.core.contracts.WorkoutStartedPayload
import `in`.beyondrep.wear.core.session.RestClock
import `in`.beyondrep.wear.core.session.SessionError
import `in`.beyondrep.wear.core.session.SessionException
import `in`.beyondrep.wear.core.session.WorkoutCursor
import `in`.beyondrep.wear.core.session.WorkoutReplay
import `in`.beyondrep.wear.core.session.WorkoutTemplate
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Builds the `session_state` message the watch broadcasts while a workout it owns is live (port of
 * SessionStateBuilder.swift). It is a pure function of the session's events and template, so the
 * golden cases in `contracts/watch_link/v1/cases/session_state` pin it. The message holds no health values.
 */
object SessionStateBuilder {
    /** A command the watch refused, newest last. */
    data class Rejection(val commandId: String, val reason: String)

    fun message(
        events: List<WorkoutEventV2>,
        template: WorkoutTemplate,
        unit: String,
        accountKey: String,
        messageId: String,
        sentAtUtc: String,
        focusExerciseId: String? = null,
        appliedCommandIds: List<String> = emptyList(),
        confirmedCommandIds: List<String> = emptyList(),
        rejectedCommands: List<Rejection> = emptyList(),
    ): WatchMessage {
        val seen = mutableSetOf<String>()
        val ordered = events.filter { seen.add(it.header.eventId) }.sortedBy { it.header.sequence }
        val state = WorkoutReplay.replay(ordered)
        var startedHeader: EventHeader? = null
        var startedPayload: WorkoutStartedPayload? = null
        val lastUnit = mutableMapOf<String, String>()
        var pausedTotalMs = 0L
        var pausedSince: String? = null
        for (event in ordered) {
            when (event) {
                is WorkoutEventV2.WorkoutStarted -> if (startedHeader == null) {
                    startedHeader = event.header
                    startedPayload = event.payload
                }
                is WorkoutEventV2.SetLogged -> lastUnit[event.values.setId] = event.values.inputUnit
                is WorkoutEventV2.SetCorrected -> lastUnit[event.values.setId] = event.values.inputUnit
                is WorkoutEventV2.WorkoutPaused -> if (pausedSince == null) pausedSince = event.header.occurredAtUtc
                is WorkoutEventV2.WorkoutResumed, is WorkoutEventV2.WorkoutCompleted, is WorkoutEventV2.WorkoutAbandoned -> {
                    // A pause ends at the next resume, completion or discard.
                    val since = pausedSince
                    val from = since?.let { WatchTimestamp.milliseconds(it) }
                    val to = WatchTimestamp.milliseconds(event.header.occurredAtUtc)
                    if (since != null && from != null && to != null) {
                        pausedTotalMs += maxOf(0L, to - from)
                        pausedSince = null
                    }
                }
                else -> Unit
            }
        }
        val header = startedHeader
        val payload = startedPayload
        if (header == null || payload == null) throw SessionException(SessionError.INVALID_TRANSITION)

        val ended = state.status == "completed" || state.status == "abandoned"
        val status = if (ended) "ended" else state.status
        val body = linkedMapOf<String, JsonElement>(
            "session_id" to JsonPrimitive(header.sessionId), "owner" to JsonPrimitive(payload.owner),
            "status" to JsonPrimitive(status), "name" to JsonPrimitive(payload.name),
            "started_at_utc" to JsonPrimitive(header.occurredAtUtc),
            "last_sequence" to JsonPrimitive(ordered.maxOfOrNull { it.header.sequence } ?: 0),
        )
        if (ended) body["end_reason"] = JsonPrimitive(if (state.status == "completed") "completed" else "discarded")
        if (status == "paused" && pausedSince != null) body["paused_at_utc"] = JsonPrimitive(pausedSince)
        val pausedSeconds = (pausedTotalMs / 1000).toInt()
        if (pausedSeconds > 0) body["paused_seconds"] = JsonPrimitive(pausedSeconds)
        RestClock.deadline(ordered)?.let { body["rest_deadline_utc"] = JsonPrimitive(WatchTimestamp.format(it)) }
        if (!ended) {
            WorkoutCursor(template, state, focusExerciseId).current?.let {
                body["current_set_id"] = JsonPrimitive(it.set.setId)
            }
        }

        val done = state.sets.associateBy { it.setId }
        val exercises = mutableListOf<JsonElement>()
        for (exercise in template.exercises.sortedBy { it.position }) {
            val sets = mutableListOf<JsonElement>()
            for (set in exercise.sets.sortedBy { it.position }) {
                val item = linkedMapOf<String, JsonElement>("set_id" to JsonPrimitive(set.setId), "position" to JsonPrimitive(set.position))
                val replayed = done[set.setId]
                if (replayed != null) {
                    if (replayed.status == "skipped") {
                        item["kind"] = JsonPrimitive(set.kind)
                        item["status"] = JsonPrimitive("skipped")
                    } else {
                        item["kind"] = JsonPrimitive(replayed.kind)
                        item["status"] = JsonPrimitive("completed")
                        item["input_unit"] = JsonPrimitive(lastUnit[set.setId] ?: unit)
                        replayed.reps?.let { item["reps"] = JsonPrimitive(it) }
                        replayed.durationSeconds?.let { item["duration_seconds"] = JsonPrimitive(it) }
                        replayed.loadGrams?.takeIf { it > 0 }?.let { item["load_grams"] = JsonPrimitive(it) }
                        replayed.rpe?.let { item["rpe"] = StrictObject.number(it) }
                    }
                } else {
                    // A planned set carries its targets so a phone can prefill it.
                    item["kind"] = JsonPrimitive(set.kind)
                    item["status"] = JsonPrimitive("planned")
                    item["input_unit"] = JsonPrimitive(unit)
                    set.targetReps?.takeIf { it > 0 }?.let { item["reps"] = JsonPrimitive(it) }
                    set.targetSeconds?.takeIf { it > 0 }?.let { item["duration_seconds"] = JsonPrimitive(it) }
                    set.targetLoadGrams?.takeIf { it > 0 }?.let { item["load_grams"] = JsonPrimitive(it) }
                    set.restSeconds?.takeIf { it in 1..3600 }?.let { item["rest_seconds"] = JsonPrimitive(it) }
                }
                sets.add(JsonObject(item))
            }
            exercises.add(
                JsonObject(
                    mapOf(
                        "exercise_id" to JsonPrimitive(exercise.exerciseId), "name" to JsonPrimitive(exercise.name),
                        "kind" to JsonPrimitive(exercise.kind), "sets" to JsonArray(sets),
                    ),
                ),
            )
        }
        body["exercises"] = JsonArray(exercises)
        // At most 20, newest last. `confirmedCommandIds` are ids the phone sent again (a duplicate);
        // they stay listed even when older than the newest 20, so a retry of an old command is still confirmed.
        val confirmed = confirmedCommandIds.distinct().takeLast(20)
        val recent = appliedCommandIds.filter { it !in confirmed }.takeLast(20 - confirmed.size)
        val listed = recent + confirmed
        if (listed.isNotEmpty()) body["applied_command_ids"] = JsonArray(listed.map { JsonPrimitive(it) })
        if (rejectedCommands.isNotEmpty()) {
            body["rejected_commands"] = JsonArray(
                rejectedCommands.takeLast(20).map {
                    JsonObject(mapOf("command_id" to JsonPrimitive(it.commandId), "reason" to JsonPrimitive(it.reason)))
                },
            )
        }
        val message = WatchMessage(messageId, sentAtUtc, accountKey, WatchMessageBody.SessionState(header.sessionId, JsonObject(body)))
        // A strict-codec failure throws here rather than at the phone.
        WatchMessage.decode(message.encode())
        return message
    }
}
