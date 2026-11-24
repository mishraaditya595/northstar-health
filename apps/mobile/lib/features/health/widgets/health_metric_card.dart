import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../data/health_reader.dart';
import '../health_format.dart';

IconData _icon(HealthMetric metric) => switch (metric) {
  HealthMetric.sleep => Icons.bedtime_outlined,
  HealthMetric.steps => Icons.directions_walk,
  HealthMetric.restingHeartRate => Icons.favorite_border,
  HealthMetric.weight => Icons.monitor_weight_outlined,
};

/// One metric: label, value and source/time caption. [onAction] makes the
/// whole card tappable (Not allowed -> Manage, Couldn't read -> Try again).
class HealthMetricCard extends StatelessWidget {
  const HealthMetricCard({
    required this.metric,
    required this.reading,
    required this.platform,
    required this.now,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final HealthMetric metric;
  final HealthReading reading;
  final HealthPlatformKind platform;
  final DateTime now;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = theme.extension<BeyondRepColors>()!.muted;
    final sleep = metric == HealthMetric.sleep;
    final iconBg = sleep
        ? (dark
              ? BeyondRepPalette.sleepSoftDark
              : BeyondRepPalette.sleepSoftLight)
        : (dark
              ? BeyondRepPalette.forestSoftDark
              : BeyondRepPalette.forestSoftLight);
    final iconColor = sleep
        ? (dark ? BeyondRepPalette.sleepDark : BeyondRepPalette.sleepLight)
        : theme.colorScheme.primary;
    final name = healthMetricLabel(metric, compact: compact);
    final reading = isHealthNoData(metric, this.reading, platform)
        ? const HealthNoData()
        : this.reading;
    final value = formatHealthValue(metric, reading);
    final caption = formatHealthCaption(metric, reading, platform, now);
    final content = Padding(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 27,
            height: 27,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_icon(metric), size: 15, color: iconColor),
          ),
          const SizedBox(height: 13),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (compact
                        ? theme.textTheme.labelSmall
                        : theme.textTheme.labelMedium)
                    ?.copyWith(color: muted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: compact
                  ? theme.textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                    )
                  : theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.4,
                    ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            caption,
            maxLines: compact ? 3 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontSize: compact ? 10 : null,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: '$name: $value. $caption',
      button: onAction != null,
      excludeSemantics: true,
      onTap: onAction,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: onAction == null
            ? content
            : InkWell(onTap: onAction, child: content),
      ),
    );
  }
}
