package `in`.beyondrep.wear.ui.workout

import `in`.beyondrep.wear.core.contracts.SetValues
import `in`.beyondrep.wear.workout.RunnerState
import java.time.Duration
import java.time.Instant

/** What the person asked to start. */
sealed interface StartTarget {
    /** Today's program workout. */
    data object Today : StartTarget

    data class Plan(val planId: String) : StartTarget

    data object Quick : StartTarget
}

/** Everything the workout screens can do. The view model runs each action on the runner. */
interface WorkoutActions {
    fun start(target: StartTarget)

    /** [onDone] gets true once the journal stored the set, false when the commit failed. */
    fun log(values: SetValues, onDone: (Boolean) -> Unit = {})

    fun setRpe(setId: String, rpe: Double?)

    fun extendRest()

    fun skipRest()

    fun pauseOrResume()

    fun addSet(exerciseId: String)

    fun addExercise(name: String, kind: String)

    fun focus(exerciseId: String)

    fun finish()

    fun discard()

    /** Closes the summary or the "another app" message. */
    fun dismiss()

    /** Does nothing: for screens that never act. */
    object None : WorkoutActions {
        override fun start(target: StartTarget) = Unit
        override fun log(values: SetValues, onDone: (Boolean) -> Unit) = Unit
        override fun setRpe(setId: String, rpe: Double?) = Unit
        override fun extendRest() = Unit
        override fun skipRest() = Unit
        override fun pauseOrResume() = Unit
        override fun addSet(exerciseId: String) = Unit
        override fun addExercise(name: String, kind: String) = Unit
        override fun focus(exerciseId: String) = Unit
        override fun finish() = Unit
        override fun discard() = Unit
        override fun dismiss() = Unit
    }
}

/** An exercise the phone listed as recent, for "+ Add exercise". */
data class RecentExercise(val name: String, val kind: String)

/**
 * What the workout screens render besides the controller: the runner state, the clock tick, the
 * journal revision (the controller is mutable, so screens recompute when it changes), ambient mode
 * and the summary's status line.
 */
data class WorkoutUi(
    val runner: RunnerState = RunnerState.Idle,
    val now: Instant = Instant.EPOCH,
    val revision: Long = 0,
    val ambient: Boolean = false,
    val summaryStatus: String = "",
    /** The workout pager's first page (0 Set, 1 Rest, 2 Overview); null opens Rest while resting, else Set. */
    val initialPage: Int? = null,
    /** How long the RPE question waits before it closes itself. */
    val rpeTimeoutMs: Long = 5_000,
) {
    companion object {
        val IDLE = WorkoutUi()
    }
}

/** `m:ss`, or `h:mm:ss` from an hour on. */
fun formatClock(duration: Duration): String {
    val total = maxOf(0L, duration.seconds)
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val seconds = total % 60
    return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds) else "%d:%02d".format(minutes, seconds)
}

/** The summary's status line. "Saved to phone" only after the phone's ack; reachable is not stored. */
object SummaryStatus {
    fun text(delivery: String?, phoneReachable: Boolean): String = when {
        delivery == "delivered" -> "Saved to phone"
        phoneReachable -> "Saved on watch · sent to phone"
        else -> "Saved on watch · waiting for phone"
    }
}
