package `in`.beyondrep.wear.ui.workout

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.session.WorkoutController
import `in`.beyondrep.wear.ui.BrButton
import `in`.beyondrep.wear.ui.BrText
import `in`.beyondrep.wear.ui.Palette
import java.time.Duration

@Composable
fun OverviewPage(
    controller: WorkoutController,
    heartRate: Int?,
    ui: WorkoutUi,
    onPauseOrResume: () -> Unit,
    onExercises: () -> Unit,
    onEnd: () -> Unit,
) {
    val paused = remember(ui.revision) { controller.status == "paused" }
    val cursor = remember(ui.revision) { controller.cursor }
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item {
            StatRow("Time") {
                if (paused) {
                    BrText("Paused", color = Palette.caution, size = 13, weight = FontWeight.SemiBold)
                } else {
                    BrText(
                        formatClock(Duration.between(controller.startedAt, ui.now)),
                        size = 13, weight = FontWeight.SemiBold,
                    )
                }
            }
        }
        item { StatRow("Heart rate") { HeartRateText(heartRate, size = 13) } }
        item {
            val done = cursor.completedCount
            val planned = cursor.plannedCount
            StatRow("Sets", "$done of $planned sets") {
                BrText("$done / $planned", size = 13, weight = FontWeight.SemiBold)
            }
        }
        item { BrButton(if (paused) "Resume" else "Pause", onPauseOrResume, Modifier.fillMaxWidth(0.85f)) }
        item { BrButton("Exercises", onExercises, Modifier.fillMaxWidth(0.85f)) }
        item { BrButton("End", onEnd, Modifier.fillMaxWidth(0.85f), destructive = true) }
    }
}

@Composable
private fun StatRow(title: String, description: String? = null, value: @Composable () -> Unit) {
    var m = Modifier.fillMaxWidth(0.8f)
    if (description != null) m = m.semantics { contentDescription = description }
    androidx.compose.foundation.layout.Row(
        m, horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically,
    ) {
        BrText(title, color = Palette.secondary, size = 11)
        value()
    }
}
