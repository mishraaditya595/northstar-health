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
  /// from an older release, fills the muscles of a copy that has none, and
  /// never changes the input mode. Touches no plans or sessions.
  ExerciseRecord materializeCatalogExercise({
    required String id,
    required String name,
    required String muscleGroup,
    required String equipment,
    required String category,
    required String mode,
    required int release,
    required List<String> primaryMuscles,
    required List<String> secondaryMuscles,
  });

  /// Brings already-stored built-in definitions up to date from the
  /// catalogue (one transaction): only existing `builtin.v1.` rows that are
  /// older than [release] or have no muscles yet. Never inserts, never
  /// touches custom rows, never changes the input mode (a row whose mode
  /// differs is skipped). Returns the number of rows updated.
  int syncCatalogDefinitions(List<CatalogDefinitionInput> items, int release);

  /// Copies a catalogue template into My Plans in one transaction:
  /// materializes every exercise (the rules of [materializeCatalogExercise]),
  /// picks an unused plan name ("name (2)" when an active plan has it) and
  /// writes the plan, UUID [requestUuid], with its rows. Repeating a request
  /// returns the existing plan. Any failure leaves nothing behind. The plan
  /// keeps no link to the template.
  WorkoutPlanRecord copyCatalogTemplate({
    required String requestUuid,
    required String name,
    required String description,
    required List<TemplateRowInput> rows,
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
