package `in`.beyondrep.wear.app

import android.content.Context
import `in`.beyondrep.wear.core.link.DataLayerRouter
import `in`.beyondrep.wear.core.link.PhoneInbox
import `in`.beyondrep.wear.core.store.WatchJournal
import `in`.beyondrep.wear.link.DataItems
import `in`.beyondrep.wear.link.DataLayerLink
import `in`.beyondrep.wear.link.OutboxFlusher
import `in`.beyondrep.wear.link.WearDataItems
import `in`.beyondrep.wear.store.AndroidSqlDatabase
import `in`.beyondrep.wear.workout.RunnerFactory
import `in`.beyondrep.wear.workout.WorkoutRunner
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.time.Instant
import java.util.concurrent.Executors

/**
 * The process-wide objects of the watch app. The journal's SQLite connection has one serial
 * owner: everything that touches it runs on [dispatcher]. [revision] changes after every journal
 * write, so screens recompute what they show.
 */
class WatchGraph(
    private val appContext: Context,
    databaseName: String = "beyondrep_watch.db",
    items: DataItems = WearDataItems(appContext.applicationContext),
) {
    val dispatcher: CoroutineDispatcher =
        Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "beyondrep-journal") }.asCoroutineDispatcher()

    val journal = WatchJournal(AndroidSqlDatabase(appContext, databaseName))
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

    /** Puts queued workouts and their heart rate series for the phone until its ack arrives. */
    val outbox = OutboxFlusher(items, journal, dispatcher)

    val link = DataLayerLink(items, router, Instant::now, ::bump, outbox::flush)

    /**
     * Drops what outlived its retention: a binding the phone did not refresh for 90 days and heart
     * rate series of workouts that ended more than 7 days ago. Runs at app start.
     */
    suspend fun pruneStale(now: Instant = Instant.now()) {
        try {
            if (withContext(dispatcher) { journal.pruneStale(now.toEpochMilli()) }) bump()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Tried again at the next start.
        }
    }

    /** The workout on the watch: journal, Health Services session, foreground service. */
    val runner: WorkoutRunner by lazy { RunnerFactory.create(this, appContext) }

    companion object {
        @Volatile
        private var instance: WatchGraph? = null

        fun get(context: Context): WatchGraph =
            instance ?: synchronized(this) {
                instance ?: WatchGraph(context.applicationContext).also { instance = it }
            }
    }
}
