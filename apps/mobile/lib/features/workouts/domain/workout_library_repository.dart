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

  /// Copies a catalogue exercise into this account's library (idempotent).
  /// Inserts when missing, refreshes display fields when the stored copy is
  /// from an older release, and never changes the input mode. Touches no
  /// plans or sessions.
  ExerciseRecord materializeCatalogExercise({
    required String id,
    required String name,
    required String muscleGroup,
    required String equipment,
    required String category,
    required String mode,
    required int release,
  });

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

  /// Compare the observed plan version in the archive transaction.
  /// A stale editor must not archive a newly updated plan.
  void archivePlan(String uuid, {required int expectedUpdatedAtMs});
}
