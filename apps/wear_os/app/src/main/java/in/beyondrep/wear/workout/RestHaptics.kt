package `in`.beyondrep.wear.workout

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/**
 * One pulse per rest deadline, scheduled from the deadline itself so it also fires with the screen
 * off (the foreground service keeps the process running). A deadline already past by more than
 * 5 s when it is first seen (a relaunch after the rest ended) gets no pulse. Same rule as
 * `hapticDeadline` in the watchOS AppModel.
 */
class RestHaptics(
    private val scope: CoroutineScope,
    private val clock: () -> Instant,
    private val pulse: () -> Unit,
) {
    private var job: Job? = null
    private var deadline: Instant? = null

    @Synchronized
    fun onDeadline(next: Instant?) {
        if (next == deadline) return
        job?.cancel()
        job = null
        deadline = next
        if (next == null) return
        val remaining = Duration.between(clock(), next).toMillis()
        if (remaining < -PAST_GRACE_MS) return
        job = scope.launch {
            if (remaining > 0) delay(remaining)
            pulse()
        }
    }

    private companion object {
        const val PAST_GRACE_MS = 5_000L
    }
}
