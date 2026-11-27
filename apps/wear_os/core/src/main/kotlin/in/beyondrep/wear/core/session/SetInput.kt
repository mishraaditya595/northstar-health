package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.SetValues
import kotlin.math.max
import kotlin.math.min

/**
 * The numbers behind the set screen: crown steps and ranges, and the conversion between the weight
 * the person sees (kg or lb, the binding unit) and the grams a set stores. Grams use 1000 per kg and
 * 453.59237 per lb, rounded, the same as the phone's `load_units.dart` (port of SetInput.swift).
 */
object SetInput {
    enum class Field { WEIGHT, REPS, SECONDS }

    private fun gramsPerUnit(unit: String): Double = if (unit == "lb") 453.59237 else 1000.0

    fun step(field: Field, unit: String): Double = when (field) {
        Field.WEIGHT -> if (unit == "lb") 5.0 else 2.5
        Field.REPS -> 1.0
        Field.SECONDS -> 5.0
    }

    fun range(field: Field, unit: String): ClosedFloatingPointRange<Double> = when (field) {
        Field.WEIGHT -> if (unit == "lb") 0.0..1100.0 else 0.0..500.0
        Field.REPS -> 1.0..100.0
        Field.SECONDS -> 5.0..3600.0
    }

    fun clamp(value: Double, field: Field, unit: String): Double {
        val bounds = range(field, unit)
        return min(bounds.endInclusive, max(bounds.start, value))
    }

    /** Grams for a displayed weight; null (no load) for 0 or less. */
    fun grams(displayWeight: Double, unit: String): Int? {
        if (displayWeight <= 0) return null
        return Math.round(displayWeight * gramsPerUnit(unit)).toInt()
    }

    /** The displayed weight for stored grams, snapped to the crown step. */
    fun displayWeight(grams: Int?, unit: String): Double {
        if (grams == null || grams <= 0) return 0.0
        val step = step(Field.WEIGHT, unit)
        val raw = grams.toDouble() / gramsPerUnit(unit)
        return clamp(Math.round(raw / step) * step, Field.WEIGHT, unit)
    }

    /** The value of `field` in `values`, in display units. */
    fun value(field: Field, values: SetValues): Double = when (field) {
        Field.WEIGHT -> displayWeight(values.loadGrams, values.inputUnit)
        Field.REPS -> (values.reps ?: 10).toDouble()
        Field.SECONDS -> (values.durationSeconds ?: 30).toDouble()
    }

    /** `values` with `field` set to `value` (display units, clamped). */
    fun applying(value: Double, field: Field, values: SetValues): SetValues {
        val clamped = clamp(value, field, values.inputUnit)
        return when (field) {
            Field.WEIGHT -> values.copy(loadGrams = grams(clamped, values.inputUnit))
            Field.REPS -> values.copy(reps = Math.round(clamped).toInt())
            Field.SECONDS -> values.copy(durationSeconds = Math.round(clamped).toInt())
        }
    }
}
