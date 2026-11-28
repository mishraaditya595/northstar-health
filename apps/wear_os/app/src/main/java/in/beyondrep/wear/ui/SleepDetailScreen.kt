package `in`.beyondrep.wear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.glance.DetailModel
import `in`.beyondrep.wear.core.glance.GlanceState
import `in`.beyondrep.wear.core.glance.Metric
import `in`.beyondrep.wear.core.glance.SleepStages

/** Time asleep, the phone's score, the stages and the last seven nights. */
@Composable
fun SleepDetailScreen(detail: DetailModel) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { BrText("Sleep", color = Palette.sleep, size = 13, weight = FontWeight.SemiBold) }
        item { BrText(detail.value, size = 24, weight = FontWeight.Bold) }
        detail.caption?.let { item { BrText(it, color = Palette.performance, size = 11) } }
        detail.stages?.let { item { StagesBar(it) } }
        item { BrText("Last 7 nights", color = Palette.secondary, size = 11) }
        item { WeekChart(detail, Metric.SLEEP, ChartStyle.BARS) }
        detail.weekAverage?.let { item { BrText("7-night average ${GlanceState.sleepText(it)}", color = Palette.secondary, size = 11) } }
    }
}

@Composable
private fun StagesBar(stages: SleepStages) {
    val parts: List<Triple<String, Int, Color>> = listOf(
        Triple("Deep", stages.deep, Palette.sleep),
        Triple("Core", stages.core, Palette.sleep.copy(alpha = 0.55f)),
        Triple("REM", stages.rem, Palette.steps),
        Triple("Awake", stages.awake, Palette.caution),
    )
    val spoken = "Sleep stages: " + parts.joinToString(", ") { "${it.first} ${GlanceState.sleepText(it.second)}" }
    Column(
        Modifier.fillMaxWidth(0.85f).semantics(mergeDescendants = true) { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Canvas(Modifier.fillMaxWidth().height(10.dp)) {
            val total = parts.sumOf { it.second }.coerceAtLeast(1).toFloat()
            val gap = 2.dp.toPx()
            val available = size.width - gap * (parts.size - 1)
            var x = 0f
            for ((_, minutes, color) in parts) {
                val width = (available * minutes / total).coerceAtLeast(2f)
                drawRoundRect(color, Offset(x, 0f), Size(width, size.height), CornerRadius(3.dp.toPx()))
                x += width + gap
            }
        }
        for (row in parts.chunked(2)) {
            Row(Modifier.fillMaxWidth()) {
                for ((name, minutes, color) in row) {
                    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Canvas(Modifier.size(6.dp)) { drawCircle(color) }
                        BrText("$name ${GlanceState.sleepText(minutes)}", color = Palette.secondary, size = 10, maxLines = 1)
                    }
                }
            }
        }
    }
}
