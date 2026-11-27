package `in`.beyondrep.wear.core.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** Port of WorkoutCursorTests.swift. */
class WorkoutCursorTest {
    private fun state(sets: List<ReplayedSet>): ReplayedWorkout {
        val done = sets.count { it.status == "completed" && it.kind == "working" }
        return ReplayedWorkout("active", sets, 0, done, emptyList())
    }

    private fun completed(set: TemplateSet, reps: Int? = 8, seconds: Int? = null, load: Int? = 60000) =
        ReplayedSet(set.setId, "completed", set.kind, reps, seconds, load, null, listOf("e"))

    private fun skipped(set: TemplateSet) = ReplayedSet(set.setId, "skipped", set.kind, null, null, null, null, listOf("e"))

    @Test
    fun currentIsTheFirstSetWhenNothingIsDone() {
        val t = TemplateFixtures.template()
        val cursor = WorkoutCursor(t, state(emptyList()))
        assertEquals(t.exercises[0].sets[0].setId, cursor.current?.set?.setId)
        assertEquals(0, cursor.current?.indexInExercise)
        assertEquals(2, cursor.current?.countInExercise)
    }

    @Test
    fun currentSkipsCompletedAndSkippedSets() {
        val t = TemplateFixtures.template()
        val press = t.exercises[0]
        val cursor = WorkoutCursor(t, state(listOf(completed(press.sets[0]), skipped(press.sets[1]))))
        assertEquals(t.exercises[1].sets[0].setId, cursor.current?.set?.setId)
        assertEquals("Synthetic plank", cursor.current?.exercise?.name)
    }

    @Test
    fun currentIsNullWhenAllDone() {
        val t = TemplateFixtures.template()
        val all = t.exercises.flatMap { it.sets }.map { completed(it) }
        assertNull(WorkoutCursor(t, state(all)).current)
    }

    @Test
    fun prefillUsesLastCompletedSetOfSameExercise() {
        var t = TemplateFixtures.template()
        // Both sets are working sets. The next targets 62.5 kg x 6, the logged one was 60 kg x 8.
        val sets = t.exercises[0].sets.toMutableList()
        sets[0] = sets[0].copy(kind = "working")
        sets[1] = sets[1].copy(targetLoadGrams = 62500, targetReps = 6)
        t = t.copy(exercises = listOf(t.exercises[0].copy(sets = sets)) + t.exercises.drop(1))
        val first = t.exercises[0].sets[0]
        val cursor = WorkoutCursor(t, state(listOf(completed(first, reps = 8, load = 60000))))
        val current = assertNotNull(cursor.current)
        assertEquals(t.exercises[0].sets[1].setId, current.set.setId)
        val values = cursor.prefill(current, "kg")
        assertEquals(8, values.reps)
        assertEquals(60000, values.loadGrams)
        assertEquals(current.set.setId, values.setId)
        assertEquals(current.exercise.exerciseId, values.exerciseId)
        assertEquals(current.set.position, values.position)
        assertEquals("working", values.kind)
    }

    @Test
    fun prefillIgnoresAWarmupForAWorkingSet() {
        val t = TemplateFixtures.template()
        val warmup = t.exercises[0].sets[0]
        val cursor = WorkoutCursor(t, state(listOf(completed(warmup, reps = 10, load = 20000))))
        val current = assertNotNull(cursor.current)
        assertEquals("working", current.set.kind)
        val values = cursor.prefill(current, "kg")
        assertEquals(8, values.reps)
        assertEquals(60000, values.loadGrams)
    }

    @Test
    fun prefillFallsBackToTargets() {
        val cursor = WorkoutCursor(TemplateFixtures.template(), state(emptyList()))
        val values = cursor.prefill(assertNotNull(cursor.current), "kg")
        assertEquals(10, values.reps)
        assertEquals(20000, values.loadGrams)
        assertEquals("warmup", values.kind)
    }

    @Test
    fun prefillDurationExerciseHasSecondsNotReps() {
        val t = TemplateFixtures.template()
        val all = t.exercises[0].sets.map { completed(it) }
        val cursor = WorkoutCursor(t, state(all))
        val values = cursor.prefill(assertNotNull(cursor.current), "kg")
        assertNull(values.reps)
        assertEquals(45, values.durationSeconds)
        assertNull(values.loadGrams)
    }

    @Test
    fun prefillUsesBindingUnit() {
        val cursor = WorkoutCursor(TemplateFixtures.template(), state(emptyList()))
        assertEquals("lb", cursor.prefill(assertNotNull(cursor.current), "lb").inputUnit)
    }

    @Test
    fun nextMovesToNextExerciseAfterLastSet() {
        val t = TemplateFixtures.template()
        val cursor = WorkoutCursor(t, state(emptyList()))
        val last = SetPosition(t.exercises[0], t.exercises[0].sets[1], 1, 2)
        assertEquals("Synthetic plank", cursor.next(last)?.exercise?.name)
        val plank = SetPosition(t.exercises[1], t.exercises[1].sets[0], 0, 1)
        assertNull(cursor.next(plank))
    }

    @Test
    fun focusExerciseComesFirst() {
        val t = TemplateFixtures.template()
        val cursor = WorkoutCursor(t, state(emptyList()), focusExerciseId = t.exercises[1].exerciseId)
        assertEquals("Synthetic plank", cursor.current?.exercise?.name)
        assertEquals("Synthetic press", cursor.next(assertNotNull(cursor.current))?.exercise?.name)
    }

    @Test
    fun countsExcludeWarmups() {
        val t = TemplateFixtures.template()
        val press = t.exercises[0]
        val cursor = WorkoutCursor(t, state(listOf(completed(press.sets[0]), completed(press.sets[1]))))
        assertEquals(2, cursor.plannedCount) // press working set and plank
        assertEquals(1, cursor.completedCount)
    }
}
