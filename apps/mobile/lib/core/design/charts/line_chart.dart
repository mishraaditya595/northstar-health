import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../beyondrep_theme.dart';

/// Line chart where `null` values are gaps (the line breaks, no dot). An
/// optional [band] is a soft filled range behind the line.
class NsLineChart extends StatelessWidget {
  const NsLineChart({
    super.key,
    required this.values,
    required this.semanticsLabel,
    this.dots = false,
    this.rollingAverage,
    this.band,
    this.height = 120,
    this.startLabel,
    this.endLabel,
  });

  final List<double?> values;
  final String semanticsLabel;
  final bool dots;
  final List<double?>? rollingAverage;
  final ({double low, double high, String label})? band;
  final double height;
  final String? startLabel;
  final String? endLabel;

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
          if (band != null) Text(band!.label, style: labelStyle, maxLines: 1),
          SizedBox(
            height: height,
            child: CustomPaint(
              painter: _LinePainter(
                values: values,
                color: theme.colorScheme.primary,
                dots: dots,
                rollingAverage: rollingAverage,
                averageColor: muted,
                band: band == null ? null : (low: band!.low, high: band!.high),
                bandColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          if (startLabel != null || endLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(startLabel ?? '', style: labelStyle),
                  Text(endLabel ?? '', style: labelStyle),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Small, label-free trend line.
class NsSparkline extends StatelessWidget {
  const NsSparkline({
    super.key,
    required this.values,
    required this.color,
    required this.semanticsLabel,
    this.width = 150,
    this.height = 30,
  });

  final List<double?> values;
  final Color color;
  final String semanticsLabel;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _LinePainter(
            values: values,
            color: color,
            strokeWidth: 2,
            padding: 2,
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.values,
    required this.color,
    this.dots = false,
    this.rollingAverage,
    this.averageColor,
    this.band,
    this.bandColor,
    this.strokeWidth = 2.5,
    this.padding = 6,
  });

  final List<double?> values;
  final Color color;
  final bool dots;
  final List<double?>? rollingAverage;
  final Color? averageColor;
  final ({double low, double high})? band;
  final Color? bandColor;
  final double strokeWidth;
  final double padding;

  @override
  void paint(Canvas canvas, Size size) {
    final all = <double>[
      ...values.whereType<double>(),
      ...?rollingAverage?.whereType<double>(),
      if (band != null) ...[band!.low, band!.high],
    ];
    if (all.isEmpty) return;
    var lo = all.reduce(math.min);
    var hi = all.reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;
    double x(int i) =>
        padding + (values.length < 2 ? w / 2 : i / (values.length - 1) * w);
    double y(double v) => padding + (hi - v) / (hi - lo) * h;

    if (band != null && bandColor != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, y(band!.high), size.width, y(band!.low)),
        Paint()..color = bandColor!,
      );
    }

    final avg = rollingAverage;
    if (avg != null && averageColor != null) {
      _stroke(
        canvas,
        avg,
        x,
        y,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = averageColor!,
      );
    }

    _stroke(
      canvas,
      values,
      x,
      y,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    final dotPaint = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final isolated =
          (i == 0 || values[i - 1] == null) &&
          (i == values.length - 1 || values[i + 1] == null);
      // A lone point has no segment to draw, so it always gets a dot.
      if (dots || isolated) {
        canvas.drawCircle(Offset(x(i), y(v)), strokeWidth + 0.5, dotPaint);
      }
    }
  }

  void _stroke(
    Canvas canvas,
    List<double?> series,
    double Function(int) x,
    double Function(double) y,
    Paint paint,
  ) {
    final path = Path();
    var open = false;
    for (var i = 0; i < series.length; i++) {
      final v = series[i];
      if (v == null) {
        open = false;
        continue;
      }
      if (open) {
        path.lineTo(x(i), y(v));
      } else {
        path.moveTo(x(i), y(v));
        open = true;
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.dots != dots ||
      old.rollingAverage != rollingAverage ||
      old.averageColor != averageColor ||
      old.band != band ||
      old.bandColor != bandColor ||
      old.strokeWidth != strokeWidth ||
      old.padding != padding;
}
