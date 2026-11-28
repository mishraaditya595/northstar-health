package `in`.beyondrep.wear.exercise

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import `in`.beyondrep.wear.WearMainActivity
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.workout.RunnerState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Which of the two requests for the service came first. `stopService` right after
 * `startForegroundService`, before the service called `startForeground`, makes the system throw
 * `ForegroundServiceDidNotStartInTimeException`, so an early stop is remembered and the service
 * stops itself once it is in the foreground.
 */
internal object WorkoutServiceState {
    private var foreground = false
    private var stopRequested = false

    @Synchronized
    fun starting() {
        stopRequested = false
    }

    /** Called once the service is in the foreground; true when a stop came in meanwhile. */
    @Synchronized
    fun enteredForeground(): Boolean {
        foreground = true
        return stopRequested
    }

    /** True when the service is in the foreground and can be stopped now; otherwise the stop is remembered. */
    @Synchronized
    fun requestStop(): Boolean {
        if (foreground) return true
        stopRequested = true
        return false
    }

    @Synchronized
    fun ended() {
        foreground = false
        stopRequested = false
    }
}

/**
 * [ServiceControl] over [WorkoutService]. On Android 14 and later a `health` foreground service
 * throws `SecurityException` unless one of the sensor permissions is granted, so without
 * `BODY_SENSORS` and `ACTIVITY_RECOGNITION` the workout records without the service: it still
 * records and is saved, but the system may stop the process while the screen is off (a relaunch
 * restores it from the journal).
 */
class WorkoutServiceControl(private val context: Context) : ServiceControl {
    override fun startForeground() {
        if (!mayRunHealthService(context)) return
        WorkoutServiceState.starting()
        ContextCompat.startForegroundService(context, Intent(context, WorkoutService::class.java))
    }

    override fun stop() {
        if (WorkoutServiceState.requestStop()) context.stopService(Intent(context, WorkoutService::class.java))
    }

    companion object {
        /** Before Android 14 the `health` type has no permission rule. From 14, one sensor permission is required. */
        fun mayRunHealthService(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
                granted(context, Manifest.permission.BODY_SENSORS) ||
                granted(context, Manifest.permission.ACTIVITY_RECOGNITION)

        private fun granted(context: Context, permission: String) =
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }
}

/**
 * Keeps the process alive while a workout records and shows the ongoing activity on the watch
 * face. The text is the workout name and set count, never a health value.
 */
class WorkoutService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var job: Job? = null
    private var restoreJob: Job? = null
    private var builder: NotificationCompat.Builder? = null
    private var ongoing: OngoingActivity? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!WorkoutServiceControl.mayRunHealthService(this)) {
            // A permission was revoked since Start: record without the service.
            WorkoutServiceState.ended()
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Workout", NotificationManager.IMPORTANCE_LOW))
        val touch = PendingIntent.getActivity(
            this, 0,
            Intent(this, WearMainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val text = statusText()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(ICON)
            .setContentTitle("BeyondRep")
            .setContentText(text)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(touch)
        builder = notification
        ongoing = OngoingActivity.Builder(applicationContext, NOTIFICATION_ID, notification)
            .setStaticIcon(ICON)
            .setTouchIntent(touch)
            .setStatus(status(text))
            .build()
            .also { it.apply(applicationContext) }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        } else {
            0
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification.build(), type)
        } catch (_: Exception) {
            // The system refused (a missing permission or a restriction): the workout records without the service.
            WorkoutServiceState.ended()
            stopSelf()
            return START_NOT_STICKY
        }
        if (WorkoutServiceState.enteredForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }
        job?.cancel()
        val graph = WatchGraph.get(applicationContext)
        job = scope.launch { graph.revision.collect { refresh(manager) } }
        if (graph.runner.state.value !is RunnerState.Running) {
            // The system restarted the service after the process died: bring the workout back from the journal.
            restoreJob?.cancel()
            restoreJob = scope.launch {
                try {
                    graph.runner.restore()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    // Not user actionable; the activity tries again on launch.
                }
                if (graph.runner.state.value !is RunnerState.Running) stopSelf()
            }
        }
        return START_STICKY
    }

    private fun status(text: String): Status =
        Status.Builder().addTemplate("#text#").addPart("text", Status.TextPart(text)).build()

    private fun statusText(): String {
        val running = WatchGraph.get(applicationContext).runner.state.value as? RunnerState.Running
            ?: return "Workout in progress"
        val sets = running.controller.state.completedSets
        return "${running.controller.template.name} · $sets ${if (sets == 1) "set" else "sets"}"
    }

    private fun refresh(manager: NotificationManager) {
        val text = statusText()
        val current = builder ?: return
        val notification: Notification = current.setContentText(text).build()
        manager.notify(NOTIFICATION_ID, notification)
        ongoing?.update(applicationContext, status(text))
    }

    override fun onDestroy() {
        WorkoutServiceState.ended()
        scope.cancel()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL_ID = "workout"
        const val NOTIFICATION_ID = 4101
        const val ICON = android.R.drawable.ic_media_play
    }
}
