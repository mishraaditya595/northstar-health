package `in`.beyondrep.wear.link

import `in`.beyondrep.wear.core.link.DataChange

/** A fake Data Layer for tests: the stored items, what was put and deleted, and an optional failure. */
internal class RecordingItems : DataItems {
    val store = linkedMapOf<String, String>()
    val puts = mutableListOf<Pair<String, String>>()
    val deletes = mutableListOf<String>()

    /** While true, every put throws. */
    var failPuts = false

    override suspend fun put(path: String, json: String) {
        if (failPuts) throw IllegalStateException("put failed")
        store[path] = json
        puts += path to json
    }

    override suspend fun delete(path: String) {
        store.remove(path)
        deletes += path
    }

    override suspend fun all(prefix: String): List<DataChange> =
        store.filterKeys { it.startsWith(prefix) }.map { (path, json) -> DataChange(path, json, deleted = false) }
}
