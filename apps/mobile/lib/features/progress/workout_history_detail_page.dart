import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/units/load_units.dart';
import '../workouts/domain/workout_models.dart';
import 'domain/workout_history_models.dart';
import 'workout_history_state.dart';

class WorkoutHistoryDetailPage extends ConsumerWidget {
  const WorkoutHistoryDetailPage({required this.sessionUuid, super.key});
  final String sessionUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(completedWorkoutHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Workout details')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                const Text('Could not load local workout history.'),
                TextButton(
                  onPressed: () => ref.invalidate(completedWorkoutHistoryProvider),
                  child: const Text('Retry'),
                ),
              ],
            )),
            data: (history) {
              WorkoutSessionRecord? chosen;
              for (final session in history.sessions) {
                if (session.uuid == sessionUuid) {
                  chosen = session;
                  break;
                }
              }
              if (chosen == null) {
                return const Center(child: Text(
                  'This completed workout is unavailable.',
                ));
              }
              return _detail(context, chosen);
            },
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, WorkoutSessionRecord session) {
    final finished = session.completedAtUtc!;
    final day = originalLocalDay(session);
    final sets = session.sets.where((s) =>
        s.status == WorkoutSetStatus.completed).toList();
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 42),
      children: [
        Text(session.name,
          style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text('${day.day}/${day.month}/${day.year} · FINISHED LOCALLY'),
        const SizedBox(height: 8),
        Text('${sets.length} recorded sets · '
            '${session.exercises.length} exercises'),
        const SizedBox(height: 6),
        Text('Session ended at ${finished.toUtc().toIso8601String()} UTC',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        if (session.exercises.isEmpty)
          const Card(child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('No exercises were recorded in this session.'),
          )),
        for (final exercise in session.exercises) ...[
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.nameSnapshot,
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800)),
                if (exercise.equipmentSnapshot.isNotEmpty)
                  Text(exercise.equipmentSnapshot,
                      style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                for (final set in session.sets.where(
                    (set) => set.exerciseUuid == exercise.uuid)) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      SizedBox(width: 58, child: Text('Set ${set.position + 1}')),
                      Expanded(child: Text(_label(set))),
                      Text(set.kind == WorkoutSetKind.warmup
                          ? 'Warm-up' : set.kind == WorkoutSetKind.working
                              ? 'Working' : 'Unknown'),
                    ]),
                  ),
                  const Divider(height: 10),
                ],
              ],
            ),
          )),
          const SizedBox(height: 10),
        ],
        const Text('Historical snapshots are read-only. '
            'Edits to the original exercise catalog or training plan '
            'cannot rewrite a completed workout.'),
      ],
    );
  }

  String _label(WorkoutSetRecord set) {
    if (set.status == WorkoutSetStatus.planned) {
      return 'Not recorded';
    }
    if (set.status == WorkoutSetStatus.skipped) {
      return 'Skipped';
    }
    if (set.status != WorkoutSetStatus.completed) {
      return 'Unsupported set status';
    }
    final load = set.loadGrams == null
        ? 'bodyweight / no logged load'
        : '${_load(set.loadGrams!, set.inputUnit)} '
            '${set.inputUnit == LoadUnit.lb ? 'lb' : 'kg'}';
    final effort = set.rpe == null ? '' : ' · RPE ${set.rpe}';
    return '${set.reps ?? '?'} reps × $load$effort';
  }

  String _load(int grams, LoadUnit unit) {
    final amount = LoadUnits.fromGrams(
        grams, unit == LoadUnit.unknown ? LoadUnit.kg : unit);
    final decimals = unit == LoadUnit.lb ? 5 : 3;
    for (var n = 1; n <= decimals; n++) {
      final text = amount.toStringAsFixed(n);
      if (LoadUnits.toGrams(double.parse(text),
              unit == LoadUnit.unknown ? LoadUnit.kg : unit) == grams) {
        return text;
      }
    }
    return amount.toStringAsFixed(decimals);
  }
}
