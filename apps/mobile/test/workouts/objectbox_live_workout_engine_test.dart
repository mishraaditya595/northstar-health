import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/ids/uuid_factory.dart';
import 'package:northstar_health/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_library_repository.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_repository.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/features/workouts/domain/workout_library_models.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';
import 'package:northstar_health/features/workouts/domain/workout_repository.dart';
import 'package:northstar_health/objectbox.g.dart';

class SequenceUuids implements UuidFactory {
  SequenceUuids(this.values);
  final List<String> values;
  var current = 0;

  @override
  String newId() => values[current++];
}

void main() {
  late Directory directory;
  late Store store;
  late ObjectBoxLiveWorkoutEngine engine;
  late ObjectBoxWorkoutRepository sessions;
  late ObjectBoxWorkoutLibraryRepository library;

  final started = DateTime.utc(2026, 10, 24, 9);
  final finished = DateTime.utc(2026, 10, 24, 10);

  setUp(() {
    directory = Directory.systemTemp.createTempSync('northstar-live-engine-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    engine = ObjectBoxLiveWorkoutEngine(store);
    sessions = ObjectBoxWorkoutRepository(store);
    library = ObjectBoxWorkoutLibraryRepository(store);
    library.ensureCatalogSeeded();
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  void makePlan() {
    library.savePlan(
      uuid: 'plan-a',
      name: 'Upper day',
      description: 'Offline template',
      exercises: const [
        PlanExerciseRecord(
          uuid: 'plan-item-a',
          exerciseUuid: 'builtin.v1.bench-press',
          position: 0,
          targetSets: 3,
          targetRepsMin: 8,
          targetRepsMax: 12,
          restSeconds: 90,
        ),
        PlanExerciseRecord(
          uuid: 'plan-item-b',
          exerciseUuid: 'builtin.v1.seated-row',
          position: 1,
          targetSets: 2,
          targetRepsMin: 6,
          targetRepsMax: 10,
        ),
      ],
    );
  }

  WorkoutSessionRecord startQuick({String id = 'quick-1'}) =>
      engine.startWorkout(
        sessionUuid: id,
        quickName: 'Quick strength',
        startedAtUtc: started,
        originalOffsetMinutes: 330,
      );

  test(
    'plan start is atomic and snapshots ordered exercises with planned sets',
    () {
      makePlan();
      final workout = engine.startWorkout(
        sessionUuid: 'session-a',
        planUuid: 'plan-a',
        startedAtUtc: started,
        originalOffsetMinutes: 330,
      );
      expect(workout.status, WorkoutStatus.inProgress);
      expect(workout.name, 'Upper day');
      expect(workout.planUuid, 'plan-a');
      expect(workout.originalOffsetMinutes, 330);
      expect(workout.startedAtUtc, started);
      expect(workout.revision, 1);
      expect(workout.exercises.map((e) => e.nameSnapshot), [
        'Barbell bench press',
        'Seated cable row',
      ]);
      expect(workout.exercises.map((e) => e.position), [0, 1]);
      expect(workout.sets, hasLength(5));
      expect(
        workout.sets.every((s) => s.status == WorkoutSetStatus.planned),
        isTrue,
      );
      expect(
        workout.sets.every((s) => s.reps == null && s.loadGrams == null),
        isTrue,
      );
      expect(
        workout.sets
            .where((s) => s.exerciseUuid == workout.exercises[0].uuid)
            .map((s) => s.position),
        [0, 1, 2],
      );
      expect(engine.readCheckpoint(workout.uuid)!.checkpointRevision, 1);

      final replay = engine.startWorkout(
        sessionUuid: 'session-a',
        planUuid: 'plan-a',
        startedAtUtc: started,
        originalOffsetMinutes: 330,
      );
      expect(
        replay.exercises.map((e) => e.uuid),
        workout.exercises.map((e) => e.uuid),
      );
      expect(store.box<WorkoutSessionEntity>().count(), 1);
      expect(store.box<WorkoutExerciseEntity>().count(), 2);
      expect(store.box<WorkoutSetEntity>().count(), 5);
    },
  );

  test(
    'only one unfinished session; direct legacy create cannot bypass it',
    () {
      final first = startQuick();
      expect(engine.recoverActiveWorkout()!.uuid, first.uuid);
      expect(() => startQuick(id: 'another'), throwsStateError);
      expect(
        () => sessions.createSession(
          uuid: 'legacy',
          name: 'Legacy',
          startedAtUtc: started,
        ),
        throwsStateError,
      );
      engine.pauseWorkout(first.uuid, expectedRevision: first.revision);
      expect(() => startQuick(id: 'another'), throwsStateError);
      expect(engine.recoverActiveWorkout()!.status, WorkoutStatus.paused);
      expect(store.box<WorkoutSessionEntity>().count(), 1);
    },
  );

  test('reopen native Store restores last acknowledged set and checkpoint', () {
    makePlan();
    final s = engine.startWorkout(
      sessionUuid: 'session-a',
      planUuid: 'plan-a',
      startedAtUtc: started,
      originalOffsetMinutes: 330,
    );
    sessions.saveSet(
      sessionUuid: s.uuid,
      expectedRevision: s.revision,
      set: WorkoutSetRecord(
        uuid: s.sets.first.uuid,
        exerciseUuid: s.exercises.first.uuid,
        position: 0,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.completed,
        reps: 9,
        loadGrams: 62500,
        rpe: 8.5,
        completedAtUtc: DateTime.utc(2026, 10, 24, 9, 5),
      ),
    );
    final revision = sessions.getSession(s.uuid)!.revision;
    store.close();
    store = Store(getObjectBoxModel(), directory: directory.path);
    engine = ObjectBoxLiveWorkoutEngine(store);
    sessions = ObjectBoxWorkoutRepository(store);
    library = ObjectBoxWorkoutLibraryRepository(store);
    final resumed = engine.recoverActiveWorkout()!;
    expect(resumed.revision, revision);
    expect(resumed.sets.first.reps, 9);
    expect(resumed.sets.first.loadGrams, 62500);
    expect(resumed.sets.first.rpe, 8.5);
    final checkpoint = engine.readCheckpoint(s.uuid)!;
    expect(checkpoint.checkpointRevision, revision);
    expect(checkpoint.selectedSetUuid, s.sets.first.uuid);
  });

  test('pause/resume use expected revisions and preserve all sets', () {
    final initial = startQuick();
    final paused = engine.pauseWorkout(
      initial.uuid,
      expectedRevision: initial.revision,
    );
    expect(paused.status, WorkoutStatus.paused);
    expect(paused.revision, initial.revision + 1);
    expect(
      engine.readCheckpoint(initial.uuid)!.checkpointRevision,
      paused.revision,
    );
    expect(
      () =>
          engine.pauseWorkout(initial.uuid, expectedRevision: initial.revision),
      throwsA(isA<WorkoutRevisionConflict>()),
    );
    expect(
      () => engine.resumeWorkout(
        initial.uuid,
        expectedRevision: initial.revision,
      ),
      throwsA(isA<WorkoutRevisionConflict>()),
    );
    final running = engine.resumeWorkout(
      initial.uuid,
      expectedRevision: paused.revision,
    );
    expect(running.status, WorkoutStatus.inProgress);
    expect(
      engine.readCheckpoint(initial.uuid)!.checkpointRevision,
      running.revision,
    );
  });

  test(
    'finish and discard release the single-active slot and remove checkpoint',
    () {
      final first = startQuick();
      final ended = engine.finishWorkout(
        first.uuid,
        expectedRevision: first.revision,
        finishedAtUtc: finished,
      );
      expect(ended.status, WorkoutStatus.completed);
      expect(ended.completedAtUtc, finished);
      expect(engine.readCheckpoint(first.uuid), isNull);
      expect(engine.recoverActiveWorkout(), isNull);
      final retry = engine.finishWorkout(
        first.uuid,
        expectedRevision: first.revision,
        finishedAtUtc: finished,
      );
      expect(retry.revision, ended.revision);

      final next = startQuick(id: 'quick-2');
      final discarded = engine.discardWorkout(
        next.uuid,
        expectedRevision: next.revision,
      );
      expect(discarded.status, WorkoutStatus.discarded);
      expect(engine.readCheckpoint(next.uuid), isNull);
      expect(engine.recoverActiveWorkout(), isNull);
      expect(
        engine
            .discardWorkout(next.uuid, expectedRevision: next.revision)
            .revision,
        discarded.revision,
      );
      expect(
        () => engine.resumeWorkout(
          next.uuid,
          expectedRevision: discarded.revision,
        ),
        throwsStateError,
      );
    },
  );

  test('stale lifecycle commands never overwrite newer set edits', () {
    final s = startQuick();
    engine.pauseWorkout(s.uuid, expectedRevision: s.revision);
    final paused = sessions.getSession(s.uuid)!;
    expect(
      () => engine.discardWorkout(s.uuid, expectedRevision: s.revision),
      throwsA(isA<WorkoutRevisionConflict>()),
    );
    expect(
      () => engine.finishWorkout(
        s.uuid,
        expectedRevision: s.revision,
        finishedAtUtc: finished,
      ),
      throwsA(isA<WorkoutRevisionConflict>()),
    );
    expect(sessions.getSession(s.uuid)!.status, WorkoutStatus.paused);
    expect(sessions.getSession(s.uuid)!.revision, paused.revision);
    expect(engine.readCheckpoint(s.uuid), isNotNull);
  });

  test('plan renames and soft archives cannot rewrite session snapshots', () {
    makePlan();
    final s = engine.startWorkout(
      sessionUuid: 'session-a',
      planUuid: 'plan-a',
      startedAtUtc: started,
      originalOffsetMinutes: 330,
    );
    final plan = library.getPlan('plan-a')!;
    library.savePlan(
      uuid: 'plan-a',
      name: 'Renamed plan',
      description: '',
      expectedUpdatedAtMs: plan.updatedAtMs,
      exercises: plan.exercises,
    );
    library.archivePlan(
      'plan-a',
      expectedUpdatedAtMs: library.getPlan('plan-a')!.updatedAtMs,
    );
    final snapshot = sessions.getSession(s.uuid)!;
    expect(snapshot.name, 'Upper day');
    expect(snapshot.exercises.first.nameSnapshot, 'Barbell bench press');
    expect(snapshot.sets, hasLength(5));
    expect(
      () => engine.startWorkout(
        sessionUuid: 'another',
        planUuid: 'plan-a',
        startedAtUtc: started,
        originalOffsetMinutes: 330,
      ),
      throwsStateError,
    );
  });

  test(
    'failed generated exercise UUID collision rolls back session and children',
    () {
      makePlan();
      final badEngine = ObjectBoxLiveWorkoutEngine(
        store,
        uuidFactory: SequenceUuids([
          'same-uuid',
          'set-0',
          'set-1',
          'set-2',
          'same-uuid',
        ]),
      );
      expect(
        () => badEngine.startWorkout(
          sessionUuid: 'bad',
          planUuid: 'plan-a',
          startedAtUtc: started,
          originalOffsetMinutes: 330,
        ),
        throwsA(isA<UniqueViolationException>()),
      );
      expect(store.box<WorkoutSessionEntity>().count(), 0);
      expect(store.box<WorkoutExerciseEntity>().count(), 0);
      expect(store.box<WorkoutSetEntity>().count(), 0);
      expect(store.box<WorkoutSessionStateEntity>().count(), 0);
    },
  );

  test(
    'invalid source plan and invalid quick start leave no ghost sessions',
    () {
      expect(
        () => engine.startWorkout(
          sessionUuid: 'ghost',
          planUuid: 'missing',
          startedAtUtc: started,
          originalOffsetMinutes: 330,
        ),
        throwsStateError,
      );
      expect(
        () => engine.startWorkout(
          sessionUuid: 'bad',
          quickName: ' ',
          startedAtUtc: started,
          originalOffsetMinutes: 330,
        ),
        throwsArgumentError,
      );
      expect(
        () => engine.startWorkout(
          sessionUuid: 'both',
          quickName: 'Quick',
          planUuid: 'plan-a',
          startedAtUtc: started,
          originalOffsetMinutes: 330,
        ),
        throwsArgumentError,
      );
      expect(store.box<WorkoutSessionEntity>().count(), 0);
    },
  );

  test(
    'missing checkpoint makes transitions fail closed without status mutation',
    () {
      final s = startQuick();
      final checkpoints = store.box<WorkoutSessionStateEntity>();
      checkpoints.remove(checkpoints.getAll().single.id);
      expect(
        () => engine.pauseWorkout(s.uuid, expectedRevision: s.revision),
        throwsStateError,
      );
      expect(
        () => engine.finishWorkout(
          s.uuid,
          expectedRevision: s.revision,
          finishedAtUtc: finished,
        ),
        throwsStateError,
      );
      expect(sessions.getSession(s.uuid)!.status, WorkoutStatus.inProgress);
      expect(sessions.getSession(s.uuid)!.revision, s.revision);
      expect(() => engine.recoverActiveWorkout(), throwsStateError);
    },
  );

  test(
    'unknown unfinished status blocks new starts without guessing state',
    () {
      final s = startQuick();
      final box = store.box<WorkoutSessionEntity>();
      final entity = box.getAll().single;
      entity.status = 'future_live_state';
      box.put(entity);
      expect(() => engine.recoverActiveWorkout(), throwsStateError);
      expect(() => startQuick(id: 'second'), throwsStateError);
      expect(sessions.getSession(s.uuid)!.status, WorkoutStatus.unknown);
      expect(store.box<WorkoutSessionEntity>().count(), 1);
    },
  );

  test(
    'start collision with existing workout UUID never mutates first workout',
    () {
      final original = startQuick();
      expect(
        () => engine.startWorkout(
          sessionUuid: original.uuid,
          quickName: 'Different name',
          startedAtUtc: started,
          originalOffsetMinutes: 330,
        ),
        throwsStateError,
      );
      expect(
        () => engine.startWorkout(
          sessionUuid: original.uuid,
          quickName: 'Quick strength',
          startedAtUtc: started,
          originalOffsetMinutes: 0,
        ),
        throwsStateError,
      );
      expect(sessions.getSession(original.uuid)!.revision, original.revision);
      expect(store.box<WorkoutSessionStateEntity>().count(), 1);
    },
  );

  test('a set/edit revision cannot masquerade as a successful resume', () {
    final s = startQuick();
    sessions.addExercise(
      const WorkoutExerciseRecord(
        uuid: 'new-exercise',
        sessionUuid: 'quick-1',
        nameSnapshot: 'Squat',
        position: 0,
      ),
    );
    final edited = sessions.getSession(s.uuid)!;
    expect(edited.revision, s.revision + 1);
    expect(
      () => engine.resumeWorkout(s.uuid, expectedRevision: s.revision),
      throwsA(isA<WorkoutRevisionConflict>()),
    );
    expect(sessions.getSession(s.uuid)!.status, WorkoutStatus.inProgress);
    expect(sessions.getSession(s.uuid)!.revision, edited.revision);
  });

  test('an edit during pause cannot be acknowledged as a repeated pause', () {
    final started = startQuick();
    final paused = engine.pauseWorkout(
      started.uuid,
      expectedRevision: started.revision,
    );
    sessions.addExercise(
      const WorkoutExerciseRecord(
        uuid: 'new-exercise',
        sessionUuid: 'quick-1',
        nameSnapshot: 'Squat',
        position: 0,
      ),
    );
    final edited = sessions.getSession(started.uuid)!;
    expect(edited.status, WorkoutStatus.paused);
    expect(edited.revision, paused.revision + 1);
    expect(
      () =>
          engine.pauseWorkout(started.uuid, expectedRevision: paused.revision),
      throwsA(isA<WorkoutRevisionConflict>()),
    );
    expect(sessions.getSession(started.uuid)!.revision, edited.revision);
  });

  test('recovery rejects a checkpoint from the wrong revision', () {
    final workout = startQuick();
    final state = store.box<WorkoutSessionStateEntity>();
    final row = state.getAll().single;
    row.checkpointRevision = workout.revision + 1;
    state.put(row);
    expect(() => engine.recoverActiveWorkout(), throwsStateError);
    expect(
      () =>
          engine.pauseWorkout(workout.uuid, expectedRevision: workout.revision),
      throwsStateError,
    );
    expect(sessions.getSession(workout.uuid)!.status, WorkoutStatus.inProgress);
  });

  test('empty plan creates a recoverable session with no exercises', () {
    library.savePlan(
      uuid: 'empty-plan',
      name: 'My empty plan',
      description: '',
      exercises: const [],
    );
    final s = engine.startWorkout(
      sessionUuid: 'session-empty',
      planUuid: 'empty-plan',
      startedAtUtc: started,
      originalOffsetMinutes: 330,
    );
    expect(s.exercises, isEmpty);
    expect(s.sets, isEmpty);
    expect(engine.recoverActiveWorkout()!.uuid, s.uuid);
    expect(engine.readCheckpoint(s.uuid)!.selectedExerciseUuid, isNull);
  });

  test(
    'renaming and archiving exercise definition leaves session snapshots',
    () {
      library.saveCustomExercise(
        uuid: 'custom-row',
        name: 'Home cable row',
        muscleGroup: 'Back',
        equipment: 'Cable',
      );
      library.savePlan(
        uuid: 'custom-plan',
        name: 'Upper',
        description: '',
        exercises: const [
          PlanExerciseRecord(
            uuid: 'custom-item',
            exerciseUuid: 'custom-row',
            position: 0,
            targetSets: 2,
          ),
        ],
      );
      final s = engine.startWorkout(
        sessionUuid: 'session-custom',
        planUuid: 'custom-plan',
        startedAtUtc: started,
        originalOffsetMinutes: 330,
      );
      final custom = library.listExercises().singleWhere(
        (e) => e.uuid == 'custom-row',
      );
      library.saveCustomExercise(
        uuid: custom.uuid,
        name: 'Renamed cable row',
        muscleGroup: 'Upper back',
        equipment: 'Resistance band',
        expectedUpdatedAtMs: custom.updatedAtMs,
      );
      library.archiveCustomExercise('custom-row');

      // Test the snapshot after a real native Store close/reopen, not just
      // in the current process's in-memory object graph.
      store.close();
      store = Store(getObjectBoxModel(), directory: directory.path);
      sessions = ObjectBoxWorkoutRepository(store);
      library = ObjectBoxWorkoutLibraryRepository(store);
      engine = ObjectBoxLiveWorkoutEngine(store);

      final savedExercise = sessions.getSession(s.uuid)!.exercises.single;
      expect(savedExercise.nameSnapshot, 'Home cable row');
      expect(savedExercise.muscleSnapshot, 'Back');
      expect(savedExercise.equipmentSnapshot, 'Cable');
      expect(sessions.getSession(s.uuid)!.sets.length, 2);
      final renamed = library
          .listExercises(includeArchived: true)
          .singleWhere((exercise) => exercise.uuid == 'custom-row');
      expect(renamed.name, 'Renamed cable row');
      expect(renamed.muscleGroup, 'Upper back');
      expect(renamed.equipment, 'Resistance band');
      expect(renamed.archivedAtMs, isNotNull);
    },
  );

  test('plan replay with quickName is invalid and cannot mutate session', () {
    makePlan();
    final s = engine.startWorkout(
      sessionUuid: 'session-a',
      planUuid: 'plan-a',
      startedAtUtc: started,
      originalOffsetMinutes: 330,
    );
    expect(
      () => engine.startWorkout(
        sessionUuid: 'session-a',
        planUuid: 'plan-a',
        quickName: 'Another name',
        startedAtUtc: started,
        originalOffsetMinutes: 330,
      ),
      throwsArgumentError,
    );
    expect(sessions.getSession(s.uuid)!.name, 'Upper day');
    expect(store.box<WorkoutSessionEntity>().count(), 1);
  });
}
