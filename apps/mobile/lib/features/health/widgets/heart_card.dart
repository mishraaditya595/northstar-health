import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/line_chart.dart';
import '../application/health_overview.dart';
import '../data/health_reader.dart';
import '../domain/health_types.dart';
import '../domain/trend.dart';
import '../health_format.dart';
import 'health_card_frame.dart';
import 'metric_unavailable.dart';

const _title = 'Heart';
const _icon = Icons.favorite_border;

/// Resting HR and HRV side by side, each with a 30-day sparkline and trend;
/// VO2 max underneath when present.
class HeartCard extends StatelessWidget {
  const HeartCard({
    required this.section,
    required this.platform,
    required this.today,
    this.onTap,
    this.onAllowMore,
    super.key,
  });

  final Section<HeartOverview> section;
  final HealthPlatformKind platform;

  /// Local date of today; the sparklines end here.
  final DateTime today;
  final VoidCallback? onTap;
  final VoidCallback? onAllowMore;

  @override
  Widget build(BuildContext context) {
    final section = this.section;
    if (section is SectionGap<HeartOverview>) {
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
    final value = (section as SectionData<HeartOverview>).value;
    final hrvName = value.hrvIsSdnn ? 'HRV (SDNN)' : 'HRV (RMSSD)';
    final rhr = value.restingHr?.value.round();
    final hrv = value.hrv?.value.round();
    final vo2 = value.vo2Max?.value.toStringAsFixed(1);
    final rhrTrend = value.restingHrVsMonth;
    final hrvTrend = value.hrvVsNormal;
    final label = [
      'Heart: resting heart rate ${rhr == null ? 'no data' : '$rhr bpm'}'
          '${rhrTrend == null ? '' : ', ${formatTrendSpoken(TrendMetric.restingHr, rhrTrend)}'}.',
      '$hrvName ${hrv == null ? 'no data' : '$hrv ms'}'
          '${hrvTrend == null ? '' : ', ${formatTrendSpoken(TrendMetric.hrv, hrvTrend)}'}.',
      if (vo2 != null) 'VO₂ max $vo2.',
    ].join(' ');
    return HealthCardFrame(
      title: _title,
      icon: _icon,
      onTap: onTap,
      semanticsLabel: label,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Metric(
                name: 'Resting HR',
                value: rhr?.toString(),
                unit: 'bpm',
                metric: TrendMetric.restingHr,
                trend: rhrTrend,
                daily: value.restingHrDaily,
                today: today,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                name: hrvName,
                value: hrv?.toString(),
                unit: 'ms',
                metric: TrendMetric.hrv,
                trend: hrvTrend,
                daily: value.hrvDaily,
                today: today,
              ),
            ),
          ],
        ),
        if (vo2 != null) ...[
          const SizedBox(height: 6),
          HealthCaption('VO₂ max $vo2'),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.name,
    required this.value,
    required this.unit,
    required this.metric,
    required this.trend,
    required this.daily,
    required this.today,
  });

  final String name;
  final String? value;
  final String unit;
  final TrendMetric metric;
  final TrendResult? trend;
  final List<DayValue> daily;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trend = this.trend;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.mutedColor),
        ),
        HealthValue(value, unit: unit),
        if (value == null)
          const HealthCaption('None in 30 days')
        else if (trend != null)
          healthTrendLabel(metric, trend),
        if (daily.length > 1) ...[
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, box) => NsSparkline(
              values: dailySlots(daily, today, 30),
              color: theme.colorScheme.primary,
              semanticsLabel: '$name, last 30 days',
              width: box.maxWidth,
            ),
          ),
        ],
      ],
    );
  }
}
