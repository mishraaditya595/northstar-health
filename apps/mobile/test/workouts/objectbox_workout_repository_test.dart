import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/units/load_units.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_repository.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';
import 'package:northstar_health/features/workouts/domain/workout_repository.dart';
import 'package:northstar_health/objectbox.g.dart';

void main() {
  late Directory directory;
  late Store store;
  late ObjectBoxWorkoutRepository repository;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('northstar-objectbox-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    repository = ObjectBoxWorkoutRepository(store);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  WorkoutSetRecord makeSet({
    String uuid = 'set-1',
    String exerciseId = 'exercise-1',
    int reps = 5,
    int? grams = 80000,
    int position = 0,
    WorkoutSetStatus status = WorkoutSetStatus.completed,
    DateTime? completedAtUtc,
  }) => WorkoutSetRecord(
    uuid: uuid,
    exerciseUuid: exerciseId,
    position: position,
    kind: WorkoutSetKind.working,
    status: status,
    reps: reps,
    loadGrams: grams,
    inputUnit: LoadUnit.kg,
    completedAtUtc: completedAtUtc ?? DateTime.utc(2026, 10, 24, 10),
  );

  WorkoutSessionRecord start({
    String id = 'session-1',
    String exerciseId = 'exercise-1',
  }) {
    repository.createSession(
      uuid: id,
      name: 'Morning strength',
      startedAtUtc: DateTime.utc(2026, 10, 24, 9),
      originalOffsetMinutes: 330,
    );
    repository.addExercise(
      WorkoutExerciseRecord(
        uuid: exerciseId,
        sessionUuid: id,
        nameSnapshot: 'Bench press',
        position: 0,
      ),
    );
    return repository.getSession(id)!;
  }

  test(
    'native DB reopens with all acknowledged sets, nulls and units intact',
    () {
      final first = start();
      final nullable = WorkoutSetRecord(
        uuid: 'set-1',
        exerciseUuid: 'exercise-1',
        position: 0,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.planned,
        inputUnit: LoadUnit.lb,
      );
      repository.saveSet(
        sessionUuid: first.uuid,
        set: nullable,
        expectedRevision: first.revision,
      );
      final revision = repository.getSession('session-1')!.revision;
      store.close();
      store = Store(getObjectBoxModel(), directory: directory.path);
      repository = ObjectBoxWorkoutRepository(store);

      final restored = repository.getSession('session-1')!;
      expect(restored.startedAtUtc, DateTime.utc(2026, 10, 24, 9));
      expect(restored.originalOffsetMinutes, 330);
      expect(restored.revision, revision);
      expect(restored.exercises.single.nameSnapshot, 'Bench press');
      final set = restored.sets.single;
      expect(set.reps, isNull);
      expect(set.loadGrams, isNull);
      expect(set.rpe, isNull);
      expect(set.completedAtUtc, isNull);
      expect(set.inputUnit, LoadUnit.lb);
      expect(set.status, WorkoutSetStatus.planned);
    },
  );

  test('identical save retry is a no-op and stale edit cannot overwrite newer reps', () {
    final active = start();
    final first = makeSet();
    repository.saveSet(
      sessionUuid: active.uuid,
      set: first,
      expectedRevision: active.revision,
    );
    final nextRev = repository.getSession(active.uuid)!.revision;
    repository.saveSet(
      sessionUuid: active.uuid,
      set: first,
      expectedRevision: active.revision,
    );
    expect(repository.getSession(active.uuid)!.revision, nextRev);

    final revised = makeSet(reps: 6);
    repository.saveSet(
      sessionUuid: active.uuid,
      set: revised,
      expectedRevision: nextRev,
    );
    final savedRev = repository.getSession(active.uuid)!.revision;
    expect(
      () => repository.saveSet(
        sessionUuid: active.uuid,
        set: makeSet(reps: 5),
        expectedRevision: nextRev,
      ),
      throwsA(isA<WorkoutRevisionConflict>()),
    );
    final finalState = repository.getSession(active.uuid)!;
    expect(finalState.sets.single.reps, 6);
    expect(finalState.revision, savedRev);
  });

  test('missing checkpoint rolls back set insert and session revision', () {
    final active = start();
    final state = store.box<WorkoutSessionStateEntity>();
    final checkpoint = state.getAll().single;
    state.remove(checkpoint.id);
    expect(
      () => repository.saveSet(
        sessionUuid: active.uuid,
        set: makeSet(),
        expectedRevision: active.revision,
      ),
      throwsStateError,
    );
    expect(store.box<WorkoutSetEntity>().count(), 0);
    expect(repository.getSession(active.uuid)!.revision, active.revision);
  });

  test(
    'foreign exercise, occupied positions and invalid input do not write',
    () {
      final first = start();
      // With the single-active invariant, finish A before starting B.
      repository.finishSession(
        first.uuid, finishedAtUtc: DateTime.utc(2026, 10, 24, 10),
      );
      final second = start(id: 'session-2', exerciseId: 'exercise-2');
      expect(
        () => repository.saveSet(
          sessionUuid: second.uuid,
          set: makeSet(exerciseId: 'exercise-1'),
          expectedRevision: second.revision,
        ),
        throwsStateError,
      );
      expect(
        () => repository.addExercise(
          const WorkoutExerciseRecord(
            uuid: 'exercise-3',
            sessionUuid: 'session-2',
            nameSnapshot: 'Another press',
            position: 0,
          ),
        ),
        throwsStateError,
      );
      expect(
        () => repository.saveSet(
          sessionUuid: second.uuid,
          set: makeSet(reps: -1, exerciseId: 'exercise-2'),
          expectedRevision: second.revision,
        ),
        throwsArgumentError,
      );
      expect(repository.getSession(first.uuid)!.sets, isEmpty);
      expect(repository.getSession(second.uuid)!.sets, isEmpty);
    },
  );

  test('position collision is rejected for distinct set UUIDs', () {
    final active = start();
    repository.saveSet(
      sessionUuid: active.uuid,
      set: makeSet(),
      expectedRevision: active.revision,
    );
    final next = repository.getSession(active.uuid)!;
    expect(
      () => repository.saveSet(
        sessionUuid: active.uuid,
        set: makeSet(uuid: 'set-2'),
        expectedRevision: next.revision,
      ),
      throwsStateError,
    );
    expect(repository.getSession(active.uuid)!.sets, hasLength(1));
  });

  test('create/exercise/finish exact repeated commands are idempotent', () {
    final first = start();
    final originalRevision = first.revision;
    repository.createSession(
      uuid: first.uuid,
      name: first.name,
      startedAtUtc: first.startedAtUtc,
      originalOffsetMinutes: first.originalOffsetMinutes,
    );
    repository.addExercise(
      const WorkoutExerciseRecord(
        uuid: 'exercise-1',
        sessionUuid: 'session-1',
        nameSnapshot: 'Bench press',
        position: 0,
      ),
    );
    expect(repository.getSession(first.uuid)!.revision, originalRevision);
    final finishedAt = DateTime.utc(2026, 10, 24, 11);
    repository.finishSession(first.uuid, finishedAtUtc: finishedAt);
    final completeRev = repository.getSession(first.uuid)!.revision;
    repository.finishSession(first.uuid, finishedAtUtc: finishedAt);
    expect(repository.getSession(first.uuid)!.revision, completeRev);
    expect(repository.getSession(first.uuid)!.status, WorkoutStatus.completed);
    expect(
      () => repository.saveSet(
        sessionUuid: first.uuid,
        set: makeSet(),
        expectedRevision: completeRev,
      ),
      throwsStateError,
    );
  });

  test('soft-deleted and unknown status sessions are read-only', () {
    final active = start();
    final sessions = store.box<WorkoutSessionEntity>();
    final item = sessions.getAll().single;
    item.status = 'future_recording_status';
    sessions.put(item);
    expect(repository.getSession(active.uuid)!.status, WorkoutStatus.unknown);
    expect(
      () => repository.addExercise(
        const WorkoutExerciseRecord(
          uuid: 'extra',
          sessionUuid: 'session-1',
          nameSnapshot: 'Row',
          position: 1,
        ),
      ),
      throwsStateError,
    );
    item.status = WorkoutStatus.inProgress.name;
    item.deletedAtMs = DateTime.utc(2026, 10, 24).millisecondsSinceEpoch;
    sessions.put(item);
    expect(repository.getSession(active.uuid), isNull);
    expect(
      () => repository.saveSet(
        sessionUuid: active.uuid,
        set: makeSet(),
        expectedRevision: active.revision,
      ),
      throwsStateError,
    );
    expect(
      () => repository.finishSession(
        active.uuid,
        finishedAtUtc: DateTime.utc(2026, 10, 24, 11),
      ),
      throwsStateError,
    );
  });

  test(
    'future set status/kind/unit is represented, never crashes a session read',
    () {
      final active = start();
      repository.saveSet(
        sessionUuid: active.uuid,
        set: makeSet(),
        expectedRevision: active.revision,
      );
      final box = store.box<WorkoutSetEntity>();
      final entity = box.getAll().single;
      entity.kind = 'experimental_kind';
      entity.status = 'future_status';
      entity.inputUnit = 'stones';
      box.put(entity);
      final reloaded = repository.getSession(active.uuid)!;
      expect(reloaded.sets.single.kind, WorkoutSetKind.unknown);
      expect(reloaded.sets.single.status, WorkoutSetStatus.unknown);
      expect(reloaded.sets.single.inputUnit, LoadUnit.unknown);
      expect(
        () => repository.saveSet(
          sessionUuid: active.uuid,
          set: reloaded.sets.single,
          expectedRevision: reloaded.revision,
        ),
        throwsArgumentError,
      );
    },
  );
}
