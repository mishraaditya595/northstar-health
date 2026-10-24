/// Local-only exercise definitions and workout templates. UUIDs are portable
/// identities, never ObjectBox integer IDs.
class ExerciseRecord {
  const ExerciseRecord({
    required this.uuid,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.movementCategory,
    required this.inputMode,
    required this.isBuiltIn,
    required this.updatedAtMs,
    this.archivedAtMs,
  });

  final String uuid;
  final String name;
  final String muscleGroup;
  final String equipment;
  final String movementCategory;
  final String inputMode;
  final bool isBuiltIn;
  final int updatedAtMs;
  final int? archivedAtMs;
}

class PlanExerciseRecord {
  const PlanExerciseRecord({
    required this.uuid,
    required this.exerciseUuid,
    required this.position,
    required this.targetSets,
    this.targetRepsMin,
    this.targetRepsMax,
    this.restSeconds,
    this.notes = '',
  });

  final String uuid;
  final String exerciseUuid;
  final int position;
  final int targetSets;
  final int? targetRepsMin;
  final int? targetRepsMax;
  final int? restSeconds;
  final String notes;

  PlanExerciseRecord withPosition(int next) => PlanExerciseRecord(
    uuid: uuid,
    exerciseUuid: exerciseUuid,
    position: next,
    targetSets: targetSets,
    targetRepsMin: targetRepsMin,
    targetRepsMax: targetRepsMax,
    restSeconds: restSeconds,
    notes: notes,
  );

  void validate() {
    if (uuid.isEmpty ||
        exerciseUuid.isEmpty ||
        position < 0 ||
        targetSets < 1 ||
        targetSets > 30 ||
        (targetRepsMin != null &&
            (targetRepsMin! < 1 || targetRepsMin! > 1000)) ||
        (targetRepsMax != null &&
            (targetRepsMax! < 1 || targetRepsMax! > 1000)) ||
        (targetRepsMin != null &&
            targetRepsMax != null &&
            targetRepsMax! < targetRepsMin!) ||
        (restSeconds != null && (restSeconds! < 0 || restSeconds! > 3600)) ||
        notes.length > 1000) {
      throw ArgumentError('Invalid plan exercise or prescription');
    }
  }
}

class WorkoutPlanRecord {
  const WorkoutPlanRecord({
    required this.uuid,
    required this.name,
    required this.description,
    required this.updatedAtMs,
    required this.exercises,
    this.archivedAtMs,
  });

  final String uuid;
  final String name;
  final String description;
  final int updatedAtMs;
  final int? archivedAtMs;
  final List<PlanExerciseRecord> exercises;
}

class WorkoutLibrarySnapshot {
  const WorkoutLibrarySnapshot({required this.exercises, required this.plans});
  final List<ExerciseRecord> exercises;
  final List<WorkoutPlanRecord> plans;
}

/// Concurrent editors must reload instead of overriding a newer saved plan.
class PlanEditConflict implements Exception {
  const PlanEditConflict();
  @override
  String toString() => 'This plan changed. Reload it before saving.';
}
