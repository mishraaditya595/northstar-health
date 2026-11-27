package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.FixtureLoader
import `in`.beyondrep.wear.core.JsonAssert
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertTrue

/** Port of ReplayCaseTests.swift. */
class ReplayCaseTest {
    /** The replay result in the shape of a case's `expected` object. */
    private fun expectedShape(w: ReplayedWorkout): JsonObject {
        val sets = w.sets.map { s ->
            val d = linkedMapOf<String, JsonElement>(
                "set_id" to JsonPrimitive(s.setId), "status" to JsonPrimitive(s.status),
                "history" to JsonArray(s.history.map { JsonPrimitive(it) }),
            )
            s.reps?.let { d["reps"] = JsonPrimitive(it) }
            s.durationSeconds?.let { d["duration_seconds"] = JsonPrimitive(it) }
            s.loadGrams?.let { d["load_grams"] = JsonPrimitive(it) }
            s.rpe?.let { d["rpe"] = JsonPrimitive(it) }
            JsonObject(d)
        }
        return JsonObject(
            mapOf(
                "status" to JsonPrimitive(w.status), "sets" to JsonArray(sets),
                "volume_grams" to JsonPrimitive(w.volumeGrams), "completed_sets" to JsonPrimitive(w.completedSets),
                "gaps" to JsonArray(w.gaps.map { JsonPrimitive(it) }),
            ),
        )
    }

    @Test
    fun thereAreAtLeastEightReplayCases() {
        assertTrue(FixtureLoader.files("contracts/watch_link/v1/cases/replay").size >= 8)
    }

    @TestFactory
    fun everyReplayCaseMatches(): List<DynamicTest> =
        FixtureLoader.files("contracts/watch_link/v1/cases/replay").map { file ->
            DynamicTest.dynamicTest(file.fileName.toString()) {
                val obj = Json.parseToJsonElement(Files.readString(file)).jsonObject
                val events = obj.getValue("events").jsonArray.map { WorkoutEventV2.fromElement(it) }
                JsonAssert.assertEqualTrees(obj["expected"], expectedShape(WorkoutReplay.replay(events)), file.fileName.toString())
            }
        }
}
