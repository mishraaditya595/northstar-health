package `in`.beyondrep.wear.core

import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.UUID

/** Synthetic watch_link messages for the inbox, journal and glance tests (TestMessages.swift). */
object TestMessages {
    val keyA = "0123456789abcdef".repeat(4)
    val keyB = "fedcba9876543210".repeat(4)

    fun id(): String = UUID.randomUUID().toString().lowercase()

    const val t0 = "2026-10-23T01:00:00Z"

    fun binding(key: String = keyA, unit: String = "kg", at: String = t0) =
        WatchMessage(id(), at, key, WatchMessageBody.AccountBinding(unit))

    fun cleared(key: String = keyA, wipe: Boolean = false, at: String = t0) =
        WatchMessage(id(), at, key, WatchMessageBody.AccountCleared(wipe))

    fun plans(
        key: String = keyA,
        names: List<String> = listOf("Synthetic push day"),
        today: Triple<String, String, String>? = null,
        exerciseCount: Int = 0,
    ): WatchMessage {
        val raw = linkedMapOf<String, JsonElement>(
            "generated_at_utc" to JsonPrimitive("2026-10-23T01:00:00Z"),
            "plans" to JsonArray(
                names.mapIndexed { i, name ->
                    JsonObject(
                        mapOf(
                            "plan_id" to JsonPrimitive("plan-$i"), "name" to JsonPrimitive(name),
                            "exercises" to JsonArray(
                                (0 until exerciseCount).map { n ->
                                    JsonObject(
                                        mapOf(
                                            "exercise_id" to JsonPrimitive("ex-$n"), "name" to JsonPrimitive("Move $n"),
                                            "kind" to JsonPrimitive("reps"), "sets" to JsonArray(emptyList()),
                                        ),
                                    )
                                },
                            ),
                        ),
                    )
                },
            ),
            "recent_exercises" to JsonArray(emptyList()),
        )
        if (today != null) {
            val (planId, label, date) = today
            raw["today"] = JsonObject(
                mapOf(
                    "plan_id" to JsonPrimitive(planId), "program_id" to JsonPrimitive("program-1"),
                    "local_date" to JsonPrimitive(date), "label" to JsonPrimitive(label),
                ),
            )
        }
        return WatchMessage(id(), "2026-10-23T01:00:00Z", key, WatchMessageBody.PlansSnapshot(JsonObject(raw)))
    }

    /** `asOf` 2026-10-23T01:40:00Z is 07:10 on 2026-10-23 in Asia/Kolkata. */
    fun health(
        key: String = keyA,
        localDate: String = "2026-10-23",
        asOf: String = "2026-10-23T01:40:00Z",
        extra: Map<String, JsonElement> = emptyMap(),
    ): WatchMessage {
        val raw = linkedMapOf<String, JsonElement>(
            "local_date" to JsonPrimitive(localDate), "as_of_utc" to JsonPrimitive(asOf),
            "readiness" to Json.parseToJsonElement(
                """{"score":72,"band":"good","headline":"Ready to train","reason":"Synthetic reason."}"""),
            "sleep" to Json.parseToJsonElement("""{"score":81,"asleep_minutes":432}"""),
            "resting_hr_bpm" to JsonPrimitive(54), "hrv_ms" to JsonPrimitive(62), "hrv_kind" to JsonPrimitive("rmssd"),
            "steps" to JsonPrimitive(1200),
        )
        raw.putAll(extra)
        return WatchMessage(id(), "2026-10-23T01:45:00Z", key, WatchMessageBody.HealthSnapshot(localDate, JsonObject(raw)))
    }
}
