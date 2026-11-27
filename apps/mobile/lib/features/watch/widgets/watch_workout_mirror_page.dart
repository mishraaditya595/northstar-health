import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock.dart';
import '../../../core/design/beyondrep_theme.dart';
import '../../../core/design/dialogs.dart';
import '../../../core/design/layout.dart';
import '../../../core/design/page_header.dart';
import '../../../core/design/status_line.dart';
import '../../../core/units/load_units.dart';
import '../../train/active_workout_page.dart' show SetEditorTile;
import '../../train/active_workout_state.dart' show activeWorkoutProvider;
import '../../workouts/domain/workout_models.dart';
import '../application/live_watch_workout.dart';
import '../domain/live_watch_workout.dart';

/// Follows and controls a workout that runs on the Apple Watch. The watch owns
/// it: every change here is a command, shown as "Saving…" until the watch
/// lists it as applied. Nothing on this page is stored on the phone.
class WatchWorkoutMirrorPage extends ConsumerStatefulWidget {
  const WatchWorkoutMirrorPage({super.key});

  @override
  ConsumerState<WatchWorkoutMirrorPage> createState() =>
      _WatchWorkoutMirrorPageState();
}

class _WatchWorkoutMirrorPageState
    extends ConsumerState<WatchWorkoutMirrorPage> {
  late DateTime _now = ref.read(wallClockProvider)().toUtc();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // A plain once-a-second redraw of the clock text; nothing animates.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = ref.read(wallClockProvider)().toUtc());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  LiveWatchWorkoutController get _live =>
      ref.read(liveWatchWorkoutProvider.notifier);

  void _onEnded(LiveWatchEnd end) {
    _live.acknowledgeEnd();
    showNsMessage(
      context,
      end.completed
          ? 'Saved on your Apple Watch'
          : 'Workout discarded on your Apple Watch',
    );
    context.go('/train');
  }

  Future<void> _confirmFinish() async {
    final yes = await showNsConfirm(
      context,
      title: 'Finish workout?',
      message: 'Only recorded sets count toward workout history.',
      cancelLabel: 'Keep training',
      confirmLabel: 'Finish workout',
    );
    if (yes && mounted) _live.finish();
  }

  Future<void> _confirmDiscard() async {
    final yes = await showNsConfirm(
      context,
      title: 'Discard workout?',
      message: 'This session will not appear in your completed history.',
      cancelLabel: 'Keep training',
      confirmLabel: 'Discard workout',
    );
    if (yes && mounted) _live.discard();
  }

  /// Maps what the shared set row saved to a command. A set type change (a
  /// warm-up toggle) is not sent: the watch owns the plan.
  void _save(WorkoutSetRecord updated) {
    switch (updated.status) {
      case WorkoutSetStatus.completed:
        _live.logSet(
          updated.uuid,
          reps: updated.reps,
          durationSeconds: updated.durationSeconds,
          loadGrams: updated.loadGrams,
          rpe: updated.rpe,
          inputUnit: updated.inputUnit == LoadUnit.lb ? 'lb' : 'kg',
        );
      case WorkoutSetStatus.skipped:
        _live.skipSet(updated.uuid);
      case WorkoutSetStatus.planned:
      case WorkoutSetStatus.unknown:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveWatchWorkoutProvider.select((s) => s.ended), (_, ended) {
      if (ended != null) _onEnded(ended);
    });
    final state = ref.watch(liveWatchWorkoutProvider);
    final workout = state.workout;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const NsBackButton(),
        title: const Text('Apple Watch workout'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: workout == null
              ? _Empty(onBack: () => context.go('/train'))
              : _body(state, workout),
        ),
      ),
    );
  }

  Widget _body(LiveWatchState state, LiveWatchWorkout workout) {
    final enabled = state.isLive && !workout.isPaused;
    final phoneWorkout = ref.watch(activeWorkoutProvider).value;
    final top = <Widget>[
      _Header(workout: workout, now: _now, stale: state.stale),
      if (phoneWorkout != null) ...[
        const SizedBox(height: 12),
        NsListCard(
          icon: Icons.phone_iphone,
          title: 'A workout is also in progress on this phone',
          subtitle: phoneWorkout.session.name,
          onTap: () => context.push('/train/workout'),
        ),
      ],
      const SizedBox(height: 12),
      _Controls(
        workout: workout,
        live: state.isLive,
        onPauseResume: () => workout.isPaused ? _live.resume() : _live.pause(),
        onFinish: _confirmFinish,
        onDiscard: _confirmDiscard,
      ),
      _Rest(
        workout: workout,
        now: _now,
        live: state.isLive,
        onStart: () => _live.startRest(90),
        onSkip: _live.clearRest,
      ),
      _CommandNotes(
        commands: [
          for (final c in state.commands)
            if (c.setId == null) c,
        ],
        onRetry: _live.retry,
        onDismiss: _live.dismiss,
      ),
    ];
    var working = 0;
    final exercises = <Widget>[
      for (final exercise in workout.exercises) ...[
        _ExerciseCard(
          exercise: exercise,
          workout: workout,
          state: state,
          enabled: enabled,
          firstWorkingNumber: working + 1,
          onSave: _save,
          onAddSet: () => _live.addSet(exercise.exerciseId),
          onRetry: _live.retry,
          onDismiss: _live.dismiss,
        ),
        const SizedBox(height: 12),
      ],
    ];
    for (final exercise in workout.exercises) {
      working += exercise.sets.where((s) => !s.isWarmup).length;
    }
    final padding = EdgeInsets.fromLTRB(
      16,
      16,
      16,
      32 + MediaQuery.paddingOf(context).bottom,
    );
    if (isWideWindow(context)) {
      return ListView(
        padding: padding,
        children: [
          NsSplitColumns(mainFlex: 3, sideFlex: 2, main: exercises, side: top),
        ],
      );
    }
    return ListView(
      padding: padding,
      children: [...top, const SizedBox(height: 16), ...exercises],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'No workout is running on your Apple Watch.',
          textAlign: TextAlign.center,
        ),
        TextButton(onPressed: onBack, child: const Text('Return to Train')),
      ],
    ),
  );
}

String _clock(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

class _Header extends StatelessWidget {
  const _Header({
    required this.workout,
    required this.now,
    required this.stale,
  });

  final LiveWatchWorkout workout;
  final DateTime now;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              workout.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const NsTag('Apple Watch'),
            if (workout.isPaused) const NsTag('Paused'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'ELAPSED ${_clock(workout.elapsed(now))}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.mutedColor,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (stale) ...[
          const SizedBox(height: 8),
          const NsTag('Apple Watch out of reach', warning: true),
          const NsStatusLine('Showing the last update. Changes are off.'),
        ],
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.workout,
    required this.live,
    required this.onPauseResume,
    required this.onFinish,
    required this.onDiscard,
  });

  final LiveWatchWorkout workout;
  final bool live;
  final VoidCallback onPauseResume;
  final VoidCallback onFinish;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton.icon(
        onPressed: live ? onPauseResume : null,
        icon: Icon(workout.isPaused ? Icons.play_arrow : Icons.pause),
        label: Text(workout.isPaused ? 'Resume' : 'Pause'),
      ),
      FilledButton.icon(
        onPressed: live ? onFinish : null,
        icon: const Icon(Icons.check),
        label: const Text('Finish'),
      ),
      IconButton(
        tooltip: 'Discard workout',
        onPressed: live ? onDiscard : null,
        icon: const Icon(Icons.delete_outline),
      ),
    ],
  );
}

class _Rest extends StatelessWidget {
  const _Rest({
    required this.workout,
    required this.now,
    required this.live,
    required this.onStart,
    required this.onSkip,
  });

  final LiveWatchWorkout workout;
  final DateTime now;
  final bool live;
  final VoidCallback onStart;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final remaining = workout.restRemaining(now);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                remaining == null
                    ? 'No rest running'
                    : 'Rest ${_clock(remaining)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (remaining != null)
                TextButton(
                  onPressed: live ? onSkip : null,
                  child: const Text('Skip rest'),
                )
              else
                TextButton(
                  onPressed: live && !workout.isPaused ? onStart : null,
                  child: const Text('Start 90 s rest'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _reasonText(String? reason) => switch (reason) {
  'unknown_session' => 'That workout is no longer running on your watch.',
  'unknown_set' => 'That set is not in the workout on your watch.',
  'invalid_values' => 'Your watch did not accept those values.',
  _ => 'Your watch cannot do that right now.',
};

/// Saving, not saved and refused notes for commands that are not about one set.
class _CommandNotes extends StatelessWidget {
  const _CommandNotes({
    required this.commands,
    required this.onRetry,
    required this.onDismiss,
  });

  final List<LiveCommand> commands;
  final void Function(String id) onRetry;
  final void Function(String id) onDismiss;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final c in commands) _CommandNote(c, onRetry, onDismiss)],
  );
}

class _CommandNote extends StatelessWidget {
  const _CommandNote(this.command, this.onRetry, this.onDismiss);

  final LiveCommand command;
  final void Function(String id) onRetry;
  final void Function(String id) onDismiss;

  @override
  Widget build(BuildContext context) {
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    switch (command.phase) {
      case LiveCommandPhase.pending:
        return const NsStatusLine('Saving…');
      case LiveCommandPhase.failed:
        return Row(
          children: [
            Expanded(child: Text('Not saved on your watch', style: error)),
            TextButton(
              onPressed: () => onRetry(command.id),
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () => onDismiss(command.id),
              child: const Text('Dismiss'),
            ),
          ],
        );
      case LiveCommandPhase.rejected:
        return Row(
          children: [
            Expanded(child: Text(_reasonText(command.reason), style: error)),
            TextButton(
              onPressed: () => onDismiss(command.id),
              child: const Text('Dismiss'),
            ),
          ],
        );
    }
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.workout,
    required this.state,
    required this.enabled,
    required this.firstWorkingNumber,
    required this.onSave,
    required this.onAddSet,
    required this.onRetry,
    required this.onDismiss,
  });

  final LiveExercise exercise;
  final LiveWatchWorkout workout;
  final LiveWatchState state;
  final bool enabled;
  final int firstWorkingNumber;
  final void Function(WorkoutSetRecord updated) onSave;
  final VoidCallback onAddSet;
  final void Function(String id) onRetry;
  final void Function(String id) onDismiss;

  WorkoutSetRecord _record(LiveSet s) => WorkoutSetRecord(
    uuid: s.setId,
    exerciseUuid: exercise.exerciseId,
    position: s.position,
    kind: s.isWarmup ? WorkoutSetKind.warmup : WorkoutSetKind.working,
    status: s.isCompleted
        ? WorkoutSetStatus.completed
        : s.isSkipped
        ? WorkoutSetStatus.skipped
        : WorkoutSetStatus.planned,
    reps: s.reps,
    durationSeconds: s.durationSeconds,
    loadGrams: s.loadGrams,
    inputUnit: s.inputUnit == 'lb' ? LoadUnit.lb : LoadUnit.kg,
    rpe: s.rpe?.toDouble(),
    completedAtUtc: s.isCompleted ? DateTime.utc(1970) : null,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = exercise.sets.where((s) => s.isCompleted).length;
    var working = firstWorkingNumber - 1;
    final numbers = <String, int>{};
    for (final s in exercise.sets) {
      if (!s.isWarmup) numbers[s.setId] = ++working;
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exercise.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                NsTag('$done/${exercise.sets.length}'),
              ],
            ),
            const SizedBox(height: 10),
            for (final set in exercise.sets) ...[
              _SetRow(
                key: ValueKey('live-set-${set.setId}'),
                current: set.setId == workout.currentSetId,
                child: SetEditorTile(
                  key: ValueKey(set.setId),
                  record: _record(set),
                  number: numbers[set.setId],
                  enabled: enabled,
                  timed: exercise.isTimed,
                  restSeconds: 0,
                  onSave: (updated, _) => onSave(updated),
                ),
              ),
              for (final c in state.commandsForSet(set.setId))
                _CommandNote(c, onRetry, onDismiss),
            ],
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: enabled ? onAddSet : null,
              icon: const Icon(Icons.add),
              label: const Text('Add set'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marks the set the watch is on: a border and a label for screen readers.
class _SetRow extends StatelessWidget {
  const _SetRow({required this.current, required this.child, super.key});

  final bool current;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!current) return child;
    return Semantics(
      label: 'Current set on your Apple Watch',
      child: DecoratedBox(
        key: const ValueKey('live-current-set'),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: child,
      ),
    );
  }
}
