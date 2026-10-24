import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids/uuid_factory.dart';
import '../../core/units/load_units.dart';
import '../workouts/data/objectbox_live_workout_engine.dart';
import '../workouts/data/objectbox_workout_library_repository.dart';
import '../workouts/data/objectbox_workout_repository.dart';
import '../workouts/domain/live_workout_engine.dart';
import '../workouts/domain/workout_library_models.dart';
import '../workouts/domain/workout_library_repository.dart';
import '../workouts/domain/workout_models.dart';
import '../workouts/domain/workout_repository.dart';

/// Reload on foreground/re-entry and after each acknowledged local commit.
/// No polling or network; the database is always the durable source.
class ActiveWorkoutView {
  const ActiveWorkoutView(this.session, this.checkpoint);
  final WorkoutSessionRecord session;
  final WorkoutRecoveryCheckpoint checkpoint;
}

final activeWorkoutProvider = FutureProvider<ActiveWorkoutView?>((ref) async {
  final engine = ref.watch(liveWorkoutEngineProvider);
  final session = engine.recoverActiveWorkout();
  if (session == null) return null;
  final checkpoint = engine.readCheckpoint(session.uuid);
  if (checkpoint == null || checkpoint.checkpointRevision != session.revision) {
    throw StateError('Recovery checkpoint is missing or outdated');
  }
  return ActiveWorkoutView(session, checkpoint);
});

abstract interface class WorkoutActions {
  WorkoutSessionRecord startQuick(String name);
  WorkoutSessionRecord startPlan(String planUuid);
  void addExercise(WorkoutSessionRecord session, ExerciseRecord definition);
  void addPlannedSet(
    WorkoutSessionRecord session,
    WorkoutExerciseRecord exercise,
  );
  void saveSet(
    WorkoutSessionRecord session,
    WorkoutSetRecord set, {
    int? restSeconds,
  });
  WorkoutSessionRecord pause(WorkoutSessionRecord session);
  WorkoutSessionRecord resume(WorkoutSessionRecord session);
  WorkoutSessionRecord finish(WorkoutSessionRecord session);
  WorkoutSessionRecord discard(WorkoutSessionRecord session);
  WorkoutRecoveryCheckpoint? checkpoint(String sessionUuid);
  WorkoutRecoveryCheckpoint startRest(
    WorkoutSessionRecord session,
    WorkoutRecoveryCheckpoint checkpoint,
    int seconds,
  );
  WorkoutRecoveryCheckpoint clearRest(
    WorkoutSessionRecord session,
    WorkoutRecoveryCheckpoint checkpoint,
  );
}

final workoutActionsProvider = Provider<WorkoutActions>(
  (ref) => RepositoryWorkoutActions(
    ref.watch(liveWorkoutEngineProvider),
    ref.watch(workoutRepositoryProvider),
    ref.watch(workoutLibraryRepositoryProvider),
    SecureUuidFactory(),
  ),
);

class RepositoryWorkoutActions implements WorkoutActions {
  RepositoryWorkoutActions(
    this.engine,
    this.repository,
    this.library,
    this.ids,
  );

  final LiveWorkoutEngine engine;
  final WorkoutRepository repository;
  final WorkoutLibraryRepository library;
  final UuidFactory ids;

  @override
  WorkoutSessionRecord startQuick(String name) {
    final now = DateTime.now();
    return engine.startWorkout(
      sessionUuid: ids.newId(),
      quickName: name,
      startedAtUtc: now.toUtc(),
      originalOffsetMinutes: now.timeZoneOffset.inMinutes,
    );
  }

  @override
  WorkoutSessionRecord startPlan(String planUuid) {
    final now = DateTime.now();
    return engine.startWorkout(
      sessionUuid: ids.newId(),
      planUuid: planUuid,
      startedAtUtc: now.toUtc(),
      originalOffsetMinutes: now.timeZoneOffset.inMinutes,
    );
  }

  @override
  void addExercise(WorkoutSessionRecord session, ExerciseRecord definition) {
    if (definition.archivedAtMs != null ||
        !library.listExercises().any((e) => e.uuid == definition.uuid)) {
      throw StateError('Exercise is no longer available');
    }
    if (session.status != WorkoutStatus.inProgress &&
        session.status != WorkoutStatus.paused) {
      throw StateError('Workout is not editable');
    }
    repository.addExercise(
      WorkoutExerciseRecord(
        uuid: ids.newId(),
        sessionUuid: session.uuid,
        definitionUuid: definition.uuid,
        nameSnapshot: definition.name,
        muscleSnapshot: definition.muscleGroup,
        equipmentSnapshot: definition.equipment,
        position: session.exercises.length,
      ),
    );
  }

  @override
  void addPlannedSet(
    WorkoutSessionRecord session,
    WorkoutExerciseRecord exercise,
  ) {
    final matching = session.sets.where((s) => s.exerciseUuid == exercise.uuid);
    repository.saveSet(
      sessionUuid: session.uuid,
      expectedRevision: session.revision,
      set: WorkoutSetRecord(
        uuid: ids.newId(),
        exerciseUuid: exercise.uuid,
        position: matching.length,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.planned,
      ),
    );
  }

  @override
  void saveSet(
    WorkoutSessionRecord session,
    WorkoutSetRecord set, {
    int? restSeconds,
  }) {
    if (session.status != WorkoutStatus.inProgress &&
        session.status != WorkoutStatus.paused) {
      throw StateError('Workout is not editable');
    }
    repository.saveSet(
      sessionUuid: session.uuid,
      expectedRevision: session.revision,
      set: set,
      restSeconds: restSeconds,
    );
  }

  @override
  WorkoutSessionRecord pause(WorkoutSessionRecord session) =>
      engine.pauseWorkout(session.uuid, expectedRevision: session.revision);

  @override
  WorkoutSessionRecord resume(WorkoutSessionRecord session) =>
      engine.resumeWorkout(session.uuid, expectedRevision: session.revision);

  @override
  WorkoutSessionRecord finish(WorkoutSessionRecord session) =>
      engine.finishWorkout(
        session.uuid,
        expectedRevision: session.revision,
        finishedAtUtc: DateTime.now().toUtc(),
      );

  @override
  WorkoutSessionRecord discard(WorkoutSessionRecord session) =>
      engine.discardWorkout(session.uuid, expectedRevision: session.revision);

  @override
  WorkoutRecoveryCheckpoint? checkpoint(String sessionUuid) =>
      engine.readCheckpoint(sessionUuid);

  @override
  WorkoutRecoveryCheckpoint startRest(
    WorkoutSessionRecord session,
    WorkoutRecoveryCheckpoint checkpoint,
    int seconds,
  ) => engine.startRestTimer(
    session.uuid,
    expectedRevision: session.revision,
    expectedCheckpointSavedAtMs: checkpoint.savedAtMs,
    seconds: seconds,
  );

  @override
  WorkoutRecoveryCheckpoint clearRest(
    WorkoutSessionRecord session,
    WorkoutRecoveryCheckpoint checkpoint,
  ) => engine.clearRestTimer(
    session.uuid,
    expectedRevision: session.revision,
    expectedCheckpointSavedAtMs: checkpoint.savedAtMs,
  );
}

/// Validation helpers remain independent of widgets for focused tests.
WorkoutSetRecord recordedSet({
  required WorkoutSetRecord previous,
  required int reps,
  required double load,
  required LoadUnit unit,
  double? rpe,
  required DateTime completedAtUtc,
}) => WorkoutSetRecord(
  uuid: previous.uuid,
  exerciseUuid: previous.exerciseUuid,
  position: previous.position,
  kind: previous.kind,
  status: WorkoutSetStatus.completed,
  reps: reps,
  loadGrams: LoadUnits.toGrams(load, unit),
  inputUnit: unit,
  rpe: rpe,
  completedAtUtc: completedAtUtc.toUtc(),
);

WorkoutSetRecord skippedSet(WorkoutSetRecord previous) => WorkoutSetRecord(
  uuid: previous.uuid,
  exerciseUuid: previous.exerciseUuid,
  position: previous.position,
  kind: previous.kind,
  status: WorkoutSetStatus.skipped,
);
