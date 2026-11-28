package `in`.beyondrep.wear.workout

import android.content.Context
import android.os.VibrationEffect
import android.os.PowerManager
import android.os.Vibrator
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.exercise.HealthServicesSensors
import `in`.beyondrep.wear.exercise.WorkoutServiceControl
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/** Builds the real runner: Health Services sensors, the foreground service and the rest haptic. */
object RunnerFactory {
    private const val PREFS = "beyondrep_watch"
    private const val DEVICE_ID_KEY = "watchInstallationId"

    /** `"watch-" + UUID`, created once and kept. */
    fun deviceId(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.getString(DEVICE_ID_KEY, null)?.let { return it }
        val made = "watch-" + UUID.randomUUID().toString().lowercase()
        prefs.edit().putString(DEVICE_ID_KEY, made).apply()
        return made
    }

    fun create(graph: WatchGraph, context: Context): WorkoutRunner {
        val app = context.applicationContext
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val vibrator = app.getSystemService(Vibrator::class.java)
        val haptics = RestHaptics(scope, Instant::now, PowerHapticWakeLock(app)) {
            vibrator?.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
        }
        return WorkoutRunner(
            graph, HealthServicesSensors(app), WorkoutServiceControl(app), Instant::now, deviceId(app),
            { ZoneId.systemDefault().id }, scope, haptics)
    }
}

/** The rest pulse's partial wake lock over `PowerManager`. */
private class PowerHapticWakeLock(context: Context) : HapticWakeLock {
    private val lock = context.getSystemService(PowerManager::class.java)
        ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "beyondrep:rest")
        ?.apply { setReferenceCounted(false) }

    override fun acquire(timeoutMs: Long) {
        lock?.acquire(timeoutMs)
    }

    override fun release() {
        lock?.takeIf { it.isHeld }?.release()
    }
}
