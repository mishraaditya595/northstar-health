import 'package:flutter/material.dart';

import '../beyondrep_theme.dart';
import '../stats.dart';

/// Whether a change is good, bad, or has no good/bad reading.
enum NsTrendTone { better, worse, neutral, same }

/// Arrow plus words plus colour, so direction and meaning never rely on
/// colour alone.
class NsTrendLabel extends StatelessWidget {
  const NsTrendLabel({
    super.key,
    required this.direction,
    required this.tone,
    required this.text,
  });

  final NsTrend direction;
  final NsTrendTone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = switch (tone) {
      NsTrendTone.better => theme.colorScheme.primary,
      NsTrendTone.worse =>
        dark ? BeyondRepPalette.amberDark : BeyondRepPalette.amberLight,
      NsTrendTone.neutral || NsTrendTone.same => theme.mutedColor,
    };
    final glyph = switch (direction) {
      NsTrend.up => '▲',
      NsTrend.down => '▼',
      NsTrend.flat => '●',
    };
    final word = switch (direction) {
      NsTrend.up => 'Up',
      NsTrend.down => 'Down',
      NsTrend.flat => 'No change',
    };
    return Semantics(
      label: '$word $text',
      excludeSemantics: true,
      child: Text(
        '$glyph $text',
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
