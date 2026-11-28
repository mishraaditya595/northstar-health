package `in`.beyondrep.wear.link

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.link.DataChange
import `in`.beyondrep.wear.core.link.DataLayerPaths
import `in`.beyondrep.wear.core.session.TemplateExercise
import `in`.beyondrep.wear.core.session.TemplateSet
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.core.session.WorkoutTemplate
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
    private val key = "0123456789abcdef".repeat(4)
    private lateinit var graph: WatchGraph
    private lateinit var items: RecordingItems

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        items = RecordingItems()
        graph = WatchGraph(context, "outbox-test-${UUID.randomUUID()}.db", items)
    }

    private fun queueOne(): String = runBlocking {
        withContext(graph.dispatcher) {
            val template = WorkoutTemplate(
                "Synthetic push",
                exercises = listOf(
                    TemplateExercise("ex-1", "Bench press", "reps", null, 0, listOf(TemplateSet(UUID.randomUUID().toString(), 0))),
                ),
            )
            val controller = WorkoutController.start(
                template, graph.journal, key, "kg", "watch-test", Instant::now, "UTC") { UUID.randomUUID().toString() }
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
}
