package `in`.beyondrep.wear.link

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.core.link.DataChange
import `in`.beyondrep.wear.core.link.DataLayerPaths
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

/**
 * Wakes the app when the phone puts or deletes a `/beyondrep` item. The callback runs on a
 * background thread, so it waits for the journal write and the ack before returning, which
 * keeps the process alive for that work.
 */
class LinkListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        // The buffer is released when this returns: copy what is needed first.
        val changes = events.mapNotNull { event ->
            val path = event.dataItem.uri.path ?: return@mapNotNull null
            when (event.type) {
                DataEvent.TYPE_CHANGED ->
                    DataChange(path, DataMapItem.fromDataItem(event.dataItem).dataMap.getString(DataLayerPaths.JSON_KEY), false)
                DataEvent.TYPE_DELETED -> DataChange(path, null, true)
                else -> null
            }
        }
        if (changes.isEmpty()) return
        val graph = WatchGraph.get(applicationContext)
        try {
            runBlocking { withContext(graph.dispatcher) { graph.link.onChanges(changes) } }
        } catch (_: Exception) {
            // Not user actionable; an unacked phone item is applied again on the next resume.
        }
    }
}
