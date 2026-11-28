package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Duration
import java.time.Instant

/**
 * The phone deletes a watch-queued item once its app has accepted it, so acks only pile up under
 * `/beyondrep/queue/watch/` while the phone app is not running or not paired. Acks are status
 * only (the phone resends what it never saw confirmed), so the watch keeps the newest [DEFAULT_KEEP]
 * younger than [MAX_AGE] and deletes the rest.
 */
object WatchQueuePruner {
    const val DEFAULT_KEEP = 20
    val MAX_AGE: Duration = Duration.ofDays(14)

    /** Paths of watch-queue items to delete. Items outside the watch queue are never listed. */
    fun stalePaths(items: List<DataChange>, now: Instant, keep: Int = DEFAULT_KEEP): List<String> {
        val dated = items
            .filter { !it.deleted && it.path.startsWith(DataLayerPaths.WATCH_QUEUE_PREFIX) }
            .map { it.path to sentAtMs(it.json) }
        val oldest = now.minus(MAX_AGE).toEpochMilli()
        val newestFirst = dated.sortedByDescending { it.second ?: Long.MIN_VALUE }
        return newestFirst.withIndex()
            .filter { (index, item) -> index >= keep || item.second == null || item.second!! < oldest }
            .map { it.value.first }
    }

    private fun sentAtMs(json: String?): Long? = try {
        val root = Json.parseToJsonElement(json ?: return null) as? JsonObject
        ((root?.get("sent_at_utc") as? JsonPrimitive)?.takeIf { it.isString })?.content?.let(WatchTimestamp::milliseconds)
    } catch (_: Exception) {
        null
    }
}
