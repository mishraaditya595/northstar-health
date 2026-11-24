import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/charts/bar_series.dart';
import '../application/health_overview.dart';
import '../domain/daily_series.dart';
import '../domain/health_types.dart';
import '../health_format.dart';
import '../widgets/detail_layout.dart';
import '../widgets/health_card_frame.dart';

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Daily steps and active calories over 7 or 30 days, read fresh and held in
/// memory only.
class ActivityDetailPage extends ConsumerStatefulWidget {
  const ActivityDetailPage({super.key});

  @override
  ConsumerState<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends ConsumerState<ActivityDetailPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    return HealthDetailScaffold(
      title: 'Activity',
      icon: Icons.directions_walk,
      chips: DetailRangeChips(
        options: detailRanges,
        selected: _days,
        onSelected: (days) => setState(() => _days = days),
      ),
      builder: (overview) => switch (overview.activity) {
        SectionGap(:final gap) => DetailPanel(
          children: [
            DetailUnavailable(
              gap: gap,
              metricName: 'Activity',
              platform: overview.platform,
              onRetry: () =>
                  ref.read(healthOverviewProvider.notifier).refresh(),
            ),
          ],
        ),
        SectionData(:final value) => _ActivityView(
          overview: overview,
          activity: value,
          days: _days,
        ),
      },
    );
  }
}

class _ActivityView extends StatelessWidget {
  const _ActivityView({
    required this.overview,
    required this.activity,
    required this.days,
  });

  final HealthOverview overview;
  final ActivityOverview activity;
  final int days;

  DateTime get _today => _dayOf(overview.readAt);

  /// Today is not over yet, so averages use the [days] days before it.
  double? _average(List<DayValue> daily) => summarizePeriod(
    daily,
    lastDay: DateTime(_today.year, _today.month, _today.day - 1),
    days: days,
  ).average;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_today.year, _today.month, _today.day - (days - 1));
    final range = '${formatHealthDate(first)} – ${formatHealthDate(_today)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _steps(context, range, first),
        _energy(context, range),
        const HealthCaption("Averages leave out today, which isn't over yet."),
      ],
    );
  }

  /// One bar per day, today highlighted; empty where a day has no data.
  List<NsBar> _bars(BuildContext context, List<double?> slots) {
    final color = Theme.of(context).colorScheme.primary;
    return [
      for (final (i, v) in slots.indexed)
        NsBar(
          highlight: i == slots.length - 1,
          segments: v == null ? const [] : [(value: v, color: color)],
        ),
    ];
  }

  Widget _steps(BuildContext context, String range, DateTime first) {
    // Today's slot uses the overview's value, which treats iOS 0 as no data.
    final slots = dailySlots(activity.stepsDaily, _today, days)
      ..last = activity.stepsToday;
    final today = activity.stepsToday;
    final average = _average(activity.stepsDaily);
    DayValue? best;
    for (final (i, v) in slots.indexed) {
      if (v != null && (best == null || v > best.value)) {
        best = (
          day: DateTime(first.year, first.month, first.day + i),
          value: v,
        );
      }
    }
    final todayText = today == null ? null : formatCount(today);
    final averageText = average == null ? '—' : formatCount(average);
    final bestText = best == null
        ? '—'
        : '${formatCount(best.value)} · ${formatHealthDate(best.day)}';
    return DetailPanel(
      title: 'Steps',
      trailing: range,
      children: [
        DetailHeadline(todayText, unit: 'today'),
        if (today == null) const HealthCaption('No steps yet today'),
        const SizedBox(height: 10),
        NsBarChart(
          bars: _bars(context, slots),
          semanticsLabel:
              'Steps per day, $range. '
              'Today ${todayText ?? 'no steps yet'}. '
              'Daily average $averageText. Best day $bestText.',
        ),
        const SizedBox(height: 6),
        DetailRow('Daily average', averageText),
        DetailRow('Best day', bestText),
      ],
    );
  }

  Widget _energy(BuildContext context, String range) {
    if (activity.activeEnergyDaily.isEmpty) {
      return const DetailPanel(
        title: 'Active calories',
        children: [
          HealthValue(null),
          HealthCaption('Active calories need a watch.'),
        ],
      );
    }
    final today = activity.activeEnergyToday;
    final average = _average(activity.activeEnergyDaily);
    final averageText = average == null ? '—' : '${average.round()} kcal';
    return DetailPanel(
      title: 'Active calories',
      trailing: range,
      children: [
        DetailHeadline(today?.round().toString(), unit: 'kcal today'),
        if (today == null) const HealthCaption('None yet today'),
        const SizedBox(height: 10),
        NsBarChart(
          bars: _bars(
            context,
            dailySlots(activity.activeEnergyDaily, _today, days),
          ),
          semanticsLabel:
              'Active calories per day, $range. '
              'Today ${today == null ? 'none yet' : '${today.round()} kcal'}. '
              'Daily average $averageText.',
        ),
        const SizedBox(height: 6),
        DetailRow('Daily average', averageText),
      ],
    );
  }
}
