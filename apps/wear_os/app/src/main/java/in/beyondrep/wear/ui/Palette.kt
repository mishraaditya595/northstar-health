package `in`.beyondrep.wear.ui

import androidx.compose.ui.graphics.Color
import `in`.beyondrep.wear.core.glance.Metric
import `in`.beyondrep.wear.core.glance.Tone

/** Performance V2 dark tokens (docs/DESIGN_SYSTEM.md), same values as Palette.swift. */
object Palette {
    val canvas = Color(0xFF0B0F13)
    val surface = Color(0xFF171E24)
    val ink = Color(0xFFF5F7F6)
    val secondary = Color(0xFFA5B0B8)
    val performance = Color(0xFFD6FF60)
    val caution = Color(0xFFFFD18B)
    val destructive = Color(0xFFFF8587)

    val sleep = Color(0xFFC1A9FF)
    val heart = Color(0xFFFF8587)
    val steps = Color(0xFF7FD8FF)

    /** The colour a status line is drawn in. */
    fun tone(tone: Tone): Color = when (tone) {
        Tone.GOOD -> performance
        Tone.NEUTRAL -> secondary
        Tone.CAUTION -> caution
    }

    /** The accent of a metric's tile and detail screen. */
    fun accent(metric: Metric): Color = when (metric) {
        Metric.SLEEP -> sleep
        Metric.RESTING_HR, Metric.HRV -> heart
        Metric.STEPS -> steps
    }

    /** The ring colour of a readiness band. */
    fun band(band: String): Color = when (band) {
        "good" -> performance
        "fair" -> caution
        else -> destructive
    }
}
