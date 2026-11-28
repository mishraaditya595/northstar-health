package `in`.beyondrep.wear.workout

import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import `in`.beyondrep.wear.core.session.HeartRateTracker
import `in`.beyondrep.wear.core.session.OrphanSessionPolicy
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.core.session.WorkoutHealthBuilder
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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
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
 * on `graph.dispatcher`. Heart rate and calories live in memory; at finish the per-minute series and the total go into one journal row (`session_health`) until the phone's ack. Start, restore, finish,
 * discard, account changes and every action take one [lock], so the awaits on Health Services
 * can never interleave two of them (two active sessions, an action on a half-restored workout).
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
    private var observing: Job? = null
    private val lock = Mutex()

    /** False from "heart rate unavailable" until the next sample, so a later calories update cannot bring back a stale value. */
    private var hrLive = true
    private val makeId: () -> String = { UUID.randomUUID().toString().lowercase() }

    private val running: RunnerState.Running? get() = _state.value as? RunnerState.Running

    /** Follows account changes: when the bound account is gone or another one, the workout is discarded. */
    @Synchronized
    fun observe(): Job {
        observing?.takeIf { it.isActive }?.let { return it }
        return scope.launch { graph.revision.collect { syncAccount() } }.also { observing = it }
    }

    private suspend fun <T> safe(default: T, block: suspend () -> T): T = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        default
    }

    /** A Health Services call that cannot hold the lock forever: a call that does not answer in time counts as failed. */
    private suspend fun <T> sensorCall(default: T, block: suspend () -> T): T =
        safe(default) { withTimeoutOrNull(SENSOR_TIMEOUT_MS) { block() } ?: default }

    private fun beginReadings(start: SensorStart) {
        readingsJob?.cancel()
        synchronized(tracker) {
            tracker.reset()
            calories = null
            hrLive = true
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
                is SensorReading.HeartRate -> {
                    tracker.add(reading.bpm, reading.at)
                    hrLive = true
                }
                is SensorReading.Calories -> calories = if (reading.total > 0) reading.total.roundToInt() else null
                SensorReading.Unavailable -> hrLive = false
            }
            val current = _state.value as? RunnerState.Running ?: return
            val hr = if (hrLive) tracker.current else null
            _state.value = current.copy(heartRate = hr, calories = calories)
        }
    }

    suspend fun start(template: WorkoutTemplate) = lock.withLock {
        withContext(graph.dispatcher) {
            if (running != null) return@withContext
            val binding = graph.journal.binding() ?: return@withContext
            if (sensorCall(ExerciseOwner.NONE) { sensors.owner() } == ExerciseOwner.OTHER_APP) {
                _state.value = RunnerState.Blocked(OTHER_APP_MESSAGE)
                return@withContext
            }
            val controller = WorkoutController.start(
                template, graph.journal, binding.accountKey, binding.unit, deviceId, clock, timeZone(), makeId)
            _state.value = RunnerState.Running(controller, null, null, hrAvailable = false, unit = binding.unit)
            // The service first: it must be in the foreground before the sensors start.
            safe(Unit) { service.startForeground() }
            val started = sensorCall(SensorStart(heartRate = false, calories = false)) { sensors.start() }
            beginReadings(started)
            didAct(controller)
        }
    }

    /** Clears a blocked or finished screen. */
    fun dismiss() {
        if (_state.value is RunnerState.Blocked || _state.value is RunnerState.Finished) _state.value = RunnerState.Idle
    }

    private suspend fun act(block: (WorkoutController) -> Unit): Boolean = lock.withLock { actLocked(block) }

    private suspend fun actLocked(block: (WorkoutController) -> Unit): Boolean = withContext(graph.dispatcher) {
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
        lock.withLock {
            if (actLocked { it.pause() }) sensorCall(Unit) { sensors.pause() }
        }
    }

    suspend fun resume() {
        lock.withLock {
            if (actLocked { it.resume() }) sensorCall(Unit) { sensors.resume() }
        }
    }

    /** Save: record the finish, end the sensors, queue the completed workout, show the summary and send it. */
    suspend fun finish() {
        lock.withLock { finishLocked() }
        graph.outbox.flush()
    }

    private suspend fun finishLocked() {
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
            sensorCall(Unit) { sensors.end() }
            readingsJob?.cancel()
            // A failed queue is retried by restore(): the finished session is in the journal.
            safe(Unit) { controller.queueCompleted(null) }
            // The series waits in the journal until the phone acks the workout. A failure only loses it.
            safe(Unit) { saveWorkoutHealth(controller, endedAt) }
            val summary = synchronized(tracker) { WorkoutSummary.of(controller, endedAt, tracker.average, calories) }
            haptics?.onDeadline(null)
            safe(Unit) { service.stop() }
            _state.value = RunnerState.Finished(summary)
            graph.bump()
        }
    }

    /**
     * Keeps the per-minute heart rate and the total calories next to the finished session (the
     * journal's only health rows, ADR-0015). Runs on the journal dispatcher. A workout with neither
     * still saves the message (empty series, no total) so the session reaches Health Connect.
     */
    private fun saveWorkoutHealth(controller: WorkoutController, endedAt: Instant) {
        val start = controller.startedAt
        val end = WorkoutController.completedAt(controller.sessionId, graph.journal) ?: endedAt
        val (series, kcal) = synchronized(tracker) { tracker.minuteSeries(start) to calories }
        val message = WorkoutHealthBuilder.message(
            controller.workoutId, start, end, series, kcal?.toDouble(), controller.accountKey, makeId(),
            WatchTimestamp.format(clock()),
        ) ?: return
        graph.journal.saveWorkoutHealth(controller.sessionId, controller.accountKey, message, end.toEpochMilli())
    }

    /** Commit first; nothing from a discarded workout is sent. */
    suspend fun discard() = lock.withLock {
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
        sensorCall(Unit) { sensors.end() }
        safe(Unit) { service.stop() }
        _state.value = RunnerState.Idle
        graph.bump()
    }

    /**
     * Discards the running workout when the bound account is gone or differs from the workout's
     * (the phone signed out or switched). Nothing is sent; another account never sees it.
     */
    suspend fun syncAccount() = lock.withLock {
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
     * After a relaunch: abandons active or paused sessions no bound account owns (another account,
     * or one the phone cleared while the process was dead), queues every finished-but-unqueued
     * workout of any account, restores the bound account's running workout and reconnects the
     * sensors, and ends a platform session no journal session explains. Nothing is ever saved to
     * the platform on Wear, so no finished workout keeps a platform session open.
     */
    suspend fun restore() {
        lock.withLock {
            withContext(graph.dispatcher) {
                val journal = graph.journal
                val binding = journal.binding()
                abandonUnownedSessions(binding?.accountKey)
                var restored: WorkoutController? = null
                if (binding != null && running == null) {
                    restored = WorkoutController.restore(
                        journal, binding.accountKey, binding.unit, deviceId, clock, timeZone())
                }
                val owner = sensorCall(ExerciseOwner.NONE) { sensors.owner() }
                for (pending in WorkoutController.pendingFinishAllAccounts(journal)) {
                    safe(Unit) {
                        WorkoutController.queuePendingFinish(
                            pending.sessionId, journal, null, pending.accountKey, null, makeId, clock)
                    }
                }
                if (restored != null) {
                    _state.value = RunnerState.Running(restored, null, null, hrAvailable = false, unit = binding?.unit ?: "kg")
                    safe(Unit) { service.startForeground() }
                    when (owner) {
                        ExerciseOwner.OURS -> beginReadings(sensorCall(SensorStart(false, false)) { sensors.attach() })
                        ExerciseOwner.NONE -> {
                            beginReadings(sensorCall(SensorStart(false, false)) { sensors.start() })
                            // A new platform session starts running: put it back to the journal's state.
                            if (restored.status == "paused") sensorCall(Unit) { sensors.pause() }
                        }
                        ExerciseOwner.OTHER_APP -> Unit
                    }
                    didAct(restored)
                } else if (running == null &&
                    owner == ExerciseOwner.OURS &&
                    OrphanSessionPolicy.shouldDiscard(restoredSession = false, unresolvedPendingFinish = false)
                ) {
                    sensorCall(Unit) { sensors.end() }
                }
                graph.bump()
            }
        }
        graph.outbox.flush()
    }

    /** Must run on the journal thread. Every session of an account that is not bound, or whose binding the phone cleared later, is abandoned. */
    private suspend fun abandonUnownedSessions(boundKey: String?) {
        val journal = graph.journal
        val boundSentAt = journal.bindingState()?.sentAtMs
        val unowned = journal.activeSessionAccounts().map { it.accountKey }.distinct().filter { key ->
            val cleared = journal.clearedAt(key)
            key != boundKey || (cleared != null && (boundSentAt == null || cleared >= boundSentAt))
        }
        for (key in unowned) {
            repeat(MAX_ABANDONED_PER_ACCOUNT) {
                safe(Unit) {
                    WorkoutController.restore(journal, key, "kg", deviceId, clock, timeZone())?.discard()
                }
            }
        }
    }

    companion object {
        const val SENSOR_TIMEOUT_MS = 10_000L
        private const val MAX_ABANDONED_PER_ACCOUNT = 5
        const val OTHER_APP_MESSAGE = "Another workout app is recording. End it there first."
    }
}
