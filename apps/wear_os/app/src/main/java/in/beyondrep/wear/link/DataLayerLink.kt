package `in`.beyondrep.wear.link

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import `in`.beyondrep.wear.core.link.AckBuilder
import `in`.beyondrep.wear.core.link.DataChange
import `in`.beyondrep.wear.core.link.DataLayerPaths
import `in`.beyondrep.wear.core.link.DataLayerRouter
import `in`.beyondrep.wear.core.link.Route
import `in`.beyondrep.wear.core.link.WatchQueuePruner
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.util.UUID

/** The Data Layer as the link needs it, so the logic below is testable without Play services. */
interface DataItems {
    suspend fun put(path: String, json: String)

    suspend fun delete(path: String)

    /** Every item whose path starts with [prefix], from any node. */
    suspend fun all(prefix: String): List<DataChange>
}

/** [DataItems] over the Wear [DataClient]. Every item holds one `json` string. */
class WearDataItems(private val context: Context) : DataItems {
    private val client: DataClient get() = Wearable.getDataClient(context)

    override suspend fun put(path: String, json: String) {
        val request = PutDataMapRequest.create(path)
        request.dataMap.putString(DataLayerPaths.JSON_KEY, json)
        client.putDataItem(request.asPutDataRequest().setUrgent()).await()
    }

    override suspend fun delete(path: String) {
        client.deleteDataItems(Uri.Builder().scheme("wear").authority("*").path(path).build()).await()
    }

    override suspend fun all(prefix: String): List<DataChange> {
        val uri = Uri.Builder().scheme("wear").authority("*").path(prefix).build()
        val buffer = client.getDataItems(uri, DataClient.FILTER_PREFIX).await()
        try {
            return buffer.mapNotNull { item ->
                val path = item.uri.path ?: return@mapNotNull null
                DataChange(path, DataMapItem.fromDataItem(item).dataMap.getString(DataLayerPaths.JSON_KEY), deleted = false)
            }
        } finally {
            buffer.release()
        }
    }
}

/**
 * Applies what the phone sent and answers it. The journal write (inside the router) comes first;
 * only then is the `ack` put at `/beyondrep/queue/watch/<ack id>`, and only after the ack is out
 * is a handled phone-queued item deleted, so a failure leaves the item to be applied again as a
 * duplicate and acked. Context items belong to the phone and are never deleted here.
 * [onApplied] runs after anything was applied, so screens refresh, and [afterApplied] after
 * that, so an `ack` that releases a queued `workout_health` puts it at once.
 */
class DataLayerLink(
    private val items: DataItems,
    private val router: DataLayerRouter,
    private val clock: () -> Instant,
    private val onApplied: () -> Unit = {},
    private val afterApplied: suspend () -> Unit = {},
) {
    suspend fun onChanges(changes: List<DataChange>) = handle(changes, ackDuplicates = true)

    /**
     * Reads everything the phone left while the app was not running. Resuming repeats the
     * context items, so duplicates are not acked again.
     */
    suspend fun catchUp() {
        val changes = items.all(DataLayerPaths.CONTEXT_PREFIX) + items.all(DataLayerPaths.PHONE_QUEUE_PREFIX)
        handle(changes, ackDuplicates = false)
    }

    private suspend fun handle(changes: List<DataChange>, ackDuplicates: Boolean) {
        val live = changes.filter { !it.deleted && it.json != null }
        if (live.isEmpty()) return
        val now = clock()
        val outcomes = router.apply(live, now)
        try {
            for (outcome in outcomes) {
                if (!ackDuplicates && outcome.result == "duplicate") continue
                val ackId = UUID.randomUUID().toString().lowercase()
                items.put(DataLayerPaths.watchQueue(ackId), AckBuilder.json(outcome, ackId, now))
            }
            // Handled, malformed or ignored alike: an undecodable item would otherwise stay forever.
            for (change in live) {
                if (DataLayerPaths.parse(change.path) is Route.PhoneQueued) items.delete(change.path)
            }
            pruneWatchQueue(now)
        } finally {
            // The journal already changed, so screens refresh even when an ack or delete failed.
            // The ack and the delete stay in order and are not retried here: a failure leaves the
            // phone item to be applied again as a duplicate and acked.
            onApplied()
            afterApplied()
        }
    }

    /** Best effort: stale acks only matter for tidiness, so a failure here is ignored. */
    private suspend fun pruneWatchQueue(now: Instant) {
        try {
            for (path in WatchQueuePruner.stalePaths(items.all(DataLayerPaths.WATCH_QUEUE_PREFIX), now)) {
                items.delete(path)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Tried again after the next batch.
        }
    }
}
