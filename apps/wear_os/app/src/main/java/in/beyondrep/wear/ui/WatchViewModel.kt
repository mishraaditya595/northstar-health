package `in`.beyondrep.wear.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.glance.DetailModel
import `in`.beyondrep.wear.core.glance.Glance
import `in`.beyondrep.wear.core.glance.GlanceState
import `in`.beyondrep.wear.core.glance.Metric
import `in`.beyondrep.wear.core.glance.PlanRow
import `in`.beyondrep.wear.core.glance.SyncLine
import `in`.beyondrep.wear.core.glance.WaitingWorkouts
import `in`.beyondrep.wear.core.session.WorkoutTemplate
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/** What the screens show. Everything is computed from the journal, never from the screen. */
sealed interface WatchUi {
    /** Before the first computation. */
    data object Loading : WatchUi

    /** Nothing bound: "Open BeyondRep on your phone". */
    data object Unbound : WatchUi

    data class Ready(
        val glance: Glance,
        val plans: List<PlanRow>,
        val today: PlanRow?,
        val sync: SyncLine,
        val waiting: WaitingWorkouts,
        /** Detail screens for the metrics that have data today. */
        val details: Map<Metric, DetailModel>,
        /** Read-only plan previews by plan id; the key null is today's program workout. */
        val previews: Map<String?, WorkoutTemplate>,
    ) : WatchUi
}

/**
 * Maps the journal revision, the clock and phone reachability to [WatchUi]. The journal is read
 * on the graph's single journal thread. At local midnight the state is recomputed, so health from
 * yesterday disappears without anything arriving.
 */
class WatchViewModel(
    private val graph: WatchGraph,
    private val clock: () -> Instant,
    private val zone: () -> ZoneId,
    private val locale: () -> Locale = { Locale.getDefault() },
) : ViewModel() {
    private val midnight = MutableStateFlow(0L)

    val ui: StateFlow<WatchUi> = combine(graph.revision, midnight, graph.phoneReachable) { _, _, reachable -> reachable }
        .map { reachable -> compute(reachable) }
        .flowOn(graph.dispatcher)
        .stateIn(viewModelScope, SharingStarted.Eagerly, WatchUi.Loading)

    init {
        viewModelScope.launch {
            while (true) {
                val now = clock()
                val z = zone()
                val next = now.atZone(z).toLocalDate().plusDays(1).atStartOfDay(z).toInstant()
                delay(Duration.between(now, next).toMillis().coerceAtLeast(1_000L) + 1_000L)
                midnight.value += 1
            }
        }
    }

    private fun compute(reachable: Boolean): WatchUi {
        val journal = graph.journal
        val now = clock()
        val z = zone()
        val loc = locale()
        val glance = (GlanceState.make(journal, now, z, loc) as? GlanceState.Ready)?.glance ?: return WatchUi.Unbound
        val key = journal.binding()?.accountKey ?: return WatchUi.Unbound
        val details = Metric.entries.mapNotNull { metric ->
            DetailModel.make(metric, journal, now, z, loc)?.let { metric to it }
        }.toMap()
        val previews = mutableMapOf<String?, WorkoutTemplate>()
        val raw = (journal.plans(key)?.body as? WatchMessageBody.PlansSnapshot)?.raw
        if (raw != null) {
            val makeId = { UUID.randomUUID().toString().lowercase() }
            WorkoutTemplate.today(raw, makeId)?.let { previews[null] = it }
            for (plan in glance.plans + listOfNotNull(glance.today)) {
                WorkoutTemplate.fromPlan(raw, plan.id, makeId)?.let { previews[plan.id] = it }
            }
        }
        return WatchUi.Ready(
            glance = glance,
            plans = glance.plans,
            today = glance.today,
            sync = SyncLine.make(journal, reachable, now, z, loc),
            waiting = WaitingWorkouts.make(journal),
            details = details,
            previews = previews,
        )
    }
}
