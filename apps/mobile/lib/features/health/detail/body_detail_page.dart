import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/charts/line_chart.dart';
import '../application/health_details.dart';
import '../application/health_overview.dart';
import '../domain/metric_explanations.dart';
import '../domain/series_stats.dart';
import '../domain/trend.dart';
import '../domain/daily_series.dart';
import '../health_format.dart';
import '../widgets/detail_layout.dart';
import '../widgets/health_card_frame.dart';
import '../widgets/metric_info_sheet.dart';

/// Signed kg per week; neutral, as goals differ.
String _rate(double perWeek) {
  final amount = perWeek.abs().toStringAsFixed(1);
  if (amount == '0.0') return '0.0 kg a week';
  return '${perWeek < 0 ? '−' : '+'}$amount kg a week';
}

/// Weight, its average weekly change, body fat and lean mass over 7 or 30
/// days, read fresh and held in memory only.
class BodyDetailPage extends ConsumerStatefulWidget {
  const BodyDetailPage({super.key});

  @override
  ConsumerState<BodyDetailPage> createState() => _BodyDetailPageState();
}

class _BodyDetailPageState extends ConsumerState<BodyDetailPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    return HealthDetailScaffold(
      title: 'Body',
      icon: Icons.monitor_weight_outlined,
      chips: DetailRangeChips(
        options: detailRanges,
        selected: _days,
        onSelected: (days) => setState(() => _days = days),
      ),
      builder: (overview) => switch (overview.body) {
        SectionGap(:final gap) => DetailPanel(
          children: [
            DetailUnavailable(
              gap: gap,
              metricName: 'Body',
              platform: overview.platform,
              onRetry: () =>
                  ref.read(healthOverviewProvider.notifier).refresh(),
            ),
          ],
        ),
        SectionData(:final value) => _BodyView(
          overview: overview,
          body: value,
          days: _days,
          onRetry: () => ref.read(healthOverviewProvider.notifier).refresh(),
        ),
      },
    );
  }
}

class _BodyView extends ConsumerWidget {
  const _BodyView({
    required this.overview,
    required this.body,
    required this.days,
    required this.onRetry,
  });

  final HealthOverview overview;
  final BodyOverview body;
  final int days;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leanAsync = ref.watch(leanMassProvider);
    // While a reload (e.g. after an account switch) runs, the previous value
    // is not shown.
    final lean = leanAsync.isLoading ? null : leanAsync.value;
    final fat = body.bodyFat;
    final tiles = [
      if (fat != null)
        DetailStat(
          'Body fat',
          '${fat.value.toStringAsFixed(1)}%',
          formatHealthDate(fat.day),
          null,
          metricInfoButton(
            context,
            MetricKey.bodyFat,
            platform: overview.platform,
          ),
        )
      else if (body.bodyFatGap case final gap?)
        DetailUnavailableTile(
          label: 'Body fat',
          gap: gap,
          metricName: 'body fat',
          platform: overview.platform,
          onRetry: onRetry,
        ),
      if (lean != null)
        DetailStat(
          'Lean mass',
          '${lean.value.toStringAsFixed(1)} kg',
          formatHealthDate(lean.day),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _weight(context),
        if (tiles.isNotEmpty) DetailPanel(children: [DetailPairs(tiles)]),
      ],
    );
  }

  Widget _weight(BuildContext context) {
    final today = dayOf(overview.readAt);
    final first = DateTime(today.year, today.month, today.day - (days - 1));
    final range = '${formatHealthDate(first)} – ${formatHealthDate(today)}';
    final latest = body.weight;
    final trend = body.weightVsMonth;
    final inRange = [
      for (final d in body.weightDaily)
        if (!d.day.isBefore(first)) d,
    ];
    final rate = weeklyChange(inRange);
    final latestText = latest?.value.toStringAsFixed(1);
    if (latest == null && body.weightGap != null) {
      return DetailGapPanel(
        title: 'Weight',
        gap: body.weightGap!,
        metricName: 'weight',
        platform: overview.platform,
        onRetry: onRetry,
      );
    }
    return DetailPanel(
      title: 'Weight',
      trailing: range,
      info: metricInfoButton(
        context,
        MetricKey.weight,
        platform: overview.platform,
        usual: usualFrom(body.weightDaily, today, reading: latest),
        unit: 'kg',
      ),
      children: [
        DetailHeadline(
          latestText,
          unit: 'kg',
          trend: trend == null
              ? null
              : healthTrendLabel(
                  TrendMetric.weight,
                  trend,
                  since: body.weightSince,
                ),
        ),
        HealthCaption(
          latest == null
              ? 'No weight in 30 days'
              : 'Weighed ${formatHealthDate(latest.day)}',
        ),
        if (inRange.isEmpty)
          HealthCaption('No weigh-ins in these $days days.')
        else ...[
          const SizedBox(height: 10),
          NsLineChart(
            values: dailySlots(body.weightDaily, today, days),
            startLabel: formatHealthDate(first),
            endLabel: 'Today',
            semanticsLabel:
                'Weight, $range: ${inRange.length} weigh-ins. '
                'Latest $latestText kg on ${formatHealthDate(latest!.day)}. '
                '${rate == null ? '' : 'Average weekly change ${_rate(rate)}.'}',
          ),
        ],
        const SizedBox(height: 6),
        DetailRow('Average weekly change', rate == null ? '—' : _rate(rate)),
        if (rate == null)
          HealthCaption('Needs 4 weigh-ins in these $days days.'),
      ],
    );
  }
}
