package `in`.beyondrep.wear.core.link

import `in`.beyondrep.wear.core.contracts.WatchMessage

/** Decides which journal messages still have to be put on the watch queue for the phone. */
object OutboxSender {
    /** `(path, json)` for each pending message whose path is not in [present], in the given order. */
    fun toPut(pending: List<WatchMessage>, present: Set<String>): List<Pair<String, String>> =
        pending
            .map { DataLayerPaths.watchQueue(it.messageId) to it }
            .filter { (path, _) -> path !in present }
            .map { (path, message) -> path to message.encode() }
}
