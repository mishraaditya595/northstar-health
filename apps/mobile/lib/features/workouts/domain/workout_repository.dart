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

  /// Set + session revision + recovery checkpoint commit atomically.
  void saveSet({required String sessionUuid, required WorkoutSetRecord set});
  void finishSession(String uuid, {required DateTime finishedAtUtc});
}
