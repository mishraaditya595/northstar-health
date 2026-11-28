package `in`.beyondrep.wear.core.session

import java.time.Instant
import kotlin.math.floor

/**
 * Latest and average heart rate of one workout. Memory only: it is never journaled, queued or
 * sent. Samples outside 1 to 250 bpm are ignored.
 */
class HeartRateTracker {
    private var sum = 0.0
    private var count = 0
    private var latest: Double? = null

    /** The latest valid sample, rounded; the UI hides it while the sensor reports unavailable. */
    val current: Int? get() = latest?.let { floor(it + 0.5).toInt() }

    val average: Int? get() = if (count == 0) null else floor(sum / count + 0.5).toInt()

    @Suppress("UNUSED_PARAMETER")
    fun add(bpm: Double, at: Instant) {
        if (!(bpm >= MIN && bpm <= MAX)) return
        sum += bpm
        count += 1
        latest = bpm
    }

    fun reset() {
        sum = 0.0
        count = 0
        latest = null
    }

    private companion object {
        const val MIN = 1.0
        const val MAX = 250.0
    }
}
