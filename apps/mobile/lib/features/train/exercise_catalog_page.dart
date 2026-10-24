import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/northstar_theme.dart';
import '../../core/ids/uuid_factory.dart';
import '../../core/ui/dispose_after_dialog.dart';
import '../workouts/data/objectbox_workout_library_repository.dart';
import '../workouts/domain/workout_library_models.dart';
import 'train_library_state.dart';

class ExerciseCatalogPage extends ConsumerStatefulWidget {
  const ExerciseCatalogPage({super.key});

  @override
  ConsumerState<ExerciseCatalogPage> createState() =>
      _ExerciseCatalogPageState();
}

class _ExerciseCatalogPageState extends ConsumerState<ExerciseCatalogPage> {
  String query = '';
  bool customOnly = false;

  Future<void> _edit(ExerciseRecord? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final muscle = TextEditingController(text: existing?.muscleGroup ?? '');
    final equipment = TextEditingController(text: existing?.equipment ?? '');
    String? error;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'New exercise' : 'Edit exercise'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      autofocus: true,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Exercise name *',
                      ),
                    ),
                    TextField(
                      controller: muscle,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Muscle group',
                      ),
                    ),
                    TextField(
                      controller: equipment,
                      maxLength: 60,
                      decoration: const InputDecoration(labelText: 'Equipment'),
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
                  try {
                    ref
                        .read(workoutLibraryRepositoryProvider)
                        .saveCustomExercise(
                          uuid: existing?.uuid ?? SecureUuidFactory().newId(),
                          name: name.text,
                          muscleGroup: muscle.text,
                          equipment: equipment.text,
                          expectedUpdatedAtMs: existing?.updatedAtMs,
                        );
                    ref.invalidate(trainLibraryProvider);
                    Navigator.pop(dialogContext);
                  } catch (_) {
                    setDialogState(
                      () => error = 'Could not save. Check the name, duplicates or an older edit.',
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      disposeAfterDialog([name, muscle, equipment]);
    }
  }

  Future<void> _archive(ExerciseRecord exercise) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive exercise?'),
        content: Text(
          'Remove "${exercise.name}" from your library? '
          'It will remain in existing plans and workout history.',
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
    if (confirm != true || !mounted) return;
    try {
      ref
          .read(workoutLibraryRepositoryProvider)
          .archiveCustomExercise(exercise.uuid);
      ref.invalidate(trainLibraryProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not archive that exercise.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trainLibraryProvider);
    final muted = Theme.of(context).extension<NorthstarColors>()!.muted;
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Custom exercise'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              Text(
                'FIND YOUR MOVEMENT',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Built-ins are read-only. Your own exercises stay on this device.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) =>
                    setState(() => query = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search exercise or equipment',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Custom only'),
                  selected: customOnly,
                  onSelected: (value) => setState(() => customOnly = value),
                ),
              ),
              const SizedBox(height: 14),
              async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => TextButton(
                  onPressed: () => ref.invalidate(trainLibraryProvider),
                  child: const Text('Could not load exercises. Retry'),
                ),
                data: (data) {
                  final visible = data.exercises
                      .where(
                        (exercise) =>
                            exercise.archivedAtMs == null &&
                            (!customOnly || !exercise.isBuiltIn) &&
                            (query.isEmpty ||
                                exercise.name.toLowerCase().contains(query) ||
                                exercise.equipment.toLowerCase().contains(
                                  query,
                                ) ||
                                exercise.muscleGroup.toLowerCase().contains(
                                  query,
                                )),
                      )
                      .toList();
                  if (visible.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No matching exercises.'),
                    );
                  }
                  return Column(
                    children: [
                      for (final exercise in visible)
                        Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            leading: Icon(
                              exercise.isBuiltIn
                                  ? Icons.fitness_center
                                  : Icons.edit_note,
                            ),
                            title: Text(
                              exercise.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              [
                                exercise.muscleGroup,
                                exercise.equipment,
                              ].where((s) => s.isNotEmpty).join(' · '),
                            ),
                            trailing: exercise.isBuiltIn
                                ? const Text('BUILT-IN')
                                : PopupMenuButton<String>(
                                    tooltip:
                                        'Exercise actions for ${exercise.name}',
                                    onSelected: (action) {
                                      if (action == 'edit') _edit(exercise);
                                      if (action == 'archive') {
                                        _archive(exercise);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'archive',
                                        child: Text('Archive'),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
