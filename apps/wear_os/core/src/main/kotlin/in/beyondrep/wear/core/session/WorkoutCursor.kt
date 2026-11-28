package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.SetValues

data class SetPosition(
    val exercise: TemplateExercise,
    val set: TemplateSet,
    val indexInExercise: Int,
    val countInExercise: Int,
)

/** Where the person is in the template, given what the session has logged (port of WorkoutCursor.swift). */
class WorkoutCursor(
    val template: WorkoutTemplate,
    val state: ReplayedWorkout,
    focusExerciseId: String? = null,
) {
    private val ordered: List<SetPosition>

    init {
        val exercises = template.exercises.sortedBy { it.position }.toMutableList()
        if (focusExerciseId != null) {
            val index = exercises.indexOfFirst { it.exerciseId == focusExerciseId }
            if (index >= 0) exercises.add(0, exercises.removeAt(index))
        }
        ordered = exercises.flatMap { exercise ->
            val sets = exercise.sets.sortedBy { it.position }
            sets.mapIndexed { index, set -> SetPosition(exercise, set, index, sets.size) }
        }
    }

    private fun isDone(position: SetPosition): Boolean = state.sets.any { it.setId == position.set.setId }

    /** The first set, focused exercise first, that is not completed or skipped. */
    val current: SetPosition? get() = ordered.firstOrNull { !isDone(it) }

    /** The first undone set after `position` in the same order. */
    fun next(position: SetPosition): SetPosition? {
        val index = ordered.indexOfFirst { it.set.setId == position.set.setId }
        if (index < 0) return null
        return ordered.drop(index + 1).firstOrNull { !isDone(it) }
    }

    /**
     * Starting values for the set screen: the last completed set of the same exercise and kind in
     * this session (a warm-up never fills a working set), else the set's targets, else a plain
     * default (10 reps or 30 s, no weight) the crown then adjusts.
     */
    fun prefill(position: SetPosition, unit: String): SetValues {
        val ids = position.exercise.sets.map { it.setId }.toSet()
        val last = state.sets.lastOrNull { it.status == "completed" && it.kind == position.set.kind && it.setId in ids }
        val timed = position.exercise.kind == "duration"
        var values = SetValues(
            setId = position.set.setId, exerciseId = position.exercise.exerciseId,
            position = position.set.position, kind = position.set.kind, inputUnit = unit)
        if (timed) {
            values = values.copy(durationSeconds = last?.durationSeconds ?: position.set.targetSeconds ?: 30)
        } else {
            values = values.copy(reps = last?.reps ?: position.set.targetReps ?: 10)
            val load = last?.loadGrams ?: position.set.targetLoadGrams
            if (load != null && load > 0) values = values.copy(loadGrams = load)
        }
        return values
    }

    /** Working sets in the template (warm-ups are not counted). */
    val plannedCount: Int get() = template.exercises.sumOf { e -> e.sets.count { it.kind == "working" } }

    /** Completed working sets, the same rule as `ReplayedWorkout.completedSets`. */
    val completedCount: Int get() = state.completedSets
}
