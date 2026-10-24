import '../../../objectbox.g.dart';
import '../domain/workout_models.dart';
import 'workout_entities.dart';

/// Query only non-terminal statuses, retaining unknown/future values to fail
/// closed. Avoid loading every completed session when history grows.
/// No model/index change: this is a query filter, not a new status index.
List<WorkoutSessionEntity> queryUnfinishedWorkoutSessions(
  Box<WorkoutSessionEntity> sessions,
) {
  final query = sessions
      .query(
        WorkoutSessionEntity_.status
            .notEquals(WorkoutStatus.completed.name)
            .and(
              WorkoutSessionEntity_.status.notEquals(
                WorkoutStatus.discarded.name,
              ),
            ),
      )
      .build();
  try {
    return query.find().where((s) => s.deletedAtMs == null).toList();
  } finally {
    query.close();
  }
}
