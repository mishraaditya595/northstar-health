import 'workout_models.dart';

abstract interface class WorkoutRepository {
  WorkoutSessionRecord createSession({
    required String uuid,
    required String name,
    DateTime? startedAtUtc,
    String? planUuid,
    int? originalOffsetMinutes,
  });
  WorkoutSessionRecord? getSession(String uuid);
  void addExercise(WorkoutExerciseRecord exercise);

  /// The caller's observed revision is mandatory for changing a set.
  /// An identical retry returns without a write, even if revision advanced.
  /// A changed stale command throws [WorkoutRevisionConflict].

  /// Set + session revision + recovery checkpoint commit atomically.
  void saveSet({
    required String sessionUuid,
    required WorkoutSetRecord set,
    required int expectedRevision,
    /// Optional rest deadline, committed atomically with a completed set.
    /// Zero/null means no automatic rest timer.
    int? restSeconds,
  });

  /// Legacy primitive: use LiveWorkoutEngine.finishWorkout in production.
  /// The caller's observed session revision is always required.
  @Deprecated('Use LiveWorkoutEngine.finishWorkout')
  void finishSession(
    String uuid, {
    required int expectedRevision,
    required DateTime finishedAtUtc,
  });
}

/// Caller must reload the latest session and re-apply its intended change.
class WorkoutRevisionConflict implements Exception {
  const WorkoutRevisionConflict(this.expected, this.actual);
  final int expected;
  final int actual;

  @override
  String toString() =>
      'Workout revision conflict (expected $expected, actual $actual)';
}
