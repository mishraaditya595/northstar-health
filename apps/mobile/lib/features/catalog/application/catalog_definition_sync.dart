import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../train/train_library_state.dart';
import '../../workouts/data/objectbox_workout_library_repository.dart';
import '../domain/exercise_choices.dart';
import 'catalog_providers.dart';
import 'exercise_choices_provider.dart';

/// Writes the catalogue's specific muscles into the account's stored built-in
/// definitions whenever a catalogue snapshot is available, so plans of the
/// seeded exercises benefit without anything being picked again. Idempotent;
/// only the repository rules decide which rows change.
final catalogDefinitionSyncProvider = Provider<void>((ref) {
  final snapshot = safeCatalogState(() => ref.watch(catalogStateProvider))
      .snapshot;
  if (snapshot == null) return;
  final repository = ref.read(workoutLibraryRepositoryProvider);
  // The library provider seeds lazily; the backfill needs the rows to exist.
  repository.ensureCatalogSeeded();
  final updated = repository.syncCatalogDefinitions([
    for (final e in snapshot.activeExercises)
      (
        id: e.id,
        name: e.name,
        muscleGroup: e.muscleGroup,
        equipment: equipmentLabel(e.equipment),
        category: categoryLabel(e.category),
        mode: e.mode,
        primaryMuscles: e.primaryMuscles,
        secondaryMuscles: e.secondaryMuscles,
      ),
  ], snapshot.release);
  if (updated > 0) {
    // Not inside provider build: refresh the library right after.
    Future.microtask(() {
      if (ref.mounted) ref.invalidate(trainLibraryProvider);
    });
  }
});

/// Runs [catalogDefinitionSyncProvider] for the account scope it sits in.
class CatalogDefinitionSyncHost extends ConsumerWidget {
  const CatalogDefinitionSyncHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(catalogDefinitionSyncProvider);
    return child;
  }
}
