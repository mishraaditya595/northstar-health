package `in`.beyondrep.wear.link

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.core.contracts.HeartRatePoint
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.link.DataChange
import `in`.beyondrep.wear.core.link.DataLayerPaths
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.testing.OTHER_TEST_KEY
import `in`.beyondrep.wear.testing.bindForTest
import `in`.beyondrep.wear.testing.syntheticTemplate
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
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class OutboxFlusherTest {
    private val key = `in`.beyondrep.wear.testing.TEST_KEY
    private lateinit var graph: WatchGraph
    private lateinit var items: RecordingItems

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        items = RecordingItems()
        graph = WatchGraph(context, "outbox-test-${UUID.randomUUID()}.db", items)
        graph.journal.bindForTest(key)
    }

    private fun queueOne(accountKey: String = key): String = runBlocking {
        withContext(graph.dispatcher) {
            val template = syntheticTemplate()
            val controller = WorkoutController.start(
                template, graph.journal, accountKey, "kg", "watch-test", Instant::now, "UTC") { UUID.randomUUID().toString() }
            val set = template.exercises[0].sets[0]
            controller.log(SetValues(set.setId, "ex-1", 0, reps = 5, loadGrams = 40_000))
            controller.markCompleted()
            controller.queueCompleted(null)
            controller.sessionId
        }
    }

    @Test
    fun flushPutsAQueuedWorkoutOnce() = runBlocking<Unit> {
        queueOne()
        val message = graph.journal.pendingCompleted(5).single()
        graph.outbox.flush()
        graph.outbox.flush()
        assertEquals(1, items.puts.size)
        assertEquals(DataLayerPaths.watchQueue(message.messageId), items.puts.single().first)
        assertTrue(items.puts.single().second.contains("completed_workout"))
    }

    @Test
    fun flushPutsAgainWhenThePhoneDeletedItWithoutAck() = runBlocking<Unit> {
        queueOne()
        graph.outbox.flush()
        items.store.clear() // the phone removed the item but its ack never arrived
        graph.outbox.flush()
        assertEquals(2, items.puts.size)
        assertEquals(items.puts[0], items.puts[1])
    }

    @Test
    fun ackDeliversAndStopsResending() = runBlocking<Unit> {
        val sessionId = queueOne()
        val message = graph.journal.pendingCompleted(5).single()
        graph.outbox.flush()
        val ack = WatchMessage(
            UUID.randomUUID().toString(), "2026-10-23T01:00:00Z", key,
            WatchMessageBody.Ack(message.messageId, "stored", null))
        val path = DataLayerPaths.phoneQueue(ack.messageId)
        withContext(graph.dispatcher) {
            graph.link.onChanges(listOf(DataChange(path, ack.encode(), deleted = false)))
        }
        assertEquals("delivered", graph.journal.delivery(sessionId))
        items.store.clear()
        items.puts.clear()
        graph.outbox.flush()
        assertTrue(items.puts.isEmpty())
    }

    @Test
    fun aFailingPutIsRetriedOnTheNextFlush() = runBlocking<Unit> {
        queueOne()
        items.failPuts = true
        graph.outbox.flush() // swallowed
        assertTrue(items.puts.isEmpty())
        items.failPuts = false
        graph.outbox.flush()
        assertEquals(1, items.puts.size)
    }

    @Test
    fun aWorkoutOfAnotherAccountIsNotPut() = runBlocking<Unit> {
        queueOne(OTHER_TEST_KEY)
        graph.outbox.flush()
        assertTrue(items.puts.isEmpty(), "a workout is never sent under another account")
        assertEquals(1, graph.journal.pendingCompleted(5).size)
    }

    // Heart rate and calories of a finished workout (stage 3b)

    private fun saveSeries(sessionId: String, endedAtMs: Long = Instant.now().toEpochMilli()): WatchMessage {
        val message = WatchMessage(
            UUID.randomUUID().toString(), "2026-10-23T11:41:00Z", key,
            WatchMessageBody.WorkoutHealth(
                UUID.randomUUID().toString(), "2026-10-23T11:00:00Z", "2026-10-23T11:40:00Z",
                listOf(HeartRatePoint("2026-10-23T11:00:00Z", 90)), 300.0))
        runBlocking { withContext(graph.dispatcher) { graph.journal.saveWorkoutHealth(sessionId, key, message, endedAtMs) } }
        return message
    }

    private suspend fun phoneAcks(messageId: String, result: String, reason: String? = null) {
        val ack = WatchMessage(
            UUID.randomUUID().toString(), "2026-10-23T11:42:00Z", key, WatchMessageBody.Ack(messageId, result, reason))
        withContext(graph.dispatcher) {
            graph.link.onChanges(listOf(DataChange(DataLayerPaths.phoneQueue(ack.messageId), ack.encode(), deleted = false)))
        }
    }

    private fun puttedTypes() = items.puts.map { WatchMessage.decode(it.second).type }

    @Test
    fun theSeriesIsPutOnlyAfterTheWorkoutAck() = runBlocking<Unit> {
        val sessionId = queueOne()
        val series = saveSeries(sessionId)
        val completed = graph.journal.pendingCompleted(5).single()
        graph.outbox.flush()
        assertEquals(listOf("completed_workout"), puttedTypes())
        phoneAcks(completed.messageId, "stored")
        // The ack itself puts the series: no wait for the next trigger.
        assertEquals(listOf("completed_workout", "workout_health"), puttedTypes())
        assertEquals(DataLayerPaths.watchQueue(series.messageId), items.puts.last().first)
        graph.outbox.flush()
        assertEquals(2, items.puts.size, "the series is put once while it is still in the Data Layer")
    }

    @Test
    fun aNotWrittenAckDeletesTheSeries() = runBlocking<Unit> {
        val sessionId = queueOne()
        val series = saveSeries(sessionId)
        phoneAcks(graph.journal.pendingCompleted(5).single().messageId, "stored")
        phoneAcks(series.messageId, "rejected", "not_written")
        items.store.clear()
        items.puts.clear()
        graph.outbox.flush()
        assertTrue(items.puts.isEmpty())
        assertTrue(graph.journal.pendingWorkoutHealth(key, 5).isEmpty())
    }

    @Test
    fun aSeriesIsPutAgainWhenThePhoneDeletedItWithoutAck() = runBlocking<Unit> {
        val sessionId = queueOne()
        saveSeries(sessionId)
        phoneAcks(graph.journal.pendingCompleted(5).single().messageId, "stored")
        items.store.clear() // a write failure on the phone: the item is gone and no ack came
        graph.outbox.flush()
        assertEquals(listOf("workout_health", "workout_health"), puttedTypes())
    }

    @Test
    fun pruneAtStartDropsASeriesOlderThanSevenDays() = runBlocking<Unit> {
        val sessionId = queueOne()
        saveSeries(sessionId, endedAtMs = Instant.now().minusSeconds(8L * 86_400).toEpochMilli())
        phoneAcks(graph.journal.pendingCompleted(5).single().messageId, "stored")
        items.puts.clear()
        items.store.clear()
        graph.pruneStale()
        graph.outbox.flush()
        assertTrue(items.puts.isEmpty())
        assertTrue(graph.journal.pendingWorkoutHealth(key, 5).isEmpty())
    }
}
