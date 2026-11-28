package `in`.beyondrep.wear.workout

import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.session.HeartRateTracker
import `in`.beyondrep.wear.core.session.OrphanSessionPolicy
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.core.session.WorkoutSummary
import `in`.beyondrep.wear.core.session.WorkoutTemplate
import `in`.beyondrep.wear.exercise.ExerciseOwner
import `in`.beyondrep.wear.exercise.ExerciseSensors
import `in`.beyondrep.wear.exercise.SensorReading
import `in`.beyondrep.wear.exercise.SensorStart
import `in`.beyondrep.wear.exercise.ServiceControl
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.util.UUID
import kotlin.math.roundToInt

sealed interface RunnerState {
    data object Idle : RunnerState

    data class Blocked(val reason: String) : RunnerState

    /** [heartRate] and [calories] are live, memory only; null shows as a dash. */
    data class Running(
        val controller: WorkoutController,
        val heartRate: Int?,
        val calories: Int?,
        val hrAvailable: Boolean,
        /** The unit weights are entered in: the phone's unit (the binding). */
        val unit: String = "kg",
    ) : RunnerState

    data class Finished(val summary: WorkoutSummary) : RunnerState
}

/**
 * Drives one workout: the journal-backed [WorkoutController], the Health Services session (only
 * for sensors and to keep the process alive) and the foreground service. The journal is the
 * authority: a set shows as saved only after its commit. Everything that touches the journal runs
 * on `graph.dispatcher`. Heart rate and calories live in memory only.
 */
class WorkoutRunner(
    private val graph: WatchGraph,
    private val sensors: ExerciseSensors,
    private val service: ServiceControl,
    private val clock: () -> Instant,
    private val deviceId: String,
    private val timeZone: () -> String,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    private val haptics: RestHaptics? = null,
) {
    private val _state = MutableStateFlow<RunnerState>(RunnerState.Idle)
    val state: StateFlow<RunnerState> = _state

    private val tracker = HeartRateTracker()
    private var calories: Int? = null
    private var readingsJob: Job? = null
    private val makeId: () -> String = { UUID.randomUUID().toString().lowercase() }

    private val running: RunnerState.Running? get() = _state.value as? RunnerState.Running

    /** Follows account changes: when the bound account is gone or another one, the workout is discarded. */
    fun observe(): Job = scope.launch {
        graph.revision.collect { syncAccount() }
    }

    private suspend fun <T> safe(default: T, block: suspend () -> T): T = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        default
    }

    private fun beginReadings(start: SensorStart) {
        readingsJob?.cancel()
        synchronized(tracker) {
            tracker.reset()
            calories = null
        }
        _state.value.let { current ->
            if (current is RunnerState.Running) {
                _state.value = current.copy(heartRate = null, calories = null, hrAvailable = start.heartRate)
            }
        }
        readingsJob = scope.launch { sensors.readings.collect(::onReading) }
    }

    private fun onReading(reading: SensorReading) {
        synchronized(tracker) {
            when (reading) {
                is SensorReading.HeartRate -> tracker.add(reading.bpm, reading.at)
                is SensorReading.Calories -> calories = if (reading.total > 0) reading.total.roundToInt() else null
                SensorReading.Unavailable -> Unit
            }
            val current = _state.value as? RunnerState.Running ?: return
            val hr = if (reading is SensorReading.Unavailable) null else tracker.current
            _state.value = current.copy(heartRate = hr, calories = calories)
        }
    }

    suspend fun start(template: WorkoutTemplate) = withContext(graph.dispatcher) {
        if (running != null) return@withContext
        val binding = graph.journal.binding() ?: return@withContext
        if (safe(ExerciseOwner.NONE) { sensors.owner() } == ExerciseOwner.OTHER_APP) {
            _state.value = RunnerState.Blocked(OTHER_APP_MESSAGE)
            return@withContext
        }
        val controller = WorkoutController.start(
            template, graph.journal, binding.accountKey, binding.unit, deviceId, clock, timeZone(), makeId)
        _state.value = RunnerState.Running(controller, null, null, hrAvailable = false, unit = binding.unit)
        val started = safe(SensorStart(heartRate = false, calories = false)) { sensors.start() }
        beginReadings(started)
        safe(Unit) { service.startForeground() }
        didAct(controller)
    }

    /** Clears a blocked or finished screen. */
    fun dismiss() {
        if (_state.value is RunnerState.Blocked || _state.value is RunnerState.Finished) _state.value = RunnerState.Idle
    }

    private suspend fun act(block: (WorkoutController) -> Unit): Boolean = withContext(graph.dispatcher) {
        val current = running ?: return@withContext false
        val committed = try {
            block(current.controller)
            true
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            false
        }
        didAct(current.controller)
        committed
    }

    private fun didAct(controller: WorkoutController) {
        haptics?.onDeadline(controller.restDeadline)
        graph.bump()
    }

    suspend fun log(values: SetValues) = act { it.log(values) }

    suspend fun setRpe(setId: String, rpe: Double?) = act { it.setRpe(setId, rpe) }

    suspend fun skip(setId: String) = act { it.skip(setId) }

    suspend fun extendRest() = act { it.extendRest() }

    suspend fun skipRest() = act { it.skipRest() }

    suspend fun addSet(exerciseId: String) = act { it.addSet(exerciseId) }

    suspend fun addExercise(name: String, kind: String, muscle: String?) = act { it.addExercise(name, kind, muscle) }

    suspend fun focus(exerciseId: String) = act { it.focus(exerciseId) }

    /** The sensor session changes only after the journal commit succeeded. */
    suspend fun pause() {
        if (act { it.pause() }) safe(Unit) { sensors.pause() }
    }

    suspend fun resume() {
        if (act { it.resume() }) safe(Unit) { sensors.resume() }
    }

    /** Save: record the finish, end the sensors, queue the completed workout, show the summary and send it. */
    suspend fun finish() {
        withContext(graph.dispatcher) {
            val current = running ?: return@withContext
            val controller = current.controller
            if (!controller.canSave) return@withContext
            try {
                controller.markCompleted()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                return@withContext
            }
            val endedAt = clock()
            safe(Unit) { sensors.end() }
            readingsJob?.cancel()
            // A failed queue is retried by restore(): the finished session is in the journal.
            safe(Unit) { controller.queueCompleted(null) }
            val summary = synchronized(tracker) { WorkoutSummary.of(controller, endedAt, tracker.average, calories) }
            haptics?.onDeadline(null)
            safe(Unit) { service.stop() }
            _state.value = RunnerState.Finished(summary)
            graph.bump()
        }
        graph.outbox.flush()
    }

    /** Commit first; nothing from a discarded workout is sent. */
    suspend fun discard() {
        withContext(graph.dispatcher) {
            val current = running ?: return@withContext
            try {
                current.controller.discard()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                return@withContext
            }
            wrapUp()
        }
    }

    private suspend fun wrapUp() {
        readingsJob?.cancel()
        haptics?.onDeadline(null)
        safe(Unit) { sensors.end() }
        safe(Unit) { service.stop() }
        _state.value = RunnerState.Idle
        graph.bump()
    }

    /**
     * Discards the running workout when the bound account is gone or differs from the workout's
     * (the phone signed out or switched). Nothing is sent; another account never sees it.
     */
    suspend fun syncAccount() {
        withContext(graph.dispatcher) {
            val current = running ?: return@withContext
            val bound = graph.journal.binding()?.accountKey
            if (bound == current.controller.accountKey) return@withContext
            // The wipe may already have removed the session rows: ending the sensors is what matters.
            safe(Unit) { current.controller.discard() }
            wrapUp()
        }
    }

    /**
     * After a relaunch: queues every finished-but-unqueued workout of any account, restores the
     * bound account's running workout and reconnects the sensors, and ends a platform session no
     * journal session explains.
     */
    suspend fun restore() {
        withContext(graph.dispatcher) {
            val journal = graph.journal
            val binding = journal.binding()
            var restored: WorkoutController? = null
            if (binding != null && running == null) {
                restored = WorkoutController.restore(
                    journal, binding.accountKey, binding.unit, deviceId, clock, timeZone())
            }
            val owner = safe(ExerciseOwner.NONE) { sensors.owner() }
            for (pending in WorkoutController.pendingFinishAllAccounts(journal)) {
                safe(Unit) {
                    WorkoutController.queuePendingFinish(
                        pending.sessionId, journal, null, pending.accountKey, null, makeId, clock)
                }
            }
            if (restored != null) {
                _state.value = RunnerState.Running(restored, null, null, hrAvailable = false, unit = binding?.unit ?: "kg")
                when (owner) {
                    ExerciseOwner.OURS -> beginReadings(safe(SensorStart(false, false)) { sensors.attach() })
                    ExerciseOwner.NONE -> beginReadings(safe(SensorStart(false, false)) { sensors.start() })
                    ExerciseOwner.OTHER_APP -> Unit
                }
                safe(Unit) { service.startForeground() }
                didAct(restored)
            } else if (running == null &&
                owner == ExerciseOwner.OURS &&
                OrphanSessionPolicy.shouldDiscard(restoredSession = false, unresolvedPendingFinish = binding == null)
            ) {
                safe(Unit) { sensors.end() }
            }
            graph.bump()
        }
        graph.outbox.flush()
    }

    companion object {
        const val OTHER_APP_MESSAGE = "Another workout app is recording. End it there first."
    }
}
