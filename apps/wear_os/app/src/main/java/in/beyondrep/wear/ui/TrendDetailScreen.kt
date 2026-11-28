package `in`.beyondrep.wear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.glance.DetailModel
import `in`.beyondrep.wear.core.glance.GlanceState
import `in`.beyondrep.wear.core.glance.Metric
import java.time.format.TextStyle
import java.util.Locale

enum class ChartStyle { BARS, LINE }

/** Resting heart rate, HRV and steps: today, the phone's usual and the last seven days. */
@Composable
fun TrendDetailScreen(detail: DetailModel, metric: Metric, style: ChartStyle) {
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { BrText(detail.title, color = Palette.accent(metric), size = 13, weight = FontWeight.SemiBold) }
        item {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                BrText(detail.value, size = 24, weight = FontWeight.Bold)
                val unit = detail.unit
                if (unit != null && detail.value != GlanceState.MISSING) BrText(unit, color = Palette.secondary, size = 11)
            }
        }
        detail.caption?.let { item { BrText(it, color = Palette.secondary, size = 11) } }
        item { BrText("Last 7 days", color = Palette.secondary, size = 11) }
        item { WeekChart(detail, metric, style) }
        detail.weekAverage?.let { average ->
            item { BrText("7-day average $average" + (detail.unit?.let { " $it" } ?: ""), color = Palette.secondary, size = 11) }
        }
    }
}

/**
 * Seven days ending today. Bars for steps and sleep (today in full colour), a line with a dashed
 * "usual" rule for resting heart rate and HRV. A day with no value has no mark, never a 0.
 */
@Composable
fun WeekChart(detail: DetailModel, metric: Metric, style: ChartStyle) {
    val tint = Palette.accent(metric)
    val usual = if (style == ChartStyle.LINE) detail.usual else null
    Column(
        Modifier.fillMaxWidth(0.85f).semantics(mergeDescendants = true) { contentDescription = spokenWeek(detail, metric) },
    ) {
        Canvas(Modifier.fillMaxWidth().height(70.dp)) {
            val values = detail.week.map { it.value?.toFloat() }
            val present = values.filterNotNull() + listOfNotNull(usual?.toFloat())
            if (present.isEmpty()) return@Canvas
            val low = if (style == ChartStyle.BARS) 0f else present.min()
            val high = present.max().let { if (it == low) low + 1f else it }
            fun y(v: Float) = size.height - (v - low) / (high - low) * size.height
            val slot = size.width / 7f
            if (style == ChartStyle.BARS) {
                detail.week.forEachIndexed { i, point ->
                    val v = point.value?.toFloat() ?: return@forEachIndexed
                    val barWidth = slot * 0.6f
                    val top = y(v)
                    drawRoundRect(
                        color = if (point.isToday) tint else tint.copy(alpha = 0.45f),
                        topLeft = Offset(slot * i + (slot - barWidth) / 2, top),
                        size = Size(barWidth, size.height - top),
                        cornerRadius = CornerRadius(3.dp.toPx()),
                    )
                }
            } else {
                if (usual != null) {
                    drawLine(
                        Palette.secondary, Offset(0f, y(usual.toFloat())), Offset(size.width, y(usual.toFloat())),
                        strokeWidth = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)),
                    )
                }
                var previous: Offset? = null
                detail.week.forEachIndexed { i, point ->
                    val v = point.value?.toFloat() ?: return@forEachIndexed
                    val at = Offset(slot * i + slot / 2, y(v))
                    previous?.let { drawLine(tint, it, at, strokeWidth = 2.dp.toPx(), cap = StrokeCap.Round) }
                    drawCircle(tint, radius = 3.dp.toPx(), center = at)
                    previous = at
                }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            for (point in detail.week) {
                BrText(point.label, color = Palette.secondary, size = 10, align = TextAlign.Center, modifier = Modifier.weight(1f))
            }
        }
    }
}

/** "Heart rate variability, last 7 days. Monday, 40. Tuesday, no data ... Your usual is 56". */
internal fun spokenWeek(detail: DetailModel, metric: Metric): String {
    val days = detail.week.map { point ->
        val name = point.date.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.getDefault())
        val value = point.value
        when {
            value == null -> "$name, no data"
            metric == Metric.SLEEP -> "$name, ${GlanceState.sleepText(value)}"
            else -> "$name, $value"
        }
    }
    var sentence = "${detail.title}, last 7 days. " + days.joinToString(". ")
    detail.usual?.let { sentence += ". Your usual is $it" }
    return sentence
}

