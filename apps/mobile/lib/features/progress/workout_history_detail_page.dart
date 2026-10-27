import 'package:flutter/material.dart';

import '../../core/design/page_header.dart';
import '../../core/design/dialogs.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/stats.dart';
import '../../core/design/section.dart';
import '../../core/design/northstar_theme.dart';
import 'domain/progress_overview.dart';
import '../../core/units/load_units.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import '../sync/workout_upload_coordinator.dart';
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
      appBar: AppBar(
        leading: const NsBackButton(),
        title: const Text('Workout details'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load local workout history.'),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(completedWorkoutHistoryProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (history) {
              WorkoutSessionRecord? chosen;
              for (final session in history.sessions) {
                if (session.uuid == sessionUuid) {
                  chosen = session;
                  break;
                }
              }
              if (chosen == null) {
                return const Center(
                  child: Text('This completed workout is unavailable.'),
                );
              }
              return _detail(
                context,
                chosen,
                ref.watch(workoutSyncFlagsProvider)[chosen.uuid],
                ref,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _detail(
    BuildContext context,
    WorkoutSessionRecord session,
    WorkoutSyncFlag? syncFlag,
    WidgetRef ref,
  ) {
    final finished = session.completedAtUtc!;
    final day = originalLocalDay(session);
    final sets = session.sets
        .where((s) => s.status == WorkoutSetStatus.completed)
        .toList();
    final theme = Theme.of(context);
    final summary = calculateWorkoutHistory([session]);
    final duration = finished.difference(session.startedAtUtc);
    final started = session.startedAtUtc.toUtc().add(
      Duration(minutes: session.originalOffsetMinutes),
    );
    final lb = sets.any(
      (s) => s.loadGrams != null && s.inputUnit == LoadUnit.lb,
    );
    final unit = lb ? LoadUnit.lb : LoadUnit.kg;
    final volume = summary.loadedWorkingSets == 0
        ? null
        : formatLoadAmount(summary.loadedVolumeGramReps, unit);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        42 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NsTag(
              'started at '
              '${started.hour.toString().padLeft(2, '0')}:'
              '${started.minute.toString().padLeft(2, '0')}',
            ),
            if (syncFlag != null) NsTag(syncFlag.label, warning: true),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          formatDurationShort(duration.isNegative ? Duration.zero : duration),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          session.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${formatWorkoutDay(day)} · FINISHED LOCALLY',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.mutedColor),
        ),
        const SizedBox(height: 2),
        Text(
          _friendlyFinish(finished, session.originalOffsetMinutes),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.mutedColor),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatTile(
                label: 'Volume',
                value: volume ?? '—',
                unit: volume == null ? null : (lb ? 'lb' : 'kg'),
                caption: volume == null ? 'No loaded sets' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(label: 'Sets', value: '${sets.length}'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Exercises',
                value: '${session.exercises.length}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SectionHeading(
          '${session.exercises.length} '
          '${session.exercises.length == 1 ? 'exercise' : 'exercises'}',
        ),
        if (session.exercises.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No exercises were recorded in this session.'),
            ),
          ),
        for (final exercise in session.exercises) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.nameSnapshot,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (exercise.equipmentSnapshot.isNotEmpty)
                    Text(
                      exercise.equipmentSnapshot,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.mutedColor,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text('SET', style: _head(theme)),
                      ),
                      Expanded(child: Text('PERFORMANCE', style: _head(theme))),
                      Text('TYPE', style: _head(theme)),
                    ],
                  ),
                  const Divider(height: 14),
                  for (final set in session.sets.where(
                    (set) => set.exerciseUuid == exercise.uuid,
                  )) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              set.kind == WorkoutSetKind.warmup
                                  ? 'W'
                                  : '${set.position + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: set.kind == WorkoutSetKind.warmup
                                    ? const Color(0xFFE5A92B)
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Expanded(child: Text(_label(set))),
                          Text(
                            set.kind == WorkoutSetKind.warmup
                                ? 'Warm-up'
                                : set.kind == WorkoutSetKind.working
                                ? 'Working'
                                : 'Unknown',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const InsightCard(
          icon: Icons.info_outline,
          text: TextSpan(
            text:
                'Historical snapshots are read-only. '
                'Edits to the original exercise catalog or training plan '
                'cannot rewrite a completed workout.',
          ),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: () => _confirmDelete(context, ref, session),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete workout'),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WorkoutSessionRecord session,
  ) async {
    final confirmed = await showNsConfirm(
      context,
      title: 'Delete completed workout?',
      message:
          'This removes the workout from this device and queues a cloud '
          'deletion for your other devices. If backup is paused or there is '
          'a conflict, remote deletion waits for sync recovery. '
          'This cannot be undone.',
      confirmLabel: 'Delete workout',
    );
    if (!confirmed || !context.mounted) return;
    try {
      ref.read(workoutOutboxProvider).deleteCompletedWorkout(
        sessionUuid: session.uuid,
        expectedLocalRevision: session.revision,
      );
      ref.invalidate(completedWorkoutHistoryProvider);
      ref.invalidate(workoutSyncFlagsProvider);
      ref.read(workoutUploadCoordinatorProvider).kick();
      if (context.mounted) {
        showNsMessage(context, 'Workout removed locally. Cloud deletion queued.');
        Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (context.mounted) {
        showNsMessage(
          context,
          'Could not delete this workout. Your workout was not changed.',
        );
      }
    }
  }

  TextStyle? _head(ThemeData theme) => theme.textTheme.labelSmall?.copyWith(
    color: theme.mutedColor,
    letterSpacing: 1,
    fontWeight: FontWeight.w800,
  );

  String _friendlyFinish(DateTime finished, int offsetMinutes) {
    final local = finished.toUtc().add(Duration(minutes: offsetMinutes));
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final hours = offsetMinutes.abs() ~/ 60;
    final minutes = offsetMinutes.abs() % 60;
    final offset =
        '${offsetMinutes >= 0 ? '+' : '-'}'
        '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
    return 'Finished at $time (UTC$offset)';
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
      grams,
      unit == LoadUnit.unknown ? LoadUnit.kg : unit,
    );
    final decimals = unit == LoadUnit.lb ? 5 : 3;
    for (var n = 1; n <= decimals; n++) {
      final text = amount.toStringAsFixed(n);
      if (LoadUnits.toGrams(
            double.parse(text),
            unit == LoadUnit.unknown ? LoadUnit.kg : unit,
          ) ==
          grams) {
        return text;
      }
    }
    return amount.toStringAsFixed(decimals);
  }
}
