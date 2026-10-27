import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/objectbox.g.dart';

String uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Store store;
  late ObjectBoxWorkoutOutbox outbox;

  void reopen() {
    store.close();
    store = Store(getObjectBoxModel(), directory: dir.path);
    outbox = ObjectBoxWorkoutOutbox(store);
  }

  WorkoutSyncOutboxEntity operation({
    required int id,
    int? workout,
    int revision = 1,
    int? createdAtMs,
    String state = 'pending',
    String payload = '{}',
    int? attemptedAtMs,
    int attempts = 0,
  }) => WorkoutSyncOutboxEntity(
    operationUuid: uuid(id + 1000000),
    sessionUuid: uuid(workout ?? id),
    localRevision: revision,
    action: 'upsert',
    payloadJson: payload,
    createdAtMs: createdAtMs ?? id,
    state: state,
    attemptedAtMs: attemptedAtMs,
    attempts: attempts,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('northstar-upload-fair-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    outbox = ObjectBoxWorkoutOutbox(store);
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  test('eligible workout behind 500 cooling-down rows is not starved', () {
    final box = store.box<WorkoutSyncOutboxEntity>();
    box.putMany([
      for (var i = 1; i <= 500; i++)
        operation(id: i, attemptedAtMs: 1000, attempts: 1),
      operation(id: 501),
    ]);
    final reserved = outbox.reserveNext(nowMs: 2000);
    expect(reserved, isNotNull);
    expect(reserved!.operation.operationUuid, uuid(1000501));
    expect(reserved.expectedServerRevision, 0);
    expect(box.getAll().where((row) => row.attempts == 2), isEmpty);
    expect(box.getAll().where((row) => row.attempts == 1), hasLength(501));
  });

  test(
    'more than 500 dependency-paused rows cannot starve an independent edit',
    () {
      final box = store.box<WorkoutSyncOutboxEntity>();
      box.putMany([
        for (var i = 1; i <= 500; i++) ...[
          operation(id: 2 * i, workout: i, state: 'conflict'),
          operation(id: 2 * i + 1, workout: i, revision: 2),
        ],
        operation(id: 3001, workout: 3001),
      ]);
      final reserved = outbox.reserveNext(nowMs: 5000);
      expect(reserved, isNotNull);
      expect(reserved!.operation.sessionUuid, uuid(3001));
      final paused = box
          .getAll()
          .where((row) => row.state == 'dependency_paused')
          .toList();
      expect(paused, hasLength(500));
      expect(
        paused.every(
          (row) =>
              row.errorCode == 'predecessor_unresolved' &&
              row.attemptedAtMs == null &&
              row.attempts == 0,
        ),
        true,
      );
      expect(outbox.syncFlags()[uuid(1)], WorkoutSyncFlag.needsReview);
    },
  );

  test(
    'dependency pause survives restart and automatically resumes after ACK',
    () {
      final box = store.box<WorkoutSyncOutboxEntity>();
      box.putMany([
        operation(id: 1, workout: 42, state: 'conflict'),
        operation(id: 2, workout: 42, revision: 2),
      ]);
      expect(outbox.reserveNext(nowMs: 2000), isNull);
      expect(box.getAll().last.state, 'dependency_paused');
      reopen();
      final operations = store.box<WorkoutSyncOutboxEntity>();
      expect(outbox.reserveNext(nowMs: 2000), isNull);
      expect(operations.getAll().last.state, 'dependency_paused');
      // Simulate a later user-reviewed resolution; no automatic conflict
      // resolution or destructive local history rewrite is added by this PR.
      final first = operations.getAll().first;
      first.state = 'acknowledged';
      first.serverRevision = 7;
      first.serverChangeSeq = 10;
      operations.put(first);
      final eligible = outbox.reserveNext(nowMs: 2001);
      expect(eligible, isNotNull);
      expect(eligible!.operation.operationUuid, uuid(1000002));
      expect(eligible.expectedServerRevision, 7);
      final resumed = operations.getAll().last;
      expect(resumed.state, 'pending');
      expect(resumed.errorCode, isNull);
      expect(resumed.attempts, 1);
    },
  );

  test(
    'corrupt first 500 are blocked without skipping the shifted next row',
    () {
      final box = store.box<WorkoutSyncOutboxEntity>();
      box.putMany([
        for (var i = 1; i <= 500; i++) operation(id: i, payload: ''),
        operation(id: 501),
      ]);
      var notifications = 0;
      final reserved = outbox.reserveNext(
        nowMs: 5000,
        onBlocked: () => notifications++,
      );
      expect(reserved?.operation.operationUuid, uuid(1000501));
      expect(notifications, 1);
      expect(outbox.blockedCount(), 500);
      expect(
        box.getAll().where((row) => row.state == 'blocked'),
        hasLength(500),
      );
    },
  );

  test('higher acknowledged revision blocks lower pending without sending', () {
    final box = store.box<WorkoutSyncOutboxEntity>();
    box.putMany([
      operation(id: 1, workout: 40, revision: 1),
      operation(id: 2, workout: 40, revision: 2, state: 'acknowledged'),
    ]);
    expect(outbox.reserveNext(nowMs: 5000), isNull);
    final first = box.getAll().first;
    expect(first.state, 'blocked');
    expect(first.errorCode, 'later_revision_acknowledged');
    expect(first.attemptedAtMs, isNull);
    expect(first.attempts, 0);
  });

  test(
    'dependency pause does not increase retry count or clear local payload',
    () {
      final box = store.box<WorkoutSyncOutboxEntity>();
      box.putMany([
        operation(id: 1, workout: 40, state: 'blocked'),
        operation(
          id: 2,
          workout: 40,
          revision: 2,
          payload: '{"hello":"world"}',
        ),
      ]);
      for (var i = 0; i < 3; i++) {
        expect(outbox.reserveNext(nowMs: 1000 + i), isNull);
      }
      final child = box.getAll().last;
      expect(child.state, 'dependency_paused');
      expect(child.attempts, 0);
      expect(child.payloadJson, '{"hello":"world"}');
      expect(outbox.syncFlags()[uuid(40)], WorkoutSyncFlag.localOnly);
    },
  );

  test('ordered scan remains owner-isolated across two physical Stores', () {
    store.box<WorkoutSyncOutboxEntity>().put(operation(id: 1));
    final otherDir = Directory.systemTemp.createTempSync('northstar-fair-b-');
    final other = Store(getObjectBoxModel(), directory: otherDir.path);
    try {
      final otherOutbox = ObjectBoxWorkoutOutbox(other);
      other.box<WorkoutSyncOutboxEntity>().put(operation(id: 2));
      expect(
        outbox.reserveNext(nowMs: 100)?.operation.operationUuid,
        uuid(1000001),
      );
      expect(
        otherOutbox.reserveNext(nowMs: 100)?.operation.operationUuid,
        uuid(1000002),
      );
    } finally {
      other.close();
      otherDir.deleteSync(recursive: true);
    }
  });
}
