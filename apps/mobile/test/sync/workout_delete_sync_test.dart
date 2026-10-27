import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/ids/uuid_factory.dart';
import 'package:northstar_health/features/sync/objectbox_workout_restore_importer.dart';
import 'package:northstar_health/features/sync/workout_restore_feed.dart';
import 'package:northstar_health/features/sync/workout_restore_transport.dart';
import 'package:northstar_health/features/sync/workout_upload_coordinator.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/objectbox.g.dart';

import '../support/fake_account_auth.dart';

const workout = '00000000-0000-4000-8000-000000001101';
const exercise = '00000000-0000-4000-8000-000000001102';
const setId = '00000000-0000-4000-8000-000000001103';
const epoch = '00000000-0000-4000-8000-000000001104';

class InvalidUuid implements UuidFactory {
  @override
  String newId() => 'not-a-uuid';
}

class RecordingUpload implements WorkoutUploadTransport {
  final sent = <(String, String, int)>[];
  @override
  Future<Map<String, dynamic>> send(
    WorkoutSyncOperation operation, {
    required int expectedServerRevision,
  }) async {
    sent.add((operation.action, operation.payloadJson, expectedServerRevision));
    return {
      'result': 'applied',
      'revision': expectedServerRevision + 1,
      'change_seq': expectedServerRevision + 1,
      'replay': false,
      'processing': 'processed',
    };
  }
}

class TombstoneFeed implements WorkoutRestoreTransport {
  int calls = 0;
  @override
  Future<WorkoutRestorePage> fetchPage({
    required int afterSeq,
    required String? cursorEpoch,
    int limit = 100,
  }) async {
    calls++;
    return WorkoutRestorePage(
      cursorEpoch: epoch,
      cursorReset: false,
      nextCursor: 2,
      hasMore: false,
      changes: [
        RemoteWorkoutChange(
          workoutId: workout,
          serverRevision: 2,
          changeSeq: 2,
          deleted: true,
          snapshot: null,
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Store store;
  late ObjectBoxWorkoutOutbox outbox;

  final start = DateTime.utc(2026, 10, 26, 10).millisecondsSinceEpoch;
  final finish = DateTime.utc(2026, 10, 26, 11).millisecondsSinceEpoch;

  void seed({
    int revision = 1,
    String status = 'completed',
    String origin = 'northstar_phone',
  }) {
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: workout,
        name: 'Private session',
        status: status,
        origin: origin,
        revision: revision,
        startedAtMs: start,
        completedAtMs: status == 'completed' ? finish : null,
        originalOffsetMinutes: 330,
        updatedAtMs: finish,
      ),
    );
    store.box<WorkoutExerciseEntity>().put(
      WorkoutExerciseEntity(
        uuid: exercise,
        sessionUuid: workout,
        position: 0,
        nameSnapshot: 'Seated row',
      ),
    );
    store.box<WorkoutSetEntity>().put(
      WorkoutSetEntity(
        uuid: setId,
        exerciseUuid: exercise,
        position: 0,
        reps: 8,
        loadGrams: 45000,
        status: 'completed',
        completedAtMs: finish,
        updatedAtMs: finish,
      ),
    );
  }

  void reopen() {
    store.close();
    store = Store(getObjectBoxModel(), directory: dir.path);
    outbox = ObjectBoxWorkoutOutbox(store);
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('northstar-delete-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    outbox = ObjectBoxWorkoutOutbox(store);
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'delete commits minimal tombstone, child purge and null outbox atomically',
    () {
      seed();
      final when = DateTime.utc(2026, 10, 27);
      expect(
        outbox.deleteCompletedWorkout(
          sessionUuid: workout,
          expectedLocalRevision: 1,
          clock: () => when,
        ),
        true,
      );
      final local = store.box<WorkoutSessionEntity>().getAll().single;
      expect(local.revision, 2);
      expect(local.deletedAtMs, when.millisecondsSinceEpoch);
      expect(local.name, 'Deleted workout');
      expect(local.planUuid, null);
      expect(store.box<WorkoutExerciseEntity>().count(), 0);
      expect(store.box<WorkoutSetEntity>().count(), 0);
      final op = store.box<WorkoutSyncOutboxEntity>().getAll().single;
      expect(op.action, 'delete');
      expect(op.localRevision, 2);
      expect(op.payloadJson, 'null');
      expect(op.state, 'pending');
      expect(
        outbox
            .reserveNext(nowMs: when.millisecondsSinceEpoch + 1)!
            .expectedServerRevision,
        0,
      );
      expect(
        outbox.deleteCompletedWorkout(
          sessionUuid: workout,
          expectedLocalRevision: 1,
        ),
        false,
      );
      expect(store.box<WorkoutSyncOutboxEntity>().count(), 1);
      reopen();
      expect(
        store.box<WorkoutSessionEntity>().getAll().single.deletedAtMs,
        when.millisecondsSinceEpoch,
      );
      expect(outbox.pending().single.action, 'delete');
      expect(outbox.backfillCompleted(), 0);
    },
  );

  test('invalid UUID for queued delete rolls back all local writes', () {
    seed();
    final bad = ObjectBoxWorkoutOutbox(store, uuidFactory: InvalidUuid());
    expect(
      () => bad.deleteCompletedWorkout(
        sessionUuid: workout,
        expectedLocalRevision: 1,
      ),
      throwsStateError,
    );
    final local = store.box<WorkoutSessionEntity>().getAll().single;
    expect(local.deletedAtMs, isNull);
    expect(local.name, 'Private session');
    expect(local.revision, 1);
    expect(store.box<WorkoutExerciseEntity>().count(), 1);
    expect(store.box<WorkoutSetEntity>().count(), 1);
    expect(outbox.pending(), isEmpty);
  });

  test('stale revision, unfinished and nonphone deletion are rejected', () {
    seed(revision: 3);
    expect(
      () => outbox.deleteCompletedWorkout(
        sessionUuid: workout,
        expectedLocalRevision: 2,
      ),
      throwsStateError,
    );
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.deletedAtMs,
      isNull,
    );
    final sessions = store.box<WorkoutSessionEntity>();
    final unfinished = sessions.getAll().single;
    unfinished.status = 'inProgress';
    unfinished.completedAtMs = null;
    unfinished.revision = 1;
    sessions.put(unfinished);
    expect(
      () => outbox.deleteCompletedWorkout(
        sessionUuid: workout,
        expectedLocalRevision: 1,
      ),
      throwsStateError,
    );
    unfinished.status = 'completed';
    unfinished.completedAtMs = finish;
    unfinished.origin = 'external_platform';
    sessions.put(unfinished);
    expect(
      () => outbox.deleteCompletedWorkout(
        sessionUuid: workout,
        expectedLocalRevision: 1,
      ),
      throwsStateError,
    );
    expect(outbox.pending(), isEmpty);
  });

  test(
    'pending upsert always ACKs before delete; echo remains idempotent',
    () async {
      seed();
      store.runInTransaction(TxMode.write, () {
        outbox.enqueueCompletedInTransaction(workout);
      });
      final original = outbox.pending().single;
      expect(original.action, 'upsert');
      outbox.deleteCompletedWorkout(
        sessionUuid: workout,
        expectedLocalRevision: 1,
      );
      final api = FakeAuthApi()..sessionId = accountA;
      final bound = FakeBoundAccountStore()..saved = accountA;
      final auth = controller(api, bound);
      await auth.restore();
      final sender = RecordingUpload();
      final importer = ObjectBoxWorkoutRestoreImporter(
        store,
        accountId: accountA,
        activeAccountId: () => auth.userId,
      );
      final feed = TombstoneFeed();
      final worker = WorkoutUploadCoordinator(
        accountId: accountA,
        auth: auth,
        outbox: outbox,
        transport: sender,
        restoreTransport: feed,
        restoreImporter: importer,
      );
      try {
        await worker.drain();
        expect(sender.sent.map((r) => r.$1), ['upsert', 'delete']);
        expect(sender.sent.map((r) => r.$3), [0, 1]);
        expect(sender.sent.last.$2, 'null');
        expect(
          store.box<WorkoutSyncOutboxEntity>().getAll().every(
            (row) => row.state == 'acknowledged',
          ),
          true,
        );
        expect(feed.calls, 1);
        expect(importer.readCursor().nextCursor, 2);
        expect(importer.readCursor().blockedCode, isNull);
        expect(store.box<WorkoutSessionEntity>().getAll().single.revision, 2);
        expect(
          store.box<WorkoutSessionEntity>().getAll().single.deletedAtMs,
          isNotNull,
        );
        expect(outbox.backfillCompleted(), 0);
      } finally {
        worker.dispose();
        auth.dispose();
        await api.dispose();
      }
    },
  );

  test(
    'imported workout deletes using remote CAS; own tombstone does not block',
    () {
      final importer = ObjectBoxWorkoutRestoreImporter(
        store,
        accountId: accountA,
        activeAccountId: () => accountA,
      );
      final first = WorkoutRestorePage(
        cursorEpoch: epoch,
        cursorReset: false,
        nextCursor: 1,
        hasMore: false,
        changes: [
          RemoteWorkoutChange(
            workoutId: workout,
            serverRevision: 5,
            changeSeq: 1,
            deleted: false,
            snapshot: RemoteWorkoutSnapshot(
              uuid: workout,
              name: 'Original server workout',
              startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                start,
                isUtc: true,
              ),
              completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                finish,
                isUtc: true,
              ),
              originalOffsetMinutes: 330,
              exercises: const [],
              sets: const [],
            ),
          ),
        ],
      );
      importer.applyPage(first, afterSeq: 0, requestedEpoch: null);
      expect(
        outbox.deleteCompletedWorkout(
          sessionUuid: workout,
          expectedLocalRevision: 1,
        ),
        true,
      );
      final reserved = outbox.reserveNext(
        nowMs: DateTime.now().millisecondsSinceEpoch + 1,
      )!;
      expect(reserved.operation.action, 'delete');
      expect(reserved.expectedServerRevision, 5);
      expect(
        outbox.acknowledge(
          operationUuid: reserved.operation.operationUuid,
          localRevision: 2,
          serverRevision: 6,
          serverChangeSeq: 2,
        ),
        true,
      );
      final echo = WorkoutRestorePage(
        cursorEpoch: epoch,
        cursorReset: false,
        nextCursor: 2,
        hasMore: false,
        changes: [
          RemoteWorkoutChange(
            workoutId: workout,
            serverRevision: 6,
            changeSeq: 2,
            deleted: true,
            snapshot: null,
          ),
        ],
      );
      final result = importer.applyPage(
        echo,
        afterSeq: 1,
        requestedEpoch: epoch,
      );
      expect(result.tombstones, 1);
      expect(importer.readCursor().blockedCode, isNull);
      expect(store.box<WorkoutSessionEntity>().getAll().single.revision, 2);
      expect(
        store.box<WorkoutRemoteStateEntity>().getAll().single.deleted,
        true,
      );
      expect(outbox.backfillCompleted(), 0);
    },
  );

  test('remote tombstone deletes completed history on another device', () {
    seed();
    final importer = ObjectBoxWorkoutRestoreImporter(
      store,
      accountId: accountA,
      activeAccountId: () => accountA,
    );
    // Device B has already imported an earlier remote workout revision.
    store.box<WorkoutRemoteStateEntity>().put(
      WorkoutRemoteStateEntity(
        workoutUuid: workout,
        ownerAccountId: accountA,
        serverRevision: 1,
        serverChangeSeq: 1,
        cursorEpoch: epoch,
        localRevisionAtImport: 1,
      ),
    );
    final result = importer.applyPage(
      WorkoutRestorePage(
        cursorEpoch: epoch,
        cursorReset: false,
        nextCursor: 2,
        hasMore: false,
        changes: [
          RemoteWorkoutChange(
            workoutId: workout,
            serverRevision: 2,
            changeSeq: 2,
            deleted: true,
            snapshot: null,
          ),
        ],
      ),
      afterSeq: 0,
      requestedEpoch: null,
    );
    expect(result.tombstones, 1);
    final session = store.box<WorkoutSessionEntity>().getAll().single;
    expect(session.deletedAtMs, isNotNull);
    expect(session.name, 'Deleted workout');
    expect(store.box<WorkoutExerciseEntity>().count(), 0);
    expect(store.box<WorkoutSetEntity>().count(), 0);
    expect(store.box<WorkoutRemoteStateEntity>().getAll().single.deleted, true);
  });
}
