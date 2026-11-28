package `in`.beyondrep.wear.exercise

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import `in`.beyondrep.wear.WearMainActivity
import `in`.beyondrep.wear.app.WatchGraph
import `in`.beyondrep.wear.workout.RunnerState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** [ServiceControl] over [WorkoutService]. */
class WorkoutServiceControl(private val context: Context) : ServiceControl {
    override fun startForeground() {
        ContextCompat.startForegroundService(context, Intent(context, WorkoutService::class.java))
    }

    override fun stop() {
        context.stopService(Intent(context, WorkoutService::class.java))
    }
}

/**
 * Keeps the process alive while a workout records and shows the ongoing activity on the watch
 * face. The text is the workout name and set count, never a health value.
 */
class WorkoutService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var job: Job? = null
    private var builder: NotificationCompat.Builder? = null
    private var ongoing: OngoingActivity? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Workout", NotificationManager.IMPORTANCE_LOW))
        val touch = PendingIntent.getActivity(
            this, 0,
            Intent(this, WearMainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
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
        startForeground(NOTIFICATION_ID, notification.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        job?.cancel()
        job = scope.launch {
            WatchGraph.get(applicationContext).revision.collect { refresh(manager) }
        }
        return START_NOT_STICKY
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
        scope.cancel()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL_ID = "workout"
        const val NOTIFICATION_ID = 4101
        const val ICON = android.R.drawable.ic_media_play
    }
}
