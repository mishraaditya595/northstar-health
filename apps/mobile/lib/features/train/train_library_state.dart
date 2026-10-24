import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workouts/data/objectbox_workout_library_repository.dart';
import '../workouts/domain/workout_library_models.dart';

/// Repository is the sole data owner: screens never operate on ObjectBox boxes.
final trainLibraryProvider = FutureProvider<WorkoutLibrarySnapshot>((ref) async {
  final repository = ref.watch(workoutLibraryRepositoryProvider);
  repository.ensureCatalogSeeded();
  return WorkoutLibrarySnapshot(
    exercises: repository.listExercises(includeArchived: true),
    plans: repository.listPlans(),
  );
});
