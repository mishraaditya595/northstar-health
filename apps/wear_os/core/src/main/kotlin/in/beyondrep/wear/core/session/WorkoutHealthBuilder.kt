package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.HeartRatePoint
import `in`.beyondrep.wear.core.contracts.WatchMessage
import `in`.beyondrep.wear.core.contracts.WatchMessageBody
import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import java.time.Instant

/** Builds the `workout_health` message of a finished workout (stage 3b). */
object WorkoutHealthBuilder {
    private const val MAX_POINTS = 600
    private const val MAX_KCAL = 10_000.0

    /**
     * [series] comes from `HeartRateTracker.minuteSeries`. Points outside the workout are dropped.
     * Returns null only for a workout that does not end after it started (to the second). With no
     * heart rate and no valid calories the message still goes, with an empty series and no total, so
     * the session itself reaches Health Connect. Values are only in the message the caller keeps in
     * the journal's `session_health` row.
     */
    fun message(
        workoutId: String,
        start: Instant,
        end: Instant,
        series: List<Pair<Instant, Int>>,
        totalKcal: Double?,
        accountKey: String,
        messageId: String,
        sentAtUtc: String,
    ): WatchMessage? {
        val startText = WatchTimestamp.format(start)
        val endText = WatchTimestamp.format(end)
        if (WatchTimestamp.milliseconds(endText)!! <= WatchTimestamp.milliseconds(startText)!!) return null
        val points = series
            .filter { !it.first.isBefore(start) && WatchTimestamp.format(it.first) <= endText }
            .take(MAX_POINTS)
            .map { HeartRatePoint(WatchTimestamp.format(it.first), it.second) }
        val kcal = totalKcal?.takeIf { it > 0 && it <= MAX_KCAL }
        return WatchMessage(
            messageId, sentAtUtc, accountKey,
            WatchMessageBody.WorkoutHealth(workoutId, startText, endText, points, kcal))
    }
}
