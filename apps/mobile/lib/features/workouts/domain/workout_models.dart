/// Immutable domain values: never expose ObjectBox IDs to presentation.
enum WorkoutStatus { inProgress, paused, completed, discarded }

enum WorkoutSetKind { warmup, working }

enum WorkoutSetStatus { planned, completed, skipped }

class WorkoutSetRecord {
  const WorkoutSetRecord({
    required this.uuid,
    required this.exerciseUuid,
    required this.position,
    required this.kind,
    required this.status,
    this.reps,
    this.loadGrams,
    this.inputUnit = 'kg',
    this.rpe,
    this.completedAtUtc,
  });

  final String uuid;
  final String exerciseUuid;
  final int position;
  final WorkoutSetKind kind;
  final WorkoutSetStatus status;
  final int? reps;
  final int? loadGrams;
  final String inputUnit;
  final double? rpe;
  final DateTime? completedAtUtc;

  void validate() {
    if (uuid.isEmpty || exerciseUuid.isEmpty || position < 0) {
      throw ArgumentError(
        'Set must have identity, exercise and valid position',
      );
    }
    if (reps != null && (reps! < 0 || reps! > 10000)) {
      throw ArgumentError.value(reps, 'reps');
    }
    if (loadGrams != null && (loadGrams! < 0 || loadGrams! > 100000000)) {
      throw ArgumentError.value(loadGrams, 'loadGrams');
    }
    if (inputUnit != 'kg' && inputUnit != 'lb') {
      throw ArgumentError.value(inputUnit, 'inputUnit');
    }
    if (rpe != null &&
        (!rpe!.isFinite || rpe! < 0 || rpe! > 10 || (rpe! * 2) % 1 != 0)) {
      throw ArgumentError.value(rpe, 'rpe');
    }
    if (status == WorkoutSetStatus.completed &&
        (reps == null || completedAtUtc == null)) {
      throw ArgumentError('Completed set requires reps and timestamp');
    }
  }
}

class WorkoutExerciseRecord {
  const WorkoutExerciseRecord({
    required this.uuid,
    required this.sessionUuid,
    required this.nameSnapshot,
    required this.position,
    this.definitionUuid,
    this.muscleSnapshot = '',
    this.equipmentSnapshot = '',
  });
  final String uuid;
  final String sessionUuid;
  final String? definitionUuid;
  final String nameSnapshot;
  final String muscleSnapshot;
  final String equipmentSnapshot;
  final int position;
}

class WorkoutSessionRecord {
  const WorkoutSessionRecord({
    required this.uuid,
    required this.name,
    required this.status,
    required this.startedAtUtc,
    required this.originalOffsetMinutes,
    required this.revision,
    this.planUuid,
    this.completedAtUtc,
    this.exercises = const [],
    this.sets = const [],
  });
  final String uuid;
  final String name;
  final WorkoutStatus status;
  final DateTime startedAtUtc;
  final int originalOffsetMinutes;
  final int revision;
  final String? planUuid;
  final DateTime? completedAtUtc;
  final List<WorkoutExerciseRecord> exercises;
  final List<WorkoutSetRecord> sets;
}
