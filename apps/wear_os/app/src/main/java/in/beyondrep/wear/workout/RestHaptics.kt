package `in`.beyondrep.wear.workout

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/** A partial wake lock held while a rest pulse is pending. Not reference counted: release drops it. */
interface HapticWakeLock {
    fun acquire(timeoutMs: Long)

    fun release()

    object None : HapticWakeLock {
        override fun acquire(timeoutMs: Long) = Unit

        override fun release() = Unit
    }
}

/**
 * One pulse per rest deadline, scheduled from the deadline itself. While a deadline is pending
 * the class holds a partial wake lock (timeout: the time left plus 5 s), so the timer still runs
 * with the screen off; the lock is released when the pulse fired or the deadline was replaced or
 * cleared. If the system kills the process there is no pulse (the journal and the Rest page are
 * still right on return). A deadline already past by more than 5 s when it is first seen (a
 * relaunch after the rest ended) gets no pulse. Same rule as `hapticDeadline` in the watchOS
 * AppModel.
 */
class RestHaptics(
    private val scope: CoroutineScope,
    private val clock: () -> Instant,
    private val wakeLock: HapticWakeLock = HapticWakeLock.None,
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
        wakeLock.release()
        if (next == null) return
        val remaining = Duration.between(clock(), next).toMillis()
        if (remaining < -PAST_GRACE_MS) return
        wakeLock.acquire(maxOf(0L, remaining) + HOLD_SLACK_MS)
        job = scope.launch {
            if (remaining > 0) delay(remaining)
            try {
                pulse()
            } finally {
                // Only the lock of this deadline: a newer one may already hold it.
                synchronized(this@RestHaptics) { if (deadline == next) wakeLock.release() }
            }
        }
    }

    private companion object {
        const val PAST_GRACE_MS = 5_000L
        const val HOLD_SLACK_MS = 5_000L
    }
}
