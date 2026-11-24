import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/bar_series.dart';
import '../application/health_overview.dart';
import '../data/health_reader.dart';
import '../health_format.dart';
import 'health_card_frame.dart';
import 'metric_unavailable.dart';

const _title = 'Activity';
const _icon = Icons.directions_walk;

/// Steps today with the 7-day average and mini bars, and active calories.
class ActivityCard extends StatelessWidget {
  const ActivityCard({
    required this.section,
    required this.platform,
    required this.today,
    this.onTap,
    this.onAllowMore,
    super.key,
  });

  final Section<ActivityOverview> section;
  final HealthPlatformKind platform;

  /// Local date of today; the bars end here.
  final DateTime today;
  final VoidCallback? onTap;
  final VoidCallback? onAllowMore;

  @override
  Widget build(BuildContext context) {
    final section = this.section;
    if (section is SectionGap<ActivityOverview>) {
      return HealthCardFrame(
        title: _title,
        icon: _icon,
        onTap: onTap,
        children: [
          MetricUnavailable(
            gap: section.gap,
            metricName: _title,
            platform: platform,
            onAction: onAllowMore,
          ),
        ],
      );
    }
    final value = (section as SectionData<ActivityOverview>).value;
    final theme = Theme.of(context);
    final steps = value.stepsToday;
    final stepsText = steps == null ? null : formatCount(steps);
    final average = value.stepsWeekAverage;
    final stepsGap = value.stepsGap;
    final caption = steps == null
        ? stepsGap == null
              ? 'No steps yet today'
              : 'Steps: ${metricUnavailableText(stepsGap, _title, platform)}'
        : average == null
        ? 'steps'
        : 'steps · avg ${formatCount(average)}';
    final energy = value.activeEnergyToday;
    final energyGap = value.energyGap;
    final energyText = energy != null
        ? '${energy.round()} active kcal'
        : energyGap != null
        ? 'Active calories: '
              '${metricUnavailableText(energyGap, _title, platform)}'
        : value.activeEnergyDaily.isEmpty
        ? 'Active calories need a watch'
        : null;
    final week = dailySlots(value.stepsDaily, today, 7);
    final border = theme.extension<BeyondRepColors>()!.border;
    final label = [
      if (stepsText == null && stepsGap != null)
        'Activity: $caption.'
      else
        'Activity: ${stepsText == null ? 'no steps yet' : '$stepsText steps'} '
            'today${average == null ? '' : ', 7-day average ${formatCount(average)}'}.',
      ?energyText,
    ].join(' ');
    return HealthCardFrame(
      title: _title,
      icon: _icon,
      onTap: onTap,
      semanticsLabel: label,
      children: [
        HealthValue(stepsText),
        HealthCaption(caption),
        const SizedBox(height: 8),
        NsBarChart(
          height: 36,
          semanticsLabel: 'Steps, last 7 days',
          bars: [
            for (var i = 0; i < week.length; i++)
              NsBar(
                highlight: i == week.length - 1,
                segments: week[i] == null
                    ? const []
                    : [
                        (
                          value: week[i]!,
                          color: i == week.length - 1
                              ? theme.colorScheme.primary
                              : border,
                        ),
                      ],
              ),
          ],
        ),
        if (energyText != null) ...[
          const SizedBox(height: 6),
          HealthCaption(energyText),
        ],
      ],
    );
  }
}
