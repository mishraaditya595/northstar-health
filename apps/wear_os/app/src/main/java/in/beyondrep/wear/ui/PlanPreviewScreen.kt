package `in`.beyondrep.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.glance.PlanSummary
import `in`.beyondrep.wear.core.session.WorkoutTemplate

/** Exercise names with "sets × reps". Read-only: no Start button before Wear stage 3. */
@Composable
fun PlanPreviewScreen(template: WorkoutTemplate?) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (template == null) {
            item { BrText("This plan is not on your watch yet.", color = Palette.secondary, size = 13, align = TextAlign.Center) }
            return@ScalingLazyColumn
        }
        item { BrText(template.name, size = 13, weight = FontWeight.SemiBold, align = TextAlign.Center) }
        for (exercise in template.exercises) {
            item {
                Row(
                    Modifier.fillMaxWidth(0.85f),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    BrText(exercise.name, size = 11, modifier = Modifier.weight(1f))
                    BrText(PlanSummary.of(exercise), color = Palette.secondary, size = 11)
                }
            }
        }
    }
}
