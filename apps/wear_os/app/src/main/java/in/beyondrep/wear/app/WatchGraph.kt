package `in`.beyondrep.wear.app

import android.content.Context
import `in`.beyondrep.wear.core.link.DataLayerRouter
import `in`.beyondrep.wear.core.link.PhoneInbox
import `in`.beyondrep.wear.core.store.WatchJournal
import `in`.beyondrep.wear.link.DataLayerLink
import `in`.beyondrep.wear.link.WearDataItems
import `in`.beyondrep.wear.store.AndroidSqlDatabase
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.Instant
import java.util.concurrent.Executors

/**
 * The process-wide objects of the watch app. The journal's SQLite connection has one serial
 * owner: everything that touches it runs on [dispatcher]. [revision] changes after every journal
 * write, so screens recompute what they show.
 */
class WatchGraph(context: Context, databaseName: String = "beyondrep_watch.db") {
    val dispatcher: CoroutineDispatcher =
        Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "beyondrep-journal") }.asCoroutineDispatcher()

    val journal = WatchJournal(AndroidSqlDatabase(context, databaseName))
    val inbox = PhoneInbox(journal)
    val router = DataLayerRouter(inbox)

    private val _revision = MutableStateFlow(0L)
    val revision: StateFlow<Long> = _revision

    fun bump() {
        _revision.value += 1
    }

    private val _phoneReachable = MutableStateFlow(false)

    /** Whether a phone with BeyondRep is nearby right now (the sync line says "Phone not nearby" when not). */
    val phoneReachable: StateFlow<Boolean> = _phoneReachable

    fun setPhoneReachable(reachable: Boolean) {
        _phoneReachable.value = reachable
    }

    val link = DataLayerLink(WearDataItems(context.applicationContext), router, Instant::now, ::bump)

    companion object {
        @Volatile
        private var instance: WatchGraph? = null

        fun get(context: Context): WatchGraph =
            instance ?: synchronized(this) {
                instance ?: WatchGraph(context.applicationContext).also { instance = it }
            }
    }
}
