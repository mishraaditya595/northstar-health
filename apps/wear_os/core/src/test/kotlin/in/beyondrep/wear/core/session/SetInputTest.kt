package `in`.beyondrep.wear.core.session

import `in`.beyondrep.wear.core.contracts.SetValues
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Port of SetInputTests.swift. */
class SetInputTest {
    @Test
    fun gramsUseTheBindingUnit() {
        assertEquals(60000, SetInput.grams(60.0, "kg"))
        assertEquals(62500, SetInput.grams(62.5, "kg"))
        assertEquals(61235, SetInput.grams(135.0, "lb"))
        assertEquals(2268, SetInput.grams(5.0, "lb"))
    }

    @Test
    fun zeroWeightIsNoLoad() {
        assertNull(SetInput.grams(0.0, "kg"))
        assertNull(SetInput.grams(-2.5, "lb"))
    }

    @Test
    fun displayWeightRoundsToTheCrownStep() {
        assertEquals(60.0, SetInput.displayWeight(60000, "kg"))
        assertEquals(135.0, SetInput.displayWeight(61235, "lb"))
        assertEquals(60.0, SetInput.displayWeight(61000, "kg")) // 61 kg snaps to 2.5
        assertEquals(0.0, SetInput.displayWeight(null, "kg"))
    }

    @Test
    fun stepsAndRanges() {
        assertEquals(2.5, SetInput.step(SetInput.Field.WEIGHT, "kg"))
        assertEquals(5.0, SetInput.step(SetInput.Field.WEIGHT, "lb"))
        assertEquals(1.0, SetInput.step(SetInput.Field.REPS, "kg"))
        assertEquals(5.0, SetInput.step(SetInput.Field.SECONDS, "lb"))
        assertEquals(0.0..500.0, SetInput.range(SetInput.Field.WEIGHT, "kg"))
        assertEquals(0.0..1100.0, SetInput.range(SetInput.Field.WEIGHT, "lb"))
        assertEquals(1.0..100.0, SetInput.range(SetInput.Field.REPS, "kg"))
        assertEquals(5.0..3600.0, SetInput.range(SetInput.Field.SECONDS, "kg"))
    }

    @Test
    fun clampKeepsAValueInsideItsRange() {
        assertEquals(500.0, SetInput.clamp(900.0, SetInput.Field.WEIGHT, "kg"))
        assertEquals(1.0, SetInput.clamp(0.0, SetInput.Field.REPS, "kg"))
        assertEquals(5.0, SetInput.clamp(1.0, SetInput.Field.SECONDS, "kg"))
    }

    @Test
    fun applyingAFieldKeepsTheRest() {
        val base = SetValues("s", "e", 0, inputUnit = "kg", reps = 8, loadGrams = 60000)
        assertEquals(65000, SetInput.applying(65.0, SetInput.Field.WEIGHT, base).loadGrams)
        assertEquals(8, SetInput.applying(65.0, SetInput.Field.WEIGHT, base).reps)
        assertEquals(10, SetInput.applying(10.0, SetInput.Field.REPS, base).reps)
        assertNull(SetInput.applying(0.0, SetInput.Field.WEIGHT, base).loadGrams)
        val timed = SetValues("s", "e", 0, durationSeconds = 45)
        assertEquals(60, SetInput.applying(60.0, SetInput.Field.SECONDS, timed).durationSeconds)
    }

    @Test
    fun valueReadsTheFieldInDisplayUnits() {
        val values = SetValues("s", "e", 0, inputUnit = "lb", reps = 8, loadGrams = 61235)
        assertEquals(135.0, SetInput.value(SetInput.Field.WEIGHT, values))
        assertEquals(8.0, SetInput.value(SetInput.Field.REPS, values))
        assertEquals(30.0, SetInput.value(SetInput.Field.SECONDS, values))
    }
}
