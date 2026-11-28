package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.contracts.SessionCommand
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.session.TemplateFixtures
import `in`.beyondrep.wear.core.session.TemplateFixtures.counterIds
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.core.store.JournalFiles
import `in`.beyondrep.wear.core.store.WatchJournal
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of CommandApplierTests.swift. */
class CommandApplierTest {
    private val key = "0123456789abcdef".repeat(4)
    private val otherKey = "fedcba9876543210".repeat(4)
    private val base = Instant.ofEpochSecond(1_792_000_000)
    private var now = base
    private lateinit var files: JournalFiles
    private lateinit var journal: WatchJournal
    private var commandCounter = 0

    @BeforeEach
    fun setUp() {
        files = JournalFiles()
        journal = WatchJournal(files.db(), makeId = counterIds(5000))
        now = base
        commandCounter = 0
    }

    @AfterEach
    fun tearDown() = files.close()

    private fun start(): WorkoutController = WorkoutController.start(
        TemplateFixtures.template(), journal, key, "kg", "watch-installation-a", { now }, "Asia/Kolkata", counterIds(1000))

    private fun restore(): WorkoutController = assertNotNull(
        WorkoutController.restore(journal, key, "kg", "watch-installation-a", { now }, "Asia/Kolkata"))

    private fun newCommandId(): String {
        commandCounter += 1
        return "88888888-4444-4444-8444-%012d".format(commandCounter)
    }

    private fun message(
        c: WorkoutController, command: String, id: String? = null, session: String? = null, account: String? = null,
        set: SetValues? = null, restSeconds: Int? = null, exerciseId: String? = null,
    ): WatchMessage = WatchMessage(
        "77777777-3333-4333-8333-%012d".format(commandCounter + 5000), "2026-10-23T11:00:00Z", account ?: key,
        WatchMessageBody.SessionCommandBody(
            SessionCommand(session ?: c.sessionId, id ?: newCommandId(), command, set, restSeconds, exerciseId)))

    /** Values for the n-th template set (0 = warm-up, 1 = working, 2 = plank). */
    private fun values(c: WorkoutController, n: Int, reps: Int? = 8, seconds: Int? = null, load: Int? = 60000): SetValues {
        val sets = c.template.exercises.flatMap { e -> e.sets.map { e to it } }
        val (exercise, set) = sets[n]
        return SetValues(set.setId, exercise.exerciseId, set.position, set.kind, reps = reps, durationSeconds = seconds, loadGrams = load)
    }

    private fun eventTypes(c: WorkoutController): List<String> = journal.events(c.sessionId).map { it.type }

    private fun stateRaw(c: WorkoutController, id: String, at: String) =
        assertIs<WatchMessageBody.SessionState>(c.sessionState(id, at).body).raw

    private fun applied(raw: kotlinx.serialization.json.JsonObject): List<String> =
        (raw["applied_command_ids"] as? JsonArray)?.map { it.jsonPrimitive.content } ?: emptyList()

    @Test
    fun logThenCorrectGivesSetLoggedThenSetCorrected() {
        val c = start()
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "log_set", set = values(c, 1))))
        assertEquals(listOf("set_logged", "rest_started"), eventTypes(c).takeLast(2))
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "correct_set", set = values(c, 1, reps = 9))))
        assertEquals("set_corrected", eventTypes(c).last())
        assertEquals(9, c.state.sets.first().reps)
    }

    @Test
    fun correctSetOnANeverLoggedSetBecomesSetLoggedAndStartsRest() {
        val c = start()
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "correct_set", set = values(c, 1))))
        assertEquals(listOf("set_logged", "rest_started"), eventTypes(c).takeLast(2))
        assertFalse("set_corrected" in eventTypes(c))
        assertNotNull(c.restDeadline)
    }

    @Test
    fun oldDuplicateCommandIsStillListedInTheNextStateAfterTheWindowMoved() {
        val c = start()
        val first = newCommandId()
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "pause", id = first)))
        repeat(24) { c.apply(message(c, "clear_rest")) }
        val before = stateRaw(c, "77777777-3333-4333-8333-0000000000f4", "2026-10-23T11:05:00Z")
        assertFalse(first in applied(before))
        assertEquals(CommandOutcome.Duplicate, c.apply(message(c, "pause", id = first)))
        val listed = applied(stateRaw(c, "77777777-3333-4333-8333-0000000000f5", "2026-10-23T11:05:01Z"))
        assertTrue(listed.size <= 20)
        assertTrue(first in listed)
    }

    @Test
    fun logOnACompletedSetBecomesACorrection() {
        val c = start()
        c.apply(message(c, "log_set", set = values(c, 1)))
        c.apply(message(c, "log_set", set = values(c, 1, reps = 10)))
        assertEquals(1, eventTypes(c).count { it == "set_logged" })
        assertEquals(1, eventTypes(c).count { it == "set_corrected" })
    }

    @Test
    fun skipSet() {
        val c = start()
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "skip_set", set = values(c, 1))))
        assertEquals("skipped", c.state.sets.first().status)
    }

    @Test
    fun startAndClearRest() {
        val c = start()
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "start_rest", restSeconds = 60)))
        assertEquals(base.plusSeconds(60), c.restDeadline)
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "clear_rest")))
        assertNull(c.restDeadline)
    }

    @Test
    fun clearRestWithoutRestIsAppliedWithoutAnEvent() {
        val c = start()
        val before = eventTypes(c).size
        val id = newCommandId()
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "clear_rest", id = id)))
        assertEquals(before, eventTypes(c).size)
        assertEquals(CommandOutcome.Duplicate, c.apply(message(c, "clear_rest", id = id)))
    }

    @Test
    fun pauseAndResumeShowInState() {
        val c = start()
        now = base.plusSeconds(100)
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "pause")))
        assertEquals("paused", c.status)
        now = base.plusSeconds(160)
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "resume")))
        val raw = stateRaw(c, "77777777-3333-4333-8333-0000000000f2", "2026-10-23T11:05:00Z")
        assertEquals("active", raw.getValue("status").jsonPrimitive.content)
        assertEquals(60, raw.getValue("paused_seconds").jsonPrimitive.content.toInt())
        assertFalse("paused_at_utc" in raw)
    }

    @Test
    fun pauseWhilePausedIsRejectedNotAllowed() {
        val c = start()
        c.apply(message(c, "pause"))
        val before = eventTypes(c).size
        assertEquals(CommandOutcome.Rejected(RejectReason.NOT_ALLOWED), c.apply(message(c, "pause")))
        assertEquals(before, eventTypes(c).size)
    }

    @Test
    fun addSetAddsATemplateSet() {
        val c = start()
        val exerciseId = c.template.exercises[0].exerciseId
        val count = c.template.exercises[0].sets.size
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "add_set", exerciseId = exerciseId)))
        assertEquals(count + 1, c.template.exercises[0].sets.size)
        assertEquals(count + 1, restore().template.exercises[0].sets.size)
    }

    @Test
    fun addSetTwiceWithOneCommandIdAddsOnce() {
        val c = start()
        val exerciseId = c.template.exercises[0].exerciseId
        val count = c.template.exercises[0].sets.size
        val id = newCommandId()
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "add_set", id = id, exerciseId = exerciseId)))
        assertEquals(CommandOutcome.Duplicate, c.apply(message(c, "add_set", id = id, exerciseId = exerciseId)))
        assertEquals(count + 1, c.template.exercises[0].sets.size)
    }

    @Test
    fun addSetForAnUnknownExerciseIsRejected() {
        val c = start()
        assertEquals(
            CommandOutcome.Rejected(RejectReason.UNKNOWN_SET),
            c.apply(message(c, "add_set", exerciseId = "builtin.v1.not-in-this-workout")))
    }

    @Test
    fun finishRecordsCompletionAndAsksTheAppToFinishTheExerciseSession() {
        val c = start()
        c.apply(message(c, "log_set", set = values(c, 1)))
        assertEquals(CommandOutcome.NeedsFinish, c.apply(message(c, "finish")))
        assertEquals("completed", c.status)
        assertEquals(1, eventTypes(c).count { it == "workout_completed" })
    }

    @Test
    fun finishWithoutACompletedSetIsRejected() {
        val c = start()
        assertEquals(CommandOutcome.Rejected(RejectReason.NOT_ALLOWED), c.apply(message(c, "finish")))
        assertEquals("active", c.status)
    }

    @Test
    fun duplicateFinishIsAppliedOnce() {
        val c = start()
        c.apply(message(c, "log_set", set = values(c, 1)))
        val id = newCommandId()
        assertEquals(CommandOutcome.NeedsFinish, c.apply(message(c, "finish", id = id)))
        assertEquals(CommandOutcome.Duplicate, c.apply(message(c, "finish", id = id)))
        assertEquals(1, eventTypes(c).count { it == "workout_completed" })
    }

    @Test
    fun discard() {
        val c = start()
        assertEquals(CommandOutcome.Applied, c.apply(message(c, "discard")))
        assertEquals("abandoned", c.status)
    }

    @Test
    fun duplicateCommandIdIsAppliedOnce() {
        val c = start()
        val id = newCommandId()
        val command = message(c, "log_set", id = id, set = values(c, 1))
        assertEquals(CommandOutcome.Applied, c.apply(command))
        val count = eventTypes(c).size
        assertEquals(CommandOutcome.Duplicate, c.apply(command))
        assertEquals(CommandOutcome.Duplicate, c.apply(message(c, "log_set", id = id, set = values(c, 1, reps = 12))))
        assertEquals(count, eventTypes(c).size)
        assertEquals(listOf(id), applied(stateRaw(c, "77777777-3333-4333-8333-0000000000f3", "2026-10-23T11:05:00Z")))
    }

    @Test
    fun commandAfterRelaunchIsStillIdempotent() {
        val c = start()
        val id = newCommandId()
        c.apply(message(c, "log_set", id = id, set = values(c, 1)))
        val count = eventTypes(c).size
        val reopened = WatchJournal(files.db())
        val restored = assertNotNull(
            WorkoutController.restore(reopened, key, "kg", "watch-installation-a", { now }, "Asia/Kolkata"))
        assertEquals(CommandOutcome.Duplicate, restored.apply(message(restored, "log_set", id = id, set = values(restored, 1))))
        assertEquals(count, reopened.events(restored.sessionId).size)
    }

    @Test
    fun anotherAccountKeyIsIgnoredAndWritesNothing() {
        val c = start()
        val before = eventTypes(c).size
        assertEquals(CommandOutcome.Ignored, c.apply(message(c, "pause", account = otherKey)))
        assertEquals(before, eventTypes(c).size)
        assertEquals("active", c.status)
        assertTrue(journal.commandLog(c.sessionId).isEmpty())
    }

    @Test
    fun anotherSessionIdIsRejectedWithNoEvent() {
        val c = start()
        val before = eventTypes(c).size
        val outcome = c.apply(message(c, "pause", session = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"))
        assertEquals(CommandOutcome.Rejected(RejectReason.UNKNOWN_SESSION), outcome)
        assertEquals(before, eventTypes(c).size)
        assertEquals("active", c.status)
    }

    @Test
    fun unknownSetIsRejectedAndListedInState() {
        val c = start()
        val bogus = values(c, 1).copy(setId = "dddddddd-dddd-4ddd-8ddd-ffffffffffff")
        val before = eventTypes(c).size
        val id = newCommandId()
        assertEquals(CommandOutcome.Rejected(RejectReason.UNKNOWN_SET), c.apply(message(c, "log_set", id = id, set = bogus)))
        assertEquals(before, eventTypes(c).size)
        val raw = stateRaw(c, "77777777-3333-4333-8333-0000000000f4", "2026-10-23T11:05:00Z")
        val rejected = raw.getValue("rejected_commands").jsonArray
        assertEquals(id, rejected.first().jsonObject.getValue("command_id").jsonPrimitive.content)
        assertEquals("unknown_set", rejected.first().jsonObject.getValue("reason").jsonPrimitive.content)
        // A resend of a rejected command is a duplicate, not a second rejection.
        assertEquals(CommandOutcome.Duplicate, c.apply(message(c, "log_set", id = id, set = bogus)))
    }

    @Test
    fun setOfAnotherExerciseIsRejectedAsUnknownSet() {
        val c = start()
        val wrong = values(c, 1).copy(exerciseId = c.template.exercises[1].exerciseId)
        assertEquals(CommandOutcome.Rejected(RejectReason.UNKNOWN_SET), c.apply(message(c, "log_set", set = wrong)))
    }

    @Test
    fun invalidValuesAreRejectedWithNoEvent() {
        val c = start()
        val before = eventTypes(c).size
        val invalid = CommandOutcome.Rejected(RejectReason.INVALID_VALUES)
        // Negative reps.
        assertEquals(invalid, c.apply(message(c, "log_set", set = values(c, 1, reps = -1))))
        // A load on a duration exercise (the plank is the third set).
        assertEquals(invalid, c.apply(message(c, "log_set", set = values(c, 2, reps = null, seconds = 40, load = 20000))))
        // Reps on a duration exercise.
        assertEquals(invalid, c.apply(message(c, "log_set", set = values(c, 2, reps = 5, load = null))))
        // Seconds on a reps exercise.
        assertEquals(invalid, c.apply(message(c, "log_set", set = values(c, 1, reps = null, seconds = 30))))
        // Rest of 0 seconds.
        assertEquals(invalid, c.apply(message(c, "start_rest", restSeconds = 0)))
        assertEquals(invalid, c.apply(message(c, "start_rest")))
        assertEquals(before, eventTypes(c).size)
    }

    @Test
    fun logWhilePausedIsNotAllowed() {
        val c = start()
        c.apply(message(c, "pause"))
        assertEquals(CommandOutcome.Rejected(RejectReason.NOT_ALLOWED), c.apply(message(c, "log_set", set = values(c, 1))))
    }
}
