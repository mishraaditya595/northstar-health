import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/sleep_stages.dart';
import '../application/health_overview.dart';
import '../data/health_reader.dart';
import '../domain/trend.dart';
import '../domain/metric_explanations.dart';
import '../health_format.dart';
import 'health_card_frame.dart';
import 'metric_info_sheet.dart';
import 'metric_unavailable.dart';

const _title = 'Sleep';
const _icon = Icons.bedtime_outlined;

/// Last night: score, time asleep vs the 7-day average, stage bar and stage
/// totals. A night from before [today] is not shown as last night.
class SleepCard extends StatelessWidget {
  const SleepCard({
    required this.section,
    required this.platform,
    required this.today,
    this.onTap,
    this.onAllowMore,
    super.key,
  });

  final Section<SleepOverview> section;
  final HealthPlatformKind platform;

  /// Local date of today.
  final DateTime today;
  final VoidCallback? onTap;
  final VoidCallback? onAllowMore;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      SectionGap(:final gap) => HealthCardFrame(
        title: _title,
        icon: _icon,
        sleepTint: true,
        onTap: onTap,
        children: [
          MetricUnavailable(
            gap: gap,
            metricName: _title,
            platform: platform,
            onAction: onAllowMore,
          ),
        ],
      ),
      SectionData(:final value) =>
        value.lastNight.date == today
            ? _lastNight(context, value)
            : _noneLastNight(value),
    };
  }

  Widget _noneLastNight(SleepOverview value) {
    const text = 'No sleep recorded last night.';
    final last = 'Last recorded ${formatHealthDate(value.lastNight.date)}';
    return HealthCardFrame(
      title: _title,
      icon: _icon,
      sleepTint: true,
      onTap: onTap,
      semanticsLabel: 'Sleep: $text $last',
      children: [
        const HealthValue(null),
        const SizedBox(height: 4),
        const HealthCaption(text),
        HealthCaption(last),
      ],
    );
  }

  Widget _lastNight(BuildContext context, SleepOverview value) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final night = value.lastNight;
    final asleep = formatDuration(night.asleep);
    final score = value.score?.value;
    final trend = value.vsWeek;
    final hr = value.sleepAvgHr;
    final hrText = hr == null ? '—' : '${hr.round()} bpm';
    final hrGap = value.sleepHrGap;
    final hrWhy = hr == null && hrGap != null
        ? 'Sleep HR: ${metricUnavailableText(hrGap, _title, platform)}'
        : null;
    final source =
        '${night.source} · ${formatTimeRange(night.start, night.end)}';
    final lightName = lightStageName(platform);
    final stats = [
      ('Deep', formatDuration(night.deep)),
      (lightName, formatDuration(night.light)),
      ('REM', formatDuration(night.rem)),
      ('Sleep HR', hrText),
    ];
    final label = [
      'Sleep: $asleep asleep${score == null ? '' : ', score $score'}.',
      if (trend != null)
        '${formatTrendSpoken(TrendMetric.sleepDuration, trend)}.',
      if (night.hasStages)
        'Deep ${stats[0].$2}, ${lightName.toLowerCase()} ${stats[1].$2}, '
            'REM ${stats[2].$2}'
            '${hr == null ? '' : ', sleep heart rate $hrText'}.'
            '${hrWhy == null ? '' : ' $hrWhy.'}'
      else
        'Stages need a watch or ring that records them.',
      '${night.source}, ${formatTimeRange(night.start, night.end)}.',
    ].join(' ');
    final muted = theme.mutedColor;
    return HealthCardFrame(
      title: _title,
      icon: _icon,
      sleepTint: true,
      onTap: onTap,
      semanticsLabel: label,
      info: score == null
          ? null
          : metricInfoButton(context, MetricKey.sleepScore, platform: platform),
      bodyInfos: night.hasStages
          ? [
              metricInfoButton(
                context,
                MetricKey.deepSleep,
                platform: platform,
              ),
              metricInfoButton(context, MetricKey.remSleep, platform: platform),
            ]
          : const [],
      trailing: score == null
          ? null
          : Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Score',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                Text(
                  '$score',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: dark
                        ? BeyondRepPalette.sleepDark
                        : BeyondRepPalette.sleepLight,
                  ),
                ),
              ],
            ),
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          runSpacing: 2,
          children: [
            HealthValue(asleep),
            if (trend != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: healthTrendLabel(TrendMetric.sleepDuration, trend),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (night.hasStages) ...[
          NsStageBar(
            totals: {
              NsStage.deep: night.deep,
              NsStage.core: night.light,
              NsStage.rem: night.rem,
              NsStage.awake: night.awake,
            },
            semanticsLabel: 'Sleep stages',
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (name, v) in stats)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ),
                          if (name == 'Deep')
                            const HealthInfoAnchor(index: 0)
                          else if (name == 'REM')
                            const HealthInfoAnchor(index: 1),
                        ],
                      ),
                      Text(
                        v,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (hrWhy != null) ...[
            const SizedBox(height: 6),
            HealthCaption(hrWhy),
          ],
        ] else
          const HealthCaption('Stages need a watch or ring that records them.'),
        const SizedBox(height: 8),
        HealthCaption(source),
      ],
    );
  }
}
