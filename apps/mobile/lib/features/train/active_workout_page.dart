import 'package:flutter/material.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../../core/design/section.dart';
import '../../core/design/northstar_theme.dart';
import '../../core/design/page_header.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/units/load_units.dart';
import '../workouts/domain/live_workout_engine.dart';
import '../workouts/domain/workout_models.dart';
import '../progress/workout_history_state.dart';
import '../workouts/domain/workout_repository.dart';
import 'previous_sets.dart';
import 'active_workout_state.dart';
import 'rest_timer_card.dart';
import 'train_library_state.dart';

class ActiveWorkoutPage extends ConsumerStatefulWidget {
  const ActiveWorkoutPage({super.key});

  @override
  ConsumerState<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends ConsumerState<ActiveWorkoutPage> {
  bool _busy = false;
  String? _error;

  Future<void> _perform(
    void Function(WorkoutActions actions) action, {
    bool leaveOnSuccess = false,
  }) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      action(ref.read(workoutActionsProvider));
      ref.invalidate(activeWorkoutProvider);
      if (leaveOnSuccess) {
        ref.invalidate(completedWorkoutHistoryProvider);
      }
      if (leaveOnSuccess && mounted) {
        context.go('/train');
      }
    } on WorkoutRevisionConflict {
      if (mounted) {
        setState(
          () => _error =
              'This workout changed elsewhere. Reload the latest saved '
              'workout and reconcile your edits.',
        );
      }
    } on ArgumentError {
      if (mounted) {
        setState(
          () => _error =
              'The set contains invalid values. Correct them and try again.',
        );
      }
    } on StateError {
      if (mounted) {
        setState(
          () => _error =
              'The workout or rest timer changed. Reload the saved state '
              'before trying again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not confirm the local save. Reload to verify whether '
              'the change was saved before retrying.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmEnd(WorkoutSessionRecord workout, bool discard) async {
    final yes = await showNsConfirm(
      context,
      title: discard ? 'Discard workout?' : 'Finish workout?',
      message: discard
          ? 'This session will not appear in your completed history.'
          : 'Only recorded sets count toward workout history.',
      cancelLabel: 'Keep training',
      confirmLabel: discard ? 'Discard workout' : 'Finish workout',
    );
    if (!yes || !mounted) {
      return;
    }
    await _perform(
      (a) => discard ? a.discard(workout) : a.finish(workout),
      leaveOnSuccess: true,
    );
  }

  Future<void> _removeSet(
    WorkoutSessionRecord workout,
    WorkoutSetRecord set,
  ) async {
    if (set.status == WorkoutSetStatus.completed) {
      final yes = await showNsConfirm(
        context,
        title: 'Remove this set?',
        message: 'This recorded set will be deleted from the workout.',
        cancelLabel: 'Keep set',
        confirmLabel: 'Remove set',
      );
      if (!yes || !mounted) {
        return;
      }
    }
    await _perform((a) => a.removeSet(workout, set));
  }

  Future<void> _chooseExercise(WorkoutSessionRecord workout) async {
    try {
      final snapshot = await ref.read(trainLibraryProvider.future);
      if (!mounted) {
        return;
      }
      final available = snapshot.exercises
          .where((exercise) => exercise.archivedAtMs == null)
          .toList();
      var search = '';
      final chosen = await showNsSheet<String>(
        context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, updateSheet) {
            final list = available
                .where(
                  (e) =>
                      e.name.toLowerCase().contains(search) ||
                      e.muscleGroup.toLowerCase().contains(search),
                )
                .toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: NsTextField(
                    prefixIcon: Icons.search,
                    label: 'Find a movement',
                    onChanged: (value) =>
                        updateSheet(() => search = value.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) => NsListCard(
                      icon: Icons.fitness_center,
                      title: list[index].name,
                      subtitle: list[index].muscleGroup,
                      onTap: () =>
                          Navigator.pop(sheetContext, list[index].uuid),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
      if (chosen == null || !mounted) {
        return;
      }
      final selected = available.singleWhere((e) => e.uuid == chosen);
      await _perform((a) => a.addExercise(workout, selected));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Exercise library is unavailable. Retry when it is ready.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeWorkoutProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const NsBackButton(),
        title: const Text('Workout in progress'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(activeWorkoutProvider),
            tooltip: 'Reload workout',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: active.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Could not recover your workout. '
                    'No local data was deleted.',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => ref.invalidate(activeWorkoutProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
            data: (current) => current == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No unfinished workout'),
                        TextButton(
                          onPressed: () => context.go('/train'),
                          child: const Text('Return to Train'),
                        ),
                      ],
                    ),
                  )
                : _workoutBody(current.session, current.checkpoint),
          ),
        ),
      ),
    );
  }

  Widget _workoutBody(
    WorkoutSessionRecord session,
    WorkoutRecoveryCheckpoint checkpoint,
  ) {
    final paused = session.status == WorkoutStatus.paused;
    final completed = session.sets
        .where((e) => e.status == WorkoutSetStatus.completed)
        .length;
    final byExercise = <String, List<WorkoutSetRecord>>{};
    for (final exercise in session.exercises) {
      byExercise[exercise.uuid] =
          session.sets.where((s) => s.exerciseUuid == exercise.uuid).toList()
            ..sort((a, b) => a.position.compareTo(b.position));
    }
    final restActive =
        checkpoint.restStatus == RestTimerStatus.running ||
        checkpoint.restStatus == RestTimerStatus.paused;
    final restTimer = RestTimerCard(
      key: ValueKey('${session.uuid}-${checkpoint.savedAtMs}'),
      checkpoint: checkpoint,
      runningWorkout: !paused,
      floating: true,
      onStart: (seconds) =>
          _perform((a) => a.startRest(session, checkpoint, seconds)),
      onClear: () => _perform((a) => a.clearRest(session, checkpoint)),
    );
    final list = ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        (restActive ? 104 : 40) + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Text(
          session.name,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
        ),
        const SizedBox(height: 6),
        Text(
          paused
              ? 'PAUSED · SAVED ON DEVICE'
              : 'RECORDING LOCALLY · NO CONNECTION NEEDED',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).extension<NorthstarColors>()!.muted,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text('$completed completed of ${session.sets.length} sets'),
        const SizedBox(height: 18),
        if (_error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _error = null);
                      ref.invalidate(activeWorkoutProvider);
                    },
                    child: const Text('Reload latest'),
                  ),
                ],
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _perform(
                        (a) => paused ? a.resume(session) : a.pause(session),
                      ),
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                label: Text(paused ? 'Resume' : 'Pause'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _confirmEnd(session, false),
                icon: const Icon(Icons.check),
                label: const Text('Finish'),
              ),
            ),
            IconButton(
              tooltip: 'Discard workout',
              onPressed: _busy ? null : () => _confirmEnd(session, true),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Same slot either way, so set rows keep their unsaved drafts when the
        // timer starts floating.
        restActive ? const SizedBox.shrink() : restTimer,
        const SizedBox(height: 16),
        for (final exercise in session.exercises) ...[
          _ExerciseCard(
            key: ValueKey(exercise.uuid),
            exercise: exercise,
            sets: byExercise[exercise.uuid]!,
            enabled: !_busy && !paused,
            onSave: (updated, rest) =>
                _perform((a) => a.saveSet(session, updated, restSeconds: rest)),
            onRemove: (set) => _removeSet(session, set),
            onAddSet: () => _perform((a) => a.addPlannedSet(session, exercise)),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _busy || paused ? null : () => _chooseExercise(session),
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Add exercise'),
        ),
        if (session.exercises.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text('Add an exercise to log your first set.'),
          ),
        const SizedBox(height: 16),
        const Text(
          'Saved sets survive app restarts. '
          'Cloud backup is not enabled in this phase.',
          textAlign: TextAlign.center,
        ),
      ],
    );
    return Stack(
      children: [
        list,
        if (restActive)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: restTimer,
          ),
      ],
    );
  }
}

/// One exercise: header, rest choice, a SET / PREVIOUS / load / reps table and
/// an Add set action.
class _ExerciseCard extends ConsumerStatefulWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.sets,
    required this.enabled,
    required this.onSave,
    required this.onRemove,
    required this.onAddSet,
    super.key,
  });

  final WorkoutExerciseRecord exercise;
  final List<WorkoutSetRecord> sets;
  final bool enabled;
  final void Function(WorkoutSetRecord set, int? restSeconds) onSave;
  final void Function(WorkoutSetRecord set) onRemove;
  final VoidCallback onAddSet;

  @override
  ConsumerState<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<_ExerciseCard> {
  int rest = 90;

  Future<void> _chooseRest() async {
    final chosen = await showNsSheet<int>(
      context,
      heightFactor: 0.5,
      builder: (sheetContext) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const SectionHeading('Rest after a recorded set'),
          for (final seconds in const [0, 60, 90, 120, 180])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NsListCard(
                icon: seconds == rest
                    ? Icons.check_circle
                    : Icons.timer_outlined,
                title: seconds == 0 ? 'No rest timer' : '$seconds seconds',
                subtitle: seconds == 0
                    ? 'Do not start a countdown'
                    : 'Starts when you record a new set',
                onTap: () => Navigator.pop(sheetContext, seconds),
              ),
            ),
        ],
      ),
    );
    if (chosen != null && mounted) setState(() => rest = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final previous = ref.watch(
      previousSetsProvider(widget.exercise.definitionUuid),
    );
    final done = widget.sets
        .where((e) => e.status == WorkoutSetStatus.completed)
        .length;
    final units = widget.sets.map((e) => e.inputUnit).toSet();
    final loadHeader = units.length > 1
        ? 'LOAD'
        : (units.firstOrNull == LoadUnit.lb ? 'LB' : 'KG');
    var working = 0;
    final numbers = <String, int>{};
    for (final set in widget.sets) {
      if (set.kind != WorkoutSetKind.warmup) working++;
      numbers[set.uuid] = working == 0 ? 1 : working;
    }
    TextStyle? head(BuildContext c) => theme.textTheme.labelSmall?.copyWith(
      color: muted,
      letterSpacing: 1,
      fontWeight: FontWeight.w800,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.exercise.nameSnapshot,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                NsTag('$done/${widget.sets.length}'),
              ],
            ),
            if (widget.exercise.equipmentSnapshot.isNotEmpty)
              Text(
                widget.exercise.equipmentSnapshot,
                style: TextStyle(color: muted),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                NsChip(
                  label: rest == 0 ? 'Rest: off' : 'Rest: ${rest}s',
                  selected: false,
                  onSelected: (_) => widget.enabled ? _chooseRest() : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.sets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: SetEditorTile.badgeWidth,
                      child: Center(child: Text('SET', style: head(context))),
                    ),
                    const SizedBox(width: SetEditorTile.gap),
                    Expanded(
                      child: Center(
                        child: Text('PREVIOUS', style: head(context)),
                      ),
                    ),
                    const SizedBox(width: SetEditorTile.gap),
                    SizedBox(
                      width: SetEditorTile.loadWidth,
                      child: Center(
                        child: Text(loadHeader, style: head(context)),
                      ),
                    ),
                    const SizedBox(width: SetEditorTile.gap),
                    SizedBox(
                      width: SetEditorTile.repsWidth,
                      child: Center(child: Text('REPS', style: head(context))),
                    ),
                    const SizedBox(width: SetEditorTile.gap),
                    SizedBox(
                      width: SetEditorTile.checkWidth,
                      child: Icon(Icons.check, size: 16, color: muted),
                    ),
                  ],
                ),
              ),
            for (var index = 0; index < widget.sets.length; index++)
              SetEditorTile(
                key: ValueKey(widget.sets[index].uuid),
                record: widget.sets[index],
                number: numbers[widget.sets[index].uuid]!,
                previous: index < previous.length ? previous[index] : null,
                enabled: widget.enabled,
                restSeconds: rest,
                onSave: widget.onSave,
                onRemove: () => widget.onRemove(widget.sets[index]),
              ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: widget.enabled ? widget.onAddSet : null,
              icon: const Icon(Icons.add),
              label: const Text('Add set'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One set as a table row: badge (tap for options), previous (tap to reuse),
/// load, reps and a check that records it.
class SetEditorTile extends StatefulWidget {
  const SetEditorTile({
    required this.record,
    required this.enabled,
    required this.onSave,
    this.onRemove,
    this.number,
    this.previous,
    this.restSeconds = 90,
    super.key,
  });

  static const badgeWidth = 44.0;
  static const loadWidth = 80.0;
  static const repsWidth = 68.0;
  static const checkWidth = 48.0;
  static const gap = 8.0;

  final WorkoutSetRecord record;
  final bool enabled;
  final void Function(WorkoutSetRecord set, int? restSeconds) onSave;

  /// Null hides the remove action.
  final VoidCallback? onRemove;

  /// Working-set number shown on the badge; defaults to position + 1.
  final int? number;

  /// Same-position set from the last completed session of this exercise.
  final WorkoutSetRecord? previous;

  /// Countdown started when a not-yet-recorded set is recorded. 0 = none.
  final int restSeconds;

  @override
  State<SetEditorTile> createState() => _SetEditorTileState();
}

class _SetEditorTileState extends State<SetEditorTile> {
  late final TextEditingController reps;
  late final TextEditingController weight;
  late final TextEditingController rpe;
  late LoadUnit unit;
  late WorkoutSetKind kind;
  String? error;

  @override
  void initState() {
    super.initState();
    final s = widget.record;
    unit = s.inputUnit == LoadUnit.unknown ? LoadUnit.kg : s.inputUnit;
    kind = s.kind == WorkoutSetKind.unknown ? WorkoutSetKind.working : s.kind;
    reps = TextEditingController(text: s.reps?.toString() ?? '');
    weight = TextEditingController(text: _savedWeightText(s.loadGrams, unit));
    rpe = TextEditingController(text: s.rpe?.toString() ?? '');
  }

  /// Keep unsaved drafts on unrelated session revisions; only refresh the
  /// editor when this set's committed values actually change.
  @override
  void didUpdateWidget(covariant SetEditorTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.record;
    final after = widget.record;
    if (before.reps == after.reps &&
        before.loadGrams == after.loadGrams &&
        before.rpe == after.rpe &&
        before.kind == after.kind &&
        before.status == after.status &&
        before.inputUnit == after.inputUnit &&
        before.completedAtUtc == after.completedAtUtc) {
      return;
    }
    unit = after.inputUnit == LoadUnit.unknown ? LoadUnit.kg : after.inputUnit;
    kind = after.kind == WorkoutSetKind.unknown
        ? WorkoutSetKind.working
        : after.kind;
    reps.text = after.reps?.toString() ?? '';
    weight.text = _savedWeightText(after.loadGrams, unit);
    rpe.text = after.rpe?.toString() ?? '';
    error = null;
  }

  static String _savedWeightText(int? grams, LoadUnit unit) {
    if (grams == null) return '';
    // Display the shortest readable value that re-encodes to the exact
    // persisted integer grams. For example, 102058 g becomes 225 lb,
    // not 224.99938 lb. Higher precision is used only when necessary.
    final load = LoadUnits.fromGrams(grams, unit);
    final limit = unit == LoadUnit.kg ? 3 : 5;
    var output = load.toStringAsFixed(limit);
    for (var digits = 1; digits <= limit; digits++) {
      final candidate = load.toStringAsFixed(digits);
      if (LoadUnits.toGrams(double.parse(candidate), unit) == grams) {
        output = candidate;
        break;
      }
    }
    // Keep at least one decimal place for familiar loads like 225.0 lb.
    while (output.contains('.') &&
        output.endsWith('0') &&
        output.split('.').last.length > 1) {
      output = output.substring(0, output.length - 1);
    }
    return output;
  }

  @override
  void dispose() {
    reps.dispose();
    weight.dispose();
    rpe.dispose();
    super.dispose();
  }

  void _record() {
    final count = int.tryParse(reps.text.trim());
    final load = weight.text.trim().isEmpty
        ? null
        : double.tryParse(weight.text.trim());
    final effort = rpe.text.trim().isEmpty
        ? null
        : double.tryParse(rpe.text.trim());
    if (count == null ||
        count < 0 ||
        (weight.text.trim().isNotEmpty && load == null) ||
        (rpe.text.trim().isNotEmpty && effort == null)) {
      setState(() => error = 'Enter valid reps, weight and RPE.');
      return;
    }
    try {
      final s = widget.record;
      final updated = WorkoutSetRecord(
        uuid: s.uuid,
        exerciseUuid: s.exerciseUuid,
        position: s.position,
        kind: kind,
        status: WorkoutSetStatus.completed,
        reps: count,
        loadGrams: load == null ? null : LoadUnits.toGrams(load, unit),
        inputUnit: unit,
        rpe: effort,
        completedAtUtc: s.completedAtUtc ?? DateTime.now().toUtc(),
      );
      updated.validate();
      widget.onSave(
        updated,
        s.status == WorkoutSetStatus.planned && widget.restSeconds > 0
            ? widget.restSeconds
            : null,
      );
    } catch (_) {
      setState(() => error = 'Check that the values are in the valid range.');
    }
  }

  String _previousText(WorkoutSetRecord p) {
    final count = p.reps?.toString() ?? '?';
    if (p.loadGrams == null) return '$count reps';
    final u = p.inputUnit == LoadUnit.lb ? 'lb' : 'kg';
    var load = _savedWeightText(p.loadGrams, p.inputUnit);
    if (load.endsWith('.0')) load = load.substring(0, load.length - 2);
    return '$load$u × $count';
  }

  void _usePrevious(WorkoutSetRecord p) {
    setState(() {
      unit = p.inputUnit == LoadUnit.unknown ? LoadUnit.kg : p.inputUnit;
      reps.text = p.reps?.toString() ?? '';
      weight.text = _savedWeightText(p.loadGrams, unit);
      error = null;
    });
  }

  Future<void> _options() async {
    final s = widget.record;
    await showNsSheet<void>(
      context,
      heightFactor: 0.7,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  SectionHeading('Set ${s.position + 1} options'),
                  NsDropdown<WorkoutSetKind>(
                    value: kind,
                    label: 'Set type',
                    onChanged: (value) {
                      setState(() => kind = value);
                      refresh(() {});
                    },
                    options: const [
                      NsOption(WorkoutSetKind.working, 'Working'),
                      NsOption(WorkoutSetKind.warmup, 'Warm-up'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  NsDropdown<LoadUnit>(
                    value: unit,
                    label: 'Load unit',
                    onChanged: (next) {
                      if (next == unit) return;
                      final entered = double.tryParse(weight.text.trim());
                      if (entered != null && entered >= 0 && entered.isFinite) {
                        final grams = LoadUnits.toGrams(entered, unit);
                        weight.text = _savedWeightText(grams, next);
                      }
                      setState(() => unit = next);
                      refresh(() {});
                    },
                    options: const [
                      NsOption(LoadUnit.kg, 'Kilograms (kg)'),
                      NsOption(LoadUnit.lb, 'Pounds (lb)'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  NsTextField(
                    key: ValueKey('rpe-${s.uuid}'),
                    controller: rpe,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    label: 'Effort (RPE, optional)',
                  ),
                  const SizedBox(height: 16),
                  if (s.status == WorkoutSetStatus.planned)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NsListCard(
                        icon: Icons.skip_next_outlined,
                        title: 'Skip set',
                        subtitle: 'Leave it out of this workout\'s totals',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          widget.onSave(skippedSet(s), null);
                        },
                      ),
                    ),
                  if (widget.onRemove != null)
                    NsListCard(
                      icon: Icons.delete_outline,
                      title: 'Remove set',
                      subtitle: 'Delete this set from the workout',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        widget.onRemove!();
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.record;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final done = s.status == WorkoutSetStatus.completed;
    final skipped = s.status == WorkoutSetStatus.skipped;
    final warm = kind == WorkoutSetKind.warmup;
    final number = widget.number ?? s.position + 1;
    final badgeColor = warm
        ? const Color(0xFFE5A92B)
        : theme.colorScheme.onSurface;
    final previous = widget.previous;
    final hintStyle = TextStyle(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: .6),
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: done
            ? (dark
                  ? NorthstarPalette.forestSoftDark
                  : NorthstarPalette.forestSoftLight)
            : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: SetEditorTile.badgeWidth,
                child: Tooltip(
                  message: 'Set ${s.position + 1} options',
                  child: Material(
                    color: theme.colorScheme.onSurface.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: widget.enabled ? _options : null,
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: Text(
                            warm ? 'W' : '$number',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: skipped
                                  ? theme.colorScheme.onSurfaceVariant
                                  : badgeColor,
                              decoration: skipped
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SetEditorTile.gap),
              Expanded(
                child: previous == null
                    ? Center(
                        child: Text(
                          skipped ? 'Skipped' : '—',
                          style: hintStyle,
                        ),
                      )
                    : Tooltip(
                        message: 'Use previous ${_previousText(previous)}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: widget.enabled
                              ? () => _usePrevious(previous)
                              : null,
                          child: SizedBox(
                            height: 48,
                            child: Center(
                              child: Text(
                                _previousText(previous),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: SetEditorTile.gap),
              SizedBox(
                width: SetEditorTile.loadWidth,
                child: NsTextField(
                  key: ValueKey('weight-${s.uuid}'),
                  controller: weight,
                  dense: true,
                  textAlign: TextAlign.center,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  hint: previous?.loadGrams == null
                      ? null
                      : _savedWeightText(previous!.loadGrams, unit),
                ),
              ),
              const SizedBox(width: SetEditorTile.gap),
              SizedBox(
                width: SetEditorTile.repsWidth,
                child: NsTextField(
                  key: ValueKey('reps-${s.uuid}'),
                  controller: reps,
                  dense: true,
                  textAlign: TextAlign.center,
                  enabled: widget.enabled,
                  keyboardType: TextInputType.number,
                  hint: previous?.reps?.toString(),
                ),
              ),
              const SizedBox(width: SetEditorTile.gap),
              SizedBox(
                width: SetEditorTile.checkWidth,
                child: NsCheckButton(
                  checked: done,
                  tooltip: done
                      ? 'Update set ${s.position + 1}'
                      : 'Save set ${s.position + 1}',
                  onPressed: widget.enabled ? _record : null,
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Text(
                error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
