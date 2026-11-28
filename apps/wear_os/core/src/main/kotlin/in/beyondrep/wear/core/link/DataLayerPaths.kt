package `in`.beyondrep.wear.core.link

/** Where a Data Layer item sits, decoded from its path. */
sealed interface Route {
    /** Latest-wins state from the phone: one item per message type. */
    data class Context(val type: String) : Route

    /** A queued message from the phone, deleted by the receiver after handling. */
    data class PhoneQueued(val id: String) : Route

    /** A queued message from the watch, deleted by the phone after handling. */
    data class WatchQueued(val id: String) : Route
}

/** The exact Data Layer paths of the phone and watch link. Each item holds one `json` string. */
object DataLayerPaths {
    const val ROOT = "/beyondrep"
    const val CONTEXT_PREFIX = "$ROOT/context/"
    const val PHONE_QUEUE_PREFIX = "$ROOT/queue/phone/"
    const val WATCH_QUEUE_PREFIX = "$ROOT/queue/watch/"
    const val JSON_KEY = "json"

    fun context(type: String): String = CONTEXT_PREFIX + type

    fun phoneQueue(id: String): String = PHONE_QUEUE_PREFIX + id

    fun watchQueue(id: String): String = WATCH_QUEUE_PREFIX + id

    /** Null for any other prefix, an empty name or a name with a slash. */
    fun parse(path: String): Route? {
        fun name(prefix: String): String? =
            path.removePrefix(prefix).takeIf { path.startsWith(prefix) && it.isNotEmpty() && '/' !in it }
        name(CONTEXT_PREFIX)?.let { return Route.Context(it) }
        name(PHONE_QUEUE_PREFIX)?.let { return Route.PhoneQueued(it) }
        name(WATCH_QUEUE_PREFIX)?.let { return Route.WatchQueued(it) }
        return null
    }
}
