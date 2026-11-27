package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.WatchTimestamp
import `in`.beyondrep.wear.core.contracts.WorkoutEventV2
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil

/**
 * The rest countdown, derived from the journal's events so it survives a relaunch: no timer state
 * is stored anywhere else (port of RestClock.swift).
 */
object RestClock {
    /**
     * The deadline of the highest-sequence `rest_started`, unless a later `rest_cleared`,
     * `set_logged`, `workout_paused`, `workout_completed` or `workout_abandoned` ended it.
     */
    fun deadline(events: List<WorkoutEventV2>): Instant? {
        var deadline: Instant? = null
        for (event in events.sortedBy { it.header.sequence }) {
            when (event) {
                is WorkoutEventV2.RestStarted -> deadline = WatchTimestamp.instant(event.deadlineUtc)
                is WorkoutEventV2.RestCleared, is WorkoutEventV2.SetLogged, is WorkoutEventV2.WorkoutPaused,
                is WorkoutEventV2.WorkoutCompleted, is WorkoutEventV2.WorkoutAbandoned -> deadline = null
                else -> Unit
            }
        }
        return deadline
    }

    /** Seconds for a new rest that adds 30 s to what remains, 1 to 3600. */
    fun extendedSeconds(remaining: Duration): Int {
        val seconds = remaining.toNanos() / 1e9
        return minOf(3600L, maxOf(1L, ceil(seconds).toLong() + 30)).toInt()
    }
}
