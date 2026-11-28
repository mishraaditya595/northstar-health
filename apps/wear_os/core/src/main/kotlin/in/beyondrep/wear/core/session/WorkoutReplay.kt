package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.WorkoutEventV2

data class ReplayedSet(
    val setId: String,
    /** `completed` or `skipped`. */
    val status: String,
    /** `working` or `warmup`. */
    val kind: String,
    val reps: Int? = null,
    val durationSeconds: Int? = null,
    val loadGrams: Int? = null,
    val rpe: Double? = null,
    /** Every event id that touched this set, in sequence order. */
    val history: List<String> = emptyList(),
)

data class ReplayedWorkout(
    /** `active`, `paused`, `completed` or `abandoned`. */
    val status: String,
    val sets: List<ReplayedSet>,
    /** Sum of reps x load over completed working sets with reps and a load. */
    val volumeGrams: Int,
    /** Completed working sets (reps or seconds). Warm-ups are not counted. */
    val completedSets: Int,
    /** Sequence numbers from 0 to the highest seen that never arrived. */
    val gaps: List<Int>,
)

/**
 * Rebuilds a workout from its events (port of WorkoutReplay.swift). Duplicates (same `event_id`)
 * are dropped, order is by `sequence` whatever the delivery order, and missing sequence numbers
 * are reported in `gaps` instead of being invented. Rules are in `contracts/watch_link/v1/README.md`.
 */
object WorkoutReplay {
    fun replay(events: List<WorkoutEventV2>): ReplayedWorkout {
        val seen = mutableSetOf<String>()
        val unique = mutableListOf<IndexedValue<WorkoutEventV2>>()
        for ((index, event) in events.withIndex()) {
            if (seen.add(event.header.eventId)) unique.add(IndexedValue(index, event))
        }
        unique.sortWith(compareBy({ it.value.header.sequence }, { it.index }))
        val present = unique.map { it.value.header.sequence }.toSet()
        val highest = present.maxOrNull()
        val gaps = if (highest != null) (0..highest).filter { it !in present } else emptyList()

        var status = "active"
        val order = mutableListOf<String>()
        val sets = mutableMapOf<String, ReplayedSet>()

        fun touch(setId: String, kind: String): ReplayedSet {
            sets[setId]?.let { return it }
            order.add(setId)
            return ReplayedSet(setId, "completed", kind)
        }

        fun logged(eventId: String, values: `in`.beyondrep.wear.core.contracts.SetValues) {
            val set = touch(values.setId, values.kind)
            sets[values.setId] = set.copy(
                status = "completed", kind = values.kind, reps = values.reps,
                durationSeconds = values.durationSeconds, loadGrams = values.loadGrams, rpe = values.rpe,
                history = set.history + eventId)
        }

        for ((_, event) in unique) {
            val eventId = event.header.eventId
            when (event) {
                is WorkoutEventV2.WorkoutPaused -> status = "paused"
                is WorkoutEventV2.WorkoutResumed -> status = "active"
                is WorkoutEventV2.WorkoutCompleted -> status = "completed"
                is WorkoutEventV2.WorkoutAbandoned -> status = "abandoned"
                is WorkoutEventV2.SetLogged -> logged(eventId, event.values)
                is WorkoutEventV2.SetCorrected -> logged(eventId, event.values)
                is WorkoutEventV2.SetSkipped -> {
                    val set = touch(event.setId, "working")
                    sets[event.setId] = set.copy(
                        status = "skipped", reps = null, durationSeconds = null, loadGrams = null, rpe = null,
                        history = set.history + eventId)
                }
                is WorkoutEventV2.WorkoutStarted, is WorkoutEventV2.ExerciseAdded, is WorkoutEventV2.RestStarted,
                is WorkoutEventV2.RestCleared, is WorkoutEventV2.PlatformWorkoutExported -> Unit
            }
        }

        var volume = 0
        var done = 0
        val ordered = order.mapNotNull { sets[it] }
        for (set in ordered) {
            if (set.status == "completed" && set.kind == "working") {
                done += 1
                val reps = set.reps
                val load = set.loadGrams
                if (reps != null && load != null && load > 0) volume += reps * load
            }
        }
        return ReplayedWorkout(status, ordered, volume, done, gaps)
    }
}
