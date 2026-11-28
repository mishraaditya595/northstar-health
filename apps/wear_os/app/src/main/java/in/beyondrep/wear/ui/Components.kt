package `in`.beyondrep.wear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material3.Text

/** A line of text in the watch's type scale (sizes in sp, so they follow the system font scale). */
@Composable
fun BrText(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = Palette.ink,
    size: Int = 12,
    weight: FontWeight = FontWeight.Normal,
    align: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
) {
    Text(
        text = text,
        modifier = modifier,
        color = color,
        fontSize = size.sp,
        fontWeight = weight,
        textAlign = align,
        maxLines = maxLines,
    )
}

/**
 * A rounded surface. With [onClick] it is one button for TalkBack and carries [description]
 * instead of reading its children; without, its children stay readable.
 */
@Composable
fun Surface(
    modifier: Modifier = Modifier,
    description: String? = null,
    onClick: (() -> Unit)? = null,
    borderColor: Color? = null,
    content: @Composable BoxScope.() -> Unit,
) {
    var m = modifier.background(Palette.surface, RoundedCornerShape(12.dp))
    if (borderColor != null) m = m.border(1.dp, borderColor, RoundedCornerShape(12.dp))
    if (onClick != null) m = m.clickable(onClick = onClick)
    if (description != null) {
        m = m.semantics(mergeDescendants = true) {
            contentDescription = description
            if (onClick != null) role = Role.Button
        }
    }
    Box(m.padding(8.dp)) { content() }
}

/** A full-width button with a 44 dp minimum height. [prominent] is the accent fill; [destructive] draws the text in red. */
@Composable
fun BrButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    prominent: Boolean = false,
    destructive: Boolean = false,
    description: String? = null,
) {
    val fill = if (prominent) Palette.performance else Palette.surface
    val ink = when {
        prominent -> Palette.canvas
        destructive -> Palette.destructive
        else -> Palette.ink
    }
    var m = modifier
        .heightIn(min = 44.dp)
        .alpha(if (enabled) 1f else 0.4f)
        .background(fill, RoundedCornerShape(22.dp))
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
    if (description != null) m = m.semantics { contentDescription = description }
    Box(m.padding(horizontal = 12.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
        BrText(text, color = ink, size = 13, weight = FontWeight.Bold, align = TextAlign.Center)
    }
}

/** The readiness ring: [score] of 100 around a number. Drawn, so it needs no component library. */
@Composable
fun ScoreRing(score: Int, color: Color, size: Int, modifier: Modifier = Modifier) {
    Box(modifier.size(size.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size.dp)) {
            val stroke = 6.dp.toPx()
            val inset = stroke / 2
            val arc = Size(this.size.width - stroke, this.size.height - stroke)
            drawArc(
                color = Palette.surface, startAngle = 0f, sweepAngle = 360f, useCenter = false,
                topLeft = Offset(inset, inset), size = arc, style = Stroke(stroke),
            )
            drawArc(
                color = color, startAngle = -90f, sweepAngle = 360f * score.coerceIn(0, 100) / 100f, useCenter = false,
                topLeft = Offset(inset, inset), size = arc, style = Stroke(stroke, cap = StrokeCap.Round),
            )
        }
        BrText("$score", size = 18, weight = FontWeight.Bold, maxLines = 1)
    }
}
