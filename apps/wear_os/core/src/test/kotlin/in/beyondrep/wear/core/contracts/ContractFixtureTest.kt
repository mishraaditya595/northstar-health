package `in`.beyondrep.wear.core.contracts

import `in`.beyondrep.wear.core.FixtureLoader
import `in`.beyondrep.wear.core.JsonAssert
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of ContractFixtureTests.swift. */
class ContractFixtureTest {
    private fun roundTrips(dir: String, minimum: Int, decode: (String) -> Any, encode: (Any) -> String) {
        val files = FixtureLoader.files(dir)
        assertTrue(files.size >= minimum, dir)
        for (file in files) {
            val original = Files.readString(file)
            val again = encode(decode(original))
            JsonAssert.assertEqualTrees(
                Json.parseToJsonElement(original), Json.parseToJsonElement(again), file.fileName.toString())
        }
    }

    private fun rejects(dir: String, minimum: Int, decode: (String) -> Unit) {
        val files = FixtureLoader.files(dir)
        assertTrue(files.size >= minimum, dir)
        for (file in files) {
            assertFailsWith<ContractException>(file.fileName.toString()) { decode(Files.readString(file)) }
        }
    }

    @Test
    fun workoutSyncV2ValidFixturesRoundTrip() = roundTrips(
        "contracts/workout_sync/v2/fixtures/valid", 15,
        { WorkoutEventV2.decode(it) }, { (it as WorkoutEventV2).encode() })

    @Test
    fun workoutSyncV2InvalidFixturesAreRejected() =
        rejects("contracts/workout_sync/v2/fixtures/invalid", 14) { WorkoutEventV2.decode(it) }

    @Test
    fun v1EnvelopeIsUnsupportedVersion() {
        val text = FixtureLoader.text("contracts/workout_sync/v1/fixtures/valid/set_logged.json")
        val error = assertFailsWith<ContractException> { WorkoutEventV2.decode(text) }
        assertEquals("unsupported_version", error.code)
    }

    @Test
    fun watchLinkValidFixturesRoundTrip() = roundTrips(
        "contracts/watch_link/v1/fixtures/valid", 20,
        { WatchMessage.decode(it) }, { (it as WatchMessage).encode() })

    @Test
    fun watchLinkInvalidFixturesAreRejected() =
        rejects("contracts/watch_link/v1/fixtures/invalid", 25) { WatchMessage.decode(it) }

    @Test
    fun workoutHealthDecodesIntoATypedBody() {
        val full = WatchMessage.decode(
            FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/workout_health.json"))
        val body = assertIs<WatchMessageBody.WorkoutHealth>(full.body)
        assertEquals("workout_health", full.type)
        assertEquals("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", body.workoutId)
        assertEquals(listOf(71, 84, 96), body.heartRate.map { it.bpm })
        assertEquals(312.5, body.totalKcal)
        val minimal = WatchMessage.decode(
            FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/workout_health_minimal.json"))
        val minimalBody = assertIs<WatchMessageBody.WorkoutHealth>(minimal.body)
        assertTrue(minimalBody.heartRate.isEmpty())
        assertNull(minimalBody.totalKcal)
        val ack = WatchMessage.decode(
            FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/ack_not_written.json"))
        assertEquals("not_written", assertIs<WatchMessageBody.Ack>(ack.body).reason)
    }

    @Test
    fun notWrittenIsOnlyAllowedWithRejected() {
        val text = FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/ack_not_written.json")
        for (result in listOf("stored", "duplicate")) {
            assertFailsWith<ContractException>(result) {
                WatchMessage.decode(text.replace("\"rejected\"", "\"$result\""))
            }
        }
    }

    @Test
    fun workoutLinkAndJoinDecodeIntoTypedBodies() {
        val link = WatchMessage.decode(FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/workout_link.json"))
        val linkBody = assertIs<WatchMessageBody.WorkoutLink>(link.body)
        assertEquals("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", linkBody.workoutId)
        assertEquals("cccccccc-cccc-4ccc-8ccc-cccccccccccc", linkBody.healthkitWorkoutUuid)
        assertEquals("workout_link", link.type)
        val join = WatchMessage.decode(FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/join.json"))
        assertEquals("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", assertIs<WatchMessageBody.Join>(join.body).sessionId)
        val any = WatchMessage.decode(FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/join_any.json"))
        assertNull(assertIs<WatchMessageBody.Join>(any.body).sessionId)
        val phone = WatchMessage.decode(
            FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/session_state_phone.json"))
        assertIs<WatchMessageBody.SessionState>(phone.body)
    }

    @Test
    fun completedWorkoutProgramDayIsChecked() {
        WatchMessage.decode(
            FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/completed_workout_program_day.json"))
        for (name in listOf("completed_workout_program_day_bad_date", "completed_workout_program_day_extra_field")) {
            val text = FixtureLoader.text("contracts/watch_link/v1/fixtures/invalid/$name.json")
            assertFailsWith<ContractException>(name) { WatchMessage.decode(text) }
        }
    }

    @Test
    fun healthSnapshotStillRejectsUnknownKey() {
        val text = FixtureLoader.text("contracts/watch_link/v1/fixtures/valid/health_snapshot_full.json")
        val message = Json.parseToJsonElement(text).jsonObject
        val body = JsonObject(message.getValue("body").jsonObject + ("bedtime" to Json.parseToJsonElement("\"23:40\"")))
        val changed = JsonObject(message + ("body" to body)).toString()
        val error = assertFailsWith<ContractException> { WatchMessage.decode(changed) }
        assertEquals("unknown_key", error.code)
    }

    @Test
    fun replayCaseEventsDecode() {
        for (file in FixtureLoader.files("contracts/watch_link/v1/cases/replay")) {
            val obj = Json.parseToJsonElement(Files.readString(file)).jsonObject
            val events: JsonArray = obj["events"]?.jsonArray ?: JsonArray(emptyList())
            for (event in events) WorkoutEventV2.decode(event.toString())
        }
    }
}
