import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/charts/bar_series.dart';
import '../../progress/workout_history_state.dart';
import '../../workouts/domain/workout_models.dart';
import '../application/health_overview.dart';
import '../domain/daily_series.dart';
import '../domain/metric_explanations.dart';
import '../domain/health_types.dart';
import '../domain/outside_workouts.dart';
import '../health_format.dart';
import '../widgets/detail_layout.dart';
import '../widgets/health_card_frame.dart';
import '../widgets/metric_info_sheet.dart';
import '../widgets/outside_workout_ui.dart';

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
          onRetry: () => ref.read(healthOverviewProvider.notifier).refresh(),
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
    required this.onRetry,
  });

  final HealthOverview overview;
  final ActivityOverview activity;
  final int days;
  final VoidCallback onRetry;

  DateTime get _today => dayOf(overview.readAt);

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
    return DetailPanels(
      children: [
        _steps(context, range, first),
        _energy(context, range),
        _WorkoutsPanel(
          overview: overview,
          days: days,
          range: range,
          onRetry: onRetry,
        ),
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
    if (activity.stepsDaily.isEmpty && activity.stepsGap != null) {
      return DetailGapPanel(
        title: 'Steps',
        gap: activity.stepsGap!,
        metricName: 'steps',
        platform: overview.platform,
        onRetry: onRetry,
      );
    }
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
      info: metricInfoButton(
        context,
        MetricKey.steps,
        platform: overview.platform,
        usual: dailyAverageFrom(activity.stepsDaily, _today),
      ),
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
    if (activity.activeEnergyDaily.isEmpty && activity.energyGap != null) {
      return DetailGapPanel(
        title: 'Active calories',
        gap: activity.energyGap!,
        metricName: 'active calories',
        platform: overview.platform,
        onRetry: onRetry,
      );
    }
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
      info: metricInfoButton(
        context,
        MetricKey.activeCalories,
        platform: overview.platform,
        usual: dailyAverageFrom(activity.activeEnergyDaily, _today),
      ),
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

/// One workout in the Activity list: a BeyondRep session or an outside
/// workout that did not merge into one.
class _Entry {
  const _Entry({
    required this.start,
    required this.minutes,
    required this.title,
    required this.when,
    required this.route,
    required this.icon,
    this.merged,
    this.source,
  });

  final DateTime start;
  final int minutes;
  final String title;
  final String when;
  final String route;
  final IconData icon;

  /// `From Apple Watch · 131 kcal` under a BeyondRep session that absorbed
  /// outside workouts.
  final String? merged;

  /// The source tag of an outside workout.
  final String? source;
}

/// Workout minutes per day and a list: BeyondRep sessions plus outside
/// workouts that did not merge into one.
class _WorkoutsPanel extends ConsumerWidget {
  const _WorkoutsPanel({
    required this.overview,
    required this.days,
    required this.range,
    required this.onRetry,
  });

  final HealthOverview overview;
  final int days;
  final String range;
  final VoidCallback onRetry;

  static const _maxRows = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(completedWorkoutHistoryProvider);
    final merge = ref.watch(workoutMergeProvider);
    final gap = switch (overview.workouts) {
      SectionGap(:final gap) => gap,
      SectionData() => null,
    };
    final sessions = [
      for (final s in history.value?.sessions ?? const <WorkoutSessionRecord>[])
        if (s.status == WorkoutStatus.completed && s.completedAtUtc != null) s,
    ];
    final now = overview.readAt;
    final today = dayOf(now);
    final first = DateTime(today.year, today.month, today.day - (days - 1));
    final merged = merge?.mergedIntoSession ?? const {};
    final entries = <_Entry>[
      for (final s in sessions)
        if (!dayOf(s.startedAtUtc.toLocal()).isBefore(first))
          () {
            final minutes = s.completedAtUtc!
                .difference(s.startedAtUtc)
                .inMinutes;
            final summary = mergedSummary(merged[s.uuid] ?? const []);
            return _Entry(
              start: s.startedAtUtc,
              minutes: minutes,
              title: s.name,
              when: workoutWhen(s.startedAtUtc, minutes, now),
              route: '/progress/workouts/${s.uuid}',
              icon: Icons.fitness_center,
              merged: summary == null
                  ? null
                  : [
                      'From ${summary.source}',
                      if (summary.kcal != null) '${summary.kcal!.round()} kcal',
                    ].join(' · '),
            );
          }(),
      for (final w in merge?.standalone ?? const <OutsideWorkout>[])
        if (!dayOf(w.start.toLocal()).isBefore(first))
          _Entry(
            start: w.start,
            minutes: w.minutes,
            title: outsideWorkoutName(w.kind),
            when: [
              workoutWhen(w.start, w.minutes, now),
              if (w.activeKcal != null) '${w.activeKcal!.round()} kcal',
            ].join(' · '),
            route: '/progress/health-workouts/${w.id}',
            icon: outsideWorkoutIcon(w.kind),
            source: w.source,
          ),
    ]..sort((a, b) => b.start.compareTo(a.start));

    final list = [
      for (final e in entries.take(_maxRows))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: WorkoutRowCard(
            icon: e.icon,
            title: e.title,
            subtitle: [e.when, ?e.merged].join('\n'),
            source: e.source,
            onTap: () => context.push(e.route),
          ),
        ),
      if (entries.length > _maxRows)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.go('/progress'),
            child: const Text('See all in Progress'),
          ),
        ),
    ];

    if (gap != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailGapPanel(
            title: 'Workouts',
            gap: gap,
            metricName: 'Workouts',
            platform: overview.platform,
            onRetry: onRetry,
          ),
          ...list,
        ],
      );
    }

    final minutesByDay = <DateTime, int>{};
    for (final e in entries) {
      minutesByDay.update(
        dayOf(e.start.toLocal()),
        (v) => v + e.minutes,
        ifAbsent: () => e.minutes,
      );
    }
    final total = entries.fold(0, (a, e) => a + e.minutes);
    final caption =
        '${entries.length} '
        '${entries.length == 1 ? 'workout' : 'workouts'} · $total min';
    final color = Theme.of(context).colorScheme.primary;
    return DetailPanel(
      title: 'Workouts',
      trailing: range,
      info: metricInfoButton(
        context,
        MetricKey.otherAppWorkouts,
        platform: overview.platform,
      ),
      children: [
        if (merge == null)
          HealthCaption(
            history.hasError
                ? "Couldn't read your BeyondRep workouts."
                : 'Reading your workouts…',
          )
        else ...[
          NsBarChart(
            bars: [
              for (var i = 0; i < days; i++)
                () {
                  final day = DateTime(first.year, first.month, first.day + i);
                  final v = minutesByDay[day];
                  return NsBar(
                    highlight: i == days - 1,
                    segments: v == null
                        ? const []
                        : [(value: v.toDouble(), color: color)],
                  );
                }(),
            ],
            semanticsLabel: 'Workout minutes per day, $range. $caption.',
          ),
          const SizedBox(height: 6),
          HealthCaption(caption),
          ...list,
        ],
      ],
    );
  }
}
