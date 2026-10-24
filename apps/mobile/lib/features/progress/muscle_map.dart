import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/page_header.dart';
import '../../core/design/northstar_theme.dart';
import 'muscle_recovery.dart';

/// Which side of the body a [MuscleMap] draws.
enum BodySide { front, back }

/// Stylised front or back figure. Pure drawing: colours come from [recovery]
/// and the theme, so changing the data source never touches this file.
class MuscleMap extends StatelessWidget {
  const MuscleMap({required this.side, required this.recovery, super.key});

  final BodySide side;
  final MuscleRecovery recovery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 100 / 215,
      child: CustomPaint(
        painter: _BodyPainter(
          side: side,
          recovery: recovery,
          silhouette: scheme.onSurface.withValues(alpha: .09),
          idle: scheme.onSurface.withValues(alpha: .15),
          worked: scheme.primary,
        ),
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.side,
    required this.recovery,
    required this.silhouette,
    required this.idle,
    required this.worked,
  });

  final BodySide side;
  final MuscleRecovery recovery;
  final Color silhouette;
  final Color idle;
  final Color worked;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 215);
    final base = Paint()..color = silhouette;
    // Silhouette: head, neck, torso, arms, hands, legs, feet.
    canvas.drawOval(const Rect.fromLTRB(42, 2, 58, 25), base);
    canvas.drawRRect(
      RRect.fromLTRBR(45, 22, 55, 32, const Radius.circular(3)),
      base,
    );
    final torso = Path()
      ..moveTo(28, 33)
      ..quadraticBezierTo(50, 25, 72, 33)
      ..cubicTo(70, 55, 66, 70, 65, 98)
      ..quadraticBezierTo(50, 108, 35, 98)
      ..cubicTo(34, 70, 30, 55, 28, 33)
      ..close();
    canvas.drawPath(torso, base);
    for (final mirror in [false, true]) {
      _flip(canvas, mirror, () {
        canvas.drawRRect(
          RRect.fromLTRBR(15, 32, 31, 60, const Radius.circular(8)),
          base,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(13, 58, 27, 94, const Radius.circular(7)),
          base,
        );
        canvas.drawOval(const Rect.fromLTRB(11, 92, 25, 108), base);
        canvas.drawRRect(
          RRect.fromLTRBR(33, 96, 50, 148, const Radius.circular(9)),
          base,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(35, 146, 49, 196, const Radius.circular(7)),
          base,
        );
        canvas.drawOval(const Rect.fromLTRB(30, 194, 49, 210), base);
      });
    }
    if (side == BodySide.front) {
      _front(canvas);
    } else {
      _back(canvas);
    }
  }

  void _flip(Canvas canvas, bool mirror, VoidCallback draw) {
    if (!mirror) return draw();
    canvas.save();
    canvas.translate(100, 0);
    canvas.scale(-1, 1);
    draw();
    canvas.restore();
  }

  /// Draws [shape] on the left half and mirrored on the right in the muscle's
  /// colour. Midline muscles pass `mirror: false`.
  void _muscle(
    Canvas canvas,
    Muscle muscle,
    void Function(Canvas, Paint) shape, {
    bool mirror = true,
  }) {
    final load = recovery.loadOf(muscle);
    final paint = Paint()
      ..color = load == 0
          ? idle
          : Color.lerp(worked.withValues(alpha: .35), worked, load)!;
    shape(canvas, paint);
    if (mirror) {
      canvas.save();
      canvas.translate(100, 0);
      canvas.scale(-1, 1);
      shape(canvas, paint);
      canvas.restore();
    }
  }

  RRect _r(double l, double t, double r, double b, [double rad = 5]) =>
      RRect.fromLTRBR(l, t, r, b, Radius.circular(rad));

  void _front(Canvas c) {
    _muscle(
      c,
      Muscle.shoulders,
      (c, p) => c.drawOval(const Rect.fromLTRB(18, 30, 33, 48), p),
    );
    _muscle(c, Muscle.chest, (c, p) => c.drawRRect(_r(34, 36, 49, 56, 7), p));
    _muscle(c, Muscle.abs, (c, p) => c.drawRRect(_r(41, 58, 49, 94, 4), p));
    _muscle(
      c,
      Muscle.obliques,
      (c, p) => c.drawRRect(_r(34, 60, 40, 92, 4), p),
    );
    _muscle(c, Muscle.biceps, (c, p) => c.drawRRect(_r(16, 48, 28, 70, 6), p));
    _muscle(
      c,
      Muscle.forearms,
      (c, p) => c.drawRRect(_r(14, 72, 26, 96, 6), p),
    );
    _muscle(c, Muscle.quads, (c, p) => c.drawRRect(_r(35, 104, 49, 146, 8), p));
    _muscle(
      c,
      Muscle.calves,
      (c, p) => c.drawRRect(_r(36, 154, 48, 192, 6), p),
    );
  }

  void _back(Canvas c) {
    _muscle(
      c,
      Muscle.shoulders,
      (c, p) => c.drawOval(const Rect.fromLTRB(18, 30, 33, 48), p),
    );
    _muscle(c, Muscle.traps, (c, p) => c.drawRRect(_r(38, 28, 49, 50, 6), p));
    _muscle(c, Muscle.lats, (c, p) => c.drawRRect(_r(34, 48, 49, 78, 7), p));
    _muscle(
      c,
      Muscle.lowerBack,
      (c, p) => c.drawRRect(_r(42, 78, 49, 96, 4), p),
    );
    _muscle(c, Muscle.triceps, (c, p) => c.drawRRect(_r(16, 48, 28, 70, 6), p));
    _muscle(
      c,
      Muscle.forearms,
      (c, p) => c.drawRRect(_r(14, 72, 26, 96, 6), p),
    );
    _muscle(c, Muscle.glutes, (c, p) => c.drawRRect(_r(34, 98, 49, 116, 8), p));
    _muscle(
      c,
      Muscle.hamstrings,
      (c, p) => c.drawRRect(_r(35, 118, 49, 148, 8), p),
    );
    _muscle(
      c,
      Muscle.calves,
      (c, p) => c.drawRRect(_r(36, 154, 48, 192, 6), p),
    );
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.side != side ||
      old.recovery != recovery ||
      old.silhouette != silhouette ||
      old.idle != idle ||
      old.worked != worked;
}

/// "Muscle Recovery" card: front and back figures plus a legend. Reads
/// [muscleRecoveryProvider]; says so when the values are placeholders.
class MuscleRecoveryCard extends ConsumerWidget {
  const MuscleRecoveryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(muscleRecoveryProvider);
    final theme = Theme.of(context);
    final worked = [
      for (final m in Muscle.values)
        if (recovery.loadOf(m) >= .5) m.name,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Muscle Recovery',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (recovery.isSample) const NsTag('Sample data'),
              ],
            ),
            const SizedBox(height: 14),
            Semantics(
              label:
                  'Body map${recovery.isSample ? ', sample data' : ''}. '
                  'Recently trained: ${worked.isEmpty ? 'none' : worked.join(', ')}.',
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: MuscleMap(
                        side: BodySide.front,
                        recovery: recovery,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: MuscleMap(side: BodySide.back, recovery: recovery),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend(
                  color: theme.colorScheme.onSurface.withValues(alpha: .15),
                  label: 'Recovered',
                ),
                const SizedBox(width: 20),
                _Legend(
                  color: theme.colorScheme.primary,
                  label: 'Recently trained',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              recovery.isSample
                  ? 'Placeholder layout: these values are not from your workouts yet.'
                  : 'Shaded by how recently each muscle was trained.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.mutedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}
