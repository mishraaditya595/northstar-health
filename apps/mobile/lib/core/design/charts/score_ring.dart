import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../beyondrep_theme.dart';

/// Ring filled `value / 100` with the value in the centre; `—` when [value]
/// is null (missing data is never drawn as zero).
class NsScoreRing extends StatelessWidget {
  const NsScoreRing({
    super.key,
    required this.value,
    required this.size,
    required this.color,
    this.caption = '',
  });

  final int? value;
  final double size;
  final Color color;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track =
        theme.extension<BeyondRepColors>()?.border ?? theme.dividerColor;
    final v = value;
    return Semantics(
      label: v == null ? '$caption: no score' : '$caption $v of 100',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            fraction: v == null ? 0 : v.clamp(0, 100) / 100,
            color: color,
            track: track,
          ),
          child: Center(
            child: Text(
              v == null ? '—' : '$v',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.08;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}
