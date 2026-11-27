package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.session.TemplateFixtures.counterIds
import kotlinx.serialization.json.JsonObject
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of WorkoutTemplateTests.swift. */
class WorkoutTemplateTest {
    private val uuidPattern = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

    private fun ids(template: WorkoutTemplate): Set<String> {
        val out = mutableSetOf<String>()
        for (exercise in template.exercises) {
            out.add(exercise.exerciseId)
            for (set in exercise.sets) out.add(set.setId)
        }
        return out
    }

    private fun fresh(): () -> String = { UUID.randomUUID().toString().lowercase() }

    @Test
    fun fromPlanMakesFreshUuidsForExercisesAndSets() {
        val template = TemplateFixtures.template()
        assertEquals("Synthetic push day", template.name)
        assertEquals("plan-synthetic-1", template.planId)
        assertNull(template.programDay)
        assertEquals(2, template.exercises.size)
        for (id in ids(template)) assertTrue(uuidPattern.matches(id), id)
        val source = setOf("builtin.v1.synthetic-move-1", "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")
        assertTrue(ids(template).intersect(source).isEmpty())
        val press = template.exercises[0]
        assertEquals("Synthetic press", press.name)
        assertEquals("reps", press.kind)
        assertEquals("chest", press.muscle)
        assertEquals(0, press.position)
        assertEquals(listOf("warmup", "working"), press.sets.map { it.kind })
        assertEquals(listOf(0, 1), press.sets.map { it.position })
        assertEquals(8, press.sets[1].targetReps)
        assertEquals(60000, press.sets[1].targetLoadGrams)
        assertEquals(90, press.sets[1].restSeconds)
        val plank = template.exercises[1]
        assertEquals("duration", plank.kind)
        assertNull(plank.muscle)
        assertEquals(1, plank.position)
        assertEquals(45, plank.sets[0].targetSeconds)
        assertNull(plank.sets[0].targetReps)
    }

    @Test
    fun twoSessionsFromOnePlanShareNoIds() {
        val raw = TemplateFixtures.planRaw()
        val a = assertNotNull(WorkoutTemplate.fromPlan(raw, "plan-synthetic-1", fresh()))
        val b = assertNotNull(WorkoutTemplate.fromPlan(raw, "plan-synthetic-1", fresh()))
        assertTrue(ids(a).intersect(ids(b)).isEmpty())
    }

    @Test
    fun todayCarriesProgramDay() {
        val template = assertNotNull(WorkoutTemplate.today(TemplateFixtures.planRaw(), counterIds()))
        assertEquals(ProgramDay("plan-synthetic-1", "program-synthetic-1", "2026-10-23"), template.programDay)
        assertEquals("plan-synthetic-1", template.planId)
        assertEquals(2, template.exercises.size)
    }

    @Test
    fun todayIsNullWithoutTodayOrPlan() {
        val raw = TemplateFixtures.planRaw()
        val missingPlan = kotlinx.serialization.json.Json.parseToJsonElement(
            """{"plan_id":"missing","program_id":"p","local_date":"2026-10-23","label":"x"}""")
        assertNull(WorkoutTemplate.today(JsonObject(raw + ("today" to missingPlan)), counterIds()))
        assertNull(WorkoutTemplate.today(JsonObject(raw - "today"), counterIds()))
    }

    @Test
    fun unknownPlanIsNull() {
        assertNull(WorkoutTemplate.fromPlan(TemplateFixtures.planRaw(), "nope", counterIds()))
    }

    @Test
    fun quickHasNoExercises() {
        val quick = WorkoutTemplate.quick()
        assertEquals("Quick workout", quick.name)
        assertTrue(quick.exercises.isEmpty())
        assertNull(quick.planId)
        assertNull(quick.programDay)
    }

    @Test
    fun addSetCopiesLastTargets() {
        val template = TemplateFixtures.template()
        val exerciseId = template.exercises[0].exerciseId
        val (changed, setId) = template.addingSet(exerciseId, counterIds(500))
        val added = changed.exercises[0].sets.last()
        assertEquals(setId, added.setId)
        assertEquals(2, added.position)
        assertEquals("working", added.kind)
        assertEquals(8, added.targetReps)
        assertEquals(60000, added.targetLoadGrams)
        assertEquals(90, added.restSeconds)
    }

    @Test
    fun addExerciseHasOneSet() {
        val (template, id) = WorkoutTemplate.quick().addingExercise("Synthetic curl", "reps", "biceps", counterIds())
        assertEquals(1, template.exercises.size)
        val exercise = template.exercises[0]
        assertEquals(id, exercise.exerciseId)
        assertEquals(0, exercise.position)
        assertEquals(1, exercise.sets.size)
        assertEquals("working", exercise.sets[0].kind)
        assertEquals(
            listOf(`in`.beyondrep.wear.core.contracts.ExerciseAddedPayload(id, "Synthetic curl", "reps", 0)),
            template.exerciseAddedPayloads)
    }

    @Test
    fun templateRoundTripsThroughJson() {
        val template = TemplateFixtures.template()
        assertEquals(template, WorkoutTemplate.decode(template.encode()))
        val withDay = assertNotNull(WorkoutTemplate.today(TemplateFixtures.planRaw(), counterIds()))
        assertEquals(withDay, WorkoutTemplate.decode(withDay.encode()))
    }
}
