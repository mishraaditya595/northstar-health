import '../../../core/units/load_units.dart';

/// Immutable domain values: never expose ObjectBox IDs to presentation.
library;

/// Where a completed workout was logged. `wire` is the cloud payload value.
enum WorkoutOrigin {
  phone('northstar_phone'),
  watch('beyondrep_watch');

  const WorkoutOrigin(this.wire);
  final String wire;

  /// Null for anything that is not exactly one of the two wire values.
  static WorkoutOrigin? fromWire(Object? value) {
    for (final origin in values) {
      if (origin.wire == value) return origin;
    }
    return null;
  }
}

enum WorkoutStatus { inProgress, paused, completed, discarded, unknown }

enum WorkoutSetKind { warmup, working, unknown }

enum WorkoutSetStatus { planned, completed, skipped, unknown }

class WorkoutSetRecord {
  const WorkoutSetRecord({
    required this.uuid,
    required this.exerciseUuid,
    required this.position,
    required this.kind,
    required this.status,
    this.reps,
    this.durationSeconds,
    this.loadGrams,
    this.inputUnit = LoadUnit.kg,
    this.rpe,
    this.completedAtUtc,
  });

  final String uuid;
  final String exerciseUuid;
  final int position;
  final WorkoutSetKind kind;
  final WorkoutSetStatus status;
  final int? reps;

  /// Seconds for a timed exercise. A set carries reps or seconds, never both.
  final int? durationSeconds;
  final int? loadGrams;
  final LoadUnit inputUnit;
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
    if (durationSeconds != null &&
        (durationSeconds! < 1 || durationSeconds! > 86400)) {
      throw ArgumentError.value(durationSeconds, 'durationSeconds');
    }
    if (reps != null && durationSeconds != null) {
      throw ArgumentError('Set cannot have both reps and seconds');
    }
    if (loadGrams != null && (loadGrams! < 0 || loadGrams! > 100000000)) {
      throw ArgumentError.value(loadGrams, 'loadGrams');
    }
    if (inputUnit == LoadUnit.unknown) {
      throw ArgumentError.value(inputUnit, 'inputUnit');
    }
    if (rpe != null &&
        (!rpe!.isFinite || rpe! < 0 || rpe! > 10 || (rpe! * 2) % 1 != 0)) {
      throw ArgumentError.value(rpe, 'rpe');
    }
    if (status == WorkoutSetStatus.unknown || kind == WorkoutSetKind.unknown) {
      throw ArgumentError(
        'Unknown persisted set status/kind cannot be written',
      );
    }
    if (status == WorkoutSetStatus.completed &&
        ((reps == null && durationSeconds == null) || completedAtUtc == null)) {
      throw ArgumentError(
        'Completed set requires reps or seconds and timestamp',
      );
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
    this.primaryMusclesSnapshot = const [],
    this.secondaryMusclesSnapshot = const [],
    this.restSeconds,
  });
  final String uuid;
  final String sessionUuid;
  final String? definitionUuid;
  final String nameSnapshot;
  final String muscleSnapshot;
  final String equipmentSnapshot;
  final int position;

  /// Specific muscles copied when the exercise joined the workout; empty for
  /// custom exercises and workouts logged before muscles existed.
  final List<String> primaryMusclesSnapshot;
  final List<String> secondaryMusclesSnapshot;

  /// Rest planned for this exercise by its plan or template row, or null
  /// (quick workouts, added exercises). Local only, never synced.
  final int? restSeconds;
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
    this.programUuid,
    this.programDayLocalDate,
    this.origin = WorkoutOrigin.phone,
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

  /// Program day this session was started for (`yyyy-MM-dd`). Local only.
  final String? programUuid;
  final String? programDayLocalDate;

  /// Which device logged the workout.
  final WorkoutOrigin origin;
}
