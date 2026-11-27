import '../../objectbox.g.dart';
import '../workouts/data/workout_entities.dart';
import 'objectbox_workout_restore_importer.dart' show RestoreImportException;
import 'workout_restore_feed.dart';

T? _one<T>(Box<T> box, QueryStringProperty<T> property, String key) {
  final query = box.query(property.equals(key)).build();
  try {
    return query.findFirst();
  } finally {
    query.close();
  }
}

List<T> _matching<T>(Box<T> box, QueryStringProperty<T> property, String key) {
  final query = box.query(property.equals(key)).build();
  try {
    return query.find();
  } finally {
    query.close();
  }
}

/// Writes a validated completed workout (session, exercises, sets) over
/// `existing` or as a new session, and returns the session's local revision.
/// Shared by cloud restore and the watch import. Must run inside a write
/// transaction. Does not touch the plan, program or outbox beyond nulling
/// `planUuid`.
int writeCompletedSnapshot(
  Store store,
  RemoteWorkoutSnapshot snapshot,
  WorkoutSessionEntity? existing, {
  required int nowMs,
}) {
  final sessions = store.box<WorkoutSessionEntity>();
  final exercises = store.box<WorkoutExerciseEntity>();
  final sets = store.box<WorkoutSetEntity>();
  // Global Unique IDs on exercises and sets must not be stolen from a
  // different local workout. Check first, then write everything atomically.
  final oldExercises = _matching(
    exercises,
    WorkoutExerciseEntity_.sessionUuid,
    snapshot.uuid,
  );
  final oldIds = oldExercises.map((e) => e.uuid).toSet();
  for (final exercise in snapshot.exercises) {
    final prior = _one(exercises, WorkoutExerciseEntity_.uuid, exercise.uuid);
    if (prior != null && prior.sessionUuid != snapshot.uuid) {
      throw const RestoreImportException('exercise_uuid_collision');
    }
  }
  for (final set in snapshot.sets) {
    final prior = _one(sets, WorkoutSetEntity_.uuid, set.uuid);
    if (prior != null && !oldIds.contains(prior.exerciseUuid)) {
      throw const RestoreImportException('set_uuid_collision');
    }
  }
  for (final exercise in oldExercises) {
    for (final set in _matching(
      sets,
      WorkoutSetEntity_.exerciseUuid,
      exercise.uuid,
    )) {
      sets.remove(set.id);
    }
    exercises.remove(exercise.id);
  }
  final session =
      existing ??
      WorkoutSessionEntity(
        uuid: snapshot.uuid,
        name: snapshot.name,
        startedAtMs: snapshot.startedAtUtc.millisecondsSinceEpoch,
        originalOffsetMinutes: snapshot.originalOffsetMinutes,
        updatedAtMs: nowMs,
      );
  session.name = snapshot.name;
  session.status = 'completed';
  session.origin = snapshot.origin.wire;
  session.planUuid = null; // Plans are never transported in the DTO.
  session.startedAtMs = snapshot.startedAtUtc.millisecondsSinceEpoch;
  session.completedAtMs = snapshot.completedAtUtc.millisecondsSinceEpoch;
  session.originalOffsetMinutes = snapshot.originalOffsetMinutes;
  session.updatedAtMs = nowMs;
  session.deletedAtMs = null;
  session.revision = existing == null ? 1 : existing.revision + 1;
  sessions.put(session);
  for (final ex in snapshot.exercises) {
    exercises.put(
      WorkoutExerciseEntity(
        uuid: ex.uuid,
        sessionUuid: snapshot.uuid,
        nameSnapshot: ex.nameSnapshot,
        muscleSnapshot: ex.muscleSnapshot,
        equipmentSnapshot: ex.equipmentSnapshot,
        position: ex.position,
        primaryMusclesSnapshot: List.of(ex.primaryMusclesSnapshot),
        secondaryMusclesSnapshot: List.of(ex.secondaryMusclesSnapshot),
      ),
    );
  }
  for (final set in snapshot.sets) {
    sets.put(
      WorkoutSetEntity(
        uuid: set.uuid,
        exerciseUuid: set.exerciseUuid,
        position: set.position,
        kind: set.kind.name,
        status: set.status.name,
        reps: set.reps,
        durationSeconds: set.durationSeconds,
        loadGrams: set.loadGrams,
        inputUnit: set.inputUnit.name,
        rpe: set.rpe,
        completedAtMs: set.completedAtUtc?.millisecondsSinceEpoch,
        updatedAtMs: nowMs,
      ),
    );
  }
  return session.revision;
}
