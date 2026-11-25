import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../domain/health_types.dart';

/// Shared shell of the overview cards: icon, title, optional trailing text
/// and chevron, then [children]. [semanticsLabel] replaces the children for
/// screen readers when set; leave it null when a child has its own action.
class HealthCardFrame extends StatelessWidget {
  const HealthCardFrame({
    required this.title,
    required this.icon,
    required this.children,
    this.sleepTint = false,
    this.trailing,
    this.semanticsLabel,
    this.onTap,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool sleepTint;
  final Widget? trailing;
  final String? semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final iconBg = sleepTint
        ? (dark
              ? BeyondRepPalette.sleepSoftDark
              : BeyondRepPalette.sleepSoftLight)
        : (dark
              ? BeyondRepPalette.forestSoftDark
              : BeyondRepPalette.forestSoftLight);
    final iconColor = sleepTint
        ? (dark ? BeyondRepPalette.sleepDark : BeyondRepPalette.sleepLight)
        : theme.colorScheme.primary;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
              if (onTap != null)
                Icon(Icons.chevron_right, size: 20, color: theme.mutedColor),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
    final label = semanticsLabel;
    return Semantics(
      container: true,
      label: label,
      button: onTap != null,
      onTap: label == null ? null : onTap,
      excludeSemantics: label != null,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Muted stand-in while the overview loads; never shows a value.
class HealthCardPlaceholder extends StatelessWidget {
  const HealthCardPlaceholder({
    required this.title,
    required this.icon,
    this.sleepTint = false,
    super.key,
  });

  final String title;
  final IconData icon;
  final bool sleepTint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HealthCardFrame(
      title: title,
      icon: icon,
      sleepTint: sleepTint,
      semanticsLabel: '$title loading',
      children: [
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: theme.extension<BeyondRepColors>()!.border.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ],
    );
  }
}

/// Big value line: `—` in muted colour when missing, never `0`.
class HealthValue extends StatelessWidget {
  const HealthValue(this.value, {this.unit, super.key});

  final String? value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    final style = theme.textTheme.headlineSmall?.copyWith(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      color: v == null ? theme.mutedColor : null,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 4,
      children: [
        Text(v ?? '—', style: style),
        if (v != null && unit != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              unit!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// Muted caption line under a value.
class HealthCaption extends StatelessWidget {
  const HealthCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(color: theme.mutedColor),
    );
  }
}

/// [daily] laid onto the [days] local days ending at [today], null where a
/// day has no value (charts draw gaps, never zeros).
List<double?> dailySlots(List<DayValue> daily, DateTime today, int days) {
  final byDay = {for (final d in daily) d.day: d.value};
  return [
    for (var i = days - 1; i >= 0; i--)
      byDay[DateTime(today.year, today.month, today.day - i)],
  ];
}
