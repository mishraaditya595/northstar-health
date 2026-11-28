package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant

/** One Data Layer change: [json] is null for a deletion or an item without the `json` key. */
data class DataChange(val path: String, val json: String?, val deleted: Boolean)

/**
 * Turns a batch of Data Layer changes into [PhoneInbox] calls. Context items and phone-queued
 * items arrive in one unordered batch, so they are applied in the order the phone sent them
 * (`sent_at_utc`), the binding before plans at equal times, like Swift's inbox. A deletion
 * changes nothing: the phone clears the watch with a queued `account_cleared`, exactly as an
 * empty application context does nothing on iOS.
 */
class DataLayerRouter(private val inbox: PhoneInbox) {
    private data class Entry(val index: Int, val route: Route, val json: String, val sentAtMs: Long, val rank: Int)

    private val typeRank = listOf("account_binding", "account_cleared", "plans_snapshot", "health_snapshot")

    fun apply(changes: List<DataChange>, now: Instant): List<AckOutcome> {
        val entries = changes.mapIndexedNotNull { index, change -> entry(index, change) }
            .sortedWith(compareBy<Entry>({ it.sentAtMs }, { it.rank }, { it.index }))
        val outcomes = mutableListOf<AckOutcome>()
        for (entry in entries) {
            when (val route = entry.route) {
                is Route.Context -> outcomes += inbox.receiveContext(mapOf(route.type to entry.json), now)
                is Route.PhoneQueued -> outcomes += inbox.receiveQueued(entry.json, now)
                is Route.WatchQueued -> Unit
            }
        }
        return outcomes
    }

    private fun entry(index: Int, change: DataChange): Entry? {
        if (change.deleted) return null
        val json = change.json ?: return null
        val route = DataLayerPaths.parse(change.path) ?: return null
        if (route is Route.WatchQueued) return null
        // An undecodable item sorts first and is rejected by the inbox, which counts it.
        val sentAt = sentAtMs(json) ?: 0L
        val rank = typeRank.indexOf(typeOf(json)).let { if (it < 0) typeRank.size else it }
        return Entry(index, route, json, sentAt, rank)
    }

    private fun root(json: String): JsonObject? = try {
        Json.parseToJsonElement(json) as? JsonObject
    } catch (_: Exception) {
        null
    }

    private fun string(json: String, key: String): String? =
        (root(json)?.get(key) as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun sentAtMs(json: String): Long? = string(json, "sent_at_utc")?.let(WatchTimestamp::milliseconds)

    private fun typeOf(json: String): String? = string(json, "type")
}
