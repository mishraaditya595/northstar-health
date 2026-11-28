package `in`.beyondrep.app

import android.content.Context
import android.net.Uri
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

/**
 * The Android side of `beyondrep/watch_link`: the same channel and methods as
 * `ios/Runner/WatchLinkBridge.swift`, carried by the Wear Data Layer.
 *
 * Paths (one `json` string per item, at most 100 KB):
 * - phone to watch, latest wins: `/beyondrep/context/<type>`
 * - phone to watch, queued: `/beyondrep/queue/phone/<message_id>`
 * - watch to phone, queued: `/beyondrep/queue/watch/<message_id>`
 *
 * Watch messages stay Data Layer items until Dart calls `startMessages`, which it does after
 * every listener has subscribed, and an item is deleted only after Dart accepted it
 * (`success`). A Dart `error` or `notImplemented` reply drops the item from memory only: it
 * stays in the Data Layer and is handed over again by the next `startMessages` (after
 * `notImplemented` the bridge also waits for that call; after `error` it keeps delivering new
 * items). Redelivery is safe because Dart handles every message idempotently by `message_id`.
 * A second `startMessages` while started does nothing. It carries no health value of its own
 * and nothing is logged.
 */
class WearLinkBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    DataClient.OnDataChangedListener,
    CapabilityClient.OnCapabilityChangedListener {

    private companion object {
        const val CHANNEL = "beyondrep/watch_link"
        const val WATCH_CAPABILITY = "beyondrep_watch_app"
        const val CONTEXT_PREFIX = "/beyondrep/context/"
        const val PHONE_QUEUE_PREFIX = "/beyondrep/queue/phone/"
        const val WATCH_QUEUE_PREFIX = "/beyondrep/queue/watch/"
        const val JSON_KEY = "json"

        // A DataItem is limited to 100 KB in all; keep a margin for the path.
        const val MAX_JSON_BYTES = 99 * 1024
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val dataClient: DataClient get() = Wearable.getDataClient(context)
    private val nodeClient get() = Wearable.getNodeClient(context)
    private val capabilityClient: CapabilityClient get() = Wearable.getCapabilityClient(context)

    private var registered = false
    private var started = false

    // Watch queue items not yet handed to Dart, by item URI. Main thread only.
    private val pending = LinkedHashMap<String, PendingItem>()
    private val inFlight = HashSet<String>()

    private class PendingItem(val uri: Uri, val json: String)

    fun register() {
        if (registered) return
        registered = true
        channel.setMethodCallHandler(this)
        scope.launch {
            try {
                dataClient.addListener(this@WearLinkBridge).await()
                capabilityClient.addListener(this@WearLinkBridge, WATCH_CAPABILITY).await()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // No Wear OS companion app or Play services: nothing to listen to.
            }
        }
    }

    fun dispose() {
        if (!registered) return
        registered = false
        channel.setMethodCallHandler(null)
        try {
            dataClient.removeListener(this)
            capabilityClient.removeListener(this)
        } catch (_: Exception) {
            // Wearable API unavailable; there was no listener to remove.
        }
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isReachableForUpdates" -> scope.launch {
                result.success(
                    try {
                        installedNodeCount(CapabilityClient.FILTER_ALL) > 0
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        false
                    },
                )
            }
            "watchStatus" -> scope.launch { result.success(watchStatus()) }
            "updateContext" -> {
                val map = call.arguments as? Map<*, *>
                val items = map?.entries?.associate { (k, v) -> k as? String to v as? String }
                if (items == null || items.any { it.key == null || it.value == null }) {
                    result.error("bad_arguments", null, null)
                    return
                }
                if (items.values.any { it!!.toByteArray(Charsets.UTF_8).size > MAX_JSON_BYTES }) {
                    result.error("too_large", null, null)
                    return
                }
                scope.launch {
                    try {
                        updateContext(items.entries.associate { it.key!! to it.value!! })
                        result.success(null)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        result.error("wear_failed", null, null)
                    }
                }
            }
            "transfer" -> {
                val json = (call.arguments as? Map<*, *>)?.get(JSON_KEY) as? String
                val messageId = json?.let {
                    try {
                        JSONObject(it).getString("message_id")
                    } catch (_: Exception) {
                        null
                    }
                }
                if (json == null || messageId.isNullOrBlank() || '/' in messageId) {
                    result.error("bad_arguments", null, null)
                    return
                }
                if (json.toByteArray(Charsets.UTF_8).size > MAX_JSON_BYTES) {
                    result.error("too_large", null, null)
                    return
                }
                scope.launch {
                    try {
                        put(PHONE_QUEUE_PREFIX + messageId, json)
                        result.success(null)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        result.error("wear_failed", null, null)
                    }
                }
            }
            "startMessages" -> {
                if (started) {
                    result.success(null)
                    return
                }
                started = true
                scope.launch {
                    try {
                        readExistingWatchItems()
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Exception) {
                        // Items that arrive later still reach onDataChanged.
                    }
                    flushPending()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // --- Status -------------------------------------------------------------

    private suspend fun watchStatus(): Map<String, Boolean> {
        val unsupported = mapOf(
            "supported" to false,
            "paired" to false,
            "installed" to false,
            "reachable" to false,
        )
        return try {
            if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) !=
                com.google.android.gms.common.ConnectionResult.SUCCESS
            ) {
                return unsupported
            }
            // Fails when the Wear OS companion app is not on this phone.
            GoogleApiAvailability.getInstance().checkApiAvailability(nodeClient).await()
            val connected = nodeClient.connectedNodes.await()
            mapOf(
                "supported" to true,
                "paired" to connected.isNotEmpty(),
                "installed" to (installedNodeCount(CapabilityClient.FILTER_ALL) > 0),
                "reachable" to (installedNodeCount(CapabilityClient.FILTER_REACHABLE) > 0),
            )
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            unsupported
        }
    }

    private suspend fun installedNodeCount(filter: Int): Int =
        capabilityClient.getCapability(WATCH_CAPABILITY, filter).await().nodes.size

    override fun onCapabilityChanged(info: CapabilityInfo) {
        scope.launch {
            channel.invokeMethod("watchStateChanged", null)
            channel.invokeMethod("watchReachabilityChanged", null)
        }
    }

    // --- Phone to watch -----------------------------------------------------

    private suspend fun put(path: String, json: String) {
        val request = PutDataMapRequest.create(path)
        request.dataMap.putString(JSON_KEY, json)
        dataClient.putDataItem(request.asPutDataRequest().setUrgent()).await()
    }

    private suspend fun updateContext(latestByType: Map<String, String>) {
        val wanted = latestByType.keys.map { CONTEXT_PREFIX + it }.toSet()
        for ((type, json) in latestByType) put(CONTEXT_PREFIX + type, json)
        // An empty map (sign out) deletes every context item, so the watch
        // never keeps showing the last account's plans.
        for (uri in itemUris(CONTEXT_PREFIX)) {
            if (uri.path !in wanted) dataClient.deleteDataItems(uri).await()
        }
    }

    // --- Watch to phone -----------------------------------------------------

    private fun prefixUri(prefix: String): Uri =
        Uri.Builder().scheme("wear").authority("*").path(prefix).build()

    private suspend fun itemUris(prefix: String): List<Uri> {
        val buffer = dataClient.getDataItems(prefixUri(prefix), DataClient.FILTER_PREFIX).await()
        try {
            return buffer.map { it.uri }
        } finally {
            buffer.release()
        }
    }

    private suspend fun readExistingWatchItems() {
        val buffer = dataClient
            .getDataItems(prefixUri(WATCH_QUEUE_PREFIX), DataClient.FILTER_PREFIX)
            .await()
        try {
            for (item in buffer) {
                val json = DataMapItem.fromDataItem(item).dataMap.getString(JSON_KEY)
                    ?: continue
                enqueue(item.uri, json)
            }
        } finally {
            buffer.release()
        }
    }

    override fun onDataChanged(events: DataEventBuffer) {
        // The buffer is released when this returns: copy what is needed now.
        val arrived = events
            .filter { it.type == DataEvent.TYPE_CHANGED }
            .filter { it.dataItem.uri.path?.startsWith(WATCH_QUEUE_PREFIX) == true }
            .mapNotNull {
                val json = DataMapItem.fromDataItem(it.dataItem).dataMap.getString(JSON_KEY)
                json?.let { value -> it.dataItem.uri to value }
            }
        if (arrived.isEmpty()) return
        scope.launch {
            for ((uri, json) in arrived) enqueue(uri, json)
            flushPending()
        }
    }

    private fun enqueue(uri: Uri, json: String) {
        val key = uri.toString()
        if (key in inFlight || key in pending) return
        pending[key] = PendingItem(uri, json)
    }

    /** Hands each buffered item to Dart once; deletes it only after Dart accepted it. */
    private fun flushPending() {
        if (!started) return
        val batch = pending.entries.toList()
        for ((key, item) in batch) {
            pending.remove(key)
            inFlight.add(key)
            channel.invokeMethod(
                "watchMessage",
                item.json,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        inFlight.remove(key)
                        scope.launch {
                            try {
                                dataClient.deleteDataItems(item.uri).await()
                            } catch (e: CancellationException) {
                                throw e
                            } catch (_: Exception) {
                                // Stays until the next start; Dart acks are idempotent.
                            }
                        }
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        inFlight.remove(key)
                    }

                    override fun notImplemented() {
                        // Dart stopped listening: keep the item for the next start.
                        inFlight.remove(key)
                        started = false
                    }
                },
            )
        }
    }
}
