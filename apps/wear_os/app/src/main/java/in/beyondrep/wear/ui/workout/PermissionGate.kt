package `in`.beyondrep.wear.ui.workout

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat

/**
 * Asks for sensors, activity recognition and notifications once, before the first Start. A denial
 * still starts the workout: it records without heart rate, calories or the notification.
 */
class PermissionGate(
    private val request: (Array<String>) -> Unit,
    private val missing: () -> List<String>,
    private val alreadyAsked: () -> Boolean,
    private val markAsked: () -> Unit,
    private val setPending: ((() -> Unit)?) -> Unit,
) {
    /** Runs [then] after the permission prompt (or at once when there is nothing to ask). */
    fun afterPrompt(then: () -> Unit) {
        val needed = missing()
        if (needed.isEmpty() || alreadyAsked()) {
            then()
            return
        }
        markAsked()
        setPending(then)
        request(needed.toTypedArray())
    }

    companion object {
        private const val PREFS = "beyondrep_watch"
        private const val ASKED_KEY = "workoutPermissionsAsked"

        fun wanted(): List<String> = buildList {
            add(Manifest.permission.BODY_SENSORS)
            add(Manifest.permission.ACTIVITY_RECOGNITION)
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }

        fun missing(context: Context): List<String> =
            wanted().filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
    }
}

@Composable
fun rememberPermissionGate(): PermissionGate {
    val context = LocalContext.current
    var pending by remember { mutableStateOf<(() -> Unit)?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        val next = pending
        pending = null
        next?.invoke()
    }
    return remember(context, launcher) {
        val prefs = context.getSharedPreferences("beyondrep_watch", Context.MODE_PRIVATE)
        PermissionGate(
            request = { launcher.launch(it) },
            missing = { PermissionGate.missing(context) },
            alreadyAsked = { prefs.getBoolean("workoutPermissionsAsked", false) },
            markAsked = { prefs.edit().putBoolean("workoutPermissionsAsked", true).apply() },
            setPending = { pending = it },
        )
    }
}
