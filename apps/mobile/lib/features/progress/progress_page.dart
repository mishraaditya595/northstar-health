import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../workouts/domain/workout_models.dart';
import 'domain/workout_history_models.dart';
import 'workout_history_state.dart';

enum _HistoryPeriod { last30Days, last90Days, all }

class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  _HistoryPeriod _period = _HistoryPeriod.last30Days;
  String? _selectedExerciseKey;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(completedWorkoutHistoryProvider);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Could not load completed workouts. '
                  'Your local workout records were not changed.'),
              TextButton.icon(
                onPressed: () => ref.invalidate(completedWorkoutHistoryProvider),
                icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
          data: (data) => _content(context, data),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, WorkoutHistorySnapshot data) {
    final now = DateTime.now().toUtc();
    final cutOff = switch (_period) {
      _HistoryPeriod.last30Days => now.subtract(const Duration(days: 30)),
      _HistoryPeriod.last90Days => now.subtract(const Duration(days: 90)),
      _HistoryPeriod.all => null,
    };
    final sessions = data.sessions.where((s) =>
        s.status == WorkoutStatus.completed &&
        s.completedAtUtc != null &&
        (cutOff == null || !s.completedAtUtc!.isBefore(cutOff))).toList();
    final summary = calculateWorkoutHistory(sessions);
    final trends = summary.exerciseTrends;
    final selected = trends.isEmpty ? null : trends.firstWhere(
      (t) => t.key == _selectedExerciseKey,
      orElse: () => trends.first,
    );
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 44),
      children: [
        Row(children: [
          Expanded(child: Text('PROGRESS',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w900, letterSpacing: -1.1))),
          IconButton(
            tooltip: 'Refresh completed workouts',
            onPressed: () => ref.invalidate(completedWorkoutHistoryProvider),
            icon: const Icon(Icons.refresh),
          ),
        ]),
        const SizedBox(height: 6),
        Text('YOUR REAL TRAINING · SAVED ON THIS DEVICE',
          style: theme.textTheme.labelSmall),
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final (period, title) in [
            (_HistoryPeriod.last30Days, '30 days'),
            (_HistoryPeriod.last90Days, '90 days'),
            (_HistoryPeriod.all, 'All time'),
          ])
            ChoiceChip(
              selected: _period == period,
              label: Text(title),
              onSelected: (_) => setState(() => _period = period),
            ),
        ]),
        const SizedBox(height: 24),
        if (data.sessions.isEmpty) ...[
          const _EmptyProgress(
            title: 'Nothing logged yet',
            message: 'Finish your first workout in Train to see real '
                'history, strength and consistency here.',
          ),
        ] else if (sessions.isEmpty) ...[
          const _EmptyProgress(
            title: 'No sessions in this period',
            message: 'Try 90 days or All time to find older completed workouts.',
          ),
        ] else ...[
          LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 560;
            final cards = [
              _SummaryCard('COMPLETED', '${summary.completedWorkouts}',
                  'workouts', Icons.check_circle_outline),
              _SummaryCard('WORKING SETS', '${summary.completedWorkingSets}',
                  'recorded', Icons.fitness_center),
              _SummaryCard('LOADED VOLUME',
                  _kilogramReps(summary.loadedVolumeGramReps),
                  'kg × reps', Icons.insights_outlined),
            ];
            return Wrap(
              spacing: 10, runSpacing: 10,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: wide ? (box.maxWidth - 20) / 3
                        : (box.maxWidth - 10) / 2,
                    child: card,
                  ),
              ],
            );
          }),
          const SizedBox(height: 12),
          if (summary.unloadedWorkingSets > 0)
            Text(
              '${summary.unloadedWorkingSets} working sets had no logged '
              'weight and are excluded from loaded volume.',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 28),
          Text('STRENGTH TREND',
            style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (selected == null)
            const _EmptyProgress(
              title: 'No loaded working sets yet',
              message: 'Record a completed working set with weight '
                  'to see exercise-level load history.',
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(selected.key),
                      initialValue: selected.key,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Exercise',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final trend in trends)
                          DropdownMenuItem(
                            value: trend.key, child: Text(trend.name)),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedExerciseKey = value),
                    ),
                    const SizedBox(height: 16),
                    Text('Best logged load · ${_kg(selected.bestLoadGrams)} kg',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    _RecentLoadBars(trend: selected),
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
          Row(children: [
            Expanded(child: Text('WORKOUT HISTORY',
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800))),
            Text('${sessions.length} finished',
                style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 10),
          for (final session in sessions) ...[
            Card(
              child: ListTile(
                minVerticalPadding: 12,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(session.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${_date(originalLocalDay(session))} · '
                  '${countWorkingSets(session)} working sets · '
                  '${session.exercises.length} exercises',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/progress/workouts/${session.uuid}'),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
        const SizedBox(height: 18),
        Text(
          'Only finished NorthStar workouts appear here. '
          'Paused, discarded and imported health workouts are excluded. '
          'Cloud backup is not available in Phase 1.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

String _kg(int grams) {
  var value = (grams / 1000).toStringAsFixed(3);
  while (value.contains('.') && value.endsWith('0')) {
    value = value.substring(0, value.length - 1);
  }
  if (value.endsWith('.')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

String _kilogramReps(int gramReps) => _kg(gramReps);
String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon),
        const SizedBox(height: 14),
        Text(heading, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900)),
        ),
        Text(note, style: Theme.of(context).textTheme.labelSmall),
      ]),
    ),
  );
}

class _EmptyProgress extends StatelessWidget {
  const _EmptyProgress({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.stacked_line_chart),
        const SizedBox(height: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(message),
      ]),
    ),
  );
}

/// Simple low-GPU bar chart with grounded labels; accessible as text too.
class _RecentLoadBars extends StatelessWidget {
  const _RecentLoadBars({required this.trend});
  final ExerciseStrengthTrend trend;

  @override
  Widget build(BuildContext context) {
    final points = trend.points.length <= 8
        ? trend.points : trend.points.sublist(trend.points.length - 8);
    final max = trend.bestLoadGrams;
    return Semantics(
      label: 'Recent best working-set loads for ${trend.name}: '
        '${points.map((p) => '${_kg(p.grams)} kilograms').join(', ')}',
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final point in points)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Tooltip(
                    message: '${_kg(point.grams)} kg × ${point.reps} reps',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(_kg(point.grams),
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          height: 96 * (max == 0 ? 0.05 :
                              point.grams / max).clamp(0.05, 1.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
