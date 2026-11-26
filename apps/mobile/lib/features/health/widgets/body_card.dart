import 'package:flutter/material.dart';

import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/charts/line_chart.dart';
import '../application/health_overview.dart';
import '../data/health_reader.dart';
import '../domain/metric_explanations.dart';
import '../domain/trend.dart';
import '../health_format.dart';
import 'health_card_frame.dart';
import 'metric_info_sheet.dart';
import 'metric_unavailable.dart';

const _title = 'Body';
const _icon = Icons.monitor_weight_outlined;

/// Latest weight with its 30-day change (neutral, no better/worse) and
/// sparkline, and body fat.
class BodyCard extends StatelessWidget {
  const BodyCard({
    required this.section,
    required this.platform,
    required this.today,
    this.onTap,
    this.onAllowMore,
    super.key,
  });

  final Section<BodyOverview> section;
  final HealthPlatformKind platform;

  /// Local date of today; the sparkline ends here.
  final DateTime today;
  final VoidCallback? onTap;
  final VoidCallback? onAllowMore;

  @override
  Widget build(BuildContext context) {
    final section = this.section;
    if (section is SectionGap<BodyOverview>) {
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
    final value = (section as SectionData<BodyOverview>).value;
    final theme = Theme.of(context);
    final weight = value.weight;
    final weightText = weight?.value.toStringAsFixed(1);
    final trend = value.weightVsMonth;
    final fat = value.bodyFat;
    String? why(MetricGap? gap) =>
        gap == null ? null : metricUnavailableText(gap, _title, platform);
    final weightNone = switch (why(value.weightGap)) {
      final text? => 'Weight: $text',
      null => 'No weight in 30 days',
    };
    final fatText = fat != null
        ? 'Body fat ${fat.value.toStringAsFixed(1)}%'
        : switch (why(value.bodyFatGap)) {
            final text? => 'Body fat: $text',
            null => null,
          };
    final label = [
      if (weight == null)
        'Body: $weightNone.'
      else
        'Body: weight $weightText kg, ${formatHealthDate(weight.day)}'
            '${trend == null ? '' : ', ${formatTrendSpoken(TrendMetric.weight, trend, since: value.weightSince)}'}.',
      if (fatText != null) '$fatText.',
    ].join(' ');
    return HealthCardFrame(
      title: _title,
      icon: _icon,
      onTap: onTap,
      semanticsLabel: label,
      bodyInfos: [
        metricInfoButton(
          context,
          MetricKey.weight,
          platform: platform,
          usual: usualFrom(value.weightDaily, today, todayValue: weight?.value),
          unit: 'kg',
        ),
        if (fatText != null)
          metricInfoButton(context, MetricKey.bodyFat, platform: platform),
      ],
      children: [
        Row(
          children: [
            Flexible(child: HealthValue(weightText, unit: 'kg')),
            const HealthInfoAnchor(index: 0),
          ],
        ),
        HealthCaption(
          weight == null
              ? weightNone
              : 'Weighed ${formatHealthDate(weight.day)}',
        ),
        if (trend != null)
          healthTrendLabel(TrendMetric.weight, trend, since: value.weightSince),
        if (value.weightDaily.length > 1) ...[
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) => NsSparkline(
              values: dailySlots(value.weightDaily, today, 30),
              color: theme.mutedColor,
              semanticsLabel: 'Weight, last 30 days',
              width: box.maxWidth,
              height: 36,
            ),
          ),
        ],
        if (fatText != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(child: HealthCaption(fatText)),
              const HealthInfoAnchor(index: 1),
            ],
          ),
        ],
      ],
    );
  }
}
