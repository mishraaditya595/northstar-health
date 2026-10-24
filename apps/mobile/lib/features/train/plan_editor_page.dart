import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/inputs.dart';
import '../../core/design/northstar_theme.dart';
import '../../core/design/page_header.dart';
import '../../core/ids/uuid_factory.dart';
import '../../core/ui/dispose_after_dialog.dart';
import '../workouts/data/objectbox_workout_library_repository.dart';
import '../workouts/domain/workout_library_models.dart';
import 'train_library_state.dart';

class PlanEditorPage extends ConsumerStatefulWidget {
  const PlanEditorPage({this.planUuid, super.key});

  final String? planUuid;

  @override
  ConsumerState<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _PlanEditorPageState extends ConsumerState<PlanEditorPage> {
  final name = TextEditingController();
  final description = TextEditingController();
  final uuidFactory = SecureUuidFactory();
  final items = <PlanExerciseRecord>[];
  late final String planUuid;
  int? expectedUpdatedAtMs;
  String? pageError;
  bool saving = false;
  bool _unavailable = false;
  bool _dirty = false;
  bool _allowLeave = false;
  bool _editConflict = false;

  // onChanged is a text change, unlike a TextEditingController listener
  // which also fires on caret movement, focus and selection changes.
  void _markDirty(String _) {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return showNsConfirm(
      context,
      title: 'Discard unsaved changes?',
      message: 'Changes to this plan have not been saved.',
      cancelLabel: 'Keep editing',
      confirmLabel: 'Discard changes',
    );
  }

  Future<void> _requestExit() async {
    if (await _confirmDiscard() && mounted) {
      setState(() => _allowLeave = true);
      context.pop();
    }
  }

  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (!didPop && !_allowLeave && mounted) {
      await _requestExit(); // System back; AppBar back calls _requestExit itself.
    }
  }

  Future<void> _reloadLatest() async {
    if (!await _confirmDiscard() || !mounted) return;
    try {
      final latest = ref
          .read(workoutLibraryRepositoryProvider)
          .getPlan(planUuid);
      if (!mounted) return;
      if (latest == null) {
        setState(() {
          _unavailable = true;
          _editConflict = false;
          pageError = 'This plan was archived or is unavailable.';
        });
        return;
      }
      name.text = latest.name;
      description.text = latest.description;
      setState(() {
        items
          ..clear()
          ..addAll(latest.exercises);
        expectedUpdatedAtMs = latest.updatedAtMs;
        _unavailable = false;
        _dirty = false;
        _editConflict = false;
        pageError = null;
      });
    } catch (_) {
      if (mounted) setState(() => pageError = 'Could not reload the plan.');
    }
  }

  @override
  void initState() {
    super.initState();
    planUuid = widget.planUuid ?? uuidFactory.newId();
    try {
      final repository = ref.read(workoutLibraryRepositoryProvider);
      if (widget.planUuid != null) {
        final existing = repository.getPlan(planUuid);
        if (existing == null) {
          _unavailable = true;
          pageError = 'This plan was archived or is unavailable.';
        } else {
          expectedUpdatedAtMs = existing.updatedAtMs;
          name.text = existing.name;
          description.text = existing.description;
          items.addAll(existing.exercises);
        }
      }
    } catch (_) {
      _unavailable = true;
      pageError = 'Could not load this plan from local storage.';
    }
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    if (_unavailable) return;
    final WorkoutLibrarySnapshot snapshot;
    try {
      snapshot = await ref.read(trainLibraryProvider.future);
    } catch (_) {
      if (mounted) {
        setState(
          () => pageError =
              'Exercise library could not load. Retry adding an exercise.',
        );
      }
      return;
    }
    if (!mounted) return;
    final definitions = snapshot.exercises
        .where((e) => e.archivedAtMs == null)
        .toList();
    var search = '';
    final selected = await showNsSheet<ExerciseRecord>(
      context,
      heightFactor: 0.75,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visible = definitions
              .where(
                (e) =>
                    e.archivedAtMs == null &&
                    (search.isEmpty ||
                        e.name.toLowerCase().contains(search) ||
                        e.muscleGroup.toLowerCase().contains(search) ||
                        e.equipment.toLowerCase().contains(search)),
              )
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ADD EXERCISE',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    NsTextField(
                      onChanged: (text) => setSheetState(
                        () => search = text.trim().toLowerCase(),
                      ),
                      prefixIcon: Icons.search,
                      hint: 'Search exercises',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('No matching exercises.'))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (_, index) {
                          final e = visible[index];
                          return ListTile(
                            title: Text(e.name),
                            subtitle: Text(
                              [
                                e.muscleGroup,
                                e.equipment,
                              ].where((s) => s.isNotEmpty).join(' · '),
                            ),
                            trailing: const Icon(Icons.add_circle_outline),
                            onTap: () => Navigator.pop(sheetContext, e),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      items.add(
        PlanExerciseRecord(
          uuid: uuidFactory.newId(),
          exerciseUuid: selected.uuid,
          position: items.length,
          targetSets: 3,
          targetRepsMin: selected.inputMode == 'duration' ? null : 8,
          targetRepsMax: selected.inputMode == 'duration' ? null : 12,
          restSeconds: 90,
        ),
      );
      pageError = null;
      _dirty = true;
    });
  }

  Future<void> _editTargets(int index) async {
    final old = items[index];
    final sets = TextEditingController(text: old.targetSets.toString());
    final min = TextEditingController(
      text: old.targetRepsMin?.toString() ?? '',
    );
    final max = TextEditingController(
      text: old.targetRepsMax?.toString() ?? '',
    );
    final rest = TextEditingController(text: old.restSeconds?.toString() ?? '');
    final note = TextEditingController(text: old.notes);
    String? error;
    int? optional(String value) =>
        value.trim().isEmpty ? null : int.tryParse(value.trim()) ?? -1;
    try {
      await showNsDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => NsDialog(
            title: 'Exercise targets',
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NsTextField(
                      controller: sets,
                      keyboardType: TextInputType.number,
                      label: 'Sets (1–30)',
                    ),
                    const SizedBox(height: 10),
                    NsTextField(
                      controller: min,
                      keyboardType: TextInputType.number,
                      label: 'Minimum reps (optional)',
                    ),
                    const SizedBox(height: 10),
                    NsTextField(
                      controller: max,
                      keyboardType: TextInputType.number,
                      label: 'Maximum reps (optional)',
                    ),
                    const SizedBox(height: 10),
                    NsTextField(
                      controller: rest,
                      keyboardType: TextInputType.number,
                      label: 'Rest seconds (optional)',
                    ),
                    const SizedBox(height: 10),
                    NsTextField(
                      controller: note,
                      maxLength: 1000,
                      minLines: 3,
                      maxLines: 3,
                      label: 'Coaching notes (local only)',
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final candidate = PlanExerciseRecord(
                    uuid: old.uuid,
                    exerciseUuid: old.exerciseUuid,
                    position: old.position,
                    targetSets: int.tryParse(sets.text.trim()) ?? -1,
                    targetRepsMin: optional(min.text),
                    targetRepsMax: optional(max.text),
                    restSeconds: optional(rest.text),
                    notes: note.text,
                  );
                  try {
                    candidate.validate();
                    setState(() {
                      items[index] = candidate;
                      _dirty = true;
                    });
                    Navigator.pop(dialogContext);
                  } catch (_) {
                    updateDialog(
                      () => error = 'Check your sets, rep range and rest time.',
                    );
                  }
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      );
    } finally {
      disposeAfterDialog([sets, min, max, rest, note]);
    }
  }

  void _move(int from, int to) {
    if (to < 0 || to >= items.length) return;
    setState(() {
      final moved = items.removeAt(from);
      items.insert(to, moved);
      for (var i = 0; i < items.length; i++) {
        items[i] = items[i].withPosition(i);
      }
      _dirty = true;
    });
  }

  void _remove(int index) {
    setState(() {
      items.removeAt(index);
      for (var i = 0; i < items.length; i++) {
        items[i] = items[i].withPosition(i);
      }
      _dirty = true;
    });
  }

  void _save() {
    if (saving || _unavailable || _editConflict) return;
    setState(() {
      saving = true;
      pageError = null;
    });
    try {
      ref
          .read(workoutLibraryRepositoryProvider)
          .savePlan(
            uuid: planUuid,
            name: name.text,
            description: description.text,
            exercises: List.unmodifiable(items),
            expectedUpdatedAtMs: expectedUpdatedAtMs,
          );
      ref.invalidate(trainLibraryProvider);
      if (mounted) {
        _allowLeave = true;
        context.pop();
      }
    } on PlanEditConflict {
      setState(() {
        _editConflict = true;
        pageError =
            'This plan changed while you were editing. '
            'Reload the latest version before saving.';
      });
    } on ArgumentError {
      setState(
        () => pageError = 'Enter a plan name and valid exercise targets.',
      );
    } on ArchivedExercisePlanConflict {
      setState(
        () => pageError =
            'An exercise in this plan was archived. '
            'Remove newly added archived exercises, then try saving again.',
      );
    } catch (_) {
      setState(
        () => pageError =
            'Could not save your plan. Nothing was partially saved.',
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _archive() async {
    final yes = await showNsConfirm(
      context,
      title: 'Archive this plan?',
      message:
          'It will leave your plan list. '
          'Previously recorded workouts will not be removed.',
      confirmLabel: 'Archive',
    );
    if (!yes || !mounted) return;
    try {
      final version = expectedUpdatedAtMs;
      if (version == null) throw StateError('Missing plan version');
      ref
          .read(workoutLibraryRepositoryProvider)
          .archivePlan(planUuid, expectedUpdatedAtMs: version);
      ref.invalidate(trainLibraryProvider);
      if (mounted) {
        _allowLeave = true;
        context.pop();
      }
    } on PlanEditConflict {
      if (mounted) {
        setState(() {
          _editConflict = true;
          pageError = 'This plan changed. Reload it before archiving.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => pageError = 'Could not archive this plan.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(trainLibraryProvider);
    final definitions = libraryState.asData?.value.exercises;
    final byId = {
      for (final d in definitions ?? const <ExerciseRecord>[]) d.uuid: d,
    };
    final missingExerciseLabel = definitions == null
        ? (libraryState.isLoading
              ? 'Loading exercise…'
              : 'Exercise details unavailable')
        : 'Exercise unavailable';
    final muted = Theme.of(context).extension<NorthstarColors>()!.muted;
    return PopScope(
      canPop: !_dirty || _allowLeave,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          leading: NsBackButton(onPressed: _requestExit),
          title: Text(
            widget.planUuid == null
                ? 'New training plan'
                : 'Edit training plan',
          ),
          actions: [
            if (widget.planUuid != null)
              IconButton(
                onPressed: _unavailable ? null : _archive,
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'Archive plan',
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                40 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Text(
                  'PLAN THE WORK',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Saved on this device. You can edit it anytime.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 20),
                NsTextField(
                  controller: name,
                  onChanged: _markDirty,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  label: 'Plan name *',
                  hint: 'e.g. Upper Body A',
                ),
                const SizedBox(height: 12),
                NsTextField(
                  controller: description,
                  onChanged: _markDirty,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 2,
                  label: 'Description (optional)',
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'EXERCISES',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _unavailable ? null : _addExercise,
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(22),
                      child: Text(
                        'No exercises yet. Add a movement from your local catalog.',
                      ),
                    ),
                  ),
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              byId[items[i].exerciseUuid]?.name ??
                                  missingExerciseLabel,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${items[i].targetSets} sets'
                              '${formatPlanRepTarget(items[i])}'
                              '${items[i].restSeconds == null ? '' : ' · ${items[i].restSeconds}s rest'}',
                              style: TextStyle(color: muted),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  tooltip:
                                      'Move ${byId[items[i].exerciseUuid]?.name ?? 'exercise'} up',
                                  onPressed: i == 0
                                      ? null
                                      : () => _move(i, i - 1),
                                  icon: const Icon(Icons.arrow_upward),
                                ),
                                IconButton(
                                  tooltip:
                                      'Move ${byId[items[i].exerciseUuid]?.name ?? 'exercise'} down',
                                  onPressed: i == items.length - 1
                                      ? null
                                      : () => _move(i, i + 1),
                                  icon: const Icon(Icons.arrow_downward),
                                ),
                                TextButton.icon(
                                  onPressed: () => _editTargets(i),
                                  icon: const Icon(Icons.tune),
                                  label: const Text('Targets'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _remove(i),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Remove'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (pageError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      pageError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_editConflict && !_unavailable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      onPressed: _reloadLatest,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reload latest plan'),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: saving || _unavailable || _editConflict
                      ? null
                      : _save,
                  icon: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save plan offline'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Human-readable prescription: an upper-only bound must remain visible.
String formatPlanRepTarget(PlanExerciseRecord item) {
  if (item.targetRepsMin == null && item.targetRepsMax == null) return '';
  if (item.targetRepsMin == null) return ' · up to ${item.targetRepsMax} reps';
  if (item.targetRepsMax == null) return ' · ${item.targetRepsMin} reps';
  return ' · ${item.targetRepsMin}–${item.targetRepsMax} reps';
}
