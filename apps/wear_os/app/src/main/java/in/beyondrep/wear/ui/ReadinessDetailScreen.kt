package `in`.beyondrep.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.glance.Glance
import `in`.beyondrep.wear.core.glance.GlanceState

/** The score, the phone's one-line reason and one line per input, in the phone's wording. */
@Composable
fun ReadinessDetailScreen(glance: Glance) {
    val line = glance.readiness
    if (line == null) {
        NoDataScreen()
        return
    }
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item {
            Row(
                Modifier.fillMaxWidth(0.9f).semantics(mergeDescendants = true) {
                    contentDescription = "Energy ${line.score} of 100, ${line.headline}"
                },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                ScoreRing(line.score, Palette.band(line.band), size = 52)
                BrText(line.headline, size = 13, weight = FontWeight.SemiBold)
            }
        }
        glance.readinessReason?.let { reason ->
            item { BrText(reason, color = Palette.secondary, size = 11, modifier = Modifier.fillMaxWidth(0.85f)) }
        }
        for (factor in glance.factors) {
            item {
                val name = factorName(factor.input)
                Surface(Modifier.fillMaxWidth(0.9f), description = "$name, ${factor.status}") {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        BrText(name, color = Palette.secondary, size = 11)
                        BrText(
                            factor.status, color = Palette.tone(factor.tone), size = 11,
                            weight = FontWeight.SemiBold, align = TextAlign.End,
                        )
                    }
                }
            }
        }
    }
}

private fun factorName(input: String) = when (input) {
    "sleep" -> "Sleep"
    "hrv" -> "HRV"
    "resting_hr" -> "Resting HR"
    "training_load" -> "Training load"
    else -> input
}

/** A detail screen for a day that has no snapshot (for example after midnight). */
@Composable
fun NoDataScreen() {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item { BrText(GlanceState.REFRESH_CAPTION, color = Palette.secondary, size = 13, align = TextAlign.Center) }
    }
}
