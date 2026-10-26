import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/sync/objectbox_workout_restore_importer.dart';
import 'package:northstar_health/features/sync/workout_restore_feed.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/objectbox.g.dart';

import '../workouts/fixtures/objectbox_pre_outbox.g.dart' as legacy;

const accountA = '00000000-0000-4000-8000-0000000000a1';
const accountB = '00000000-0000-4000-8000-0000000000b2';
const workout = '00000000-0000-4000-8000-000000000101';
const workoutB = '00000000-0000-4000-8000-000000000102';
const exercise = '00000000-0000-4000-8000-000000000201';
const setId = '00000000-0000-4000-8000-000000000301';
const epochA = '00000000-0000-4000-8000-000000000901';
const epochB = '00000000-0000-4000-8000-000000000902';

Map<String, dynamic> dto({String id = workout, String name = 'Rows'}) => {
  'schema_version': 1,
  'workout_id': id,
  'origin': 'northstar_phone',
  'status': 'completed',
  'name': name,
  'started_at_utc': '2026-10-25T05:00:00Z',
  'completed_at_utc': '2026-10-25T06:00:00Z',
  'original_offset_minutes': 330,
  'exercises': [
    {
      'id': exercise,
      'name': 'Seated row',
      'position': 0,
      'sets': [
        {
          'id': setId,
          'position': 0,
          'kind': 'working',
          'status': 'completed',
          'reps': 10,
          'load_grams': 60000,
          'input_unit': 'kg',
          'completed_at_utc': '2026-10-25T05:30:00Z',
        },
      ],
    },
  ],
};

WorkoutRestorePage feed({
  int after = 0,
  String? requestedEpoch,
  String epoch = epochA,
  int seq = 1,
  int revision = 1,
  String id = workout,
  String? name = 'Rows',
  bool tombstone = false,
  bool reset = false,
}) => WorkoutRestorePage.decode(
  {
    'schema_version': 1,
    'cursor_epoch': epoch,
    'cursor_reset': reset,
    'next_cursor': reset ? 0 : seq,
    'has_more': false,
    'changes': reset
        ? <Object>[]
        : [
            {
              'workout_id': id,
              'server_revision': revision,
              'change_seq': seq,
              'deleted': tombstone,
              'payload': tombstone ? null : dto(id: id, name: name!),
            },
          ],
  },
  afterSeq: after,
  requestedEpoch: requestedEpoch,
  limit: 100,
);

void main() {
  late Directory dir;
  late Store store;
  late String? activeOwner;
  late ObjectBoxWorkoutRestoreImporter importer;

  void bind() {
    importer = ObjectBoxWorkoutRestoreImporter(
      store,
      accountId: accountA,
      activeAccountId: () => activeOwner,
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('northstar-restore-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    activeOwner = accountA;
    bind();
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  test('atomically restores a completed log and cursor without uploading', () {
    final done = importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null);
    expect(done.imported, 1);
    expect(done.cursor.epoch, epochA);
    expect(done.cursor.nextCursor, 1);
    final session = store.box<WorkoutSessionEntity>().getAll().single;
    expect(session.uuid, workout);
    expect(session.revision, 1); // Local optimistic revision, not server CAS.
    expect(session.status, 'completed');
    expect(session.planUuid, isNull);
    expect(
      store.box<WorkoutExerciseEntity>().getAll().single.nameSnapshot,
      'Seated row',
    );
    final set = store.box<WorkoutSetEntity>().getAll().single;
    expect(set.reps, 10);
    expect(set.loadGrams, 60000);
    expect(set.rpe, isNull); // Missing is never treated as zero.
    final remote = store.box<WorkoutRemoteStateEntity>().getAll().single;
    expect(remote.serverRevision, 1);
    expect(remote.cursorEpoch, epochA);
    expect(remote.localRevisionAtImport, 1);
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 0);
    expect(ObjectBoxWorkoutOutbox(store).backfillCompleted(), 0);
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 0);
  });

  test('restart keeps imported rows, metadata and cursor; replay is no-op', () {
    final first = feed();
    importer.applyPage(first, afterSeq: 0, requestedEpoch: null);
    store.close();
    store = Store(getObjectBoxModel(), directory: dir.path);
    bind();
    expect(importer.readCursor().nextCursor, 1);
    expect(importer.readCursor().epoch, epochA);
    final replay = importer.applyPage(first, afterSeq: 0, requestedEpoch: null);
    expect(replay.alreadyApplied, true);
    expect(replay.imported, 0);
    expect(store.box<WorkoutSessionEntity>().count(), 1);
    expect(store.box<WorkoutExerciseEntity>().count(), 1);
    expect(store.box<WorkoutSetEntity>().count(), 1);
  });

  test('crash at last write rolls back every row and cursor', () {
    expect(
      () => importer.applyPage(
        feed(),
        afterSeq: 0,
        requestedEpoch: null,
        beforeCommitForTest: () => throw StateError('synthetic crash'),
      ),
      throwsStateError,
    );
    expect(store.box<WorkoutSessionEntity>().count(), 0);
    expect(store.box<WorkoutRemoteStateEntity>().count(), 0);
    expect(store.box<WorkoutRestoreCursorEntity>().count(), 0);
    expect(store.box<WorkoutExerciseEntity>().count(), 0);
    expect(store.box<WorkoutSetEntity>().count(), 0);
    expect(importer.readCursor().nextCursor, 0);
    expect(
      importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null).imported,
      1,
    );
  });

  test('unknown tombstone is durable but creates no phantom workout', () {
    final applied = importer.applyPage(
      feed(tombstone: true),
      afterSeq: 0,
      requestedEpoch: null,
    );
    expect(applied.tombstones, 1);
    expect(store.box<WorkoutSessionEntity>().count(), 0);
    final metadata = store.box<WorkoutRemoteStateEntity>().getAll().single;
    expect(metadata.deleted, true);
    expect(metadata.workoutUuid, workout);
    expect(importer.readCursor().nextCursor, 1);
    expect(
      () => importer.applyPage(
        feed(after: 1, requestedEpoch: epochA, seq: 2, revision: 2),
        afterSeq: 1,
        requestedEpoch: epochA,
      ),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'tombstone_resurrection',
        ),
      ),
    );
    expect(importer.readCursor().nextCursor, 1);
  });

  test('remote deletion soft-deletes an imported log with no re-upload', () {
    importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null);
    final response = importer.applyPage(
      feed(
        after: 1,
        requestedEpoch: epochA,
        seq: 2,
        revision: 2,
        tombstone: true,
      ),
      afterSeq: 1,
      requestedEpoch: epochA,
    );
    expect(response.tombstones, 1);
    final saved = store.box<WorkoutSessionEntity>().getAll().single;
    expect(saved.deletedAtMs, isNotNull);
    expect(saved.revision, 2);
    expect(store.box<WorkoutRemoteStateEntity>().getAll().single.deleted, true);
    expect(ObjectBoxWorkoutOutbox(store).backfillCompleted(), 0);
    expect(importer.readCursor().nextCursor, 2);
  });

  test('pending local outbox prevents overwrite and blocks same cursor', () {
    final time = DateTime.utc(2026, 10, 25, 5).millisecondsSinceEpoch;
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: workout,
        name: 'Preserve locally edited workout',
        status: 'completed',
        startedAtMs: time,
        completedAtMs: time + 3600000,
        originalOffsetMinutes: 330,
        updatedAtMs: time,
      ),
    );
    store.box<WorkoutSyncOutboxEntity>().put(
      WorkoutSyncOutboxEntity(
        operationUuid: '00000000-0000-4000-8000-000000000401',
        sessionUuid: workout,
        localRevision: 1,
        action: 'upsert',
        payloadJson: '{}',
        createdAtMs: time,
      ),
    );
    expect(
      () => importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'local_outbox_unresolved',
        ),
      ),
    );
    expect(importer.readCursor().nextCursor, 0);
    expect(importer.readCursor().blockedCode, 'local_outbox_unresolved');
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.name,
      'Preserve locally edited workout',
    );
    expect(store.box<WorkoutRemoteStateEntity>().count(), 0);
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 1);
  });

  test('existing untracked local session is never overwritten', () {
    final time = DateTime.utc(2026, 10, 25).millisecondsSinceEpoch;
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: workout,
        name: 'Local first',
        status: 'completed',
        startedAtMs: time,
        completedAtMs: time + 3600000,
        originalOffsetMinutes: 330,
        updatedAtMs: time,
      ),
    );
    expect(
      () => importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'untracked_local_workout',
        ),
      ),
    );
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.name,
      'Local first',
    );
    expect(importer.readCursor().blockedCode, 'untracked_local_workout');
  });

  test('acknowledged local version can reconcile newer server correction', () {
    final time = DateTime.utc(2026, 10, 25, 5).millisecondsSinceEpoch;
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: workout,
        name: 'Uploaded version',
        status: 'completed',
        revision: 5,
        startedAtMs: time,
        completedAtMs: time + 3600000,
        originalOffsetMinutes: 330,
        updatedAtMs: time,
      ),
    );
    store.box<WorkoutSyncOutboxEntity>().put(
      WorkoutSyncOutboxEntity(
        operationUuid: '00000000-0000-4000-8000-000000000402',
        sessionUuid: workout,
        localRevision: 5,
        action: 'upsert',
        state: 'acknowledged',
        payloadJson: '{}',
        serverRevision: 1,
        serverChangeSeq: 1,
        createdAtMs: time,
      ),
    );
    final applied = importer.applyPage(
      feed(revision: 2, name: 'Corrected remotely'),
      afterSeq: 0,
      requestedEpoch: null,
    );
    expect(applied.imported, 1);
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.name,
      'Corrected remotely',
    );
    expect(store.box<WorkoutSessionEntity>().getAll().single.revision, 6);
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 1);
    expect(
      store.box<WorkoutRemoteStateEntity>().getAll().single.serverRevision,
      2,
    );
  });

  test('changed local revision after import is a durable conflict', () {
    importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null);
    final existing = store.box<WorkoutSessionEntity>().getAll().single;
    existing.revision++;
    existing.name = 'Edited locally';
    store.box<WorkoutSessionEntity>().put(existing);
    expect(
      () => importer.applyPage(
        feed(after: 1, requestedEpoch: epochA, seq: 2, revision: 2),
        afterSeq: 1,
        requestedEpoch: epochA,
      ),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'local_revision_changed',
        ),
      ),
    );
    expect(importer.readCursor().nextCursor, 1);
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.name,
      'Edited locally',
    );
  });

  test('account switch rejects writes and owner store cross-use', () {
    activeOwner = accountB;
    expect(
      () => importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'account_changed',
        ),
      ),
    );
    expect(store.box<WorkoutRestoreCursorEntity>().count(), 0);
    activeOwner = accountA;
    importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null);
    final other = ObjectBoxWorkoutRestoreImporter(
      store,
      accountId: accountB,
      activeAccountId: () => accountB,
    );
    expect(
      () => other.readCursor(),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'owner_store_mismatch',
        ),
      ),
    );
  });

  test('new epoch resets cursor but never silently overwrites newer data', () {
    importer.applyPage(feed(revision: 4), afterSeq: 0, requestedEpoch: null);
    final reset = feed(
      after: 1,
      requestedEpoch: epochA,
      epoch: epochB,
      reset: true,
    );
    importer.applyPage(reset, afterSeq: 1, requestedEpoch: epochA);
    expect(importer.readCursor().epoch, epochB);
    expect(importer.readCursor().nextCursor, 0);
    expect(
      () => importer.applyPage(
        feed(epoch: epochB, revision: 1),
        afterSeq: 0,
        requestedEpoch: epochB,
      ),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'restore_epoch_rewind_conflict',
        ),
      ),
    );
    expect(importer.readCursor().nextCursor, 0);
    expect(
      store.box<WorkoutRemoteStateEntity>().getAll().single.serverRevision,
      4,
    );
  });

  test('blocked decoder reason survives restart; success clears it', () {
    expect(
      importer.recordBlocked(
        afterSeq: 0,
        requestedEpoch: null,
        code: 'invalid_timestamp',
      ),
      true,
    );
    store.close();
    store = Store(getObjectBoxModel(), directory: dir.path);
    bind();
    expect(importer.readCursor().blockedCode, 'invalid_timestamp');
    importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null);
    expect(importer.readCursor().blockedCode, isNull);
    expect(
      importer.recordBlocked(
        afterSeq: 0,
        requestedEpoch: null,
        code: 'invalid_uuid',
      ),
      false,
    );
  });

  test('cross-workout exercise identity collision rolls back the page', () {
    store.box<WorkoutExerciseEntity>().put(
      WorkoutExerciseEntity(
        uuid: exercise,
        sessionUuid: workoutB,
        nameSnapshot: 'Another workout',
        position: 0,
      ),
    );
    expect(
      () => importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'exercise_uuid_collision',
        ),
      ),
    );
    expect(store.box<WorkoutSessionEntity>().count(), 0);
    expect(store.box<WorkoutExerciseEntity>().count(), 1);
    expect(importer.readCursor().nextCursor, 0);
  });

  test('frozen older ObjectBox model upgrades retaining workout identity', () {
    final oldDir = Directory.systemTemp.createTempSync('northstar-restore-v1-');
    try {
      final old = Store(legacy.getObjectBoxModel(), directory: oldDir.path);
      old.box<WorkoutSessionEntity>().put(
        WorkoutSessionEntity(
          uuid: workoutB,
          name: 'Previous version',
          status: 'completed',
          startedAtMs: 10,
          completedAtMs: 20,
          originalOffsetMinutes: 330,
          updatedAtMs: 20,
        ),
      );
      old.close();
      final upgraded = Store(getObjectBoxModel(), directory: oldDir.path);
      try {
        expect(
          upgraded.box<WorkoutSessionEntity>().getAll().single.uuid,
          workoutB,
        );
        expect(upgraded.box<WorkoutRestoreCursorEntity>().count(), 0);
        expect(upgraded.box<WorkoutRemoteStateEntity>().count(), 0);
      } finally {
        upgraded.close();
      }
    } finally {
      oldDir.deleteSync(recursive: true);
    }
  });

  test('newer remote correction replaces child rows without duplicates', () {
    importer.applyPage(feed(), afterSeq: 0, requestedEpoch: null);
    final updated = importer.applyPage(
      feed(
        after: 1,
        requestedEpoch: epochA,
        seq: 2,
        revision: 2,
        name: 'Rows after correction',
      ),
      afterSeq: 1,
      requestedEpoch: epochA,
    );
    expect(updated.imported, 1);
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.name,
      'Rows after correction',
    );
    expect(store.box<WorkoutSessionEntity>().getAll().single.revision, 2);
    expect(store.box<WorkoutExerciseEntity>().count(), 1);
    expect(store.box<WorkoutSetEntity>().count(), 1);
    expect(
      store.box<WorkoutRemoteStateEntity>().getAll().single.serverRevision,
      2,
    );
    expect(importer.readCursor().nextCursor, 2);
    expect(ObjectBoxWorkoutOutbox(store).backfillCompleted(), 0);
  });

  test('second change collision rolls back the first change in the page', () {
    // The server validates each workout independently; exercise UUIDs can
    // legitimately collide across workouts, but the local Box index cannot.
    final raw = <String, dynamic>{
      'schema_version': 1,
      'cursor_epoch': epochA,
      'cursor_reset': false,
      'next_cursor': 2,
      'has_more': false,
      'changes': [
        {
          'workout_id': workout,
          'server_revision': 1,
          'change_seq': 1,
          'deleted': false,
          'payload': dto(),
        },
        {
          'workout_id': workoutB,
          'server_revision': 1,
          'change_seq': 2,
          'deleted': false,
          'payload': dto(id: workoutB),
        },
      ],
    };
    final page = WorkoutRestorePage.decode(
      raw,
      afterSeq: 0,
      requestedEpoch: null,
      limit: 100,
    );
    expect(
      () => importer.applyPage(page, afterSeq: 0, requestedEpoch: null),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'exercise_uuid_collision',
        ),
      ),
    );
    expect(store.box<WorkoutSessionEntity>().count(), 0);
    expect(store.box<WorkoutExerciseEntity>().count(), 0);
    expect(store.box<WorkoutSetEntity>().count(), 0);
    expect(store.box<WorkoutRemoteStateEntity>().count(), 0);
    expect(importer.readCursor().nextCursor, 0);
    expect(importer.readCursor().blockedCode, 'exercise_uuid_collision');
  });

  test('account changing immediately before commit rolls back all writes', () {
    expect(
      () => importer.applyPage(
        feed(),
        afterSeq: 0,
        requestedEpoch: null,
        beforeCommitForTest: () => activeOwner = accountB,
      ),
      throwsA(
        isA<RestoreImportException>().having(
          (e) => e.code,
          'code',
          'account_changed',
        ),
      ),
    );
    expect(store.box<WorkoutSessionEntity>().count(), 0);
    expect(store.box<WorkoutRestoreCursorEntity>().count(), 0);
    activeOwner = accountA;
  });
}
