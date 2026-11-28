package `in`.beyondrep.wear.workout

import `in`.beyondrep.wear.exercise.ExerciseOwner
import `in`.beyondrep.wear.exercise.ExerciseSensors
import `in`.beyondrep.wear.exercise.SensorReading
import `in`.beyondrep.wear.exercise.SensorStart
import `in`.beyondrep.wear.exercise.ServiceControl
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** Sensors that report what the test scripts and count what the runner asked. */
internal class FakeSensors(
    var owner: ExerciseOwner = ExerciseOwner.NONE,
    var startResult: SensorStart = SensorStart(heartRate = true, calories = true),
    private val scripted: List<SensorReading> = emptyList(),
    private val trace: MutableList<String>? = null,
) : ExerciseSensors {
    /** While set, owner() waits on it: a Health Services call that has not answered yet. */
    var ownerGate: CompletableDeferred<Unit>? = null
    val ownerEntered = CompletableDeferred<Unit>()

    var started = 0
    var attached = 0
    var ended = 0
    var paused = 0
    var resumed = 0

    override suspend fun owner(): ExerciseOwner {
        ownerGate?.let {
            ownerEntered.complete(Unit)
            it.await()
        }
        return owner
    }

    override suspend fun start(): SensorStart {
        started += 1
        trace?.add("sensors.start")
        return startResult
    }

    override suspend fun attach(): SensorStart {
        attached += 1
        return startResult
    }

    override suspend fun pause() {
        paused += 1
    }

    override suspend fun resume() {
        resumed += 1
    }

    override suspend fun end() {
        ended += 1
    }

    override val readings: Flow<SensorReading> = flow { scripted.forEach { emit(it) } }
}

internal class FakeServiceControl(private val trace: MutableList<String>? = null) : ServiceControl {
    var started = false
    var stopped = false

    override fun startForeground() {
        trace?.add("service.start")
        started = true
        stopped = false
    }

    override fun stop() {
        stopped = true
        started = false
    }
}
