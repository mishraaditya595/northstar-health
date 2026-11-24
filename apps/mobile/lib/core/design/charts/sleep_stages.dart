import 'package:flutter/material.dart';

import '../beyondrep_theme.dart';

/// Kit-level sleep stage; features map their own stage enum onto it.
enum NsStage { awake, rem, core, deep }

class NsStageColors {
  const NsStageColors._();

  static Color of(NsStage s, Brightness b) {
    final dark = b == Brightness.dark;
    return switch (s) {
      NsStage.deep => dark ? const Color(0xFF5B48A8) : const Color(0xFF3E2F7A),
      NsStage.core => dark ? const Color(0xFF8E7AE0) : const Color(0xFF6650AB),
      NsStage.rem =>
        dark ? BeyondRepPalette.sleepDark : const Color(0xFF9C86E0),
      NsStage.awake =>
        dark ? BeyondRepPalette.amberDark : BeyondRepPalette.amberLight,
    };
  }
}

Color _track(ThemeData theme) =>
    theme.extension<BeyondRepColors>()?.border ?? theme.dividerColor;

/// One 10 px rounded bar of stage proportions (deep, core, REM, awake).
/// An empty or zero total draws only the muted track.
class NsStageBar extends StatelessWidget {
  const NsStageBar({
    super.key,
    required this.totals,
    required this.semanticsLabel,
  });

  final Map<NsStage, Duration> totals;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: 10,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarPainter(
            totals: totals,
            brightness: theme.brightness,
            track: _track(theme),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.totals,
    required this.brightness,
    required this.track,
  });

  final Map<NsStage, Duration> totals;
  final Brightness brightness;
  final Color track;

  static const _order = [
    NsStage.deep,
    NsStage.core,
    NsStage.rem,
    NsStage.awake,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.clipRRect(clip);
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final total = _order.fold<int>(
      0,
      (a, s) => a + (totals[s]?.inMicroseconds ?? 0),
    );
    if (total <= 0) return;
    var x = 0.0;
    for (final s in _order) {
      final us = totals[s]?.inMicroseconds ?? 0;
      if (us <= 0) continue;
      final w = size.width * us / total;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, w, size.height),
        Paint()..color = NsStageColors.of(s, brightness),
      );
      x += w;
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.totals != totals ||
      old.brightness != brightness ||
      old.track != track;
}

/// Four-row hypnogram (Awake, REM, Core, Deep top to bottom), x = time.
class NsStageTimeline extends StatelessWidget {
  const NsStageTimeline({
    super.key,
    required this.segments,
    required this.startLabel,
    required this.endLabel,
    required this.semanticsLabel,
  });

  final List<({DateTime from, DateTime to, NsStage stage})> segments;
  final String startLabel;
  final String endLabel;
  final String semanticsLabel;

  static const _rows = [
    (NsStage.awake, 'Awake'),
    (NsStage.rem, 'REM'),
    (NsStage.core, 'Core'),
    (NsStage.deep, 'Deep'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 96,
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in _rows)
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(r.$2, style: small),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      segments: segments,
                      brightness: theme.brightness,
                      track: _track(theme),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(startLabel, style: small),
              Text(endLabel, style: small),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.segments,
    required this.brightness,
    required this.track,
  });

  final List<({DateTime from, DateTime to, NsStage stage})> segments;
  final Brightness brightness;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const rows = NsStageTimeline._rows;
    final rowH = size.height / rows.length;
    final grid = Paint()..color = track;
    for (var i = 0; i < rows.length; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, rowH * i + rowH / 2 - 0.5, size.width, 1),
        grid,
      );
    }
    if (segments.isEmpty) return;
    var start = segments.first.from;
    var end = segments.first.to;
    for (final s in segments) {
      if (s.from.isBefore(start)) start = s.from;
      if (s.to.isAfter(end)) end = s.to;
    }
    final span = end.difference(start).inMicroseconds;
    if (span <= 0) return;
    for (final s in segments) {
      final row = rows.indexWhere((r) => r.$1 == s.stage);
      final x0 = size.width * s.from.difference(start).inMicroseconds / span;
      final x1 = size.width * s.to.difference(start).inMicroseconds / span;
      final bar = Rect.fromLTRB(
        x0,
        rowH * row + rowH * 0.15,
        x1,
        rowH * (row + 1) - rowH * 0.15,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          bar.width < 1 ? bar.inflate(0.5) : bar,
          const Radius.circular(2),
        ),
        Paint()..color = NsStageColors.of(s.stage, brightness),
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.segments != segments ||
      old.brightness != brightness ||
      old.track != track;
}
