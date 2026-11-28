package `in`.beyondrep.wear.workout

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.link.DataChange
import `in`.beyondrep.wear.core.link.DataLayerPaths
import `in`.beyondrep.wear.core.session.WorkoutTemplate
import `in`.beyondrep.wear.exercise.ExerciseOwner
import `in`.beyondrep.wear.exercise.SensorReading
import `in`.beyondrep.wear.exercise.SensorStart
import `in`.beyondrep.wear.link.RecordingItems
import `in`.beyondrep.wear.testing.OTHER_TEST_KEY
import `in`.beyondrep.wear.testing.TEST_KEY
import `in`.beyondrep.wear.testing.bindForTest
import `in`.beyondrep.wear.testing.syntheticTemplate
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WorkoutRunnerTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val dbName = "runner-test-${UUID.randomUUID()}.db"
    private lateinit var items: RecordingItems
    private lateinit var graph: WatchGraph
    private lateinit var template: WorkoutTemplate

    @Before
    fun setUp() {
        items = RecordingItems()
        graph = WatchGraph(context, dbName, items)
        graph.journal.bindForTest()
        template = syntheticTemplate()
    }

    private fun runner(sensors: FakeSensors, service: FakeServiceControl, haptics: RestHaptics? = null) = WorkoutRunner(
        graph, sensors, service, Instant::now, "watch-test", { "UTC" }, CoroutineScope(Dispatchers.Unconfined), haptics)

    private val t0 = Instant.parse("2026-10-23T11:00:00Z")
    private var now = t0

    /** A runner whose clock the test moves, so the workout has a real length. */
    private fun timedRunner(sensors: FakeSensors) = WorkoutRunner(
        graph, sensors, FakeServiceControl(), { now }, "watch-test", { "UTC" }, CoroutineScope(Dispatchers.Unconfined))

    /** The phone's ack of the queued completed workout, as the Data Layer would deliver it. */
    private suspend fun ackCompleted(result: String = "stored") {
        val completed = withContext(graph.dispatcher) { graph.journal.pendingCompleted(5).single() }
        val ack = WatchMessage(
            UUID.randomUUID().toString(), "2026-10-23T11:41:00Z", TEST_KEY,
            WatchMessageBody.Ack(completed.messageId, result, null))
        withContext(graph.dispatcher) {
            graph.link.onChanges(listOf(DataChange(DataLayerPaths.phoneQueue(ack.messageId), ack.encode(), deleted = false)))
        }
    }

    private suspend fun pendingSeries() = withContext(graph.dispatcher) { graph.journal.pendingWorkoutHealth(TEST_KEY, 5) }

    private suspend fun activeSessions() = withContext(graph.dispatcher) { graph.journal.activeSessionAccounts() }

    private suspend fun untilIdle(runner: WorkoutRunner) = withTimeout(5_000) {
        while (runner.state.value !is RunnerState.Idle) delay(10)
    }

    private fun running(runner: WorkoutRunner) = assertIs<RunnerState.Running>(runner.state.value)

    private fun values(index: Int = 0): SetValues {
        val set = template.exercises[0].sets[index]
        return SetValues(set.setId, "ex-1", set.position, reps = 5, loadGrams = 40_000)
    }

    @Test
    fun startCreatesSessionStartsSensorsAndService() = runBlocking<Unit> {
        val sensors = FakeSensors()
        val service = FakeServiceControl()
        val runner = runner(sensors, service)
        runner.start(template)
        assertIs<RunnerState.Running>(runner.state.value)
        assertEquals(1, sensors.started)
        assertTrue(service.started)
        assertNotNull(withContext(graph.dispatcher) { graph.journal.activeSession(TEST_KEY) })
    }

    @Test
    fun anotherAppsExerciseBlocksStartWithoutAJournalSession() = runBlocking<Unit> {
        val sensors = FakeSensors(owner = ExerciseOwner.OTHER_APP)
        val service = FakeServiceControl()
        val runner = runner(sensors, service)
        runner.start(template)
        val blocked = assertIs<RunnerState.Blocked>(runner.state.value)
        assertEquals("Another workout app is recording. End it there first.", blocked.reason)
        assertNull(withContext(graph.dispatcher) { graph.journal.activeSession(TEST_KEY) })
        assertEquals(0, sensors.started)
        assertFalse(service.started)
    }

    @Test
    fun deniedHeartRateStillRecords() = runBlocking<Unit> {
        val sensors = FakeSensors(startResult = SensorStart(heartRate = false, calories = false))
        val runner = runner(sensors, FakeServiceControl())
        runner.start(template)
        val state = running(runner)
        assertNull(state.heartRate)
        assertFalse(state.hrAvailable)
        runner.log(values())
        assertEquals(1, running(runner).controller.state.completedSets)
    }

    @Test
    fun finishQueuesFlushesStopsAndSummarises() = runBlocking<Unit> {
        val sensors = FakeSensors(
            scripted = listOf(
                SensorReading.HeartRate(70.0, Instant.now()),
                SensorReading.HeartRate(72.0, Instant.now()),
                SensorReading.Calories(100.4),
            ),
        )
        val service = FakeServiceControl()
        val runner = runner(sensors, service)
        runner.start(template)
        runner.log(values())
        runner.finish()
        val finished = assertIs<RunnerState.Finished>(runner.state.value)
        assertEquals(1, finished.summary.sets)
        assertEquals(71, finished.summary.averageHeartRate)
        assertEquals(100, finished.summary.totalCalories)
        assertEquals(1, items.puts.size)
        assertTrue(items.puts.single().second.contains("completed_workout"))
        assertTrue(service.stopped)
        assertEquals(1, sensors.ended)
    }

    @Test
    fun finishWithoutHeartRateHasNullAverage() = runBlocking<Unit> {
        val runner = runner(FakeSensors(startResult = SensorStart(false, false)), FakeServiceControl())
        runner.start(template)
        runner.log(values())
        runner.finish()
        val finished = assertIs<RunnerState.Finished>(runner.state.value)
        assertNull(finished.summary.averageHeartRate)
        assertNull(finished.summary.totalCalories)
    }

    @Test
    fun discardSendsNothing() = runBlocking<Unit> {
        val sensors = FakeSensors()
        val service = FakeServiceControl()
        val runner = runner(sensors, service)
        runner.start(template)
        runner.log(values())
        runner.discard()
        assertIs<RunnerState.Idle>(runner.state.value)
        assertTrue(items.puts.isEmpty())
        assertTrue(withContext(graph.dispatcher) { graph.journal.pendingCompleted(5) }.isEmpty())
        assertEquals(1, sensors.ended)
        assertTrue(service.stopped)
    }

    @Test
    fun restoreReattachesWhenOursIsRunning() = runBlocking<Unit> {
        runner(FakeSensors(), FakeServiceControl()).also { it.start(template); it.log(values()) }
        // The process died: a new runner over the same database.
        val sensors = FakeSensors(owner = ExerciseOwner.OURS)
        val service = FakeServiceControl()
        val restored = runner(sensors, service)
        restored.restore()
        assertEquals(1, running(restored).controller.state.completedSets)
        assertEquals(1, sensors.attached)
        assertEquals(0, sensors.started)
        assertTrue(service.started)
    }

    @Test
    fun restoreStartsSensorsWhenNoneIsRunning() = runBlocking<Unit> {
        runner(FakeSensors(), FakeServiceControl()).also { it.start(template); it.log(values()) }
        val sensors = FakeSensors(owner = ExerciseOwner.NONE)
        val restored = runner(sensors, FakeServiceControl())
        restored.restore()
        assertIs<RunnerState.Running>(restored.state.value)
        assertEquals(1, sensors.started)
        assertEquals(0, sensors.attached)
    }

    @Test
    fun restoreKeepsRecordingWithoutSensorsWhenAnotherAppOwnsTheExercise() = runBlocking<Unit> {
        runner(FakeSensors(), FakeServiceControl()).also { it.start(template); it.log(values()) }
        val sensors = FakeSensors(owner = ExerciseOwner.OTHER_APP)
        val restored = runner(sensors, FakeServiceControl())
        restored.restore()
        assertFalse(running(restored).hrAvailable)
        assertEquals(0, sensors.started + sensors.attached + sensors.ended)
    }

    @Test
    fun restoreQueuesAFinishedButUnqueuedSession() = runBlocking<Unit> {
        val first = runner(FakeSensors(), FakeServiceControl())
        first.start(template)
        first.log(values())
        // The app died between workout_completed and the queue.
        withContext(graph.dispatcher) { running(first).controller.markCompleted() }
        val sensors = FakeSensors(owner = ExerciseOwner.OURS)
        val restored = runner(sensors, FakeServiceControl())
        restored.restore()
        assertIs<RunnerState.Idle>(restored.state.value)
        assertEquals(1, withContext(graph.dispatcher) { graph.journal.pendingCompleted(5) }.size)
        assertEquals(1, items.puts.size)
        assertEquals(1, sensors.ended, "a sensor session no journal session explains is ended")
    }

    @Test
    fun signOutMidWorkoutDiscardsAndStops() = runBlocking<Unit> {
        val sensors = FakeSensors()
        val service = FakeServiceControl()
        val runner = runner(sensors, service)
        runner.start(template)
        runner.log(values())
        val cleared = WatchMessage(
            UUID.randomUUID().toString(), "2026-10-23T02:00:00Z", TEST_KEY, WatchMessageBody.AccountCleared(false))
        withContext(graph.dispatcher) {
            graph.link.onChanges(
                listOf(DataChange(DataLayerPaths.context("account_cleared"), cleared.encode(), deleted = false)))
        }
        runner.syncAccount()
        assertIs<RunnerState.Idle>(runner.state.value)
        assertTrue(service.stopped)
        assertEquals(1, sensors.ended)
        assertNull(withContext(graph.dispatcher) { graph.journal.activeSession(TEST_KEY) })
        assertTrue(withContext(graph.dispatcher) { graph.journal.pendingCompleted(5) }.isEmpty())
        assertTrue(items.puts.none { it.second.contains("completed_workout") })
    }

    @Test
    fun finishSavesTheSeriesWithTheWorkout() = runBlocking<Unit> {
        val sensors = FakeSensors(
            scripted = listOf(
                SensorReading.HeartRate(70.0, t0.plusSeconds(5)),
                SensorReading.HeartRate(72.0, t0.plusSeconds(50)),
                SensorReading.HeartRate(80.0, t0.plusSeconds(125)),
                SensorReading.Calories(987.0),
            ),
        )
        val runner = timedRunner(sensors)
        now = t0
        runner.start(template)
        runner.log(values())
        now = t0.plusSeconds(600)
        runner.finish()
        assertTrue(pendingSeries().isEmpty(), "held back until the phone acks the workout")
        ackCompleted()
        val series = pendingSeries().single()
        val body = assertIs<WatchMessageBody.WorkoutHealth>(series.body)
        assertEquals(listOf(71, 80), body.heartRate.map { it.bpm })
        assertEquals(listOf("2026-10-23T11:00:00Z", "2026-10-23T11:02:00Z"), body.heartRate.map { it.atUtc })
        assertEquals(987.0, body.totalKcal)
        assertEquals("2026-10-23T11:00:00Z", body.startUtc)
        assertEquals("2026-10-23T11:10:00Z", body.endUtc)
        val completed = items.puts.map { WatchMessage.decode(it.second) }
            .map { it.body }.filterIsInstance<WatchMessageBody.CompletedWorkout>().single()
        assertEquals(completed.workoutId, body.workoutId)
    }

    @Test
    fun finishWithoutReadingsStillSavesTheSessionWithAnEmptySeries() = runBlocking<Unit> {
        val runner = timedRunner(FakeSensors(startResult = SensorStart(false, false)))
        now = t0
        runner.start(template)
        runner.log(values())
        now = t0.plusSeconds(600)
        runner.finish()
        ackCompleted()
        val body = assertIs<WatchMessageBody.WorkoutHealth>(pendingSeries().single().body)
        assertTrue(body.heartRate.isEmpty())
        assertEquals(null, body.totalKcal)
    }

    @Test
    fun healthValuesNeverReachTheJournalOrTheDataLayer() = runBlocking<Unit> {
        // Sentinels that show up nowhere else: a leak of either would be a bug. They may be in the
        // session_health row and in the workout_health put, and nowhere else.
        val sensors = FakeSensors(
            scripted = listOf(SensorReading.HeartRate(173.0, t0.plusSeconds(5)), SensorReading.Calories(987.0)),
        )
        val runner = timedRunner(sensors)
        now = t0
        runner.start(template)
        assertEquals(173, running(runner).heartRate)
        assertEquals(987, running(runner).calories)
        runner.log(values())
        now = t0.plusSeconds(600)
        runner.finish()
        ackCompleted() // releases the series: the one place the values may travel
        val sentinel = Regex("""\b(173|987)\b""")
        val db = SQLiteDatabase.openDatabase(
            context.getDatabasePath(dbName).path, null, SQLiteDatabase.OPEN_READONLY)
        try {
            val tables = mutableListOf<String>()
            db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'", null).use { c ->
                while (c.moveToNext()) tables += c.getString(0)
            }
            assertTrue(tables.isNotEmpty())
            assertTrue("session_health" in tables)
            val dump = StringBuilder()
            val seriesRows = StringBuilder()
            for (table in tables) {
                db.rawQuery("SELECT * FROM \"$table\"", null).use { c ->
                    while (c.moveToNext()) {
                        val row = if (table == "session_health") seriesRows else dump
                        for (i in 0 until c.columnCount) {
                            when (c.getType(i)) {
                                Cursor.FIELD_TYPE_BLOB -> row.append(String(c.getBlob(i), Charsets.UTF_8))
                                Cursor.FIELD_TYPE_NULL -> Unit
                                else -> row.append(c.getString(i))
                            }
                            row.append(' ')
                        }
                    }
                }
            }
            val text = dump.toString().lowercase()
            assertFalse(sentinel.containsMatchIn(text), "journal rows contain a health sentinel")
            for (forbidden in listOf("bpm", "heart", "calor")) {
                assertFalse(text.contains(forbidden), "journal rows contain \"$forbidden\"")
            }
            // The values wait here, and only here, until the phone's answer.
            assertTrue(seriesRows.contains("173") && seriesRows.contains("987"))
        } finally {
            db.close()
        }
        assertTrue(items.puts.isNotEmpty())
        var healthPuts = 0
        for ((path, json) in items.puts) {
            val type = WatchMessage.decode(json).type
            if (type == "workout_health") {
                healthPuts += 1
                assertTrue(json.contains("173") && json.contains("987"))
                continue
            }
            assertFalse(sentinel.containsMatchIn(json), "Data Layer item $path contains a health sentinel")
            for (forbidden in listOf("bpm", "heart", "calor")) {
                assertFalse(json.lowercase().contains(forbidden), "Data Layer item $path contains \"$forbidden\"")
            }
        }
        assertEquals(1, healthPuts)
    }

    // --- Restore, account changes and concurrency ------------------------------------------------

    @Test
    fun restoreUnboundWithOursEndsTheSensors() = runBlocking<Unit> {
        runner(FakeSensors(), FakeServiceControl()).also { it.start(template); it.log(values()) }
        // The phone signed out while the process was dead: the binding is gone, the session rows stay.
        withContext(graph.dispatcher) { graph.journal.clearAccount(TEST_KEY, wipeUnsent = false) }
        val sensors = FakeSensors(owner = ExerciseOwner.OURS)
        val service = FakeServiceControl()
        val restored = runner(sensors, service)
        restored.restore()
        assertIs<RunnerState.Idle>(restored.state.value)
        assertEquals(1, sensors.ended, "a platform session no bound workout explains is ended")
        assertFalse(service.started)
        assertTrue(activeSessions().isEmpty(), "the unowned session is abandoned, not left active")
    }

    @Test
    fun aClearedAccountsActiveSessionIsAbandonedAtRestore() = runBlocking<Unit> {
        runner(FakeSensors(), FakeServiceControl()).also { it.start(template); it.log(values()) }
        // Another account is bound now and the first one has a clear tombstone.
        withContext(graph.dispatcher) {
            graph.journal.recordCleared(TEST_KEY, Instant.parse("2026-10-24T00:00:00Z").toEpochMilli())
            graph.journal.bindForTest(OTHER_TEST_KEY)
        }
        val sensors = FakeSensors(owner = ExerciseOwner.OURS)
        val restored = runner(sensors, FakeServiceControl())
        restored.restore()
        assertIs<RunnerState.Idle>(restored.state.value)
        assertTrue(activeSessions().isEmpty())
        assertEquals(1, sensors.ended)
        assertTrue(items.puts.none { it.second.contains("completed_workout") })
    }

    @Test
    fun aClearNewerThanTheBindingAbandonsEvenTheBoundAccountsSession() = runBlocking<Unit> {
        runner(FakeSensors(), FakeServiceControl()).also { it.start(template); it.log(values()) }
        // bindForTest sends at 2026-10-23T01:00:00Z; the phone cleared the account after that.
        withContext(graph.dispatcher) {
            graph.journal.recordCleared(TEST_KEY, Instant.parse("2026-10-24T00:00:00Z").toEpochMilli())
        }
        val restored = runner(FakeSensors(owner = ExerciseOwner.OURS), FakeServiceControl())
        restored.restore()
        assertIs<RunnerState.Idle>(restored.state.value)
        assertTrue(activeSessions().isEmpty())
    }

    @Test
    fun startDuringARestoreCannotCreateASecondSession() = runBlocking<Unit> {
        runner(FakeSensors(), FakeServiceControl()).also { it.start(template); it.log(values()) }
        val sensors = FakeSensors(owner = ExerciseOwner.OURS)
        val gate = CompletableDeferred<Unit>()
        sensors.ownerGate = gate
        val restored = runner(sensors, FakeServiceControl())
        val restoring = async(Dispatchers.Default) { restored.restore() }
        // Restore is now suspended on a Health Services answer; the person taps Start meanwhile.
        sensors.ownerEntered.await()
        val starting = async(Dispatchers.Default) { restored.start(syntheticTemplate("Second")) }
        delay(200)
        gate.complete(Unit)
        restoring.await()
        starting.await()
        assertEquals(1, activeSessions().size)
        assertEquals(0, sensors.started, "Start found the restored workout and did nothing")
        assertEquals(1, sensors.attached)
        assertEquals("Synthetic push", running(restored).controller.template.name)
    }

    @Test
    fun restoredPausedWorkoutPausesTheNewSensorSession() = runBlocking<Unit> {
        val first = runner(FakeSensors(), FakeServiceControl())
        first.start(template)
        first.log(values())
        first.pause()
        val sensors = FakeSensors(owner = ExerciseOwner.NONE)
        val restored = runner(sensors, FakeServiceControl())
        restored.restore()
        assertEquals("paused", running(restored).controller.status)
        assertEquals(1, sensors.started)
        assertEquals(1, sensors.paused, "a new platform session must not run while the workout is paused")
    }

    @Test
    fun observeIsIdempotent() {
        val runner = runner(FakeSensors(), FakeServiceControl())
        val first = runner.observe()
        assertTrue(first.isActive)
        assertEquals(first, runner.observe())
    }

    @Test
    fun signOutThroughObserveDiscardsTheWorkout() = runBlocking<Unit> {
        val sensors = FakeSensors()
        val service = FakeServiceControl()
        val runner = runner(sensors, service)
        runner.observe()
        runner.start(template)
        runner.log(values())
        val cleared = WatchMessage(
            UUID.randomUUID().toString(), "2026-10-23T02:00:00Z", TEST_KEY, WatchMessageBody.AccountCleared(false))
        // Only the link delivers the change; nothing calls syncAccount directly.
        withContext(graph.dispatcher) {
            graph.link.onChanges(
                listOf(DataChange(DataLayerPaths.context("account_cleared"), cleared.encode(), deleted = false)))
        }
        untilIdle(runner)
        assertTrue(service.stopped)
        assertEquals(1, sensors.ended)
        assertTrue(activeSessions().isEmpty())
        assertTrue(items.puts.none { it.second.contains("completed_workout") })
    }

    @Test
    fun anAccountSwitchThroughObserveDiscardsTheWorkoutOfTheFirstAccount() = runBlocking<Unit> {
        val sensors = FakeSensors()
        val runner = runner(sensors, FakeServiceControl())
        runner.observe()
        runner.start(template)
        runner.log(values())
        withContext(graph.dispatcher) { graph.journal.bindForTest(OTHER_TEST_KEY) }
        graph.bump()
        untilIdle(runner)
        assertEquals(1, sensors.ended)
        assertTrue(activeSessions().isEmpty())
        assertTrue(withContext(graph.dispatcher) { graph.journal.pendingCompleted(5) }.isEmpty())
    }

    @Test
    fun aFailedJournalCommitLeavesTheSetUnsaved() = runBlocking<Unit> {
        val runner = runner(FakeSensors(), FakeServiceControl())
        runner.start(template)
        // Break the events table behind the journal's back: the next commit throws.
        val db = SQLiteDatabase.openDatabase(context.getDatabasePath(dbName).path, null, SQLiteDatabase.OPEN_READWRITE)
        try {
            db.execSQL("ALTER TABLE events RENAME TO events_broken")
        } finally {
            db.close()
        }
        val stored = runner.log(values())
        assertFalse(stored, "the commit failed, so the set must not be reported as saved")
        assertEquals(0, running(runner).controller.state.completedSets)
    }

    @Test
    fun heartRateStaysHiddenAfterUnavailableEvenWhenCaloriesArrive() = runBlocking<Unit> {
        val sensors = FakeSensors(
            scripted = listOf(
                SensorReading.HeartRate(70.0, Instant.now()),
                SensorReading.Unavailable,
                SensorReading.Calories(100.0),
            ),
        )
        val runner = runner(sensors, FakeServiceControl())
        runner.start(template)
        assertNull(running(runner).heartRate)
        assertEquals(100, running(runner).calories)
    }

    @Test
    fun theServiceStartsBeforeTheSensors() = runBlocking<Unit> {
        val trace = mutableListOf<String>()
        runner(FakeSensors(trace = trace), FakeServiceControl(trace)).start(template)
        assertEquals(listOf("service.start", "sensors.start"), trace)
    }

    @Test
    fun restDeadlinesReachTheHapticsAndHoldTheWakeLock() = runBlocking<Unit> {
        val lock = FakeWakeLock()
        var pulses = 0
        val haptics = RestHaptics(CoroutineScope(Dispatchers.Unconfined), Instant::now, lock) { pulses += 1 }
        val runner = runner(FakeSensors(), FakeServiceControl(), haptics)
        runner.start(template)
        assertTrue(lock.acquired.isEmpty())
        runner.log(values())
        assertEquals(1, lock.acquired.size, "logging a set with a 60 s rest holds the lock for that rest")
        assertTrue(lock.acquired.single() in 60_000L..65_000L)
        assertTrue(lock.held)
        runner.skipRest()
        assertFalse(lock.held, "skipping the rest releases it")
        assertEquals(0, pulses)
    }
}
