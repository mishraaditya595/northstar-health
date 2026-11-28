package `in`.beyondrep.wear.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import `in`.beyondrep.wear.core.glance.GlanceState
import `in`.beyondrep.wear.core.glance.GlanceTile
import `in`.beyondrep.wear.core.glance.Metric
import `in`.beyondrep.wear.core.glance.SyncLine

/** Where a tap on Home leads (navigation routes). */
object Routes {
    const val PAGES = "pages"
    const val READINESS = "readiness"
    const val SYNC = "sync"
    const val TODAY = "today"
    const val METRIC = "metric"
    const val PLAN = "plan"

    fun metric(metric: Metric) = "$METRIC/${metric.name}"

    fun plan(id: String) = "$PLAN/${android.net.Uri.encode(id)}"
}

/** The glance: phone-computed readiness and today's numbers. Read-only. */
@Composable
fun HomeScreen(ui: WatchUi.Ready, onOpen: (String) -> Unit, onTrain: () -> Unit) {
    val glance = ui.glance
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item { SyncStatusLine(ui.sync) { onOpen(Routes.SYNC) } }
        glance.readiness?.let { line ->
            item { ReadinessHero(line.score, line.band, line.headline, glance.readinessReason) { onOpen(Routes.READINESS) } }
        }
        item {
            BrText(glance.caption, color = Palette.secondary, size = 11, modifier = Modifier.fillMaxWidth(0.85f))
        }
        for (pair in glance.tiles.chunked(2)) {
            item {
                Row(Modifier.fillMaxWidth(0.9f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (tile in pair) {
                        Tile(tile, Modifier.weight(1f)) { onOpen(Routes.metric(tile.metric)) }
                    }
                }
            }
        }
        item {
            Surface(
                Modifier.fillMaxWidth(0.7f), description = "Train", onClick = onTrain,
            ) {
                BrText("Train", color = Palette.performance, size = 13, weight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.Center))
            }
        }
    }
}

@Composable
private fun SyncStatusLine(line: SyncLine, onClick: () -> Unit) {
    val (color, text) = when (line) {
        SyncLine.NotPaired -> return
        is SyncLine.Synced -> Palette.performance to "Synced ${line.time}"
        is SyncLine.PhoneAway -> Palette.caution to "Phone not nearby"
    }
    Row(
        Modifier.clickable(onClick = onClick).semantics(mergeDescendants = true) {
            contentDescription = "$text. Opens sync details"
        },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(Modifier.size(6.dp).background(color, CircleShape))
        BrText(text, color = Palette.secondary, size = 11)
    }
}

@Composable
private fun ReadinessHero(score: Int, band: String, headline: String, reason: String?, onClick: () -> Unit) {
    val spoken = "Energy $score of 100, $headline" + (reason?.let { ". $it" } ?: "")
    Row(
        Modifier.fillMaxWidth(0.9f).clickable(onClick = onClick).semantics(mergeDescendants = true) {
            contentDescription = "$spoken. Opens energy details"
        },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        ScoreRing(score, Palette.band(band), size = 52)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            BrText(headline, size = 13, weight = FontWeight.SemiBold)
            if (reason != null) BrText(reason, color = Palette.secondary, size = 11)
        }
    }
}

/** One tile: label, big value, one coloured status line. Every tile has the same shape. */
@Composable
private fun Tile(tile: GlanceTile, modifier: Modifier, onClick: () -> Unit) {
    Surface(modifier.heightIn(min = 76.dp), description = spoken(tile), onClick = onClick) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            BrText(tile.label, color = Palette.accent(tile.metric), size = 11, maxLines = 1)
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                BrText(tile.value, size = 20, weight = FontWeight.Bold, maxLines = 1)
                tile.unit?.let { BrText(it, color = Palette.secondary, size = 10, maxLines = 1) }
            }
            BrText(tile.status ?: " ", color = Palette.tone(tile.tone), size = 10)
        }
    }
}

/** "Resting heart rate 61 beats per minute, 2 below your usual", "Steps, no data". */
internal fun spoken(tile: GlanceTile): String {
    val name = when (tile.metric) {
        Metric.RESTING_HR -> "Resting heart rate"
        Metric.HRV -> "Heart rate variability"
        Metric.SLEEP -> "Sleep"
        Metric.STEPS -> "Steps"
    }
    if (tile.value == GlanceState.MISSING) return "$name, no data"
    val status = tile.status?.let { ", " + spokenStatus(it) } ?: ""
    return when (tile.metric) {
        Metric.RESTING_HR -> "$name ${tile.value} beats per minute$status"
        Metric.HRV -> "$name ${tile.value} milliseconds$status"
        else -> "$name ${tile.value}$status"
    }
}

/** "−2 vs usual" is read as "2 below your usual". */
internal fun spokenStatus(status: String): String {
    val suffix = " vs usual"
    if (status.endsWith(suffix)) {
        val number = status.dropLast(suffix.length)
        if (number.startsWith("−")) return "${number.drop(1)} below your usual"
        if (number.startsWith("+")) return "${number.drop(1)} above your usual"
    }
    return status
}

