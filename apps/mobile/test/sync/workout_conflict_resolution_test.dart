import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/sync/objectbox_workout_restore_importer.dart';
import 'package:northstar_health/features/sync/workout_restore_feed.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/objectbox.g.dart';

import '../support/fake_account_auth.dart';

const workout = '00000000-0000-4000-8000-000000006701';
const epoch = '00000000-0000-4000-8000-000000006702';
const ex = '00000000-0000-4000-8000-000000006703';
const setId = '00000000-0000-4000-8000-000000006704';
final started = DateTime.utc(2026, 10, 26, 10).millisecondsSinceEpoch;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Store store;
  late ObjectBoxWorkoutOutbox outbox;
  late ObjectBoxWorkoutRestoreImporter importer;
  String activeOwner = accountA;

  void seed() {
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: workout,
        name: 'Local strength',
        status: 'completed',
        revision: 1,
        startedAtMs: started,
        completedAtMs: started + 3600000,
        originalOffsetMinutes: 330,
        updatedAtMs: started + 3600000,
      ),
    );
    store.box<WorkoutExerciseEntity>().put(
      WorkoutExerciseEntity(
        uuid: ex,
        sessionUuid: workout,
        position: 0,
        nameSnapshot: 'Row',
      ),
    );
    store.box<WorkoutSetEntity>().put(
      WorkoutSetEntity(
        uuid: setId,
        exerciseUuid: ex,
        position: 0,
        kind: 'working',
        status: 'completed',
        reps: 8,
        loadGrams: 30000,
        completedAtMs: started + 10000,
        updatedAtMs: started + 10000,
      ),
    );
  }

  WorkoutRemoteReview review({
    int revision = 3,
    int seq = 7,
    bool deleted = false,
    bool missing = false,
  }) => WorkoutRemoteReview(
    cursorEpoch: epoch,
    change: missing
        ? null
        : RemoteWorkoutChange(
            workoutId: workout,
            serverRevision: revision,
            changeSeq: seq,
            deleted: deleted,
            snapshot: deleted
                ? null
                : RemoteWorkoutSnapshot(
                    uuid: workout,
                    name: 'Cloud strength',
                    startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                      started,
                      isUtc: true,
                    ),
                    completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                      started + 3600000,
                      isUtc: true,
                    ),
                    originalOffsetMinutes: 330,
                    exercises: const [],
                    sets: const [],
                  ),
          ),
  );

  void conflict() {
    store.runInTransaction(TxMode.write, () {
      outbox.enqueueCompletedInTransaction(workout);
    });
    final op = outbox.pending().single;
    expect(
      outbox.markConflict(
        operationUuid: op.operationUuid,
        localRevision: op.localRevision,
      ),
      true,
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('northstar-recovery-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    outbox = ObjectBoxWorkoutOutbox(store);
    activeOwner = accountA;
    importer = ObjectBoxWorkoutRestoreImporter(
      store,
      accountId: accountA,
      activeAccountId: () => activeOwner,
    );
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'explicit cloud choice imports and supersedes terminal local upload',
    () {
      seed();
      conflict();
      final candidate = importer.readConflictCandidates().single;
      expect(candidate.localRevision, 1);
      expect(candidate.name, 'Local strength');
      importer.resolveReviewedWorkout(
        workoutUuid: workout,
        expectedLocalRevision: 1,
        review: review(),
        action: WorkoutResolutionAction.useCloud,
      );
      expect(importer.readConflictCandidates(), isEmpty);
      expect(
        store.box<WorkoutSessionEntity>().getAll().single.name,
        'Cloud strength',
      );
      expect(
        store.box<WorkoutSyncOutboxEntity>().getAll().single.state,
        'superseded',
      );
      expect(outbox.pending(), isEmpty);
      expect(outbox.reserveNext(nowMs: started + 10000000), isNull);
      // The point lookup was ahead of the shared restore cursor. Replay of the
      // identical change must advance the cursor, not block as a duplicate.
      importer.applyPage(
        WorkoutRestorePage(
          cursorEpoch: epoch,
          cursorReset: false,
          nextCursor: 7,
          hasMore: false,
          changes: [review().change!],
        ),
        afterSeq: 0,
        requestedEpoch: null,
      );
      expect(importer.readCursor().nextCursor, 7);
      expect(importer.readCursor().blockedCode, isNull);
    },
  );

  test('retry local requeues a new immutable op at fresh server CAS', () {
    seed();
    conflict();
    importer.resolveReviewedWorkout(
      workoutUuid: workout,
      expectedLocalRevision: 1,
      review: review(),
      action: WorkoutResolutionAction.retryLocal,
    );
    final records = store.box<WorkoutSyncOutboxEntity>().getAll()
      ..sort((a, b) => a.localRevision.compareTo(b.localRevision));
    expect(records.map((op) => op.state), ['superseded', 'pending']);
    expect(records.last.localRevision, 2);
    final reserved = outbox.reserveNext(nowMs: started + 10000000)!;
    expect(reserved.operation.localRevision, 2);
    expect(reserved.expectedServerRevision, 3);
    expect(importer.readConflictCandidates(), isEmpty);
    expect(
      outbox.acknowledge(
        operationUuid: reserved.operation.operationUuid,
        localRevision: 2,
        serverRevision: 4,
        serverChangeSeq: 8,
      ),
      true,
    );
    importer.applyPage(
      WorkoutRestorePage(
        cursorEpoch: epoch,
        cursorReset: false,
        nextCursor: 8,
        hasMore: false,
        changes: [review(revision: 4, seq: 8).change!],
      ),
      afterSeq: 0,
      requestedEpoch: null,
    );
    expect(importer.readCursor().blockedCode, isNull);
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.name,
      'Local strength',
    );
  });

  test('stale local optimistic revision refuses all writes', () {
    seed();
    conflict();
    expect(
      () => importer.resolveReviewedWorkout(
        workoutUuid: workout,
        expectedLocalRevision: 0,
        review: review(),
        action: WorkoutResolutionAction.useCloud,
      ),
      throwsA(isA<RestoreImportException>()),
    );
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.name,
      'Local strength',
    );
    expect(
      store.box<WorkoutSyncOutboxEntity>().getAll().single.state,
      'conflict',
    );
  });

  test('pending uncertain upload cannot be discarded by a server lookup', () {
    seed();
    store.runInTransaction(TxMode.write, () {
      outbox.enqueueCompletedInTransaction(workout);
    });
    // Force a durable skip, as if an older conflicting dependency exists.
    store.box<WorkoutRestoreSkipEntity>().put(
      WorkoutRestoreSkipEntity(
        workoutUuid: workout,
        ownerAccountId: accountA,
        serverChangeSeq: 7,
        cursorEpoch: epoch,
        skippedAtMs: started,
      ),
    );
    expect(
      () => importer.resolveReviewedWorkout(
        workoutUuid: workout,
        expectedLocalRevision: 1,
        review: review(),
        action: WorkoutResolutionAction.useCloud,
      ),
      throwsA(isA<RestoreImportException>()),
    );
    expect(outbox.pending(), hasLength(1));
    expect(store.box<WorkoutRestoreSkipEntity>().count(), 1);
  });

  test('remote tombstone is sticky: cannot retry upload', () {
    seed();
    conflict();
    expect(
      () => importer.resolveReviewedWorkout(
        workoutUuid: workout,
        expectedLocalRevision: 1,
        review: review(deleted: true),
        action: WorkoutResolutionAction.retryLocal,
      ),
      throwsA(isA<RestoreImportException>()),
    );
    importer.resolveReviewedWorkout(
      workoutUuid: workout,
      expectedLocalRevision: 1,
      review: review(deleted: true),
      action: WorkoutResolutionAction.useCloud,
    );
    expect(store.box<WorkoutExerciseEntity>().count(), 0);
    expect(store.box<WorkoutSetEntity>().count(), 0);
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.deletedAtMs,
      isNotNull,
    );
    expect(importer.readConflictCandidates(), isEmpty);
    expect(
      store.box<WorkoutSyncOutboxEntity>().getAll().single.payloadJson,
      'null',
    );
  });

  test('cloud missing may be retried as new upsert, not invented deletion', () {
    seed();
    conflict();
    importer.resolveReviewedWorkout(
      workoutUuid: workout,
      expectedLocalRevision: 1,
      review: review(missing: true),
      action: WorkoutResolutionAction.retryLocal,
    );
    expect(
      outbox.reserveNext(nowMs: started + 10000000)!.expectedServerRevision,
      0,
    );
  });

  test('pending deletion behind conflict rebases to server revision', () {
    seed();
    conflict();
    outbox.deleteCompletedWorkout(
      sessionUuid: workout,
      expectedLocalRevision: 1,
    );
    // Existing conflict makes delete dependency-paused, never sent.
    expect(outbox.reserveNext(nowMs: started + 10000000), isNull);
    final current = importer.readConflictCandidates().single;
    expect(current.deletedLocally, true);
    importer.resolveReviewedWorkout(
      workoutUuid: workout,
      expectedLocalRevision: current.localRevision,
      review: review(),
      action: WorkoutResolutionAction.finishDeletion,
    );
    final reserved = outbox.reserveNext(nowMs: started + 10000000)!;
    expect(reserved.operation.action, 'delete');
    expect(reserved.operation.payloadJson, 'null');
    expect(reserved.expectedServerRevision, 3);
    expect(outbox.pending().single.localRevision, 3);
    expect(importer.readConflictCandidates(), isEmpty);
  });


  test('a reviewed live cloud copy cannot resurrect an irreversible delete', () {
    seed();
    conflict();
    outbox.deleteCompletedWorkout(
      sessionUuid: workout,
      expectedLocalRevision: 1,
    );
    outbox.reserveNext(nowMs: started + 10000000);
    expect(
      () => importer.resolveReviewedWorkout(
        workoutUuid: workout,
        expectedLocalRevision: 2,
        review: review(),
        action: WorkoutResolutionAction.useCloud,
      ),
      throwsA(
        isA<RestoreImportException>().having(
          (error) => error.code,
          'code',
          'local_tombstone_sticky',
        ),
      ),
    );
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.deletedAtMs,
      isNotNull,
    );
    expect(store.box<WorkoutSyncOutboxEntity>().getAll().first.state,
        'conflict');
    expect(importer.readConflictCandidates().single.deletedLocally, true);
  });

  test(
    'deleted workout with absent server row resolves without network work',
    () {
      seed();
      conflict();
      outbox.deleteCompletedWorkout(
        sessionUuid: workout,
        expectedLocalRevision: 1,
      );
      outbox.reserveNext(nowMs: started + 10000000);
      importer.resolveReviewedWorkout(
        workoutUuid: workout,
        expectedLocalRevision: 2,
        review: review(missing: true),
        action: WorkoutResolutionAction.finishDeletion,
      );
      expect(outbox.pending(), isEmpty);
      expect(importer.readConflictCandidates(), isEmpty);
      expect(
        store.box<WorkoutSessionEntity>().getAll().single.deletedAtMs,
        isNotNull,
      );
    },
  );

  test('account switch prevents local mutation of reviewed server state', () {
    seed();
    conflict();
    activeOwner = accountB;
    expect(
      () => importer.resolveReviewedWorkout(
        workoutUuid: workout,
        expectedLocalRevision: 1,
        review: review(),
        action: WorkoutResolutionAction.useCloud,
      ),
      throwsA(isA<RestoreImportException>()),
    );
    expect(
      store.box<WorkoutSyncOutboxEntity>().getAll().single.state,
      'conflict',
    );
  });
}
