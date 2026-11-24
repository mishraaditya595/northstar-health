import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/charts/line_chart.dart';
import '../application/health_details.dart';
import '../application/health_overview.dart';
import '../domain/series_stats.dart';
import '../domain/trend.dart';
import '../health_format.dart';
import '../widgets/detail_layout.dart';
import '../widgets/health_card_frame.dart';

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

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
  });

  final HealthOverview overview;
  final BodyOverview body;
  final int days;

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
        _weight(),
        if (tiles.isNotEmpty) DetailPanel(children: [DetailPairs(tiles)]),
      ],
    );
  }

  Widget _weight() {
    final today = _dayOf(overview.readAt);
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
    return DetailPanel(
      title: 'Weight',
      trailing: range,
      children: [
        DetailHeadline(
          latestText,
          unit: 'kg',
          trend: trend == null
              ? null
              : healthTrendLabel(TrendMetric.weight, trend),
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
