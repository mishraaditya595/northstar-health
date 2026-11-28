package `in`.beyondrep.wear.ui.workout

import kotlin.math.abs

/**
 * Turns the bezel or crown's scroll pixels into whole detents: one step per [pixelsPerStep],
 * the remainder carried over. Clockwise (positive) raises the value.
 */
class RotaryStepper(private val pixelsPerStep: Float = 30f) {
    private var carry = 0f

    /** The signed number of whole steps now due. */
    fun consume(pixels: Float): Int {
        carry += pixels
        val steps = (abs(carry) / pixelsPerStep).toInt()
        if (steps == 0) return 0
        val signed = if (carry > 0) steps else -steps
        carry -= signed * pixelsPerStep
        return signed
    }
}
