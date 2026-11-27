package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.ContractException
import `in`.beyondrep.wear.core.contracts.ExerciseAddedPayload
import `in`.beyondrep.wear.core.contracts.StrictObject
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.floor

data class TemplateSet(
    val setId: String,
    val position: Int,
    val kind: String = "working",
    val targetReps: Int? = null,
    val targetSeconds: Int? = null,
    val targetLoadGrams: Int? = null,
    val restSeconds: Int? = null,
)

data class TemplateExercise(
    val exerciseId: String,
    val name: String,
    /** `reps` or `duration`. */
    val kind: String,
    val muscle: String?,
    val position: Int,
    val sets: List<TemplateSet>,
)

data class ProgramDay(val planId: String, val programId: String, val localDate: String)

/**
 * The exercises and planned sets of one watch session (port of WorkoutTemplate.swift). Its JSON
 * uses snake_case keys, the same as the shared golden cases. Every exercise and set id is made
 * fresh when the workout starts (never copied from a plan or the catalogue), so two workouts from
 * one plan never share an id on the phone.
 */
data class WorkoutTemplate(
    val name: String,
    val planId: String? = null,
    val programDay: ProgramDay? = null,
    val exercises: List<TemplateExercise> = emptyList(),
) {
    /** Adds an exercise with one empty working set; returns the changed template and the new exercise id. */
    fun addingExercise(name: String, kind: String, muscle: String?, makeId: () -> String): Pair<WorkoutTemplate, String> {
        val exerciseId = makeId()
        val exercise = TemplateExercise(
            exerciseId, name, kind, muscle, exercises.size, listOf(TemplateSet(makeId(), 0, "working")))
        return copy(exercises = exercises + exercise) to exerciseId
    }

    /** Adds a working set that copies the last set's targets; returns the changed template and the set id. */
    fun addingSet(exerciseId: String, makeId: () -> String): Pair<WorkoutTemplate, String> {
        val setId = makeId()
        val index = exercises.indexOfFirst { it.exerciseId == exerciseId }
        if (index < 0) return this to setId
        val exercise = exercises[index]
        val last = exercise.sets.lastOrNull()
        val added = TemplateSet(
            setId, (last?.position ?: -1) + 1, "working", last?.targetReps, last?.targetSeconds,
            last?.targetLoadGrams, last?.restSeconds)
        val changed = exercises.toMutableList()
        changed[index] = exercise.copy(sets = exercise.sets + added)
        return copy(exercises = changed) to setId
    }

    /** One `exercise_added` payload per exercise, in position order. */
    val exerciseAddedPayloads: List<ExerciseAddedPayload>
        get() = exercises.sortedBy { it.position }.map { ExerciseAddedPayload(it.exerciseId, it.name, it.kind, it.position) }

    fun toJson(): JsonObject {
        val out = linkedMapOf<String, JsonElement>("name" to JsonPrimitive(name))
        planId?.let { out["plan_id"] = JsonPrimitive(it) }
        programDay?.let {
            out["program_day"] = JsonObject(
                mapOf(
                    "plan_id" to JsonPrimitive(it.planId), "program_id" to JsonPrimitive(it.programId),
                    "local_date" to JsonPrimitive(it.localDate),
                ),
            )
        }
        out["exercises"] = JsonArray(exercises.map { exerciseJson(it) })
        return JsonObject(out)
    }

    fun encode(): String = StrictObject.encode(toJson())

    private fun exerciseJson(e: TemplateExercise): JsonObject {
        val out = linkedMapOf<String, JsonElement>(
            "exercise_id" to JsonPrimitive(e.exerciseId), "name" to JsonPrimitive(e.name),
            "kind" to JsonPrimitive(e.kind),
        )
        e.muscle?.let { out["muscle"] = JsonPrimitive(it) }
        out["position"] = JsonPrimitive(e.position)
        out["sets"] = JsonArray(e.sets.map { setJson(it) })
        return JsonObject(out)
    }

    private fun setJson(s: TemplateSet): JsonObject {
        val out = linkedMapOf<String, JsonElement>(
            "set_id" to JsonPrimitive(s.setId), "position" to JsonPrimitive(s.position), "kind" to JsonPrimitive(s.kind),
        )
        s.targetReps?.let { out["target_reps"] = JsonPrimitive(it) }
        s.targetSeconds?.let { out["target_seconds"] = JsonPrimitive(it) }
        s.targetLoadGrams?.let { out["target_load_grams"] = JsonPrimitive(it) }
        s.restSeconds?.let { out["rest_seconds"] = JsonPrimitive(it) }
        return JsonObject(out)
    }

    companion object {
        fun quick(name: String = "Quick workout"): WorkoutTemplate = WorkoutTemplate(name)

        /** A whole JSON number as Int (Swift `as? Int`), else null. */
        private fun int(e: JsonElement?): Int? {
            val p = e as? JsonPrimitive ?: return null
            if (p.isString) return null
            val d = p.content.toDoubleOrNull() ?: return null
            if (d != floor(d) || d > Int.MAX_VALUE || d < Int.MIN_VALUE) return null
            return d.toInt()
        }

        private fun string(e: JsonElement?): String? = (e as? JsonPrimitive)?.takeIf { it.isString }?.content

        /**
         * Builds the template of `planId` from a `plans_snapshot` body, or null when the plan is not
         * in it. Source exercise ids are not kept.
         */
        fun fromPlan(plansSnapshot: JsonObject, planId: String, makeId: () -> String): WorkoutTemplate? {
            val plans = plansSnapshot["plans"] as? JsonArray ?: return null
            val plan = plans.firstOrNull { (it as? JsonObject)?.get("plan_id")?.let(::string) == planId } as? JsonObject
                ?: return null
            val name = string(plan["name"]) ?: return null
            val exercises = mutableListOf<TemplateExercise>()
            for ((index, item) in ((plan["exercises"] as? JsonArray) ?: JsonArray(emptyList())).withIndex()) {
                val x = item as? JsonObject ?: continue
                val exerciseName = string(x["name"]) ?: continue
                val kind = string(x["kind"]) ?: continue
                val exerciseId = makeId()
                val sets = mutableListOf<TemplateSet>()
                for (entry in (x["sets"] as? JsonArray) ?: JsonArray(emptyList())) {
                    val s = entry as? JsonObject ?: continue
                    sets.add(
                        TemplateSet(
                            setId = makeId(), position = int(s["position"]) ?: sets.size,
                            kind = string(s["kind"]) ?: "working",
                            targetReps = int(s["target_reps"]), targetSeconds = int(s["target_seconds"]),
                            targetLoadGrams = int(s["target_load_grams"]), restSeconds = int(s["rest_seconds"]),
                        ),
                    )
                }
                sets.sortBy { it.position }
                exercises.add(TemplateExercise(exerciseId, exerciseName, kind, string(x["muscle"]), index, sets))
            }
            return WorkoutTemplate(name, planId, null, exercises)
        }

        /** Today's program workout (`plans_snapshot.today`), carrying its program day. */
        fun today(plansSnapshot: JsonObject, makeId: () -> String): WorkoutTemplate? {
            val today = plansSnapshot["today"] as? JsonObject ?: return null
            val planId = string(today["plan_id"]) ?: return null
            val programId = string(today["program_id"]) ?: return null
            val localDate = string(today["local_date"]) ?: return null
            val template = fromPlan(plansSnapshot, planId, makeId) ?: return null
            return template.copy(programDay = ProgramDay(planId, programId, localDate))
        }

        fun decode(json: String): WorkoutTemplate {
            val element = try {
                Json.parseToJsonElement(json)
            } catch (_: SerializationException) {
                throw ContractException("invalid_value")
            }
            return fromJson(element)
        }

        /** Strict about required keys and types like Swift `Codable`; unknown keys are ignored. */
        fun fromJson(element: JsonElement): WorkoutTemplate {
            fun obj(e: JsonElement?) = e as? JsonObject ?: throw ContractException("invalid_value")
            fun req(o: JsonObject, key: String) = o[key] ?: throw ContractException("missing_field")
            fun str(e: JsonElement?) = string(e) ?: throw ContractException("invalid_value")
            fun num(e: JsonElement?) = int(e) ?: throw ContractException("invalid_value")
            fun optStr(o: JsonObject, key: String) = if (key in o) str(o[key]) else null
            fun optNum(o: JsonObject, key: String) = if (key in o) num(o[key]) else null
            val o = obj(element)
            val day = o["program_day"]?.let {
                val d = obj(it)
                ProgramDay(str(req(d, "plan_id")), str(req(d, "program_id")), str(req(d, "local_date")))
            }
            val exercises = (req(o, "exercises") as? JsonArray ?: throw ContractException("invalid_value")).map { item ->
                val x = obj(item)
                TemplateExercise(
                    exerciseId = str(req(x, "exercise_id")), name = str(req(x, "name")), kind = str(req(x, "kind")),
                    muscle = optStr(x, "muscle"), position = num(req(x, "position")),
                    sets = (req(x, "sets") as? JsonArray ?: throw ContractException("invalid_value")).map { entry ->
                        val s = obj(entry)
                        TemplateSet(
                            setId = str(req(s, "set_id")), position = num(req(s, "position")), kind = str(req(s, "kind")),
                            targetReps = optNum(s, "target_reps"), targetSeconds = optNum(s, "target_seconds"),
                            targetLoadGrams = optNum(s, "target_load_grams"), restSeconds = optNum(s, "rest_seconds"),
                        )
                    },
                )
            }
            return WorkoutTemplate(str(req(o, "name")), optStr(o, "plan_id"), day, exercises)
        }
    }
}
