package `in`.beyondrep.wear.exercise

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.health.services.client.ExerciseClient
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DataTypeAvailability
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseTrackedStatus
import androidx.health.services.client.data.ExerciseLapSummary
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseUpdate
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.guava.await
import java.time.Instant

/** Who runs the platform exercise right now. */
enum class ExerciseOwner { NONE, OURS, OTHER_APP }

/** What the device supports and the person allowed. Heart rate and calories are live values for the screen only. */
data class SensorStart(val heartRate: Boolean, val calories: Boolean)

/** One live reading. Memory only: never journaled, queued, sent or logged. */
sealed interface SensorReading {
    data class HeartRate(val bpm: Double, val at: Instant) : SensorReading

    data class Calories(val total: Double) : SensorReading

    /** Heart rate is not being measured right now (off wrist, still acquiring). */
    data object Unavailable : SensorReading
}

/** The platform exercise session, used only for sensors and to keep the process alive. The journal is the authority. */
interface ExerciseSensors {
    suspend fun owner(): ExerciseOwner

    /** Starts a new exercise session and returns what it measures. */
    suspend fun start(): SensorStart

    /** Listens to an exercise session of ours that survived a process death. */
    suspend fun attach(): SensorStart

    suspend fun pause()

    suspend fun resume()

    /** Ends the exercise session. Harmless when none is running. */
    suspend fun end()

    val readings: Flow<SensorReading>
}

/** [ExerciseSensors] over Health Services `ExerciseClient`: strength training, heart rate and calories where supported and allowed, no GPS, no auto-pause. */
class HealthServicesSensors(private val context: Context) : ExerciseSensors {
    private val client: ExerciseClient get() = HealthServices.getClient(context).exerciseClient
    private val flow = MutableSharedFlow<SensorReading>(extraBufferCapacity = 64)
    private var callback: ExerciseUpdateCallback? = null

    override val readings: Flow<SensorReading> = flow.asSharedFlow()

    override suspend fun owner(): ExerciseOwner {
        val info = client.getCurrentExerciseInfoAsync().await()
        return when (info.exerciseTrackedStatus) {
            ExerciseTrackedStatus.OWNED_EXERCISE_IN_PROGRESS -> ExerciseOwner.OURS
            ExerciseTrackedStatus.OTHER_APP_IN_PROGRESS -> ExerciseOwner.OTHER_APP
            else -> ExerciseOwner.NONE
        }
    }

    private fun allowed(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /** The exercise type and data types this device supports, limited to what the person allowed. */
    private suspend fun plan(): Pair<ExerciseType, Set<DataType<*, *>>> {
        val capabilities = client.getCapabilitiesAsync().await()
        val supported = capabilities.supportedExerciseTypes
        val type = when {
            ExerciseType.STRENGTH_TRAINING in supported -> ExerciseType.STRENGTH_TRAINING
            else -> ExerciseType.WEIGHTLIFTING
        }
        val available = if (type in supported) capabilities.getExerciseTypeCapabilities(type).supportedDataTypes else emptySet()
        val wanted = mutableSetOf<DataType<*, *>>()
        if (DataType.HEART_RATE_BPM in available && allowed(Manifest.permission.BODY_SENSORS)) wanted += DataType.HEART_RATE_BPM
        if (DataType.CALORIES_TOTAL in available && allowed(Manifest.permission.ACTIVITY_RECOGNITION)) wanted += DataType.CALORIES_TOTAL
        return type to wanted
    }

    private fun register() {
        if (callback != null) return
        val created = object : ExerciseUpdateCallback {
            override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
                if (update.exerciseStateInfo.state.isEnded) {
                    // The platform ended the session (another app, the system): nothing live is measured any more.
                    flow.tryEmit(SensorReading.Unavailable)
                    return
                }
                val now = Instant.now()
                update.latestMetrics.getData(DataType.HEART_RATE_BPM).lastOrNull()?.let {
                    flow.tryEmit(SensorReading.HeartRate(it.value, now))
                }
                update.latestMetrics.getData(DataType.CALORIES_TOTAL)?.let {
                    flow.tryEmit(SensorReading.Calories(it.total))
                }
            }

            override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) = Unit

            override fun onRegistered() = Unit

            override fun onRegistrationFailed(throwable: Throwable) = Unit

            override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) {
                if (dataType == DataType.HEART_RATE_BPM && availability is DataTypeAvailability &&
                    availability != DataTypeAvailability.AVAILABLE
                ) {
                    flow.tryEmit(SensorReading.Unavailable)
                }
            }
        }
        callback = created
        client.setUpdateCallback(created)
    }

    override suspend fun start(): SensorStart {
        val (type, dataTypes) = plan()
        val config = ExerciseConfig.builder(type)
            .setDataTypes(dataTypes)
            .setIsAutoPauseAndResumeEnabled(false)
            .setIsGpsEnabled(false)
            .build()
        register()
        client.startExerciseAsync(config).await()
        return SensorStart(DataType.HEART_RATE_BPM in dataTypes, DataType.CALORIES_TOTAL in dataTypes)
    }

    override suspend fun attach(): SensorStart {
        val (_, dataTypes) = plan()
        register()
        return SensorStart(DataType.HEART_RATE_BPM in dataTypes, DataType.CALORIES_TOTAL in dataTypes)
    }

    override suspend fun pause() {
        client.pauseExerciseAsync().await()
    }

    override suspend fun resume() {
        client.resumeExerciseAsync().await()
    }

    override suspend fun end() {
        try {
            client.endExerciseAsync().await()
        } finally {
            callback?.let { client.clearUpdateCallbackAsync(it) }
            callback = null
        }
    }
}

/** Keeps the app process alive and shows the ongoing activity while a workout records. */
interface ServiceControl {
    fun startForeground()

    fun stop()
}
