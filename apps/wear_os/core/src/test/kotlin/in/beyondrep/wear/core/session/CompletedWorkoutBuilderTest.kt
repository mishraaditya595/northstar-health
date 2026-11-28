package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.FixtureLoader
import `in`.beyondrep.wear.core.JsonAssert
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.nio.file.Files
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of CompletedWorkoutBuilderTests.swift. Events are built by EventFactory (the machine comes later). */
class CompletedWorkoutBuilderTest {
    private val key = "0123456789abcdef".repeat(4)

    @Test
    fun thereAreAtLeastTwoGoldenCases() {
        assertTrue(FixtureLoader.files("contracts/watch_link/v1/cases/completed").size >= 2)
    }

    @TestFactory
    fun goldenCasesMatch(): List<DynamicTest> =
        FixtureLoader.files("contracts/watch_link/v1/cases/completed").map { file ->
            DynamicTest.dynamicTest(file.fileName.toString()) {
                val root = Json.parseToJsonElement(Files.readString(file)).jsonObject
                val events = root.getValue("events").jsonArray.map { WorkoutEventV2.fromElement(it) }
                val context = root.getValue("context").jsonObject
                val template = WorkoutTemplate.fromJson(context.getValue("template"))
                val message = CompletedWorkoutBuilder.message(
                    events = events, template = template, unit = context.getValue("unit").jsonPrimitive.content,
                    accountKey = context.getValue("account_key").jsonPrimitive.content,
                    healthkitWorkoutUuid = (context["healthkit_workout_uuid"] as? JsonPrimitive)?.content,
                    messageId = context.getValue("message_id").jsonPrimitive.content,
                    sentAtUtc = context.getValue("sent_at_utc").jsonPrimitive.content)
                JsonAssert.assertEqualTrees(
                    root["expected"], Json.parseToJsonElement(message.encode()), file.fileName.toString())
            }
        }

    private fun build(events: List<WorkoutEventV2>, template: WorkoutTemplate, uuid: String? = null): WatchMessage =
        CompletedWorkoutBuilder.message(
            events, template, "kg", key, uuid, "77777777-3333-4333-8333-0000000000b1", "2026-10-23T11:40:05Z")

    private fun values(template: WorkoutTemplate) = SetValues(
        template.exercises[0].sets[0].setId, template.exercises[0].exerciseId, 0, reps = 8, loadGrams = 60000)

    private fun body(message: WatchMessage): JsonObject = Json.parseToJsonElement(message.encode()).jsonObject.getValue("body").jsonObject

    @Test
    fun throwsWhenNotCompleted() {
        val template = TemplateFixtures.template()
        val f = EventFactory()
        f.start(template)
        f.log(values(template))
        val error = assertFailsWith<SessionException> { build(f.events, template) }
        assertEquals(SessionError.INVALID_TRANSITION, error.error)
    }

    @Test
    fun throwsWhenNoCompletedSet() {
        val template = TemplateFixtures.template()
        val f = EventFactory()
        f.start(template)
        f.complete()
        val error = assertFailsWith<SessionException> { build(f.events, template) }
        assertEquals(SessionError.INVALID_TRANSITION, error.error)
    }

    @Test
    fun outputDecodesWithStrictCodec() {
        val template = TemplateFixtures.template()
        val f = EventFactory()
        f.start(template)
        f.log(values(template))
        f.complete()
        val decoded = WatchMessage.decode(build(f.events, template).encode())
        val b = assertIs<WatchMessageBody.CompletedWorkout>(decoded.body)
        assertEquals("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", b.workoutId)
        assertEquals(4, b.lastSequence)
        assertNull(b.healthkitWorkoutUuid)
    }

    @Test
    fun unknownMuscleKeepsMuscleButOmitsPrimaryMuscles() {
        var template = TemplateFixtures.template()
        template = template.copy(exercises = listOf(template.exercises[0].copy(muscle = "Synthetic muscle")) + template.exercises.drop(1))
        val f = EventFactory()
        f.start(template)
        f.log(values(template))
        f.complete()
        val workout = body(build(f.events, template)).getValue("workout").jsonObject
        val exercise = workout.getValue("exercises").jsonArray.first().jsonObject
        assertEquals("Synthetic muscle", exercise.getValue("muscle").jsonPrimitive.content)
        assertFalse("primary_muscles" in exercise)
    }

    @Test
    fun skippedWarmupIsSentAsWarmup() {
        val template = TemplateFixtures.template()
        val press = template.exercises[0]
        assertEquals("warmup", press.sets[0].kind)
        val f = EventFactory()
        f.start(template)
        f.skip(press.sets[0].setId)
        f.log(SetValues(press.sets[1].setId, press.exerciseId, 1, reps = 8, loadGrams = 60000))
        f.complete()
        val workout = body(build(f.events, template)).getValue("workout").jsonObject
        val sets = workout.getValue("exercises").jsonArray.first().jsonObject.getValue("sets").jsonArray
        assertEquals("skipped", sets[0].jsonObject.getValue("status").jsonPrimitive.content)
        assertEquals("warmup", sets[0].jsonObject.getValue("kind").jsonPrimitive.content)
        assertEquals("working", sets[1].jsonObject.getValue("kind").jsonPrimitive.content)
    }

    private fun offsetFor(start: String): Int {
        val template = TemplateFixtures.template()
        val f = EventFactory(timeZone = "America/New_York", now = Instant.parse(start))
        f.start(template)
        f.log(values(template))
        f.now = Instant.parse("2026-03-08T08:00:00Z")
        f.complete()
        return body(build(f.events, template)).getValue("workout").jsonObject
            .getValue("original_offset_minutes").jsonPrimitive.content.toInt()
    }

    @Test
    fun offsetUsesZoneAtStartInstant() {
        // New York switches to daylight time at 2026-03-08T07:00:00Z.
        assertEquals(-300, offsetFor("2026-03-08T06:30:00Z"))
        assertEquals(-240, offsetFor("2026-03-08T07:30:00Z"))
    }

    @Test
    fun omitsHealthkitUuidWhenNull() {
        val template = TemplateFixtures.template()
        val f = EventFactory()
        f.start(template)
        f.log(values(template))
        f.complete()
        val message = build(f.events, template, uuid = null)
        assertFalse("healthkit_workout_uuid" in body(message))
        WatchMessage.decode(message.encode())
        val withUuid = build(f.events, template, uuid = "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
        assertEquals("cccccccc-cccc-4ccc-8ccc-cccccccccccc", body(withUuid).getValue("healthkit_workout_uuid").jsonPrimitive.content)
    }
}

