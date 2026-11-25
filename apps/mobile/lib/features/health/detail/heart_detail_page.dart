import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/charts/line_chart.dart';
import '../../../core/design/charts/trend_label.dart';
import '../application/health_details.dart';
import '../application/health_overview.dart';
import '../application/training_insights.dart';
import '../data/health_reader.dart';
import '../domain/daily_series.dart';
import '../domain/health_types.dart';
import '../domain/series_stats.dart';
import '../domain/trend.dart';
import '../health_format.dart';
import '../widgets/detail_layout.dart';
import '../widgets/health_card_frame.dart';
import '../widgets/training_insight_line.dart';

const _vo2Name = 'Cardio fitness (VO₂ max)';
const _walkingName = 'Walking heart rate';

/// "your normal 53–57": the 30-day mean ± 1 SD; null with under 7 days.
({double low, double high, String label})? _band(
  List<DayValue> daily,
  String unit,
) {
  final b = normalBand([for (final d in daily) d.value]);
  if (b == null) return null;
  return (
    low: b.low,
    high: b.high,
    label: 'your normal ${b.low.round()}–${b.high.round()}$unit',
  );
}

/// Resting HR, HRV, VO2 max and (iOS) walking heart rate over 7 or 30 days,
/// read fresh and held in memory only.
class HeartDetailPage extends ConsumerStatefulWidget {
  const HeartDetailPage({super.key});

  @override
  ConsumerState<HeartDetailPage> createState() => _HeartDetailPageState();
}

class _HeartDetailPageState extends ConsumerState<HeartDetailPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    return HealthDetailScaffold(
      title: 'Heart',
      icon: Icons.favorite_border,
      chips: DetailRangeChips(
        options: detailRanges,
        selected: _days,
        onSelected: (days) => setState(() => _days = days),
      ),
      builder: (overview) => switch (overview.heart) {
        SectionGap(:final gap) => DetailPanel(
          children: [
            DetailUnavailable(
              gap: gap,
              metricName: 'Heart',
              platform: overview.platform,
              onRetry: () =>
                  ref.read(healthOverviewProvider.notifier).refresh(),
            ),
          ],
        ),
        SectionData(:final value) => _HeartView(
          overview: overview,
          heart: value,
          days: _days,
        ),
      },
    );
  }
}

class _HeartView extends ConsumerWidget {
  const _HeartView({
    required this.overview,
    required this.heart,
    required this.days,
  });

  final HealthOverview overview;
  final HeartOverview heart;
  final int days;

  DateTime get _today => dayOf(overview.readAt);

  DateTime get _first =>
      DateTime(_today.year, _today.month, _today.day - (days - 1));

  void _retry(WidgetRef ref) =>
      ref.read(healthOverviewProvider.notifier).refresh();

  String _when(DateTime day) =>
      day == _today ? 'today' : 'on ${formatHealthDate(day)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _restingHr(ref),
        _hrv(ref),
        _tiles(ref),
        if (ref.watch(trainingInsightsProvider)?.restingHr case final rhr?)
          TrainingInsightLine.restingHr(rhr),
      ],
    );
  }

  /// A chart over the range, or why there is none.
  List<Widget> _chart({
    required List<double?> values,
    required String noneText,
    required String semanticsLabel,
    required ({double low, double high, String label})? band,
    bool dots = false,
    List<double?>? rollingAverage,
  }) {
    if (values.every((v) => v == null)) {
      return [HealthCaption(noneText)];
    }
    return [
      const SizedBox(height: 10),
      NsLineChart(
        values: values,
        dots: dots,
        rollingAverage: rollingAverage,
        band: band,
        startLabel: formatHealthDate(_first),
        endLabel: 'Today',
        semanticsLabel: semanticsLabel,
      ),
      if (band == null) const HealthCaption('Your normal needs 7 days.'),
    ];
  }

  Widget _restingHr(WidgetRef ref) {
    final latest = heart.restingHr;
    if (latest == null && heart.restingHrGap != null) {
      return DetailGapPanel(
        title: 'Resting heart rate',
        trailing: 'Lower is better',
        gap: heart.restingHrGap!,
        metricName: 'resting heart rate',
        platform: overview.platform,
        onRetry: () => _retry(ref),
      );
    }
    final trend = heart.restingHrVsMonth;
    final value = latest?.value.round();
    final band = _band(heart.restingHrDaily, '');
    return DetailPanel(
      title: 'Resting heart rate',
      trailing: 'Lower is better',
      children: [
        DetailHeadline(
          value?.toString(),
          unit: latest == null ? null : 'bpm ${_when(latest.day)}',
          trend: trend == null
              ? null
              : healthTrendLabel(TrendMetric.restingHr, trend),
        ),
        ..._chart(
          values: dailySlots(heart.restingHrDaily, _today, days),
          noneText: 'No resting heart rate in these $days days.',
          band: band,
          semanticsLabel:
              'Resting heart rate, last $days days. '
              '${value == null ? '' : 'Latest $value bpm ${_when(latest!.day)}. '}'
              '${band == null ? '' : 'Your normal ${band.low.round()} to ${band.high.round()} bpm.'}',
        ),
      ],
    );
  }

  Widget _hrv(WidgetRef ref) {
    final latest = heart.hrv;
    if (latest == null && heart.hrvGap != null) {
      return DetailGapPanel(
        title: 'Heart rate variability',
        trailing: 'Higher is better',
        gap: heart.hrvGap!,
        metricName: 'HRV',
        platform: overview.platform,
        onRetry: () => _retry(ref),
      );
    }
    final trend = heart.hrvVsNormal;
    final value = latest?.value.round();
    final band = _band(heart.hrvDaily, ' ms');
    final name = heart.hrvIsSdnn ? 'SDNN' : 'RMSSD';
    // The 7-day average runs over the whole 30 days so the 7-day view's
    // first points still average their earlier days.
    final month = dailySlots(heart.hrvDaily, _today, 30);
    final average = rollingMean(month, 7);
    return DetailPanel(
      title: 'Heart rate variability',
      trailing: 'Higher is better',
      children: [
        DetailHeadline(
          value?.toString(),
          unit: latest == null ? null : 'ms ${_when(latest.day)}',
          trend: trend == null
              ? null
              : healthTrendLabel(TrendMetric.hrv, trend),
        ),
        ..._chart(
          values: month.sublist(30 - days),
          rollingAverage: average.sublist(30 - days),
          dots: true,
          noneText: 'No HRV in these $days days.',
          band: band,
          semanticsLabel:
              'Heart rate variability ($name), daily values and 7-day '
              'average, last $days days. '
              '${value == null ? '' : 'Latest $value ms ${_when(latest!.day)}. '}'
              '${band == null ? '' : 'Your normal ${band.low.round()} to ${band.high.round()} ms.'}',
        ),
        const SizedBox(height: 8),
        HealthCaption(
          heart.hrvIsSdnn
              ? 'Apple Health reports HRV as SDNN. Android watches report '
                    "RMSSD, so numbers aren't comparable across phones."
              : 'Health Connect reports HRV as RMSSD. Apple Watch reports '
                    "SDNN, so numbers aren't comparable across phones.",
        ),
      ],
    );
  }

  Widget _tiles(WidgetRef ref) {
    final ios = overview.platform == HealthPlatformKind.appleHealth;
    return DetailPanel(
      children: [
        DetailPairs([_vo2(ref), if (ios) ?_walking(ref)]),
      ],
    );
  }

  Widget _vo2(WidgetRef ref) {
    final latest = heart.vo2Max;
    if (latest == null && heart.vo2Gap != null) {
      return DetailUnavailableTile(
        label: _vo2Name,
        gap: heart.vo2Gap!,
        metricName: 'VO₂ max',
        platform: overview.platform,
        onRetry: () => _retry(ref),
      );
    }
    if (latest == null) {
      return const DetailStat(_vo2Name, '—', 'None in the last 90 days');
    }
    final earlier = earlierReading(heart.vo2MaxDaily, 30);
    final trend = earlier == null
        ? null
        : trendOf(TrendMetric.vo2Max, latest.value, earlier.value);
    final t = trend == null ? null : nsTrendOf(trend);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailStat(
          _vo2Name,
          latest.value.toStringAsFixed(1),
          'ml/kg/min · ${formatHealthDate(latest.day)}',
        ),
        if (t != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: NsTrendLabel(
              direction: t.direction,
              tone: t.tone,
              text: trend!.direction == TrendDirection.flat
                  ? 'same as ${formatHealthDate(earlier!.day)}'
                  : '${trend.delta.abs().toStringAsFixed(1)} since '
                        '${formatHealthDate(earlier!.day)}',
            ),
          ),
      ],
    );
  }

  /// Null when there is nothing for this account (e.g. while switching).
  Widget? _walking(WidgetRef ref) {
    final async = ref.watch(walkingHrProvider);
    // While a reload (e.g. after an account switch) runs, the previous value
    // is not shown.
    if (async.isLoading) return const DetailLoading();
    return switch (async.value) {
      null => null,
      SectionData(:final value) => DetailStat(
        _walkingName,
        '${value.value.round()} bpm',
        'avg ${_when(value.day)}',
      ),
      SectionGap(:final gap) => DetailUnavailableTile(
        label: _walkingName,
        gap: gap,
        metricName: 'walking heart rate',
        platform: overview.platform,
        onRetry: () => ref.invalidate(walkingHrProvider),
      ),
    };
  }
}
