import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../beyondrep_theme.dart';

/// One bar: stacked [segments] bottom to top. An empty list is a no-data day,
/// drawn as a thin muted stub, never as a zero bar.
class NsBar {
  const NsBar({required this.segments, this.highlight = false});

  final List<({double value, Color color})> segments;
  final bool highlight;

  double get total => segments.fold(0.0, (sum, s) => sum + s.value);
}

/// Stacked bar chart with an optional dashed reference line. Axis labels are
/// real [Text] widgets so they follow text scaling.
class NsBarChart extends StatelessWidget {
  const NsBarChart({
    super.key,
    required this.bars,
    required this.semanticsLabel,
    this.referenceValue,
    this.referenceLabel,
    this.height = 130,
    this.axisLabels = const [],
  });

  final List<NsBar> bars;
  final String semanticsLabel;
  final double? referenceValue;
  final String? referenceLabel;
  final double height;
  final List<String> axisLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.mutedColor;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: muted);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (referenceLabel != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(referenceLabel!, style: labelStyle),
            ),
          SizedBox(
            height: height,
            child: CustomPaint(
              painter: _BarPainter(
                bars: bars,
                referenceValue: referenceValue,
                muted: muted,
                highlightColor: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (axisLabels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  for (final label in axisLabels)
                    Expanded(
                      child: Text(
                        label,
                        style: labelStyle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.bars,
    required this.referenceValue,
    required this.muted,
    required this.highlightColor,
  });

  final List<NsBar> bars;
  final double? referenceValue;
  final Color muted;
  final Color highlightColor;

  @override
  void paint(Canvas canvas, Size size) {
    var maxValue = referenceValue ?? 0;
    for (final b in bars) {
      maxValue = math.max(maxValue, b.total);
    }
    maxValue = maxValue <= 0 ? 1 : maxValue * 1.1;
    double y(double v) => size.height - v / maxValue * size.height;

    if (bars.isNotEmpty) {
      final slot = size.width / bars.length;
      final barWidth = slot * 0.6;
      for (var i = 0; i < bars.length; i++) {
        final bar = bars[i];
        final left = i * slot + (slot - barWidth) / 2;
        if (bar.segments.isEmpty) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, size.height - 2, barWidth, 2),
              const Radius.circular(1),
            ),
            Paint()..color = muted.withValues(alpha: 0.5),
          );
          continue;
        }
        var acc = 0.0;
        for (var s = 0; s < bar.segments.length; s++) {
          final seg = bar.segments[s];
          final top = y(acc + seg.value);
          final bottom = y(acc);
          acc += seg.value;
          final isTop = s == bar.segments.length - 1;
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTRB(left, top, left + barWidth, bottom),
              topLeft: isTop ? const Radius.circular(3) : Radius.zero,
              topRight: isTop ? const Radius.circular(3) : Radius.zero,
            ),
            Paint()..color = seg.color,
          );
        }
        if (bar.highlight) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(left, y(acc), left + barWidth, size.height),
              const Radius.circular(3),
            ),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = highlightColor,
          );
        }
      }
    }

    final ref = referenceValue;
    if (ref != null) {
      final paint = Paint()
        ..color = muted
        ..strokeWidth = 1;
      final ry = y(ref);
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(
          Offset(x, ry),
          Offset(math.min(x + 4, size.width), ry),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.bars != bars ||
      old.referenceValue != referenceValue ||
      old.muted != muted ||
      old.highlightColor != highlightColor;
}
