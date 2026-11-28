package `in`.beyondrep.wear.core.glance

import `in`.beyondrep.wear.core.session.TemplateExercise

/** The "sets × reps" text next to an exercise in a plan preview. */
object PlanSummary {
    /** "3 × 8", "3 × 0:45" or just the set count. */
    fun of(exercise: TemplateExercise): String {
        val working = exercise.sets.filter { it.kind == "working" }
        val first = working.firstOrNull() ?: return "${exercise.sets.size} sets"
        first.targetReps?.let { return "${working.size} × $it" }
        first.targetSeconds?.let { return "${working.size} × ${it / 60}:${"%02d".format(it % 60)}" }
        return "${working.size} sets"
    }
}
