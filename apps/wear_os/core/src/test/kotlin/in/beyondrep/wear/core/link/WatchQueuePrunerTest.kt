package `in`.beyondrep.wear.core.link

import org.junit.jupiter.api.Test
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WatchQueuePrunerTest {
    private val now = Instant.parse("2026-10-23T02:00:00Z")

    private fun item(id: String, sentAt: String?): DataChange {
        val json = if (sentAt == null) "{nope" else """{"type":"ack","sent_at_utc":"$sentAt"}"""
        return DataChange(DataLayerPaths.watchQueue(id), json, deleted = false)
    }

    @Test
    fun keepsTheNewestAndDropsTheRest() {
        val items = (1..5).map { item("a$it", "2026-10-23T01:0$it:00Z") }
        val stale = WatchQueuePruner.stalePaths(items, now, keep = 3)
        assertEquals(setOf(DataLayerPaths.watchQueue("a1"), DataLayerPaths.watchQueue("a2")), stale.toSet())
    }

    @Test
    fun dropsItemsOlderThanTheMaximumAgeEvenUnderTheCap() {
        val fresh = item("new", "2026-10-23T01:00:00Z")
        val old = item("old", "2026-10-01T01:00:00Z")
        assertEquals(listOf(old.path), WatchQueuePruner.stalePaths(listOf(old, fresh), now, keep = 20))
    }

    @Test
    fun anUndecodableItemIsStale() {
        val bad = item("bad", null)
        val good = item("good", "2026-10-23T01:00:00Z")
        assertEquals(listOf(bad.path), WatchQueuePruner.stalePaths(listOf(good, bad), now, keep = 20))
    }

    @Test
    fun ignoresPathsOutsideTheWatchQueueAndDeletions() {
        val other = DataChange(DataLayerPaths.context("plans_snapshot"), "{}", deleted = false)
        val gone = DataChange(DataLayerPaths.watchQueue("x"), null, deleted = true)
        assertTrue(WatchQueuePruner.stalePaths(listOf(other, gone), now, keep = 0).isEmpty())
    }

    @Test
    fun nothingIsStaleWhenWithinTheCap() {
        val items = (1..3).map { item("a$it", "2026-10-23T01:0$it:00Z") }
        assertTrue(WatchQueuePruner.stalePaths(items, now, keep = 20).isEmpty())
    }

    @Test
    fun neverPrunesACompletedWorkout() {
        val acks = (1..22).map { item("ack${"%02d".format(it)}", "2026-10-23T01:%02d:00Z".format(it)) }
        fun workout(id: String, at: String) =
            DataChange(DataLayerPaths.watchQueue(id), """{"type":"completed_workout","sent_at_utc":"$at"}""", deleted = false)
        val workouts = listOf(
            workout("w1", "2026-09-23T01:00:00Z"),
            workout("w2", "2026-10-23T01:30:00Z"),
            workout("w3", "2026-10-23T01:31:00Z"),
        )
        val stale = WatchQueuePruner.stalePaths(acks + workouts, now, keep = 20)
        assertEquals(
            setOf(DataLayerPaths.watchQueue("ack01"), DataLayerPaths.watchQueue("ack02")),
            stale.toSet(),
        )
    }
}
