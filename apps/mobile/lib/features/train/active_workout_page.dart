import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/units/load_units.dart';
import '../workouts/domain/live_workout_engine.dart';
import '../workouts/domain/workout_models.dart';
import '../workouts/domain/workout_repository.dart';
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

  Future<void> _perform(void Function(WorkoutActions actions) action, {
    bool leaveOnSuccess = false,
  }) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      action(ref.read(workoutActionsProvider));
      ref.invalidate(activeWorkoutProvider);
      if (leaveOnSuccess && mounted) context.go('/train');
    } on WorkoutRevisionConflict {
      if (mounted) {
        setState(() => _error =
            'This workout changed. Reload before retrying. '
            'Your unsaved input remains on screen.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'The local write did not complete. Review the values and retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEnd(WorkoutSessionRecord workout, bool discard) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(discard ? 'Discard workout?' : 'Finish workout?'),
        content: Text(discard
            ? 'This session will not appear in your completed history.'
            : 'Only recorded sets count toward workout history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep training')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(discard ? 'Discard workout' : 'Finish workout')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _perform((a) => discard ? a.discard(workout) : a.finish(workout),
        leaveOnSuccess: true);
  }

  Future<void> _chooseExercise(WorkoutSessionRecord workout) async {
    try {
      final snapshot = await ref.read(trainLibraryProvider.future);
      if (!mounted) return;
      final available = snapshot.exercises
          .where((exercise) => exercise.archivedAtMs == null).toList();
      var search = '';
      final chosen = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.78,
            child: StatefulBuilder(builder: (context, updateSheet) {
              final list = available.where((e) =>
                  e.name.toLowerCase().contains(search) ||
                  e.muscleGroup.toLowerCase().contains(search)).toList();
              return Column(children: [
                Padding(padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Find a movement',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => updateSheet(
                        () => search = value.trim().toLowerCase()),
                  )),
                Expanded(child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, index) => ListTile(
                    title: Text(list[index].name),
                    subtitle: Text(list[index].muscleGroup),
                    onTap: () => Navigator.pop(sheetContext, list[index].uuid),
                  ),
                )),
              ]);
            }),
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      final selected = available.singleWhere((e) => e.uuid == chosen);
      await _perform((a) => a.addExercise(workout, selected));
    } catch (_) {
      if (mounted) setState(() => _error =
          'Exercise library is unavailable. Retry when it is ready.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeWorkoutProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Workout in progress'),
        actions: [
          IconButton(onPressed: () => ref.invalidate(activeWorkoutProvider),
            tooltip: 'Reload workout', icon: const Icon(Icons.refresh)),
        ]),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: active.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Column(mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Padding(padding: EdgeInsets.all(24),
                child: Text('Could not recover your workout. '
                    'No local data was deleted.')),
              TextButton.icon(
                onPressed: () => ref.invalidate(activeWorkoutProvider),
                icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ]),
          data: (current) => current == null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('No unfinished workout'),
                  TextButton(onPressed: () => context.go('/train'),
                    child: const Text('Return to Train')),
                ]))
              : _workoutBody(current.session, current.checkpoint),
        ),
      )),
    );
  }

  Widget _workoutBody(
    WorkoutSessionRecord session, WorkoutRecoveryCheckpoint checkpoint) {
    final paused = session.status == WorkoutStatus.paused;
    final completed = session.sets
        .where((e) => e.status == WorkoutSetStatus.completed).length;
    final byExercise = <String, List<WorkoutSetRecord>>{};
    for (final exercise in session.exercises) {
      byExercise[exercise.uuid] = session.sets
          .where((s) => s.exerciseUuid == exercise.uuid).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(session.name, style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(paused ? 'PAUSED · SAVED ON DEVICE'
            : 'RECORDING LOCALLY · NO CONNECTION NEEDED',
          style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Text('$completed completed of ${session.sets.length} sets · '
            'revision ${session.revision}'),
        const SizedBox(height: 18),
        if (_error != null) Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_error!, style: TextStyle(color: Theme.of(context)
                .colorScheme.error)),
            TextButton(
              onPressed: () {
                setState(() => _error = null);
                ref.invalidate(activeWorkoutProvider);
              },
              child: const Text('Reload latest'),
            ),
          ]),
        )),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _perform(
                (a) => paused ? a.resume(session) : a.pause(session)),
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            label: Text(paused ? 'Resume' : 'Pause'),
          )),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(
            onPressed: _busy ? null : () => _confirmEnd(session, false),
            icon: const Icon(Icons.check),
            label: const Text('Finish'),
          )),
          IconButton(
            tooltip: 'Discard workout',
            onPressed: _busy ? null : () => _confirmEnd(session, true),
            icon: const Icon(Icons.delete_outline),
          ),
        ]),
        const SizedBox(height: 12),
        if (checkpoint != null) RestTimerCard(
          key: ValueKey('${session.uuid}-${checkpoint.savedAtMs}'),
          checkpoint: checkpoint,
          runningWorkout: !paused,
          onStart: (seconds) => _perform(
            (a) => a.startRest(session, checkpoint, seconds)),
          onClear: () => _perform((a) => a.clearRest(session, checkpoint)),
        ),
        const SizedBox(height: 16),
        for (final exercise in session.exercises) ...[
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exercise.nameSnapshot,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
              if (exercise.equipmentSnapshot.isNotEmpty)
                Text(exercise.equipmentSnapshot),
              const SizedBox(height: 12),
              for (final set in byExercise[exercise.uuid]!)
                SetEditorTile(
                  key: ValueKey('${set.uuid}-${session.revision}'),
                  record: set,
                  enabled: !_busy && !paused,
                  onSave: (updated, rest) => _perform(
                    (a) => a.saveSet(session, updated, restSeconds: rest)),
                ),
              Align(alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy || paused ? null : () => _perform(
                    (a) => a.addPlannedSet(session, exercise)),
                  icon: const Icon(Icons.add), label: const Text('Add set'),
                )),
            ]),
          )),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _busy || paused ? null : () => _chooseExercise(session),
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Add exercise'),
        ),
        if (session.exercises.isEmpty)
          const Padding(padding: EdgeInsets.all(18),
            child: Text('Add an exercise to log your first set.')),
        const SizedBox(height: 16),
        const Text('Saved sets survive app restarts. '
            'Cloud backup is not enabled in this phase.',
          textAlign: TextAlign.center),
      ],
    );
  }
}

class SetEditorTile extends StatefulWidget {
  const SetEditorTile({
    required this.record,
    required this.enabled,
    required this.onSave,
    super.key,
  });

  final WorkoutSetRecord record;
  final bool enabled;
  final void Function(WorkoutSetRecord set, int? restSeconds) onSave;

  @override
  State<SetEditorTile> createState() => _SetEditorTileState();
}

class _SetEditorTileState extends State<SetEditorTile> {
  late final TextEditingController reps;
  late final TextEditingController weight;
  late final TextEditingController rpe;
  late LoadUnit unit;
  int rest = 90;
  String? error;

  @override
  void initState() {
    super.initState();
    final s = widget.record;
    unit = s.inputUnit == LoadUnit.unknown ? LoadUnit.kg : s.inputUnit;
    reps = TextEditingController(text: s.reps?.toString() ?? '');
    weight = TextEditingController(
      text: s.loadGrams == null ? '' :
          LoadUnits.fromGrams(s.loadGrams!, unit).toStringAsFixed(1),
    );
    rpe = TextEditingController(text: s.rpe?.toString() ?? '');
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
        ? null : double.tryParse(weight.text.trim());
    final effort = rpe.text.trim().isEmpty ? null
        : double.tryParse(rpe.text.trim());
    if (count == null || count < 0 ||
        (weight.text.trim().isNotEmpty && load == null) ||
        (rpe.text.trim().isNotEmpty && effort == null)) {
      setState(() => error = 'Enter valid reps, weight and RPE.');
      return;
    }
    try {
      final s = widget.record;
      final updated = WorkoutSetRecord(
        uuid: s.uuid, exerciseUuid: s.exerciseUuid,
        position: s.position, kind: s.kind,
        status: WorkoutSetStatus.completed, reps: count,
        loadGrams: load == null ? null : LoadUnits.toGrams(load, unit),
        inputUnit: unit, rpe: effort,
        completedAtUtc: s.completedAtUtc ?? DateTime.now().toUtc(),
      );
      updated.validate();
      widget.onSave(updated, rest > 0 ? rest : null);
    } catch (_) {
      setState(() => error = 'Check that the values are in the valid range.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.record;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SET ${s.position + 1} · ${s.status.name.toUpperCase()}',
          style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 82, child: TextField(
              key: ValueKey('reps-${s.uuid}'),
              controller: reps, enabled: widget.enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reps',
                border: OutlineInputBorder()))),
            SizedBox(width: 108, child: TextField(
              key: ValueKey('weight-${s.uuid}'),
              controller: weight, enabled: widget.enabled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight',
                border: OutlineInputBorder()))),
            DropdownButton<LoadUnit>(
              value: unit,
              onChanged: widget.enabled ? (next) {
                if (next == null || next == unit) return;
                final entered = double.tryParse(weight.text.trim());
                if (entered != null && entered >= 0 && entered.isFinite) {
                  final grams = LoadUnits.toGrams(entered, unit);
                  weight.text = LoadUnits.fromGrams(grams, next)
                      .toStringAsFixed(next == LoadUnit.kg ? 2 : 1);
                }
                setState(() => unit = next);
              } : null,
              items: const [
                DropdownMenuItem(value: LoadUnit.kg, child: Text('kg')),
                DropdownMenuItem(value: LoadUnit.lb, child: Text('lb')),
              ],
            ),
            SizedBox(width: 82, child: TextField(
              key: ValueKey('rpe-${s.uuid}'),
              controller: rpe, enabled: widget.enabled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'RPE',
                border: OutlineInputBorder()))),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<int>(
              value: rest,
              onChanged: widget.enabled ? (v) {
                if (v != null) setState(() => rest = v);
              } : null,
              items: const [
                DropdownMenuItem(value: 0, child: Text('No rest')),
                DropdownMenuItem(value: 60, child: Text('Rest 60s')),
                DropdownMenuItem(value: 90, child: Text('Rest 90s')),
                DropdownMenuItem(value: 120, child: Text('Rest 120s')),
              ],
            ),
            FilledButton(
              onPressed: widget.enabled ? _record : null,
              child: Text(s.status == WorkoutSetStatus.completed
                  ? 'Update set' : 'Save set')),
            TextButton(
              onPressed: !widget.enabled ? null : () =>
                  widget.onSave(skippedSet(s), null),
              child: const Text('Skip'),
            ),
          ]),
        if (error != null) Text(error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
    );
  }
}
