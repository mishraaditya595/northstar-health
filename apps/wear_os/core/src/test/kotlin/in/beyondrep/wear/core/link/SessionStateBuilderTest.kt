package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.FixtureLoader
import `in`.beyondrep.wear.core.JsonAssert
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import `in`.beyondrep.wear.core.session.EventFactory
import `in`.beyondrep.wear.core.session.TemplateFixtures
import `in`.beyondrep.wear.core.session.WorkoutTemplate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Port of SessionStateBuilderTests.swift. Events are built by EventFactory (the machine comes later). */
class SessionStateBuilderTest {
    private val key = "0123456789abcdef".repeat(4)

    @Test
    fun thereAreAtLeastFourGoldenCases() {
        assertTrue(FixtureLoader.files("contracts/watch_link/v1/cases/session_state").size >= 4)
    }

    @TestFactory
    fun goldenCasesMatch(): List<DynamicTest> =
        FixtureLoader.files("contracts/watch_link/v1/cases/session_state").map { file ->
            DynamicTest.dynamicTest(file.fileName.toString()) {
                val root = Json.parseToJsonElement(Files.readString(file)).jsonObject
                val events = root.getValue("events").jsonArray.map { WorkoutEventV2.fromElement(it) }
                val context = root.getValue("context").jsonObject
                val template = WorkoutTemplate.fromJson(context.getValue("template"))
                val rejected = (context["rejected_commands"] as? JsonArray ?: JsonArray(emptyList())).map {
                    val o = it.jsonObject
                    SessionStateBuilder.Rejection(
                        o["command_id"]?.jsonPrimitive?.content ?: "", o["reason"]?.jsonPrimitive?.content ?: "")
                }
                val message = SessionStateBuilder.message(
                    events = events, template = template, unit = context.getValue("unit").jsonPrimitive.content,
                    accountKey = context.getValue("account_key").jsonPrimitive.content,
                    messageId = context.getValue("message_id").jsonPrimitive.content,
                    sentAtUtc = context.getValue("sent_at_utc").jsonPrimitive.content,
                    appliedCommandIds = (context["applied_command_ids"] as? JsonArray)?.map { it.jsonPrimitive.content }
                        ?: emptyList(),
                    rejectedCommands = rejected)
                JsonAssert.assertEqualTrees(
                    root["expected"], Json.parseToJsonElement(message.encode()), file.fileName.toString())
            }
        }

    private fun started(): Pair<WorkoutTemplate, List<WorkoutEventV2>> {
        val template = TemplateFixtures.template()
        val f = EventFactory()
        f.start(template)
        return template to f.events.toList()
    }

    private fun ids() = (1..25).map { "88888888-4444-4444-8444-%012d".format(it) }

    private fun listed(message: `in`.beyondrep.wear.core.contracts.WatchMessage): List<String> {
        val raw = (message.body as WatchMessageBody.SessionState).raw
        return (raw["applied_command_ids"] as JsonArray).map { (it as JsonPrimitive).content }
    }

    @Test
    fun onlyTheNewestTwentyCommandIdsAreKept() {
        val (template, events) = started()
        val ids = ids()
        val message = SessionStateBuilder.message(
            events, template, "kg", key, "77777777-3333-4333-8333-0000000000f1", "2026-10-23T11:00:00Z",
            appliedCommandIds = ids)
        assertEquals(ids.takeLast(20), listed(message))
    }

    @Test
    fun confirmedCommandIdsStayListedEvenWhenOlderThanTheNewestTwenty() {
        val (template, events) = started()
        val ids = ids()
        val message = SessionStateBuilder.message(
            events, template, "kg", key, "77777777-3333-4333-8333-0000000000f1", "2026-10-23T11:00:00Z",
            appliedCommandIds = ids, confirmedCommandIds = listOf(ids[1]))
        val listed = listed(message)
        assertEquals(20, listed.size)
        assertEquals(ids[1], listed.last())
        assertEquals(ids.takeLast(19), listed.dropLast(1))
    }

    @Test
    fun anUnstartedEventListThrows() {
        val error = kotlin.test.assertFailsWith<`in`.beyondrep.wear.core.session.SessionException> {
            SessionStateBuilder.message(
                emptyList(), TemplateFixtures.template(), "kg", key, "77777777-3333-4333-8333-0000000000f1",
                "2026-10-23T11:00:00Z")
        }
        assertEquals(`in`.beyondrep.wear.core.session.SessionError.INVALID_TRANSITION, error.error)
    }
}

