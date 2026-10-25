// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/ids/uuid_factory.dart';
import 'package:northstar_health/core/units/load_units.dart';
import 'package:northstar_health/features/workouts/data/objectbox_live_workout_engine.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_repository.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/features/workouts/domain/workout_models.dart';
import 'package:northstar_health/objectbox.g.dart';

import 'fixtures/objectbox_pre_outbox.g.dart' as pre_outbox;

const workoutId = '00000000-0000-4000-8000-000000000101';
const exerciseId = '00000000-0000-4000-8000-000000000201';
const setId = '00000000-0000-4000-8000-000000000301';
const operationId = '00000000-0000-4000-8000-000000000401';

class SingleUuid implements UuidFactory {
  @override
  String newId() => operationId;
}

void main() {
  late Directory directory;
  late Store store;
  late ObjectBoxWorkoutOutbox outbox;
  late ObjectBoxLiveWorkoutEngine engine;
  late ObjectBoxWorkoutRepository repository;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('northstar-outbox-');
    store = Store(getObjectBoxModel(), directory: directory.path);
    outbox = ObjectBoxWorkoutOutbox(store, uuidFactory: SingleUuid());
    engine = ObjectBoxLiveWorkoutEngine(store, outbox: outbox);
    repository = ObjectBoxWorkoutRepository(store);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  WorkoutSessionRecord begin({String id = workoutId}) {
    final started = engine.startWorkout(
      sessionUuid: id,
      quickName: 'Morning training',
      startedAtUtc: DateTime.utc(2026, 10, 25, 9),
      originalOffsetMinutes: 330,
    );
    repository.addExercise(
      WorkoutExerciseRecord(
        uuid: exerciseId,
        sessionUuid: id,
        nameSnapshot: 'Seated row',
        position: 0,
      ),
    );
    return repository.getSession(started.uuid)!;
  }

  WorkoutSessionRecord withSet() {
    final active = begin();
    repository.saveSet(
      sessionUuid: active.uuid,
      expectedRevision: active.revision,
      set: WorkoutSetRecord(
        uuid: setId,
        exerciseUuid: exerciseId,
        position: 0,
        kind: WorkoutSetKind.working,
        status: WorkoutSetStatus.completed,
        reps: 8,
        loadGrams: 60000,
        inputUnit: LoadUnit.kg,
        completedAtUtc: DateTime.utc(2026, 10, 25, 9, 15),
      ),
    );
    return repository.getSession(active.uuid)!;
  }

  test('only completed phone workout gets exact server DTO in same commit', () {
    final active = withSet();
    expect(outbox.pending(), isEmpty);
    engine.pauseWorkout(active.uuid, expectedRevision: active.revision);
    expect(outbox.pending(), isEmpty);
    final paused = repository.getSession(active.uuid)!;
    engine.finishWorkout(
      workoutId,
      expectedRevision: paused.revision,
      finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    final queued = outbox.pending();
    expect(queued, hasLength(1));
    final op = queued.single;
    expect(op.operationUuid, operationId);
    expect(op.localRevision, repository.getSession(workoutId)!.revision);
    final dto = jsonDecode(op.payloadJson) as Map<String, dynamic>;
    expect(
      dto.keys,
      containsAll([
        'schema_version',
        'workout_id',
        'origin',
        'status',
        'started_at_utc',
        'completed_at_utc',
        'exercises',
      ]),
    );
    expect(dto['status'], 'completed');
    expect(dto['origin'], 'northstar_phone');
    expect(dto['workout_id'], workoutId);
    final exercises = dto['exercises'] as List<dynamic>;
    final sets =
        (exercises.single as Map<String, dynamic>)['sets'] as List<dynamic>;
    expect((sets.single as Map<String, dynamic>)['load_grams'], 60000);
    expect(op.payloadJson, isNot(contains('restDeadline')));
  });

  test(
    'restart preserves operation UUID and unchanged replay is idempotent',
    () {
      final active = withSet();
      final finishedAt = DateTime.utc(2026, 10, 25, 10);
      engine.finishWorkout(
        workoutId,
        expectedRevision: active.revision,
        finishedAtUtc: finishedAt,
      );
      final first = outbox.pending().single;
      engine.finishWorkout(
        workoutId,
        expectedRevision: active.revision,
        finishedAtUtc: finishedAt,
      );
      expect(outbox.pending(), hasLength(1));
      store.close();
      store = Store(getObjectBoxModel(), directory: directory.path);
      outbox = ObjectBoxWorkoutOutbox(store, uuidFactory: SingleUuid());
      expect(outbox.pending().single.operationUuid, first.operationUuid);
      expect(outbox.pending().single.payloadJson, first.payloadJson);
      expect(
        outbox.acknowledge(
          operationUuid: operationId,
          localRevision: first.localRevision + 1,
          serverRevision: 1,
          serverChangeSeq: 1,
        ),
        false,
      );
      expect(outbox.pending(), hasLength(1));
      expect(
        outbox.acknowledge(
          operationUuid: operationId,
          localRevision: first.localRevision,
          serverRevision: 1,
          serverChangeSeq: 1,
        ),
        true,
      );
      expect(outbox.pending(), isEmpty);
      expect(
        outbox.acknowledge(
          operationUuid: operationId,
          localRevision: first.localRevision,
          serverRevision: 1,
          serverChangeSeq: 1,
        ),
        true,
      );
    },
  );

  test('discard never enqueues an unfinished phone workout', () {
    final active = withSet();
    engine.discardWorkout(workoutId, expectedRevision: active.revision);
    expect(outbox.pending(), isEmpty);
    expect(repository.getSession(workoutId)!.status, WorkoutStatus.discarded);
  });

  test('invalid cloud DTO never prevents finishing an offline workout', () {
    final active = begin(id: 'legacy-non-uuid');
    engine.finishWorkout(
      active.uuid,
      expectedRevision: active.revision,
      finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    expect(repository.getSession(active.uuid)!.status, WorkoutStatus.completed);
    expect(engine.readCheckpoint(active.uuid), isNull);
    expect(outbox.pending(), isEmpty);
    expect(outbox.blockedCount(), 1);
    expect(outbox.isBlocked(active.uuid), true);
  });

  test('server rejects early set timestamp locally without losing finish', () {
    final active = withSet();
    final set = store.box<WorkoutSetEntity>().getAll().single;
    set.completedAtMs = DateTime.utc(2026, 10, 25, 8).millisecondsSinceEpoch;
    store.box<WorkoutSetEntity>().put(set);
    engine.finishWorkout(
      active.uuid,
      expectedRevision: active.revision,
      finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    expect(repository.getSession(workoutId)!.status, WorkoutStatus.completed);
    expect(outbox.pending(), isEmpty);
    expect(outbox.blockedCount(), 1);
  });

  test(
    '160 emoji code points are valid; 161 are blocked without losing data',
    () {
      final active = withSet();
      final box = store.box<WorkoutExerciseEntity>();
      final exercise = box.getAll().single;
      exercise.nameSnapshot = '💪' * 160;
      box.put(exercise);
      engine.finishWorkout(
        active.uuid,
        expectedRevision: active.revision,
        finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
      );
      expect(outbox.pending(), hasLength(1));

      final otherDirectory = Directory.systemTemp.createTempSync('ns-unicode-');
      final other = Store(getObjectBoxModel(), directory: otherDirectory.path);
      try {
        final out = ObjectBoxWorkoutOutbox(other, uuidFactory: SingleUuid());
        final now = DateTime.utc(2026, 10, 25);
        other.box<WorkoutSessionEntity>().put(
          WorkoutSessionEntity(
            uuid: workoutId,
            name: 'Completed',
            status: 'completed',
            origin: 'northstar_phone',
            startedAtMs: now.millisecondsSinceEpoch,
            completedAtMs: now
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            originalOffsetMinutes: 330,
            updatedAtMs: now.millisecondsSinceEpoch,
          ),
        );
        other.box<WorkoutExerciseEntity>().put(
          WorkoutExerciseEntity(
            uuid: exerciseId,
            sessionUuid: workoutId,
            nameSnapshot: '💪' * 161,
            position: 0,
          ),
        );
        out.enqueueCompletedInTransaction(workoutId);
        expect(out.pending(), isEmpty);
        expect(out.blockedCount(), 1);
      } finally {
        other.close();
        otherDirectory.deleteSync(recursive: true);
      }
    },
  );

  test('server jsonb spacing margin rejects near-limit payloads', () {
    final active = begin();
    final box = store.box<WorkoutExerciseEntity>();
    // 86 emoji-heavy exercises form about 64.5 KiB compact JSON, but
    // PostgreSQL jsonb::text expands it past 64 KiB with whitespace.
    for (var i = 1; i < 86; i++) {
      box.put(
        WorkoutExerciseEntity(
          uuid:
              '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
          sessionUuid: workoutId,
          nameSnapshot: '🔥' * 160,
          position: i,
        ),
      );
    }
    final first = box.getAll().first;
    first.nameSnapshot = '🔥' * 160;
    box.put(first);
    engine.finishWorkout(
      active.uuid,
      expectedRevision: active.revision,
      finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    expect(repository.getSession(workoutId)!.status, WorkoutStatus.completed);
    expect(outbox.pending(), isEmpty);
    expect(outbox.blockedCount(), 1);
  });

  test('count limit rejects 121 exercises while preserving completed log', () {
    final active = begin();
    final box = store.box<WorkoutExerciseEntity>();
    for (var i = 1; i <= 120; i++) {
      box.put(
        WorkoutExerciseEntity(
          uuid:
              '00000000-0000-4000-9000-${i.toRadixString(16).padLeft(12, '0')}',
          sessionUuid: workoutId,
          nameSnapshot: 'Valid',
          position: i,
        ),
      );
    }
    engine.finishWorkout(
      active.uuid,
      expectedRevision: active.revision,
      finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    expect(outbox.pending(), isEmpty);
    expect(outbox.blockedCount(), 1);
  });

  test('direct outbox retry does not create duplicate operation', () {
    final active = withSet();
    engine.finishWorkout(
      workoutId,
      expectedRevision: active.revision,
      finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    final original = outbox.pending().single;
    store.runInTransaction(TxMode.write, () {
      outbox.enqueueCompletedInTransaction(workoutId);
    });
    expect(outbox.pending(), hasLength(1));
    expect(outbox.pending().single.operationUuid, original.operationUuid);
  });

  test('deprecated finishSession also enqueues atomically', () {
    final active = withSet();
    final legacy = ObjectBoxWorkoutRepository(store, outbox: outbox);
    legacy.finishSession(
      workoutId,
      expectedRevision: active.revision,
      finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    expect(outbox.pending(), hasLength(1));
  });

  test('bounded pending query filters blocked and acknowledged rows', () {
    final box = store.box<WorkoutSyncOutboxEntity>();
    for (var i = 1; i <= 150; i++) {
      box.put(
        WorkoutSyncOutboxEntity(
          operationUuid:
              '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
          sessionUuid: workoutId,
          localRevision: i,
          action: 'upsert',
          payloadJson: '{}',
          createdAtMs: i,
          state: i == 150 ? 'blocked' : 'pending',
        ),
      );
    }
    expect(outbox.pending(limit: 40), hasLength(40));
    expect(outbox.pending(), hasLength(100));
    expect(outbox.blockedCount(), 1);
    expect(() => outbox.pending(limit: 501), throwsArgumentError);
  });

  test('equal-timestamp operations are ordered before the batch limit', () {
    final box = store.box<WorkoutSyncOutboxEntity>();
    // Deliberately insert high revisions first. ObjectBox must order the
    // *query* rather than sorting an arbitrarily limited result afterward.
    for (final revision in [9, 5, 2, 1]) {
      box.put(
        WorkoutSyncOutboxEntity(
          operationUuid:
              '00000000-0000-4000-8000-${revision.toRadixString(16).padLeft(12, '0')}',
          sessionUuid: workoutId,
          localRevision: revision,
          action: 'upsert',
          payloadJson: '{}',
          createdAtMs: 123456789,
        ),
      );
    }
    expect(outbox.pending(limit: 1).single.localRevision, 1);
    expect(
      outbox.pending(limit: 2).map((e) => e.localRevision),
      orderedEquals([1, 2]),
    );
    expect(
      outbox.pending(limit: 4).map((e) => e.localRevision),
      orderedEquals([1, 2, 5, 9]),
    );
  });

  test('populated owner A/B stores remain isolated across reopen', () {
    final otherDirectory = Directory.systemTemp.createTempSync(
      'northstar-other-owner-',
    );
    try {
      final active = withSet();
      engine.finishWorkout(
        active.uuid,
        expectedRevision: active.revision,
        finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
      );
      var other = Store(getObjectBoxModel(), directory: otherDirectory.path);
      const otherWorkout = '00000000-0000-4000-8000-000000000102';
      const otherOperation = '00000000-0000-4000-8000-000000000402';
      final at = DateTime.utc(2026, 10, 25).millisecondsSinceEpoch;
      other.box<WorkoutSessionEntity>().put(
        WorkoutSessionEntity(
          uuid: otherWorkout,
          name: 'Account B only',
          status: 'completed',
          startedAtMs: at,
          completedAtMs: at + 3600000,
          originalOffsetMinutes: 330,
          updatedAtMs: at,
        ),
      );
      other.box<WorkoutSyncOutboxEntity>().put(
        WorkoutSyncOutboxEntity(
          operationUuid: otherOperation,
          sessionUuid: otherWorkout,
          localRevision: 1,
          action: 'upsert',
          payloadJson: '{}',
          createdAtMs: at,
        ),
      );
      expect(outbox.pending().single.sessionUuid, workoutId);
      expect(
        ObjectBoxWorkoutOutbox(other).pending().single.sessionUuid,
        otherWorkout,
      );
      other.close();
      other = Store(getObjectBoxModel(), directory: otherDirectory.path);
      try {
        expect(
          ObjectBoxWorkoutOutbox(other).pending().single.sessionUuid,
          otherWorkout,
        );
        expect(
          other.box<WorkoutSessionEntity>().getAll().single.uuid,
          otherWorkout,
        );
        expect(outbox.pending().single.sessionUuid, workoutId);
        expect(
          store.box<WorkoutSessionEntity>().getAll().single.uuid,
          workoutId,
        );
      } finally {
        other.close();
      }
    } finally {
      otherDirectory.deleteSync(recursive: true);
    }
  });

  test('301 sets are blocked without discarding the finished workout', () {
    final active = begin();
    final box = store.box<WorkoutSetEntity>();
    final now = DateTime.utc(2026, 10, 25, 9).millisecondsSinceEpoch;
    for (var i = 0; i <= 300; i++) {
      box.put(
        WorkoutSetEntity(
          uuid:
              '00000000-0000-4000-b000-${i.toRadixString(16).padLeft(12, '0')}',
          exerciseUuid: exerciseId,
          position: i,
          updatedAtMs: now,
        ),
      );
    }
    engine.finishWorkout(
      workoutId,
      expectedRevision: active.revision,
      finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    expect(repository.getSession(workoutId)!.status, WorkoutStatus.completed);
    expect(outbox.pending(), isEmpty);
    expect(outbox.blockedCount(), 1);
    expect(
      outbox.acknowledge(
        operationUuid: operationId,
        localRevision: repository.getSession(workoutId)!.revision,
        serverRevision: 1,
        serverChangeSeq: 1,
      ),
      false,
    );
  });

  test('case variant session UUID never bypasses outbox deduplication', () {
    const upper = '00000000-0000-4000-ABCD-000000000101';
    final active = begin(id: upper);
    engine.finishWorkout(
      upper,
      expectedRevision: active.revision,
      finishedAtUtc: DateTime.utc(2026, 10, 25, 10),
    );
    expect(outbox.pending(), hasLength(1));
    expect(outbox.pending().single.sessionUuid, upper.toLowerCase());
    store.runInTransaction(TxMode.write, () {
      outbox.enqueueCompletedInTransaction(upper);
    });
    expect(outbox.pending(), hasLength(1));
  });

  test('exact base (PR14) DB schema upgrades with unchanged IDs', () {
    final upgradeDir = Directory.systemTemp.createTempSync(
      'northstar-outbox-upgrade-',
    );
    try {
      final old = Store(
        pre_outbox.getObjectBoxModel(),
        directory: upgradeDir.path,
      );
      old.box<WorkoutSessionEntity>().put(
        WorkoutSessionEntity(
          uuid: workoutId,
          name: 'Prior session',
          status: 'completed',
          startedAtMs: DateTime.utc(2026, 10, 24, 9).millisecondsSinceEpoch,
          completedAtMs: DateTime.utc(2026, 10, 24, 10).millisecondsSinceEpoch,
          originalOffsetMinutes: 330,
          updatedAtMs: DateTime.utc(2026, 10, 24, 10).millisecondsSinceEpoch,
        ),
      );
      old.close();
      final upgraded = Store(getObjectBoxModel(), directory: upgradeDir.path);
      try {
        expect(upgraded.box<WorkoutSessionEntity>().count(), 1);
        expect(
          upgraded.box<WorkoutSessionEntity>().getAll().single.uuid,
          workoutId,
        );
        expect(upgraded.box<WorkoutSyncOutboxEntity>().count(), 0);
      } finally {
        upgraded.close();
      }
    } finally {
      upgradeDir.deleteSync(recursive: true);
    }
  });
}
