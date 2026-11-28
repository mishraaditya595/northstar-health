package `in`.beyondrep.wear.core.session

import java.time.Duration
import java.time.Instant

/**
 * What the watch shows after a workout (port of WorkoutSummary in AppModel.swift). Heart rate and
 * calories come from memory and stay null when unknown, never 0.
 */
data class WorkoutSummary(
    val sessionId: String,
    val name: String,
    val elapsed: Duration,
    val sets: Int,
    val averageHeartRate: Int?,
    val totalCalories: Int?,
) {
    companion object {
        fun of(controller: WorkoutController, endedAt: Instant, averageHeartRate: Int?, totalCalories: Int?): WorkoutSummary {
            val elapsed = Duration.between(controller.startedAt, endedAt)
            return WorkoutSummary(
                sessionId = controller.sessionId,
                name = controller.template.name,
                elapsed = if (elapsed.isNegative) Duration.ZERO else elapsed,
                sets = controller.state.completedSets,
                averageHeartRate = averageHeartRate,
                totalCalories = totalCalories,
            )
        }
    }
}
