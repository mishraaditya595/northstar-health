import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/northstar_theme.dart';
import '../../core/design/page_header.dart';
import 'muscle_recovery.dart';

/// Which side of the body a [MuscleMap] draws.
enum BodySide { front, back }

const _labels = {
  Muscle.chest: 'Chest',
  Muscle.shoulders: 'Shoulders',
  Muscle.biceps: 'Biceps',
  Muscle.forearms: 'Forearms',
  Muscle.abs: 'Abs',
  Muscle.obliques: 'Obliques',
  Muscle.quads: 'Quads',
  Muscle.calves: 'Calves',
  Muscle.traps: 'Traps',
  Muscle.lats: 'Lats',
  Muscle.lowerBack: 'Lower back',
  Muscle.triceps: 'Triceps',
  Muscle.glutes: 'Glutes',
  Muscle.hamstrings: 'Hamstrings',
};

/// Absolute-coordinate SVG path (M L C Q Z) in the 100 x 215 figure space.
/// Shapes describe the figure's left half; the painter mirrors them.
Path _svg(String data) {
  final path = Path();
  final tokens = RegExp(r'[MLCQZ]|-?\d+(\.\d+)?').allMatches(data);
  String? command;
  final numbers = <double>[];
  void flush() {
    final n = numbers;
    switch (command) {
      case 'M':
        path.moveTo(n[0], n[1]);
      case 'L':
        path.lineTo(n[0], n[1]);
      case 'C':
        path.cubicTo(n[0], n[1], n[2], n[3], n[4], n[5]);
      case 'Q':
        path.quadraticBezierTo(n[0], n[1], n[2], n[3]);
      case 'Z':
        path.close();
    }
    numbers.clear();
  }

  for (final match in tokens) {
    final text = match.group(0)!;
    if (RegExp('[MLCQZ]').hasMatch(text)) {
      if (command != null) flush();
      command = text;
      if (text == 'Z') {
        flush();
        command = null;
      }
    } else {
      numbers.add(double.parse(text));
    }
  }
  if (command != null) flush();
  return path;
}

// Front muscles (left half).
final _frontShapes = <Muscle, List<Path>>{
  Muscle.shoulders: [
    _svg('M28 33 C21 32 15 38 15 46 C15 52 20 55 25 52 C28 47 29 40 28 33 Z'),
  ],
  Muscle.chest: [
    _svg(
      'M49 37 L49 57 C43 60 35 57 31 50 C29 44 31 38 37 36 C41 35 45 36 49 37 Z',
    ),
  ],
  Muscle.abs: [
    for (final y in const [59.0, 69.0, 79.0, 89.0])
      _svg('M41 $y L48.4 $y L48.4 ${y + 8.5} L41 ${y + 8.5} Z'),
  ],
  Muscle.obliques: [
    _svg('M39 60 C35 67 34 79 37 93 L40 93 C40 81 40 69 39 60 Z'),
  ],
  Muscle.biceps: [
    _svg('M15 51 C12 58 12 65 15 70 C19 71 23 67 24 59 C24 55 22 52 20 49 Z'),
  ],
  Muscle.forearms: [
    _svg('M12 73 C10 81 11 89 13 96 L21 96 C23 89 24 81 23 73 Z'),
  ],
  Muscle.quads: [
    _svg('M37 102 C33 116 34 136 38 149 L48 149 C51 135 51 115 48 102 Z'),
  ],
  Muscle.calves: [
    _svg('M38 157 C36 170 38 185 42 193 L46 193 C48 181 48 168 46 157 Z'),
  ],
};

// Back muscles (left half).
final _backShapes = <Muscle, List<Path>>{
  Muscle.shoulders: _frontShapes[Muscle.shoulders]!,
  Muscle.traps: [_svg('M50 27 C45 29 41 32 38 36 C40 45 45 53 50 65 Z')],
  Muscle.lats: [_svg('M37 50 C32 59 33 71 38 81 L48 86 C48 73 46 60 42 50 Z')],
  Muscle.lowerBack: [_svg('M43 85 C42 91 43 97 46 101 L49.2 101 L49.2 85 Z')],
  Muscle.triceps: [
    _svg('M14 48 C11 56 11 65 14 71 C18 73 23 69 24 60 C24 54 21 49 19 46 Z'),
  ],
  Muscle.forearms: _frontShapes[Muscle.forearms]!,
  Muscle.glutes: [
    _svg('M49.2 101 C42 98 35 102 35 110 C35 118 42 122 49.2 119 Z'),
  ],
  Muscle.hamstrings: [
    _svg('M36 123 C34 135 35 146 39 151 L48 151 C51 141 51 129 49 123 Z'),
  ],
  Muscle.calves: [
    _svg('M37 157 C34 167 36 181 42 191 L47 191 C51 181 50 167 47 157 Z'),
  ],
};

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
          idle: scheme.onSurface.withValues(alpha: .2),
          worked: scheme.primary,
          outline: scheme.surface,
          detail: scheme.onSurface.withValues(alpha: .22),
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
    required this.outline,
    required this.detail,
  });

  final BodySide side;
  final MuscleRecovery recovery;
  final Color silhouette;
  final Color idle;
  final Color worked;
  final Color outline;
  final Color detail;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 215);
    final base = Paint()..color = silhouette;
    canvas.drawOval(const Rect.fromLTRB(42, 2, 58, 25), base);
    canvas.drawRRect(
      RRect.fromLTRBR(45, 22, 55, 32, const Radius.circular(3)),
      base,
    );
    canvas.drawPath(
      _svg(
        'M28 33 Q50 25 72 33 C70 55 66 70 65 98 Q50 108 35 98 C34 70 30 55 28 33 Z',
      ),
      base,
    );
    for (final mirror in [false, true]) {
      _flip(canvas, mirror, () {
        canvas.drawRRect(
          RRect.fromLTRBR(13, 32, 28, 64, const Radius.circular(8)),
          base,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(10, 62, 25, 98, const Radius.circular(7)),
          base,
        );
        canvas.drawOval(const Rect.fromLTRB(9, 96, 24, 111), base);
        canvas.drawRRect(
          RRect.fromLTRBR(33, 96, 50, 152, const Radius.circular(9)),
          base,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(35, 150, 49, 197, const Radius.circular(7)),
          base,
        );
        canvas.drawOval(const Rect.fromLTRB(30, 195, 49, 210), base);
      });
    }
    final shapes = side == BodySide.front ? _frontShapes : _backShapes;
    shapes.forEach((muscle, paths) => _muscle(canvas, muscle, paths));
    _details(canvas);
  }

  void _flip(Canvas canvas, bool mirror, VoidCallback draw) {
    if (!mirror) return draw();
    canvas.save();
    canvas.translate(100, 0);
    canvas.scale(-1, 1);
    draw();
    canvas.restore();
  }

  void _muscle(Canvas canvas, Muscle muscle, List<Path> paths) {
    final load = recovery.loadOf(muscle);
    final fill = Paint()
      ..color = load == 0
          ? idle
          : Color.lerp(worked.withValues(alpha: .4), worked, load)!;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..color = outline;
    for (final mirror in [false, true]) {
      _flip(canvas, mirror, () {
        for (final path in paths) {
          canvas.drawPath(path, fill);
          canvas.drawPath(path, edge);
        }
      });
    }
  }

  /// Cues that make the sides unmistakable: collarbone and centre line on the
  /// front; spine and shoulder blades on the back.
  void _details(Canvas canvas) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..strokeCap = StrokeCap.round
      ..color = detail;
    if (side == BodySide.front) {
      canvas.drawLine(const Offset(36, 33), const Offset(48, 31), line);
      canvas.drawLine(const Offset(64, 33), const Offset(52, 31), line);
      canvas.drawLine(const Offset(50, 36), const Offset(50, 97), line);
      canvas.drawCircle(const Offset(50, 85), 1, Paint()..color = detail);
    } else {
      canvas.drawLine(const Offset(50, 27), const Offset(50, 100), line);
      for (final mirror in [false, true]) {
        _flip(canvas, mirror, () {
          canvas.drawPath(_svg('M44 42 C41 47 41 53 44 58'), line);
        });
      }
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.side != side ||
      old.recovery != recovery ||
      old.silhouette != silhouette ||
      old.idle != idle ||
      old.worked != worked ||
      old.outline != outline ||
      old.detail != detail;
}

/// "Muscle Recovery" card: front and back figures, labels, legend and the
/// muscles trained recently. Reads [muscleRecoveryProvider]; says so when the
/// values are placeholders.
class MuscleRecoveryCard extends ConsumerWidget {
  const MuscleRecoveryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(muscleRecoveryProvider);
    final theme = Theme.of(context);
    final worked = [
      for (final m in Muscle.values)
        if (recovery.loadOf(m) >= .5) m,
    ]..sort((a, b) => recovery.loadOf(b).compareTo(recovery.loadOf(a)));
    final workedText = worked.map((m) => _labels[m]!).join(' · ');
    Widget figure(BodySide side, String label) => Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MuscleMap(side: side, recovery: recovery),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.mutedColor,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
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
                  'Recently trained: '
                  '${worked.isEmpty ? 'none' : worked.map((m) => m.name).join(', ')}.',
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  figure(BodySide.front, 'FRONT'),
                  const SizedBox(width: 20),
                  figure(BodySide.back, 'BACK'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend(
                  color: theme.colorScheme.onSurface.withValues(alpha: .2),
                  label: 'Recovered',
                ),
                const SizedBox(width: 20),
                _Legend(
                  color: theme.colorScheme.primary,
                  label: 'Recently trained',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                worked.isEmpty
                    ? 'No muscle group trained recently'
                    : workedText,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
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
