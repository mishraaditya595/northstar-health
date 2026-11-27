package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.TestMessages
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.session.TemplateFixtures.counterIds
import `in`.beyondrep.wear.core.store.FailingSqlDatabase
import `in`.beyondrep.wear.core.store.JournalFiles
import `in`.beyondrep.wear.core.store.WatchJournal
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of WorkoutControllerTests.swift. */
class WorkoutControllerTest {
    private val key = "0123456789abcdef".repeat(4)
    private val otherKey = "fedcba9876543210".repeat(4)
    private val base = Instant.ofEpochSecond(1_792_000_000)
    private var now = base
    private lateinit var files: JournalFiles
    private lateinit var failing: FailingSqlDatabase
    private lateinit var journal: WatchJournal
    private lateinit var ids: () -> String

    @BeforeEach
    fun setUp() {
        files = JournalFiles()
        failing = FailingSqlDatabase(files.db())
        journal = WatchJournal(failing, makeId = counterIds(5000))
        now = base
        ids = counterIds(1000)
    }

    @AfterEach
    fun tearDown() = files.close()

    private fun start(template: WorkoutTemplate, journal: WatchJournal = this.journal, makeId: () -> String = ids) =
        WorkoutController.start(
            template, journal, key, "kg", "watch-installation-a", { now }, "Asia/Kolkata", makeId)

    private fun restore(account: String? = null, journal: WatchJournal = this.journal) =
        WorkoutController.restore(journal, account ?: key, "kg", "watch-installation-a", { now }, "Asia/Kolkata")

    private fun logCurrent(controller: WorkoutController): SetValues {
        val current = assertNotNull(controller.cursor.current)
        val values = controller.cursor.prefill(current, "kg")
        controller.log(values)
        return values
    }

    @Test
    fun startCommitsStartedExercisesAndTemplate() {
        val template = TemplateFixtures.template()
        val controller = start(template)
        val active = assertNotNull(journal.activeSession(key))
        assertEquals(1 + template.exercises.size, active.events.size)
        assertEquals(controller.sessionId, active.sessionId)
        assertNotNull(journal.template(controller.sessionId))
        assertEquals("active", controller.status)
        assertEquals(base, controller.startedAt)
    }

    @Test
    fun logStartsRestWithPlanSeconds() {
        val template = TemplateFixtures.template()
        val controller = start(TemplateFixtures.template())
        logCurrent(controller)
        assertEquals(base.plusSeconds(90), controller.restDeadline)
        assertEquals(3 + 2, journal.activeSession(key)?.events?.size)

        val first = template.exercises[0]
        val changed = template.copy(
            exercises = listOf(first.copy(sets = listOf(first.sets[0].copy(restSeconds = 45)) + first.sets.drop(1))) +
                template.exercises.drop(1))
        val other = start(changed, WatchJournal(files.db("b.sqlite")), counterIds(3000))
        logCurrent(other)
        assertEquals(base.plusSeconds(45), other.restDeadline)
    }

    @Test
    fun setRpeCorrectsTheSet() {
        val controller = start(TemplateFixtures.template())
        val values = logCurrent(controller)
        controller.setRpe(values.setId, 8.0)
        val set = assertNotNull(controller.state.sets.firstOrNull { it.setId == values.setId })
        assertEquals(8.0, set.rpe)
        assertEquals(2, set.history.size)
        assertEquals(values.reps, set.reps)
    }

    @Test
    fun restoreAfterRelaunchKeepsCursorAndRest() {
        val controller = start(TemplateFixtures.template())
        logCurrent(controller)
        val restored = assertNotNull(restore())
        assertEquals(controller.cursor.current?.set?.setId, restored.cursor.current?.set?.setId)
        assertEquals(controller.restDeadline, restored.restDeadline)
        assertEquals(controller.template, restored.template)
        assertEquals(controller.sessionId, restored.sessionId)
        assertEquals(controller.state, restored.state)
    }

    @Test
    fun restoreIgnoresOtherAccount() {
        start(TemplateFixtures.template())
        assertNull(restore(account = otherKey))
    }

    @Test
    fun pauseAndResumeAreDurable() {
        val controller = start(TemplateFixtures.template())
        controller.pause()
        assertEquals("paused", restore()?.status)
        controller.resume()
        assertEquals("active", restore()?.status)
    }

    @Test
    fun extendAndSkipRest() {
        val controller = start(TemplateFixtures.template())
        logCurrent(controller)
        now = base.plusSeconds(50) // 40 s remain
        controller.extendRest()
        assertEquals(base.plusSeconds(50 + 70), controller.restDeadline)
        controller.skipRest()
        assertNull(controller.restDeadline)
        assertNull(restore()?.restDeadline)
    }

    @Test
    fun skipSetMovesTheCursorOn() {
        val controller = start(TemplateFixtures.template())
        val first = assertNotNull(controller.cursor.current)
        controller.skip(first.set.setId)
        assertNotEquals(first.set.setId, controller.cursor.current?.set?.setId)
    }

    @Test
    fun markCompletedDoesNotQueue() {
        val controller = start(TemplateFixtures.template())
        logCurrent(controller)
        controller.markCompleted()
        assertTrue(journal.pendingCompleted(10).isEmpty())
        assertEquals(listOf(controller.sessionId), WorkoutController.pendingFinish(journal, key))
        assertNull(restore())
    }

    @Test
    fun queueCompletedQueuesOnce() {
        val controller = start(TemplateFixtures.template())
        logCurrent(controller) // the warm-up, not counted
        logCurrent(controller) // the first working set
        controller.markCompleted()
        val uuid = "11111111-2222-4333-8444-555555555555"
        controller.queueCompleted(uuid)
        controller.queueCompleted(uuid)
        val queued = journal.pendingCompleted(10)
        assertEquals(1, queued.size)
        assertTrue(WorkoutController.pendingFinish(journal, key).isEmpty())
        assertEquals(uuid, assertIs<WatchMessageBody.CompletedWorkout>(queued[0].body).healthkitWorkoutUuid)
    }

    @Test
    fun addSetGoesToTheMostRecentlyLoggedExercise() {
        val controller = start(TemplateFixtures.template())
        val press = controller.template.exercises[0]
        val plank = controller.template.exercises[1]
        assertEquals(plank.exerciseId, controller.addSetExerciseId) // nothing logged: the last exercise
        controller.focus(press.exerciseId)
        assertEquals(press.exerciseId, controller.addSetExerciseId) // focused
        controller.focus(plank.exerciseId)
        logCurrent(controller) // the plank is focused, so it is logged first
        controller.focus(press.exerciseId)
        logCurrent(controller) // a press set
        assertEquals(press.exerciseId, controller.addSetExerciseId)
    }

    @Test
    fun onlyWarmupsCannotBeSaved() {
        val controller = start(TemplateFixtures.template())
        assertFalse(controller.canSave)
        logCurrent(controller) // the warm-up
        assertFalse(controller.canSave)
        logCurrent(controller) // the first working set
        assertTrue(controller.canSave)
    }

    @Test
    fun finishingSessionIsFoundAfterRestart() {
        val controller = start(TemplateFixtures.template())
        val sessionId = controller.sessionId
        logCurrent(controller)
        logCurrent(controller)
        controller.markCompleted()
        val reopened = WatchJournal(files.db())
        assertEquals(listOf(sessionId), WorkoutController.pendingFinish(reopened, key))
        val uuid = "11111111-2222-4333-8444-555555555555"
        WorkoutController.queuePendingFinish(sessionId, reopened, "kg", key, uuid, ids) { now }
        // A second recovery pass queues nothing more.
        WorkoutController.queuePendingFinish(sessionId, reopened, "kg", key, uuid, ids) { now }
        val queued = reopened.pendingCompleted(10)
        assertEquals(1, queued.size)
        assertEquals(uuid, assertIs<WatchMessageBody.CompletedWorkout>(queued[0].body).healthkitWorkoutUuid)
        assertEquals("queued", reopened.delivery(sessionId))
    }

    @Test
    fun finishUnderAccountAIsQueuedForAWhileBoundToB() {
        val controller = start(TemplateFixtures.template())
        logCurrent(controller) // the warm-up
        logCurrent(controller) // the first working set
        now = base.plusSeconds(600)
        controller.markCompleted()
        journal.saveBinding(TestMessages.binding(otherKey))

        assertTrue(WorkoutController.pendingFinish(journal, otherKey).isEmpty())
        val pending = WorkoutController.pendingFinishAllAccounts(journal)
        assertEquals(listOf(controller.sessionId), pending.map { it.sessionId })
        assertEquals(listOf(key), pending.map { it.accountKey })
        assertEquals(base.plusSeconds(600), WorkoutController.completedAt(controller.sessionId, journal))

        WorkoutController.queuePendingFinish(pending[0].sessionId, journal, null, pending[0].accountKey, null, ids) { now }
        assertEquals(listOf(key), journal.pendingCompleted(10).map { it.accountKey })
        // The bound account is B, so nothing is sendable: the workout waits.
        assertEquals(otherKey, journal.binding()?.accountKey)
        val counts = journal.waitingCounts(otherKey)
        assertEquals(0, counts.thisAccount)
        assertEquals(1, counts.otherAccounts)
        assertTrue(WorkoutController.pendingFinishAllAccounts(journal).isEmpty())
    }

    @Test
    fun discardQueuesNothing() {
        val controller = start(TemplateFixtures.template())
        logCurrent(controller)
        controller.discard()
        assertTrue(journal.pendingOutbox(50).isEmpty())
        assertEquals("abandoned", controller.status)
        assertNull(restore())
    }

    @Test
    fun addExerciseInQuickWorkout() {
        val controller = start(WorkoutTemplate.quick())
        val exerciseId = controller.addExercise("Synthetic curl", "reps", "biceps")
        val set = controller.template.exercises.first().sets.first()
        controller.log(SetValues(set.setId, exerciseId, 0, reps = 10, loadGrams = 15000))
        controller.markCompleted()
        controller.queueCompleted(null)
        val message = assertNotNull(journal.pendingCompleted(10).firstOrNull())
        val raw = assertIs<WatchMessageBody.CompletedWorkout>(message.body).raw
        val exercises = raw.getValue("workout").jsonObject.getValue("exercises").jsonArray
        assertEquals(1, exercises.size)
        assertEquals("Synthetic curl", exercises[0].jsonObject.getValue("name").jsonPrimitive.content)
        assertEquals(exerciseId, exercises[0].jsonObject.getValue("id").jsonPrimitive.content)
        assertNull(restore())
    }

    @Test
    fun addExerciseSurvivesRestore() {
        val controller = start(WorkoutTemplate.quick())
        val exerciseId = controller.addExercise("Synthetic curl", "reps", null)
        assertEquals(listOf(exerciseId), restore()?.template?.exercises?.map { it.exerciseId })
    }

    @Test
    fun addSetIsStoredWithTheTemplate() {
        val controller = start(TemplateFixtures.template())
        val exerciseId = controller.template.exercises[0].exerciseId
        val setId = controller.addSet(exerciseId)
        assertEquals(setId, restore()?.template?.exercises?.get(0)?.sets?.last()?.setId)
    }

    @Test
    fun cannotQueueWithoutCompletedSet() {
        val controller = start(TemplateFixtures.template())
        controller.markCompleted()
        assertFailsWith<SessionException> { controller.queueCompleted(null) }
        assertTrue(journal.pendingCompleted(10).isEmpty())
    }

    @Test
    fun failedCommitLeavesStateUnchanged() {
        val controller = start(TemplateFixtures.template())
        val before = controller.state
        val events = assertNotNull(journal.activeSession(key)).events.size
        failing.failAfter = { sql, _ -> sql.startsWith("INSERT INTO sessions") }
        val current = assertNotNull(controller.cursor.current)
        val values = controller.cursor.prefill(current, "kg")
        assertFailsWith<IllegalStateException> { controller.log(values) }
        assertEquals(before, controller.state)
        assertEquals(0, controller.state.completedSets)
        assertEquals(events, journal.activeSession(key)?.events?.size)
        // The sequence continues without a gap once the journal works again.
        failing.failAfter = null
        controller.log(values)
        assertEquals(emptyList(), controller.state.gaps)
        assertEquals(controller.state, restore()?.state)
    }

    @Test
    fun aFailedAddExerciseKeepsTemplateAndMachine() {
        val controller = start(WorkoutTemplate.quick())
        failing.failAfter = { sql, _ -> sql.startsWith("INSERT INTO sessions") }
        assertFailsWith<IllegalStateException> { controller.addExercise("Synthetic curl", "reps", null) }
        assertTrue(controller.template.exercises.isEmpty())
        assertEquals(1, controller.state.sets.size + 1)
        failing.failAfter = null
        controller.addExercise("Synthetic curl", "reps", null)
        assertEquals(emptyList(), controller.state.gaps)
    }
}

