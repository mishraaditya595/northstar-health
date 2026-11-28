package `in`.beyondrep.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.ui.workout.StartTarget

/**
 * Today's program workout first, then the plans, each with a Start button, then a quick workout.
 * A tap on the card opens the plan preview.
 */
@Composable
fun TrainScreen(
    ui: WatchUi.Ready,
    onOpenToday: () -> Unit,
    onOpenPlan: (String) -> Unit,
    onStart: (StartTarget) -> Unit = {},
) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item { BrText("Train", color = Palette.secondary, size = 13, weight = FontWeight.ExtraBold) }
        ui.today?.let { today ->
            item {
                val description = "Today, ${today.name}" + (today.subtitle?.let { ", $it" } ?: "")
                Surface(
                    Modifier.fillMaxWidth(0.9f), description = description, onClick = onOpenToday,
                    borderColor = Palette.performance,
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        BrText("Today", color = Palette.performance, size = 11, weight = FontWeight.ExtraBold)
                        BrText(today.name, size = 13, weight = FontWeight.SemiBold)
                        today.subtitle?.let { BrText(it, color = Palette.secondary, size = 11) }
                    }
                }
            }
            item {
                BrButton(
                    "Start", { onStart(StartTarget.Today) }, Modifier.fillMaxWidth(0.9f), prominent = true,
                    description = "Start today, ${today.name}",
                )
            }
        }
        if (ui.plans.isEmpty() && ui.today == null) {
            item {
                BrText(
                    "No plans yet. Create one in BeyondRep on your phone.",
                    color = Palette.secondary, size = 13, modifier = Modifier.fillMaxWidth(0.85f),
                )
            }
        }
        for (plan in ui.plans) {
            item {
                val count = when (plan.exerciseCount) {
                    0 -> null
                    1 -> "1 exercise"
                    else -> "${plan.exerciseCount} exercises"
                }
                Surface(
                    Modifier.fillMaxWidth(0.9f),
                    description = plan.name + (count?.let { ", $it" } ?: ""),
                    onClick = { onOpenPlan(plan.id) },
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        BrText(plan.name, size = 13, weight = FontWeight.SemiBold)
                        count?.let { BrText(it, color = Palette.secondary, size = 11) }
                    }
                }
            }
            item {
                BrButton(
                    "Start", { onStart(StartTarget.Plan(plan.id)) }, Modifier.fillMaxWidth(0.9f),
                    description = "Start ${plan.name}",
                )
            }
        }
        item { BrButton("+ Quick workout", { onStart(StartTarget.Quick) }, Modifier.fillMaxWidth(0.9f)) }
    }
}
