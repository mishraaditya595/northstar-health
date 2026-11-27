package `in`.beyondrep.wear.core.contracts

import `in`.beyondrep.wear.core.FixtureLoader
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class StrictJsonTest {
    private fun withReps(literal: String): String =
        FixtureLoader.text("contracts/workout_sync/v2/fixtures/valid/set_logged.json")
            .replace("\"reps\": 8", "\"reps\": $literal")

    private fun reps(literal: String): Int? =
        (WorkoutEventV2.decode(withReps(literal)) as WorkoutEventV2.SetLogged).values.reps

    private fun assertRejected(literal: String) {
        val error = assertFailsWith<ContractException>(literal) { WorkoutEventV2.decode(withReps(literal)) }
        assertEquals("invalid_value", error.code, literal)
    }

    @Test
    fun numberEdgeCasesMatchSwift() {
        assertEquals(10, reps("10"))
        // StrictJSON.int: `double == double.rounded()` accepts a whole number written as 10.0 or 1e1.
        assertEquals(10, reps("10.0"))
        assertEquals(10, reps("1e1"))
        // -0 is the whole number 0 and passes the `min: 0` check.
        assertEquals(0, reps("-0"))
        // `double == double.rounded()` fails for 10.5.
        assertRejected("10.5")
        // `dict[key] as? NSNumber` fails for a string, and isBool rejects true.
        assertRejected("\"10\"")
        assertRejected("true")
        assertRejected("null")
        // Swift accepts up to 9e15 (Int is 64-bit); Kotlin Int fields reject above Int.MAX_VALUE
        // (plan decision), and both reject abs(double) >= 9e15.
        assertRejected("2147483648")
        assertRejected("9007199254740993")
        assertRejected("-1")
    }

    @Test
    fun rpeAcceptsWholeAndHalfStepsOnly() {
        val base = FixtureLoader.text("contracts/workout_sync/v2/fixtures/valid/set_logged.json")
        fun rpe(literal: String) = WorkoutEventV2.decode(base.replace("\"rpe\": 8.5", "\"rpe\": $literal"))
        assertEquals(8.0, (rpe("8") as WorkoutEventV2.SetLogged).values.rpe)
        assertFailsWith<ContractException> { rpe("8.3") }
        assertFailsWith<ContractException> { rpe("true") }
    }

    @Test
    fun unknownKeysAndNonObjectsAreRejected() {
        assertEquals("unknown_key", assertFailsWith<ContractException> {
            WorkoutEventV2.decode(withReps("8").replace("\"position\": 0,", "\"position\": 0, \"extra\": 1,"))
        }.code)
        assertEquals("invalid_value", assertFailsWith<ContractException> { WorkoutEventV2.decode("[1]") }.code)
        assertEquals("invalid_value", assertFailsWith<ContractException> { WorkoutEventV2.decode("not json") }.code)
    }
}
