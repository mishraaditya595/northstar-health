import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/northstar_theme.dart';
import '../../core/ids/uuid_factory.dart';
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
  bool _ignoreFieldChange = false;
  bool _editConflict = false;

  void _markDirty() {
    if (!_ignoreFieldChange && !_dirty && mounted) {
      setState(() => _dirty = true);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text('Changes to this plan have not been saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard changes'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop || _allowLeave || !mounted) return;
    if (await _confirmDiscard() && mounted) {
      setState(() => _allowLeave = true);
      context.pop();
    }
  }

  Future<void> _reloadLatest() async {
    if (!await _confirmDiscard() || !mounted) return;
    try {
      final latest = ref.read(workoutLibraryRepositoryProvider).getPlan(planUuid);
      if (!mounted) return;
      if (latest == null) {
        setState(() {
          _unavailable = true;
          _editConflict = false;
          _unavailable = true;
          pageError = 'This plan was archived or is unavailable.';
        });
        return;
      }
      _ignoreFieldChange = true;
      name.text = latest.name;
      description.text = latest.description;
      _ignoreFieldChange = false;
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
      _ignoreFieldChange = false;
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
    name.addListener(_markDirty);
    description.addListener(_markDirty);
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    final snapshot = await ref.read(trainLibraryProvider.future);
    if (!mounted) return;
    final definitions = snapshot.exercises
        .where((e) => e.archivedAtMs == null)
        .toList();
    var search = '';
    final selected = await showModalBottomSheet<ExerciseRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: StatefulBuilder(
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
                        TextField(
                          onChanged: (text) => setSheetState(
                            () => search = text.trim().toLowerCase(),
                          ),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search exercises',
                            border: OutlineInputBorder(),
                          ),
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
        ),
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
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => AlertDialog(
            title: const Text('Exercise targets'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: sets,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Sets (1–30)',
                      ),
                    ),
                    TextField(
                      controller: min,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minimum reps (optional)',
                      ),
                    ),
                    TextField(
                      controller: max,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Maximum reps (optional)',
                      ),
                    ),
                    TextField(
                      controller: rest,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rest seconds (optional)',
                      ),
                    ),
                    TextField(
                      controller: note,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Coaching notes (local only)',
                      ),
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
      sets.dispose();
      min.dispose();
      max.dispose();
      rest.dispose();
      note.dispose();
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
        pageError = 'This plan changed while you were editing. '
            'Reload the latest version before saving.';
      });
    } on ArgumentError {
      setState(
        () => pageError = 'Enter a plan name and valid exercise targets.',
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
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive this plan?'),
        content: const Text(
          'It will leave your plan list. '
          'Previously recorded workouts will not be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      final version = expectedUpdatedAtMs;
      if (version == null) throw StateError('Missing plan version');
      ref.read(workoutLibraryRepositoryProvider).archivePlan(
        planUuid, expectedUpdatedAtMs: version,
      );
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
    final definitions =
        ref.watch(trainLibraryProvider).asData?.value.exercises ??
        const <ExerciseRecord>[];
    final byId = {for (final d in definitions) d.uuid: d};
    final muted = Theme.of(context).extension<NorthstarColors>()!.muted;
    return PopScope(
      canPop: !_dirty || _allowLeave,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.planUuid == null ? 'New training plan' : 'Edit training plan',
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
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
              TextField(
                controller: name,
                maxLength: 100,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Plan name *',
                  hintText: 'e.g. Upper Body A',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                maxLength: 1000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
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
                    onPressed: _addExercise,
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
                                'Archived exercise',
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
