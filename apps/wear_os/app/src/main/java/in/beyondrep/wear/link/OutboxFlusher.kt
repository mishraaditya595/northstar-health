package `in`.beyondrep.wear.link

import `in`.beyondrep.wear.core.link.DataLayerPaths
import `in`.beyondrep.wear.core.link.OutboxSender
import `in`.beyondrep.wear.core.store.WatchJournal
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * Puts the completed workouts waiting in the journal on `/beyondrep/queue/watch/` until the
 * phone's `ack` removes them from the journal. The phone deletes an item once imported, so an item
 * missing from the Data Layer without an ack is put again; the phone answers a repeat as a
 * duplicate. Triggers: app start, catch-up, the phone becoming reachable and a finished workout.
 */
class OutboxFlusher(
    private val items: DataItems,
    private val journal: WatchJournal,
    private val dispatcher: CoroutineDispatcher,
) {
    suspend fun flush() {
        try {
            val pending = withContext(dispatcher) { journal.pendingCompleted(LIMIT) }
            if (pending.isEmpty()) return
            val present = items.all(DataLayerPaths.WATCH_QUEUE_PREFIX).map { it.path }.toSet()
            for ((path, json) in OutboxSender.toPut(pending, present)) items.put(path, json)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // The next trigger retries; the journal still holds the workout.
        }
    }

    private companion object {
        const val LIMIT = 50
    }
}
