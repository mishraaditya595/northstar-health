import 'workout_library_models.dart';

abstract interface class WorkoutLibraryRepository {
  /// Seeds versioned built-in exercises transactionally, retaining user data.
  void ensureCatalogSeeded();

  /// Archived definitions are returned when explicitly requested to allow
  /// historical plan references to remain intelligible.
  List<ExerciseRecord> listExercises({bool includeArchived = false});

  /// Only custom exercises can be created, renamed or archived.
  ExerciseRecord saveCustomExercise({
    required String uuid,
    required String name,
    required String muscleGroup,
    required String equipment,
    int? expectedUpdatedAtMs,
  });

  void archiveCustomExercise(String uuid);

  List<WorkoutPlanRecord> listPlans();

  WorkoutPlanRecord? getPlan(String uuid);

  /// Saves the complete ordered template and children in one transaction.
  /// Edits require the plan timestamp observed by the caller.
  WorkoutPlanRecord savePlan({
    required String uuid,
    required String name,
    required String description,
    required List<PlanExerciseRecord> exercises,
    int? expectedUpdatedAtMs,
  });

  void archivePlan(String uuid);
}
