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
import `in`.beyondrep.wear.testing.TEST_KEY
import `in`.beyondrep.wear.testing.bindForTest
import `in`.beyondrep.wear.testing.syntheticTemplate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
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

    private fun runner(sensors: FakeSensors, service: FakeServiceControl) = WorkoutRunner(
        graph, sensors, service, Instant::now, "watch-test", { "UTC" }, CoroutineScope(Dispatchers.Unconfined))

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
        assertEquals(100, finished.summary.activeCalories)
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
        assertNull(finished.summary.activeCalories)
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
    fun healthValuesNeverReachTheJournal() = runBlocking<Unit> {
        val sensors = FakeSensors(
            scripted = listOf(SensorReading.HeartRate(70.0, Instant.now()), SensorReading.Calories(250.0)),
        )
        val runner = runner(sensors, FakeServiceControl())
        runner.start(template)
        runner.log(values())
        runner.finish()
        val db = SQLiteDatabase.openDatabase(
            context.getDatabasePath(dbName).path, null, SQLiteDatabase.OPEN_READONLY)
        try {
            val tables = mutableListOf<String>()
            db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'", null).use { c ->
                while (c.moveToNext()) tables += c.getString(0)
            }
            assertTrue(tables.isNotEmpty())
            val dump = StringBuilder()
            for (table in tables) {
                db.rawQuery("SELECT * FROM \"$table\"", null).use { c ->
                    while (c.moveToNext()) {
                        for (i in 0 until c.columnCount) {
                            when (c.getType(i)) {
                                Cursor.FIELD_TYPE_BLOB -> dump.append(String(c.getBlob(i), Charsets.UTF_8))
                                Cursor.FIELD_TYPE_NULL -> Unit
                                else -> dump.append(c.getString(i))
                            }
                            dump.append(' ')
                        }
                    }
                }
            }
            val text = dump.toString().lowercase()
            for (forbidden in listOf("bpm", "heart", "calor")) {
                assertFalse(text.contains(forbidden), "journal rows contain \"$forbidden\"")
            }
        } finally {
            db.close()
        }
    }
}
