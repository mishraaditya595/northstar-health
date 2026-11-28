package `in`.beyondrep.wear.ui.workout

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.session.WorkoutSummary
import `in`.beyondrep.wear.ui.BrButton
import `in`.beyondrep.wear.ui.BrText
import `in`.beyondrep.wear.ui.Palette

/** After Save. The heart rate row appears only when a heart rate was measured; the status line says what the phone has. */
@Composable
fun SummaryScreen(summary: WorkoutSummary, status: String, onDone: () -> Unit) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { BrText("Done", color = Palette.performance, size = 13, weight = FontWeight.ExtraBold) }
        item {
            BrText(
                summary.name, size = 13, weight = FontWeight.SemiBold, align = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(0.85f),
            )
        }
        item { Stat("Time", formatClock(summary.elapsed)) }
        item { Stat("Sets", "${summary.sets}") }
        summary.averageHeartRate?.let { item { Stat("Heart rate", "$it avg") } }
        item {
            BrText(
                status, color = Palette.secondary, size = 11, align = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(0.85f),
            )
        }
        item { BrButton("Done", onDone, Modifier.fillMaxWidth(0.85f), prominent = true) }
    }
}

@Composable
private fun Stat(title: String, value: String) {
    Row(
        Modifier.fillMaxWidth(0.8f).semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        BrText(title, color = Palette.secondary, size = 11)
        BrText(value, size = 13, weight = FontWeight.SemiBold, maxLines = 1)
    }
}
