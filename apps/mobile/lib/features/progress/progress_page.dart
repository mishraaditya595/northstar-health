import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/inputs.dart';
import '../../core/design/layout.dart';
import '../../core/design/beyondrep_theme.dart';
import '../../core/design/page_header.dart';
import '../../core/design/section.dart';
import '../../core/units/load_units.dart';

import '../../core/design/stats.dart';
import '../health/application/health_overview.dart';
import '../health/application/health_summary_controller.dart';
import '../health/application/workout_heart_rate.dart';
import '../health/domain/outside_workouts.dart';
import '../health/health_format.dart';
import '../health/widgets/health_card_frame.dart';
import '../health/widgets/outside_workout_ui.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import '../workouts/domain/workout_models.dart';
import 'domain/progress_overview.dart';
import 'muscle_map.dart';
import 'outside_workout_detail_page.dart';
import 'workout_history_detail_page.dart';
import 'domain/workout_history_models.dart';
import 'workout_history_state.dart';

class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage>
    with WidgetsBindingObserver {
  WorkoutHistoryPeriod _period = WorkoutHistoryPeriod.last30Days;
  String? _selectedExerciseKey;
  LoadUnit? _selectedLoadUnit;
  DateTime? _month;

  /// Wide windows: the history item open in the detail pane
  /// (`/progress/workouts/<uuid>` or `/progress/health-workouts/<id>`).
  String? _selectedRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The tab may stay mounted during days in background. Recalculate the
      // rolling period without discarding the cached ObjectBox history.
      ref.invalidate(progressNowProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(completedWorkoutHistoryProvider);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWideWindow(context) ? double.infinity : 920,
        ),
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            padding: EdgeInsets.all(20)
                .copyWith(bottom: 20 + MediaQuery.paddingOf(context).bottom),
            children: [
              const Text(
                'Could not load completed workouts. '
                'Your local workout records were not changed.',
              ),
              TextButton.icon(
                onPressed: () =>
                    ref.invalidate(completedWorkoutHistoryProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
          data: (data) => NsListDetail(
            list: _content(context, data),
            detail: _detail(data),
            emptyDetail: const Center(
              child: HealthCaption('Pick a workout to see its sets.'),
            ),
            selectedRoute: _selectedRoute,
            onCollapsed: _collapse,
          ),
        ),
      ),
    );
  }

  void _select(String route) => setState(() => _selectedRoute = route);

  /// The window narrowed with an item open: it becomes a pushed page.
  void _collapse(String route) {
    if (!mounted) return;
    setState(() => _selectedRoute = null);
    context.push(route);
  }

  /// The pane's page for [_selectedRoute], or null (clearing the selection)
  /// when that item is gone.
  Widget? _detail(WorkoutHistorySnapshot data) {
    final route = _selectedRoute;
    if (route == null) return null;
    final id = route.split('/').last;
    final Widget? page;
    if (route.startsWith('/progress/health-workouts/')) {
      final overview = ref.watch(healthOverviewProvider).value;
      var gone = false;
      if (overview != null &&
          overview.ownerId == ref.watch(healthOwnerIdProvider)) {
        final workouts = overview.workouts;
        gone =
            workouts is SectionData<WorkoutsOverview> &&
            !workouts.value.outside.any((w) => w.id == id);
      }
      page = gone
          ? null
          : OutsideWorkoutDetailPage(
              key: ValueKey(route),
              workoutId: id,
              embedded: true,
            );
    } else {
      page = data.sessions.any((s) => s.uuid == id)
          ? WorkoutHistoryDetailPage(
              key: ValueKey(route),
              sessionUuid: id,
              embedded: true,
            )
          : null;
    }
    if (page == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedRoute == route) {
          setState(() => _selectedRoute = null);
        }
      });
    }
    return page;
  }

  Widget _overview(
    BuildContext context,
    WorkoutHistorySnapshot data,
    LoadUnit unit,
  ) {
    final local = ref.watch(progressNowProvider).toLocal();
    final today = DateTime.utc(local.year, local.month, local.day);
    final week = weekOverview(data, today);
    final month = _month ?? DateTime.utc(today.year, today.month);
    final consistency = monthConsistency(data, today, month);
    final volume = week.volumeGramReps;
    final unitLabel = unit == LoadUnit.lb ? 'lb' : 'kg';
    NsTrend? trendOf(int? percent) => percent == null
        ? null
        : percent > 0
        ? NsTrend.up
        : percent < 0
        ? NsTrend.down
        : NsTrend.flat;
    final volumeTrend = trendOf(week.volumeChangePercent);
    final timeTrend = trendOf(week.timeChangePercent);
    final atCurrentMonth =
        month.year == today.year && month.month == today.month;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatTile(
                label: 'Volume',
                value: volume == null ? '—' : _volume(volume, unit),
                unit: volume == null ? null : unitLabel,
                trend: volumeTrend,
                trendLabel: volumeTrend == null
                    ? null
                    : '${week.volumeChangePercent!.abs()}%',
                caption: volume == null && week.sessions > 0
                    ? 'No loaded sets this week'
                    : 'This week',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Workout time',
                value: formatDurationShort(week.workoutTime),
                trend: timeTrend,
                trendLabel: timeTrend == null
                    ? null
                    : '${week.timeChangePercent!.abs()}%',
                caption: 'This week',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NsMonthCalendar(
                  month: month,
                  highlighted: consistency.trainedDays,
                  today: today,
                  onPrevious: () => setState(
                    () => _month = DateTime.utc(month.year, month.month - 1),
                  ),
                  onNext: atCurrentMonth
                      ? null
                      : () => setState(
                          () => _month = DateTime.utc(
                            month.year,
                            month.month + 1,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Fact(
                        '${consistency.totalSessions}',
                        'Total sessions',
                      ),
                    ),
                    Icon(
                      Icons.local_fire_department,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Fact(
                        consistency.weekStreak == 0
                            ? '—'
                            : '${consistency.weekStreak} wk',
                        'Week streak',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const MuscleRecoveryCard(),
      ],
    );
  }

  Widget _outsideRow(BuildContext context, OutsideWorkout w) {
    final start = w.start.toLocal();
    final km = w.distanceMeters;
    final kcal = w.activeKcal;
    return WorkoutRowCard(
      icon: outsideWorkoutIcon(w.kind),
      title: outsideWorkoutName(w.kind),
      subtitle: [
        formatHealthDate(start),
        formatClockTime(start),
        '${w.minutes} min',
        if (km != null) '${(km / 1000).toStringAsFixed(1)} km',
        if (kcal != null) '${kcal.round()} kcal',
      ].join(' · '),
      source: w.source,
      onTap: () => openListItem(
        context,
        route: '/progress/health-workouts/${w.id}',
        select: () => _select('/progress/health-workouts/${w.id}'),
      ),
    );
  }

  /// BeyondRep session cards with outside workouts between them by start,
  /// newest first; the sessions keep their own order.
  List<Widget> _trainingList(
    BuildContext context,
    List<WorkoutSessionRecord> sessions,
    List<OutsideWorkout> outside,
    Map<String, List<OutsideWorkout>> merged,
    LoadUnit unit,
  ) {
    final rows = <Widget>[];
    var next = 0;
    void addOutsideBefore(DateTime? startUtc) {
      while (next < outside.length &&
          (startUtc == null || outside[next].start.isAfter(startUtc))) {
        rows
          ..add(_outsideRow(context, outside[next++]))
          ..add(const SizedBox(height: 12));
      }
    }

    for (final session in sessions) {
      addOutsideBefore(session.startedAtUtc);
      rows
        ..add(
          _SessionSummaryCard(
            session: session,
            unit: unit,
            syncFlag: ref.watch(workoutSyncFlagsProvider)[session.uuid],
            merged: merged[session.uuid] ?? const [],
            onOpen: () => openListItem(
              context,
              route: '/progress/workouts/${session.uuid}',
              select: () => _select('/progress/workouts/${session.uuid}'),
            ),
          ),
        )
        ..add(const SizedBox(height: 12));
    }
    addOutsideBefore(null);
    return rows;
  }

  Widget _content(BuildContext context, WorkoutHistorySnapshot data) {
    final sessions = workoutsInPeriod(
      data,
      _period,
      ref.watch(progressNowProvider),
    );
    final summary = calculateWorkoutHistory(sessions);
    final trends = summary.exerciseTrends;
    final selected = trends.isEmpty
        ? null
        : trends.firstWhere(
            (t) => t.key == _selectedExerciseKey,
            orElse: () => trends.first,
          );
    // Workouts from other apps show only when the overview for this account
    // holds them; otherwise the page is exactly what it was without health.
    final overview = ref.watch(healthOverviewProvider).value;
    final merge = ref.watch(workoutMergeProvider);
    final showOutside =
        overview != null &&
        overview.ownerId == ref.watch(healthOwnerIdProvider) &&
        overview.workouts is SectionData &&
        merge != null;
    final nowUtc = ref.watch(progressNowProvider);
    final outside = [
      if (showOutside)
        for (final w in merge.standalone)
          if (_outsideInPeriod(w, _period, nowUtc)) w,
    ];
    List<Widget> outsideRows() => [
      for (final w in outside) ...[
        _outsideRow(context, w),
        const SizedBox(height: 12),
      ],
      if (_period == WorkoutHistoryPeriod.all && outside.isNotEmpty)
        Text(
          'Workouts from other apps go back 90 days.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ];
    final theme = Theme.of(context);
    final displayUnit =
        _selectedLoadUnit ??
        (selected != null && selected.points.last.inputUnit == LoadUnit.lb
            ? LoadUnit.lb
            : LoadUnit.kg);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        44 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        PageHeader(
          title: 'Progress',
          eyebrow: 'REVIEW CHANGE OVER TIME',
          actions: [
            SquareButton(
              tooltip: 'Refresh completed workouts',
              onPressed: () => ref.invalidate(completedWorkoutHistoryProvider),
              child: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _overview(context, data, displayUnit),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final (period, title) in [
              (WorkoutHistoryPeriod.last30Days, '30 days'),
              (WorkoutHistoryPeriod.last90Days, '90 days'),
              (WorkoutHistoryPeriod.all, 'All time'),
            ])
              NsChip(
                selected: _period == period,
                label: title,
                onSelected: (_) => setState(() => _period = period),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (data.sessions.isEmpty) ...[
          const _EmptyProgress(
            title: 'Nothing logged yet',
            message:
                'Finish your first workout in Train to see real '
                'history, strength and consistency here.',
          ),
          if (outside.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionHeading('From other apps'),
            ...outsideRows(),
          ],
        ] else if (sessions.isEmpty) ...[
          const _EmptyProgress(
            title: 'No sessions in this period',
            message:
                'Try 90 days or All time to find older completed workouts.',
          ),
          if (outside.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionHeading('From other apps'),
            ...outsideRows(),
          ],
        ] else ...[
          LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 560;
              final cards = [
                _SummaryCard(
                  'COMPLETED',
                  '${summary.completedWorkouts}',
                  'workouts',
                  Icons.check_circle_outline,
                ),
                _SummaryCard(
                  'WORKING SETS',
                  '${summary.completedWorkingSets}',
                  'recorded',
                  Icons.fitness_center,
                ),
                _SummaryCard(
                  'LOADED VOLUME',
                  summary.loadedWorkingSets == 0
                      ? '—'
                      : _volume(summary.loadedVolumeGramReps, displayUnit),
                  summary.loadedWorkingSets == 0
                      ? 'No loaded sets'
                      : '${displayUnit == LoadUnit.lb ? 'lb' : 'kg'} × reps',
                  Icons.insights_outlined,
                ),
              ];
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final card in cards)
                    SizedBox(
                      width: wide
                          ? (box.maxWidth - 20) / 3
                          : (box.maxWidth - 10) / 2,
                      child: card,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (summary.unloadedWorkingSets > 0)
            Text(
              '${summary.unloadedWorkingSets} working sets had no logged '
              'weight and are excluded from loaded volume.',
              style: theme.textTheme.bodySmall,
            ),
          if (summary.zeroLoadWorkingSets > 0)
            Text(
              '${summary.zeroLoadWorkingSets} working sets recorded with '
              '0 kg are excluded from loaded volume and strength trends.',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 28),
          const SectionHeading('Strength trend'),
          if (selected == null)
            const _EmptyProgress(
              title: 'No loaded working sets yet',
              message:
                  'Record a completed working set with weight '
                  'to see exercise-level load history.',
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NsDropdown<String>(
                      key: ValueKey(selected.key),
                      value: selected.key,
                      label: 'Exercise',
                      options: [
                        for (final trend in trends)
                          NsOption(trend.key, trend.name),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedExerciseKey = value),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Best logged load · ${_mass(selected.bestLoadGrams, displayUnit)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final unit in [LoadUnit.kg, LoadUnit.lb])
                          NsChip(
                            label: unit == LoadUnit.kg ? 'kg' : 'lb',
                            selected: displayUnit == unit,
                            onSelected: (_) =>
                                setState(() => _selectedLoadUnit = unit),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _RecentLoadBars(trend: selected, unit: displayUnit),
                    const SizedBox(height: 8),
                    const Text(
                      'Top working-set weight per workout · actual logs, '
                      'not an estimated 1-rep maximum',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 28),
          SectionHeading(
            'Training summary',
            action: '${sessions.length} finished',
          ),
          ..._trainingList(
            context,
            sessions,
            outside,
            merge?.mergedIntoSession ?? const {},
            displayUnit,
          ),
          if (_period == WorkoutHistoryPeriod.all && outside.isNotEmpty)
            Text(
              'Workouts from other apps go back 90 days.',
              style: theme.textTheme.bodySmall,
            ),
        ],
        const SizedBox(height: 18),
        Text(
          showOutside
              ? 'Only finished BeyondRep workouts count towards your totals '
                    'and back up to your account. Workouts from other apps '
                    'are read from ${healthPlatformName(overview.platform)} '
                    'for the last 90 days, never saved, and shown here for '
                    'reference.'
              : 'Only finished BeyondRep workouts appear here. '
                    'Paused, discarded and imported health workouts are '
                    'excluded. Finished workouts back up to your account '
                    'when you are online.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

bool _outsideInPeriod(
  OutsideWorkout w,
  WorkoutHistoryPeriod period,
  DateTime nowUtc,
) {
  final days = switch (period) {
    WorkoutHistoryPeriod.last30Days => 30,
    WorkoutHistoryPeriod.last90Days => 90,
    WorkoutHistoryPeriod.all => null,
  };
  return days == null ||
      !w.start.isBefore(nowUtc.toUtc().subtract(Duration(days: days)));
}

/// User-facing values are rounded for readability. Integer grams remain the
/// canonical source of truth; never round and re-store displayed values.
String _decimalLoad(int grams, LoadUnit unit) => formatLoadAmount(grams, unit);

String _volume(int gramReps, LoadUnit unit) => _decimalLoad(gramReps, unit);

String _mass(int grams, LoadUnit unit) =>
    '${_decimalLoad(grams, unit)} ${unit == LoadUnit.lb ? 'lb' : 'kg'}';

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.heading, this.value, this.note, this.icon);
  final String heading;
  final String value;
  final String note;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 27,
            height: 27,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? BeyondRepPalette.forestSoftDark
                  : BeyondRepPalette.forestSoftLight,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 15,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(heading, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Text(note, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.mutedColor),
        ),
      ],
    );
  }
}

/// One finished workout: name, date, four facts and a View details action.
class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({
    required this.session,
    required this.unit,
    required this.onOpen,
    this.syncFlag,
    this.merged = const [],
  });

  final WorkoutSessionRecord session;

  /// Workouts from other apps that merged into this session.
  final List<OutsideWorkout> merged;
  final LoadUnit unit;
  final VoidCallback onOpen;
  final WorkoutSyncFlag? syncFlag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = calculateWorkoutHistory([session]);
    final duration = session.completedAtUtc!.difference(session.startedAtUtc);
    final volume = summary.loadedWorkingSets == 0
        ? '—'
        : '${_volume(summary.loadedVolumeGramReps, unit)} '
              '${unit == LoadUnit.lb ? 'lb' : 'kg'}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wrap, not Row: the tag moves under the name at large text.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    session.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (syncFlag != null) NsTag(syncFlag!.label, warning: true),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                formatWorkoutDay(originalLocalDay(session)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.mutedColor,
                ),
              ),
              if (merged.isNotEmpty) _MergedLine(session, merged),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _Fact(
                      formatDurationClock(
                        duration.isNegative ? Duration.zero : duration,
                      ),
                      'Duration',
                    ),
                  ),
                  Expanded(
                    child: _Fact('${session.exercises.length}', 'Exercises'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Fact(
                      '${countWorkingSets(session)}',
                      'Working sets',
                    ),
                  ),
                  Expanded(child: _Fact(volume, 'Volume')),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpen,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('View details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `From Apple Watch · 131 kcal · avg 112 bpm` under a session that absorbed
/// outside workouts; each part is left out when unknown. The average comes
/// from heart rate samples inside the session's own window.
class _MergedLine extends ConsumerWidget {
  const _MergedLine(this.session, this.merged);

  final WorkoutSessionRecord session;
  final List<OutsideWorkout> merged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = mergedSummary(merged);
    if (summary == null) return const SizedBox.shrink();
    final hr = ref
        .watch(
          workoutAverageHrProvider((
            start: session.startedAtUtc,
            end: session.completedAtUtc!,
          )),
        )
        .value;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        [
          'From ${summary.source}',
          if (summary.kcal != null) '${summary.kcal!.round()} kcal',
          if (hr != null) 'avg ${hr.round()} bpm',
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.mutedColor),
      ),
    );
  }
}

class _EmptyProgress extends StatelessWidget {
  const _EmptyProgress({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.stacked_line_chart),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message),
        ],
      ),
    ),
  );
}

/// Simple low-GPU bar chart with grounded labels; accessible as text too.
class _RecentLoadBars extends StatelessWidget {
  const _RecentLoadBars({required this.trend, required this.unit});
  final ExerciseStrengthTrend trend;
  final LoadUnit unit;

  @override
  Widget build(BuildContext context) {
    final points = trend.points.length <= 8
        ? trend.points
        : trend.points.sublist(trend.points.length - 8);
    final max = trend.bestLoadGrams;
    return Semantics(
      label:
          'Recent best working-set loads for ${trend.name}: '
          '${points.map((p) => '${formatWorkoutDay(p.originalLocalDay)}: '
              '${_mass(p.grams, unit)} for ${p.reps} reps').join('; ')}',
      child: SizedBox(
        height: 192,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visible = points.length > 4 ? 4 : points.length;
            final barWidth = (constraints.maxWidth / visible).clamp(
              78.0,
              155.0,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final point in points)
                    SizedBox(
                      width: barWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Tooltip(
                          message:
                              '${formatWorkoutDay(point.originalLocalDay)} · '
                              '${_mass(point.grams, unit)} × ${point.reps} reps',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                _mass(point.grams, unit),
                                maxLines: 1,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                height:
                                    68 *
                                    (max == 0 ? 0.05 : point.grams / max).clamp(
                                      0.05,
                                      1.0,
                                    ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${point.originalLocalDay.day.toString().padLeft(2, '0')}/'
                                '${point.originalLocalDay.month.toString().padLeft(2, '0')}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              Text(
                                '${point.reps} reps',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
