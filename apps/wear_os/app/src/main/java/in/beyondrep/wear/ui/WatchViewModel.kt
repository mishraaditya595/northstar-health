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
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.ui.workout.RecentExercise
import `in`.beyondrep.wear.ui.workout.StartTarget
import `in`.beyondrep.wear.ui.workout.SummaryStatus
import `in`.beyondrep.wear.ui.workout.WorkoutActions
import `in`.beyondrep.wear.workout.RunnerState
import `in`.beyondrep.wear.workout.WorkoutRunner
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
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
        /** Exercises the phone listed as recent, for "+ Add exercise". */
        val recent: List<RecentExercise> = emptyList(),
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
    private val runner: WorkoutRunner = graph.runner,
) : ViewModel(), WorkoutActions {
    private val midnight = MutableStateFlow(0L)

    val ui: StateFlow<WatchUi> = combine(graph.revision, midnight, graph.phoneReachable) { _, _, reachable -> reachable }
        .map { reachable -> compute(reachable) }
        .flowOn(graph.dispatcher)
        .stateIn(viewModelScope, SharingStarted.Eagerly, WatchUi.Loading)

    /** The running workout, its summary or the "another app" message. */
    val workout: StateFlow<RunnerState> = runner.state

    /** The journal revision: the controller is mutable, so workout screens recompute on it. */
    val revision: StateFlow<Long> = graph.revision

    private val _ambient = MutableStateFlow(false)
    val ambient: StateFlow<Boolean> = _ambient

    fun setAmbient(value: Boolean) {
        _ambient.value = value
    }

    private val _now = MutableStateFlow(clock())

    /** The clock for the workout screens: every second, every minute in ambient mode, still when no workout shows. */
    val now: StateFlow<Instant> = _now

    /** Ambient mode redraws once a minute by the system's own call: the timer below may not run with the screen dimmed. */
    fun onAmbientUpdate() {
        _now.value = clock()
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    private val clockTicks = combine(runner.state, _ambient) { state, ambient ->
        if (state is RunnerState.Running) (if (ambient) 60_000L else 1_000L) else 0L
    }.distinctUntilChanged().flatMapLatest { period ->
        flow {
            while (true) {
                emit(clock())
                if (period == 0L) break
                delay(period)
            }
        }
    }.onEach { _now.value = it }.launchIn(viewModelScope)

    /** The summary's status line, from the journal's delivery state and phone reachability. */
    @OptIn(ExperimentalCoroutinesApi::class)
    val summaryStatus: StateFlow<String> =
        combine(runner.state, graph.revision, graph.phoneReachable) { state, _, reachable -> state to reachable }
            .map { (state, reachable) ->
                if (state is RunnerState.Finished) {
                    SummaryStatus.text(graph.journal.delivery(state.summary.sessionId), reachable)
                } else {
                    ""
                }
            }
            .flowOn(graph.dispatcher)
            .stateIn(viewModelScope, SharingStarted.Eagerly, "")

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

    // --- Workout actions: each runs on the runner, which moves to the journal thread -----------

    override fun start(target: StartTarget) {
        viewModelScope.launch {
            val template = withContext(graph.dispatcher) { freshTemplate(target) } ?: return@launch
            runner.start(template)
        }
    }

    /** A template with new exercise and set ids, so two workouts from one plan never share an id. */
    private fun freshTemplate(target: StartTarget): WorkoutTemplate? {
        if (target == StartTarget.Quick) return WorkoutTemplate.quick()
        val key = graph.journal.binding()?.accountKey ?: return null
        val raw = (graph.journal.plans(key)?.body as? WatchMessageBody.PlansSnapshot)?.raw ?: return null
        val makeId = { UUID.randomUUID().toString().lowercase() }
        return when (target) {
            StartTarget.Today -> WorkoutTemplate.today(raw, makeId)
            is StartTarget.Plan -> WorkoutTemplate.fromPlan(raw, target.planId, makeId)
            StartTarget.Quick -> null
        }
    }

    override fun log(values: SetValues, onDone: (Boolean) -> Unit) {
        viewModelScope.launch { onDone(runner.log(values)) }
    }

    override fun setRpe(setId: String, rpe: Double?) {
        viewModelScope.launch { runner.setRpe(setId, rpe) }
    }

    override fun extendRest() {
        viewModelScope.launch { runner.extendRest() }
    }

    override fun skipRest() {
        viewModelScope.launch { runner.skipRest() }
    }

    override fun pauseOrResume() {
        viewModelScope.launch {
            val running = workout.value as? RunnerState.Running ?: return@launch
            if (running.controller.status == "paused") runner.resume() else runner.pause()
        }
    }

    override fun addSet(exerciseId: String) {
        viewModelScope.launch { runner.addSet(exerciseId) }
    }

    override fun addExercise(name: String, kind: String) {
        viewModelScope.launch { runner.addExercise(name, kind, null) }
    }

    override fun focus(exerciseId: String) {
        viewModelScope.launch { runner.focus(exerciseId) }
    }

    override fun finish() {
        viewModelScope.launch { runner.finish() }
    }

    override fun discard() {
        viewModelScope.launch { runner.discard() }
    }

    override fun dismiss() = runner.dismiss()

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
            recent = recent(raw),
        )
    }

    private fun recent(raw: JsonObject?): List<RecentExercise> =
        (raw?.get("recent_exercises") as? JsonArray).orEmpty().mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            val name = (item["name"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
            val kind = (item["kind"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
            RecentExercise(name, kind)
        }
}
