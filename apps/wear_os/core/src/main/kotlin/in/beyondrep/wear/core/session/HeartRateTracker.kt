package `in`.beyondrep.wear.core.session

import java.time.Instant
import kotlin.math.floor

/**
 * Latest and average heart rate of one workout, and its per-minute series. Memory only: nothing
 * here is journaled or sent; the caller builds `workout_health` from [minuteSeries].
 * Samples outside 1 to 250 bpm are ignored.
 */
class HeartRateTracker {
    private var sum = 0.0
    private var count = 0
    private var latest: Double? = null
    private val samples = mutableListOf<Pair<Long, Double>>()

    /** The latest valid sample, rounded; the UI hides it while the sensor reports unavailable. */
    val current: Int? get() = latest?.let { floor(it + 0.5).toInt() }

    val average: Int? get() = if (count == 0) null else floor(sum / count + 0.5).toInt()

    fun add(bpm: Double, at: Instant) {
        if (!(bpm >= MIN && bpm <= MAX)) return
        sum += bpm
        count += 1
        latest = bpm
        samples.add(at.toEpochMilli() to bpm)
    }

    /**
     * One average per started minute since [start] (the minute's start and the rounded mean), in
     * time order. Minutes without a valid sample and samples before [start] are left out.
     */
    fun minuteSeries(start: Instant): List<Pair<Instant, Int>> {
        val startMs = start.toEpochMilli()
        val sums = java.util.TreeMap<Long, Pair<Double, Int>>()
        for ((atMs, bpm) in samples) {
            if (atMs < startMs) continue
            val minute = (atMs - startMs) / 60_000
            val (total, n) = sums[minute] ?: (0.0 to 0)
            sums[minute] = (total + bpm) to (n + 1)
        }
        return sums.map { (minute, agg) ->
            start.plusSeconds(minute * 60) to floor(agg.first / agg.second + 0.5).toInt()
        }.filter { it.second >= SERIES_MIN } // workout_health takes 25 to 250
    }

    fun reset() {
        sum = 0.0
        count = 0
        latest = null
        samples.clear()
    }

    private companion object {
        const val MIN = 1.0
        const val MAX = 250.0
        const val SERIES_MIN = 25
    }
}
