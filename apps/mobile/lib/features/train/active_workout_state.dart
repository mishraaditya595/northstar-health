import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids/uuid_factory.dart';
import '../programs/domain/program_models.dart';
import '../programs/domain/program_schedule.dart';
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

/// ObjectBox reads are synchronous. Return an explicit AsyncValue to keep
/// recoverability errors visible without introducing transient loading states
/// or destroying in-progress form controls after each saved set.
final activeWorkoutProvider = Provider<AsyncValue<ActiveWorkoutView?>>((ref) {
  try {
    final engine = ref.watch(liveWorkoutEngineProvider);
    final session = engine.recoverActiveWorkout();
    if (session == null) {
      return const AsyncData<ActiveWorkoutView?>(null);
    }
    final checkpoint = engine.readCheckpoint(session.uuid);
    if (checkpoint == null ||
        checkpoint.checkpointRevision != session.revision) {
      throw StateError('Recovery checkpoint is missing or outdated');
    }
    return AsyncData<ActiveWorkoutView?>(
      ActiveWorkoutView(session, checkpoint),
    );
  } catch (error, trace) {
    return AsyncError<ActiveWorkoutView?>(error, trace);
  }
});

abstract interface class WorkoutActions {
  WorkoutSessionRecord startQuick(String name);
  WorkoutSessionRecord startPlan(String planUuid);

  /// Starts the workout scheduled for [localNow]'s date, recording which
  /// program day it was for. A rest day throws [StateError].
  WorkoutSessionRecord startProgramDay(
    TrainingProgramRecord program,
    DateTime localNow,
  );

  /// Materializes the template's exercises, then starts an unsaved workout
  /// from its rows. Throws the usual "finish or discard" [StateError] and
  /// changes nothing while another workout is unfinished.
  WorkoutSessionRecord startTemplate(
    String name,
    List<TemplateRowInput> rows,
    int release,
  );
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
  void removeSet(WorkoutSessionRecord session, WorkoutSetRecord set);
  WorkoutSessionRecord pause(WorkoutSessionRecord session);
  WorkoutSessionRecord resume(WorkoutSessionRecord session);
  WorkoutSessionRecord finish(WorkoutSessionRecord session);
  WorkoutSessionRecord discard(WorkoutSessionRecord session);
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
  WorkoutSessionRecord startProgramDay(
    TrainingProgramRecord program,
    DateTime localNow,
  ) {
    final planUuid = dayFor(program, localNow).planUuid;
    if (planUuid == null) throw StateError('Today is a rest day');
    return engine.startWorkout(
      sessionUuid: ids.newId(),
      planUuid: planUuid,
      programDay: (
        programUuid: program.uuid,
        localDate: localDateKey(localNow),
      ),
      startedAtUtc: localNow.toUtc(),
      originalOffsetMinutes: localNow.timeZoneOffset.inMinutes,
    );
  }

  @override
  WorkoutSessionRecord startTemplate(
    String name,
    List<TemplateRowInput> rows,
    int release,
  ) {
    if (engine.recoverActiveWorkout() != null) {
      throw StateError('Finish or discard the existing workout first');
    }
    // Each exercise is copied in its own transaction before the session
    // starts. That is safe: the rows are the catalogue's own definitions, the
    // copy is idempotent, and an exercise left behind by a failed start is
    // only an unused library entry, never a plan or a workout.
    for (final row in rows) {
      final e = row.exercise;
      library.materializeCatalogExercise(
        id: e.id,
        name: e.name,
        muscleGroup: e.muscleGroup,
        equipment: e.equipment,
        category: e.category,
        mode: e.mode,
        release: release,
        primaryMuscles: e.primaryMuscles,
        secondaryMuscles: e.secondaryMuscles,
      );
    }
    final now = DateTime.now();
    return engine.startTemplateWorkout(
      sessionUuid: ids.newId(),
      name: name,
      rows: [
        for (var i = 0; i < rows.length; i++)
          PlanExerciseRecord(
            uuid: ids.newId(),
            exerciseUuid: rows[i].exercise.id,
            position: i,
            targetSets: rows[i].sets,
            targetRepsMin: rows[i].repsMin,
            targetRepsMax: rows[i].repsMax,
            targetDurationSeconds: rows[i].durationSeconds,
            restSeconds: rows[i].restSeconds,
            notes: rows[i].note,
          ),
      ],
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
        primaryMusclesSnapshot: definition.primaryMuscles,
        secondaryMusclesSnapshot: definition.secondaryMuscles,
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
  void removeSet(WorkoutSessionRecord session, WorkoutSetRecord set) {
    if (session.status != WorkoutStatus.inProgress &&
        session.status != WorkoutStatus.paused) {
      throw StateError('Workout is not editable');
    }
    repository.removeSet(
      sessionUuid: session.uuid,
      setUuid: set.uuid,
      expectedRevision: session.revision,
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

WorkoutSetRecord skippedSet(WorkoutSetRecord previous) => WorkoutSetRecord(
  uuid: previous.uuid,
  exerciseUuid: previous.exerciseUuid,
  position: previous.position,
  kind: previous.kind,
  status: WorkoutSetStatus.skipped,
);
