package `in`.beyondrep.wear.core.glance

import `in`.beyondrep.wear.core.session.TemplateExercise
import `in`.beyondrep.wear.core.session.TemplateSet
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class PlanSummaryTest {
    private fun exercise(vararg sets: TemplateSet) =
        TemplateExercise("e", "Move", "reps", null, 0, sets.toList())

    @Test
    fun repsAreShownAsSetsTimesReps() {
        val sets = (0 until 3).map { TemplateSet("s$it", it, targetReps = 8) }
        assertEquals("3 × 8", PlanSummary.of(exercise(*sets.toTypedArray())))
    }

    @Test
    fun secondsAreShownAsMinutesAndSeconds() {
        val sets = (0 until 3).map { TemplateSet("s$it", it, targetSeconds = 45) }
        assertEquals("3 × 0:45", PlanSummary.of(exercise(*sets.toTypedArray())))
        assertEquals("1 × 1:05", PlanSummary.of(exercise(TemplateSet("a", 0, targetSeconds = 65))))
    }

    @Test
    fun warmUpSetsAreNotCounted() {
        val summary = PlanSummary.of(
            exercise(TemplateSet("w", 0, kind = "warmup", targetReps = 12), TemplateSet("a", 1, targetReps = 8)))
        assertEquals("1 × 8", summary)
    }

    @Test
    fun withoutTargetsJustTheSetCount() {
        assertEquals("2 sets", PlanSummary.of(exercise(TemplateSet("a", 0), TemplateSet("b", 1))))
        assertEquals("0 sets", PlanSummary.of(exercise()))
        assertEquals("1 sets", PlanSummary.of(exercise(TemplateSet("w", 0, kind = "warmup"))))
    }
}
