import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/storage/objectbox_store_provider.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';
import 'package:northstar_health/features/progress/workout_history_state.dart';
import 'package:northstar_health/features/account/account_auth_controller.dart';
import 'package:northstar_health/features/sync/objectbox_workout_restore_importer.dart';
import 'package:northstar_health/features/sync/workout_restore_feed.dart';
import 'package:northstar_health/features/sync/workout_restore_transport.dart';
import 'package:northstar_health/features/sync/workout_upload_coordinator.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/objectbox.g.dart';

import '../support/fake_account_auth.dart';

const epoch = '00000000-0000-4000-8000-000000000901';
const newEpoch = '00000000-0000-4000-8000-000000000902';
const workout = '00000000-0000-4000-8000-000000000101';
const operation = '00000000-0000-4000-8000-000000000401';

String workoutId(int number) =>
    '00000000-0000-4000-8000-${number.toRadixString(16).padLeft(12, '0')}';

RemoteWorkoutChange change(int seq, {String? id}) => RemoteWorkoutChange(
  workoutId: id ?? workoutId(seq),
  serverRevision: 1,
  changeSeq: seq,
  deleted: false,
  snapshot: RemoteWorkoutSnapshot(
    uuid: id ?? workoutId(seq),
    name: 'Restored workout',
    startedAtUtc: DateTime.utc(2026, 10, 25, 9),
    completedAtUtc: DateTime.utc(2026, 10, 25, 10),
    originalOffsetMinutes: 330,
    exercises: const [],
    sets: const [],
  ),
);

WorkoutRestorePage page({
  String cursorEpoch = epoch,
  int nextCursor = 1,
  bool hasMore = false,
  bool cursorReset = false,
  List<RemoteWorkoutChange>? changes,
}) => WorkoutRestorePage(
  cursorEpoch: cursorEpoch,
  nextCursor: nextCursor,
  hasMore: hasMore,
  cursorReset: cursorReset,
  changes: changes ?? [change(nextCursor, id: workout)],
);

class FakePull implements WorkoutRestoreTransport {
  final requests = <(int, String?, int)>[];
  final events = <String>[];
  Future<WorkoutRestorePage> Function(int, String?)? handler;

  @override
  Future<WorkoutRestorePage> fetchPage({
    required int afterSeq,
    required String? cursorEpoch,
    int limit = 100,
  }) async {
    requests.add((afterSeq, cursorEpoch, limit));
    events.add('pull');
    final fetch = handler;
    if (fetch == null) throw StateError('Unexpected remote request');
    return fetch(afterSeq, cursorEpoch);
  }
}

class FakePush implements WorkoutUploadTransport {
  final events = <String>[];
  Future<Map<String, dynamic>> Function(WorkoutSyncOperation, int)? handler;

  @override
  Future<Map<String, dynamic>> send(
    WorkoutSyncOperation op, {
    required int expectedServerRevision,
  }) async {
    events.add('upload');
    final send = handler;
    if (send != null) return send(op, expectedServerRevision);
    return {
      'result': 'applied',
      'revision': expectedServerRevision + 1,
      'change_seq': expectedServerRevision + 1,
      'replay': false,
      'processing': 'processed',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Store store;
  late FakeAuthApi api;
  late FakeBoundAccountStore binding;
  late AccountAuthController auth;
  late ObjectBoxWorkoutOutbox outbox;
  late ObjectBoxWorkoutRestoreImporter importer;
  late FakePull pull;
  late FakePush push;
  late WorkoutUploadCoordinator worker;
  late int notifications;

  void makeWorker() {
    worker = WorkoutUploadCoordinator(
      accountId: accountA,
      auth: auth,
      outbox: outbox,
      transport: push,
      restoreTransport: pull,
      restoreImporter: importer,
      onRestored: () => notifications++,
      pollInterval: const Duration(hours: 1),
    );
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('northstar-foreground-pull-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    api = FakeAuthApi()..sessionId = accountA;
    binding = FakeBoundAccountStore()..saved = accountA;
    auth = controller(api, binding);
    await auth.restore();
    outbox = ObjectBoxWorkoutOutbox(store);
    importer = ObjectBoxWorkoutRestoreImporter(
      store,
      accountId: accountA,
      activeAccountId: () => auth.userId,
    );
    pull = FakePull();
    push = FakePush();
    notifications = 0;
    makeWorker();
  });

  tearDown(() async {
    worker.dispose();
    auth.dispose();
    await api.dispose();
    store.close();
    dir.deleteSync(recursive: true);
  });

  test('new account imports remote workout and durable epoch/cursor', () async {
    pull.handler = (after, currentEpoch) async {
      expect(after, 0);
      expect(currentEpoch, null);
      return page();
    };
    await worker.drain();
    expect(pull.requests, [(0, null, 100)]);
    expect(store.box<WorkoutSessionEntity>().getAll().single.uuid, workout);
    expect(importer.readCursor().epoch, epoch);
    expect(importer.readCursor().nextCursor, 1);
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 0);
    expect(notifications, 1);
    expect(worker.lastRestoreFailureKind, null);
    store.close();
    store = Store(getObjectBoxModel(), directory: dir.path);
    outbox = ObjectBoxWorkoutOutbox(store);
    importer = ObjectBoxWorkoutRestoreImporter(
      store,
      accountId: accountA,
      activeAccountId: () => auth.userId,
    );
    worker.dispose();
    makeWorker();
    pull.handler = (after, currentEpoch) async {
      expect(after, 1);
      expect(currentEpoch, epoch);
      return page(nextCursor: 1, changes: const []);
    };
    await worker.drain();
    expect(importer.readCursor().nextCursor, 1);
    expect(store.box<WorkoutSessionEntity>().count(), 1);
    expect(notifications, 1);
  });

  test('100-row page continues to next page and does not duplicate', () async {
    final initial = [for (var i = 1; i <= 100; i++) change(i)];
    pull.handler = (after, _) async {
      if (after == 0) {
        return page(nextCursor: 100, hasMore: true, changes: initial);
      }
      expect(after, 100);
      return page(nextCursor: 101, changes: [change(101)]);
    };
    await worker.drain();
    expect(pull.requests.map((r) => r.$1), [0, 100]);
    expect(store.box<WorkoutSessionEntity>().count(), 101);
    expect(importer.readCursor().nextCursor, 101);
    expect(notifications, 2);
  });

  test('new remote epoch resets and refetches from zero safely', () async {
    pull.handler = (after, currentEpoch) async {
      if (currentEpoch == null) {
        return page(
          cursorReset: true,
          cursorEpoch: newEpoch,
          nextCursor: 0,
          changes: const [],
        );
      }
      expect(currentEpoch, newEpoch);
      expect(after, 0);
      return page(cursorEpoch: newEpoch);
    };
    await worker.drain();
    expect(pull.requests.length, 2);
    expect(importer.readCursor().epoch, newEpoch);
    expect(importer.readCursor().nextCursor, 1);
    expect(notifications, 1);
  });

  test('uploads finish before restore begins; upload ACK is durable', () async {
    store.box<WorkoutSyncOutboxEntity>().put(
      WorkoutSyncOutboxEntity(
        operationUuid: operation,
        sessionUuid: workout,
        localRevision: 1,
        action: 'upsert',
        payloadJson:
            '{"schema_version":1,"workout_id":"$workout","status":"completed","origin":"northstar_phone"}',
        createdAtMs: 10,
      ),
    );
    final events = <String>[];
    push.handler = (_, expected) async {
      events.add('upload');
      expect(expected, 0);
      return {
        'result': 'applied',
        'revision': 1,
        'change_seq': 1,
        'replay': false,
        'processing': 'processed',
      };
    };
    pull.handler = (_, _) async {
      events.add('pull');
      return page(nextCursor: 0, changes: const []);
    };
    await worker.drain();
    expect(events, ['upload', 'pull']);
    expect(
      store.box<WorkoutSyncOutboxEntity>().getAll().single.state,
      'acknowledged',
    );
  });

  test('failed upload defers pull without a persistent restore block', () async {
    store.box<WorkoutSyncOutboxEntity>().put(
      WorkoutSyncOutboxEntity(
        operationUuid: operation,
        sessionUuid: workout,
        localRevision: 1,
        action: 'upsert',
        payloadJson:
            '{"schema_version":1,"workout_id":"$workout","status":"completed","origin":"northstar_phone"}',
        createdAtMs: 10,
      ),
    );
    push.handler = (_, _) => throw StateError('offline');
    pull.handler = (_, _) async => page();
    await worker.drain();
    expect(pull.requests, isEmpty);
    expect(worker.lastRestoreFailureKind, 'upload_unresolved');
    expect(importer.readCursor().blockedCode, null);
  });

  test(
    'new local operation during fetch defers import without conflict',
    () async {
      final response = Completer<WorkoutRestorePage>();
      pull.handler = (_, _) => response.future;
      final ongoing = worker.drain();
      await Future<void>.delayed(Duration.zero);
      store.box<WorkoutSyncOutboxEntity>().put(
        WorkoutSyncOutboxEntity(
          operationUuid: operation,
          sessionUuid: workout,
          localRevision: 1,
          action: 'upsert',
          payloadJson: '{}',
          createdAtMs: 10,
        ),
      );
      response.complete(page());
      await ongoing;
      expect(store.box<WorkoutSessionEntity>().count(), 0);
      expect(importer.readCursor().nextCursor, 0);
      expect(importer.readCursor().blockedCode, null);
      expect(worker.lastRestoreFailureKind, 'upload_unresolved');
    },
  );

  test('account switch during pull never writes old owner data', () async {
    final response = Completer<WorkoutRestorePage>();
    pull.handler = (_, _) => response.future;
    final ongoing = worker.drain();
    await Future<void>.delayed(Duration.zero);
    api.emitSession(accountB);
    response.complete(page());
    await ongoing;
    expect(store.box<WorkoutSessionEntity>().count(), 0);
    expect(store.box<WorkoutRestoreCursorEntity>().count(), 0);
  });

  test('blocked upload for another workout never stops restore', () async {
    store.box<WorkoutSyncOutboxEntity>().put(
      WorkoutSyncOutboxEntity(
        operationUuid: operation,
        sessionUuid: workoutId(50),
        localRevision: 1,
        action: 'upsert',
        state: 'blocked',
        errorCode: 'payload_too_large',
        payloadJson: '{}',
        createdAtMs: 10,
      ),
    );
    pull.handler = (_, _) async => page();
    await worker.drain();
    expect(pull.requests, hasLength(1));
    expect(store.box<WorkoutSessionEntity>().getAll().single.uuid, workout);
    expect(importer.readCursor().nextCursor, 1);
    expect(importer.readCursor().blockedCode, isNull);
    expect(store.box<WorkoutRestoreSkipEntity>().count(), 0);
    expect(worker.lastRestoreFailureKind, isNull);
  });

  test(
    'blocked or conflicted workout in the feed is skipped and recorded',
    () async {
      for (final status in ['conflict', 'blocked']) {
        final rowId = store.box<WorkoutSyncOutboxEntity>().put(
          WorkoutSyncOutboxEntity(
            operationUuid: operation,
            sessionUuid: workout,
            localRevision: 1,
            action: 'upsert',
            state: status,
            payloadJson: '{}',
            createdAtMs: 10,
          ),
        );
        final base = importer.readCursor().nextCursor;
        pull.handler = (_, _) async => page(
          nextCursor: base + 2,
          changes: [
            change(base + 1, id: workout),
            change(base + 2, id: workoutId(60 + base)),
          ],
        );
        await worker.drain();
        // The local copy wins until a reviewed resolution; the other
        // device's unrelated workout still restores.
        expect(
          store
              .box<WorkoutSessionEntity>()
              .getAll()
              .map((s) => s.uuid)
              .contains(workout),
          false,
        );
        expect(
          store
              .box<WorkoutSessionEntity>()
              .getAll()
              .map((s) => s.uuid)
              .contains(workoutId(60 + base)),
          true,
        );
        final skip = store.box<WorkoutRestoreSkipEntity>().getAll().single;
        expect(skip.workoutUuid, workout);
        expect(skip.ownerAccountId, accountA);
        expect(skip.serverChangeSeq, base + 1);
        expect(importer.readCursor().nextCursor, base + 2);
        expect(importer.readCursor().blockedCode, isNull);
        expect(worker.lastRestoreFailureKind, isNull);
        store.box<WorkoutSyncOutboxEntity>().remove(rowId);
      }
    },
  );

  test('each drain refreshes per-workout sync tags once', () async {
    var refreshes = 0;
    worker.dispose();
    worker = WorkoutUploadCoordinator(
      accountId: accountA,
      auth: auth,
      outbox: outbox,
      transport: push,
      restoreTransport: pull,
      restoreImporter: importer,
      onSyncStateChanged: () => refreshes++,
      pollInterval: const Duration(hours: 1),
    );
    pull.handler = (_, _) async => page();
    await worker.drain();
    expect(refreshes, 1);
    worker.dispose();
    await worker.drain();
    expect(refreshes, 1);
  });

  test('conflict created during fetch is skipped, not imported', () async {
    final response = Completer<WorkoutRestorePage>();
    pull.handler = (_, _) => response.future;
    final ongoing = worker.drain();
    await Future<void>.delayed(Duration.zero);
    store.box<WorkoutSyncOutboxEntity>().put(
      WorkoutSyncOutboxEntity(
        operationUuid: operation,
        sessionUuid: workout,
        localRevision: 1,
        action: 'upsert',
        state: 'conflict',
        payloadJson: '{}',
        createdAtMs: 10,
      ),
    );
    response.complete(page());
    await ongoing;
    expect(store.box<WorkoutSessionEntity>().count(), 0);
    expect(
      store.box<WorkoutRestoreSkipEntity>().getAll().single.workoutUuid,
      workout,
    );
    expect(importer.readCursor().nextCursor, 1);
    expect(importer.readCursor().blockedCode, isNull);
  });

  WorkoutSessionEntity localCompleted() => WorkoutSessionEntity(
    uuid: workout,
    name: 'This phone copy',
    status: 'completed',
    startedAtMs: DateTime.utc(2026, 10, 25, 9).millisecondsSinceEpoch,
    completedAtMs: DateTime.utc(2026, 10, 25, 10).millisecondsSinceEpoch,
    originalOffsetMinutes: 330,
    updatedAtMs: DateTime.utc(2026, 10, 25, 10).millisecondsSinceEpoch,
  );

  WorkoutSyncOutboxEntity conflictOp() => WorkoutSyncOutboxEntity(
    operationUuid: operation,
    sessionUuid: workout,
    localRevision: 1,
    action: 'upsert',
    state: 'conflict',
    payloadJson: '{}',
    createdAtMs: 10,
  );

  test(
    'conflicted workout keeps its local copy across repeated remote changes',
    () async {
      store.box<WorkoutSessionEntity>().put(localCompleted());
      store.box<WorkoutSyncOutboxEntity>().put(conflictOp());
      pull.handler = (_, _) async => page();
      await worker.drain();
      pull.handler = (_, _) async =>
          page(nextCursor: 2, changes: [change(2, id: workout)]);
      await worker.drain();
      expect(
        store.box<WorkoutSessionEntity>().getAll().single.name,
        'This phone copy',
      );
      final skip = store.box<WorkoutRestoreSkipEntity>().getAll().single;
      expect(skip.serverChangeSeq, 2);
      expect(store.box<WorkoutRemoteStateEntity>().count(), 0);
      expect(importer.readCursor().nextCursor, 2);
      expect(importer.readCursor().blockedCode, isNull);
    },
  );

  test('resolution contract: dropping a conflict without reconciling the '
      'importer baseline is refused, so P2-07 must reconcile both', () async {
    store.box<WorkoutSessionEntity>().put(localCompleted());
    final rowId = store.box<WorkoutSyncOutboxEntity>().put(conflictOp());
    pull.handler = (_, _) async => page();
    await worker.drain();
    store.box<WorkoutSyncOutboxEntity>().remove(rowId);
    pull.handler = (_, _) async =>
        page(nextCursor: 2, changes: [change(2, id: workout)]);
    await worker.drain();
    // The importer never overwrites an untracked local copy. This is why
    // ADR-0006 requires the future resolution flow to write the remote
    // baseline (and fetch the server version) instead of deleting rows.
    expect(importer.readCursor().blockedCode, 'untracked_local_workout');
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.name,
      'This phone copy',
    );
    expect(store.box<WorkoutRestoreSkipEntity>().count(), 1);
  });

  test('skip record owned by another account is refused', () async {
    store.box<WorkoutSyncOutboxEntity>().put(conflictOp());
    store.box<WorkoutRestoreSkipEntity>().put(
      WorkoutRestoreSkipEntity(
        workoutUuid: workout,
        ownerAccountId: accountB,
        serverChangeSeq: 1,
        cursorEpoch: epoch,
        skippedAtMs: 1,
      ),
    );
    pull.handler = (_, _) async => page();
    await worker.drain();
    expect(worker.lastRestoreFailureKind, 'owner_store_mismatch');
    expect(importer.readCursor().nextCursor, 0);
    expect(
      store.box<WorkoutRestoreSkipEntity>().getAll().single.ownerAccountId,
      accountB,
    );
  });

  test(
    'token expires in-flight: network response cannot mutate the Store',
    () async {
      final response = Completer<WorkoutRestorePage>();
      pull.handler = (_, _) => response.future;
      final ongoing = worker.drain();
      await Future<void>.delayed(Duration.zero);
      api.emitSession(accountA, isExpired: true);
      response.complete(page());
      await ongoing;
      expect(store.box<WorkoutSessionEntity>().count(), 0);
      expect(store.box<WorkoutRestoreCursorEntity>().count(), 0);
      expect(importer.readCursor().blockedCode, null);
      api.emitSession(accountA);
      pull.handler = (_, _) async => page();
      await worker.drain();
      expect(importer.readCursor().nextCursor, 1);
    },
  );

  test('malformed half-configured upload and restore worker is rejected', () {
    expect(
      () => WorkoutUploadCoordinator(
        accountId: accountA,
        auth: auth,
        outbox: outbox,
        transport: push,
        restoreTransport: pull,
      ),
      throwsAssertionError,
    );
    expect(
      () => WorkoutUploadCoordinator(
        accountId: accountA,
        auth: auth,
        outbox: outbox,
        transport: push,
        restoreImporter: importer,
      ),
      throwsAssertionError,
    );
  });

  test('offline RPC retry uses unchanged cursor on next drain', () async {
    var attempts = 0;
    pull.handler = (_, _) async {
      attempts++;
      if (attempts == 1) throw StateError('temporary network failure');
      return page();
    };
    await worker.drain();
    expect(worker.lastRestoreFailureKind, 'restore_unavailable');
    expect(importer.readCursor().nextCursor, 0);
    expect(importer.readCursor().blockedCode, null);
    await worker.drain();
    expect(pull.requests.map((r) => r.$1), [0, 0]);
    expect(importer.readCursor().nextCursor, 1);
    expect(worker.lastRestoreFailureKind, null);
  });

  test(
    'malformed remote page blocks and stops further network attempts',
    () async {
      pull.handler = (_, _) =>
          throw const RestoreContractException('invalid_page_cursor');
      await worker.drain();
      expect(importer.readCursor().nextCursor, 0);
      expect(importer.readCursor().blockedCode, 'invalid_page_cursor');
      await worker.drain();
      expect(pull.requests, hasLength(1));
      expect(worker.lastRestoreFailureKind, 'invalid_page_cursor');
    },
  );

  test('remote collision creates a durable blocker, not retry loop', () async {
    final started = DateTime.utc(2026, 10, 24).millisecondsSinceEpoch;
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: workout,
        name: 'Unsynced old local session',
        status: 'inProgress',
        startedAtMs: started,
        completedAtMs: null,
        originalOffsetMinutes: 0,
        updatedAtMs: started,
      ),
    );
    pull.handler = (_, _) async => page();
    await worker.drain();
    expect(importer.readCursor().blockedCode, 'local_workout_conflict');
    await worker.drain();
    expect(pull.requests, hasLength(1));
    expect(
      store.box<WorkoutSessionEntity>().getAll().single.name,
      'Unsynced old local session',
    );
  });

  test(
    'repeated cursor reset halts a pass without a durable blocker',
    () async {
      pull.handler = (_, _) async => page(
        cursorReset: true,
        cursorEpoch: newEpoch,
        nextCursor: 0,
        changes: const [],
      );
      await worker.drain();
      expect(pull.requests, [(0, null, 100), (0, newEpoch, 100)]);
      expect(worker.lastRestoreFailureKind, 'repeated_cursor_reset');
      expect(importer.readCursor().epoch, newEpoch);
      expect(importer.readCursor().nextCursor, 0);
      expect(importer.readCursor().blockedCode, isNull);
    },
  );

  test('resets to two different epochs in one pass halt safely', () async {
    const thirdEpoch = '00000000-0000-4000-8000-000000000903';
    pull.handler = (_, requestedEpoch) async => page(
      cursorReset: true,
      cursorEpoch: requestedEpoch == null ? newEpoch : thirdEpoch,
      nextCursor: 0,
      changes: const [],
    );
    await worker.drain();
    expect(pull.requests, [(0, null, 100), (0, newEpoch, 100)]);
    expect(worker.lastRestoreFailureKind, 'repeated_cursor_reset');
    expect(importer.readCursor().epoch, thirdEpoch);
    expect(importer.readCursor().nextCursor, 0);
    expect(importer.readCursor().blockedCode, isNull);
  });

  test('a reset on the last page slot reruns instead of waiting', () async {
    pull.handler = (after, requestedEpoch) async {
      if (requestedEpoch == newEpoch) {
        return page(cursorEpoch: newEpoch, nextCursor: 0, changes: const []);
      }
      if (after == 300) {
        return page(
          cursorReset: true,
          cursorEpoch: newEpoch,
          nextCursor: 0,
          changes: const [],
        );
      }
      return page(
        nextCursor: after + 100,
        hasMore: true,
        changes: [change(after + 100)],
      );
    };
    await worker.drain();
    expect(pull.requests.map((r) => (r.$1, r.$2)), [
      (0, null),
      (100, epoch),
      (200, epoch),
      (300, epoch),
      (0, newEpoch),
    ]);
    expect(importer.readCursor().epoch, newEpoch);
    expect(worker.lastRestoreFailureKind, isNull);
  });

  test(
    'concurrent already-applied page reports no progress, not data loss',
    () async {
      final first = page(
        nextCursor: 100,
        hasMore: true,
        changes: [for (var i = 1; i <= 100; i++) change(i)],
      );
      pull.handler = (_, _) async {
        // Simulates a second foreground reader committing while the first
        // request is outstanding. The stale page is replayed harmlessly.
        importer.applyPage(first, afterSeq: 0, requestedEpoch: null);
        return first;
      };
      await worker.drain();
      expect(worker.lastRestoreFailureKind, 'restore_no_progress');
      expect(importer.readCursor().nextCursor, 100);
      expect(importer.readCursor().blockedCode, isNull);
      expect(store.box<WorkoutSessionEntity>().count(), 100);
      expect(pull.requests, hasLength(1));
    },
  );

  test(
    'four-page budget schedules the fifth page in a serialized pass',
    () async {
      pull.handler = (after, _) async {
        final next = after + 100 >= 401 ? 401 : after + 100;
        return page(
          nextCursor: next,
          hasMore: next < 401,
          changes: [for (var i = after + 1; i <= next; i++) change(i)],
        );
      };
      await worker.drain();
      expect(pull.requests.map((request) => request.$1), [
        0,
        100,
        200,
        300,
        400,
      ]);
      expect(importer.readCursor().nextCursor, 401);
      expect(store.box<WorkoutSessionEntity>().count(), 401);
      expect(notifications, 5);
      expect(worker.lastRestoreFailureKind, isNull);
    },
  );

  test(
    'restarts midway through paging from committed epoch and cursor',
    () async {
      pull.handler = (after, _) async {
        if (after == 0) {
          return page(
            nextCursor: 100,
            hasMore: true,
            changes: [for (var i = 1; i <= 100; i++) change(i)],
          );
        }
        throw StateError('offline on second page');
      };
      await worker.drain();
      expect(importer.readCursor().nextCursor, 100);
      expect(importer.readCursor().epoch, epoch);
      expect(store.box<WorkoutSessionEntity>().count(), 100);
      expect(worker.lastRestoreFailureKind, 'restore_unavailable');

      worker.dispose();
      store.close();
      store = Store(getObjectBoxModel(), directory: dir.path);
      outbox = ObjectBoxWorkoutOutbox(store);
      importer = ObjectBoxWorkoutRestoreImporter(
        store,
        accountId: accountA,
        activeAccountId: () => auth.userId,
      );
      makeWorker();
      pull.requests.clear();
      pull.handler = (after, requestedEpoch) async {
        expect(after, 100);
        expect(requestedEpoch, epoch);
        return page(nextCursor: 101, changes: [change(101)]);
      };
      await worker.drain();
      expect(pull.requests, [(100, epoch, 100)]);
      expect(importer.readCursor().nextCursor, 101);
      expect(store.box<WorkoutSessionEntity>().count(), 101);
      expect(notifications, 2);
    },
  );

  test('device importing its own upload ACK does not bump local revision', () async {
    final started = DateTime.utc(2026, 10, 25, 9).millisecondsSinceEpoch;
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: workout,
        name: 'Restored workout',
        revision: 1,
        status: 'completed',
        origin: 'northstar_phone',
        startedAtMs: started,
        completedAtMs: started + 3600000,
        originalOffsetMinutes: 330,
        updatedAtMs: started,
      ),
    );
    store.box<WorkoutSyncOutboxEntity>().put(
      WorkoutSyncOutboxEntity(
        operationUuid: operation,
        sessionUuid: workout,
        localRevision: 1,
        action: 'upsert',
        payloadJson:
            '{"schema_version":1,"workout_id":"$workout","status":"completed","origin":"northstar_phone"}',
        createdAtMs: 10,
      ),
    );
    pull.handler = (_, _) async => page(changes: [change(1, id: workout)]);
    await worker.drain();
    final ack = store.box<WorkoutSyncOutboxEntity>().getAll().single;
    expect(ack.state, 'acknowledged');
    expect(ack.serverRevision, 1);
    expect(pull.requests, hasLength(1));
    final local = store.box<WorkoutSessionEntity>().getAll().single;
    expect(local.revision, 1);
    expect(local.name, 'Restored workout');
    expect(
      store.box<WorkoutRemoteStateEntity>().getAll().single.serverRevision,
      1,
    );
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 1);
  });

  test(
    'real Riverpod history provider refreshes after imported workout',
    () async {
      pull.handler = (after, _) async =>
          after == 0 ? page() : page(nextCursor: after, changes: const []);
      final container = ProviderContainer(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutUploadTransportProvider.overrideWithValue((_) => push),
          workoutRestoreTransportProvider.overrideWithValue((_) => pull),
        ],
      );
      final subscription = container.listen(
        completedWorkoutHistoryProvider,
        (_, _) {},
        fireImmediately: true,
      );
      try {
        final initially = await container.read(
          completedWorkoutHistoryProvider.future,
        );
        expect(initially.sessions, isEmpty);
        final mounted = container.read(workoutUploadCoordinatorProvider);
        await mounted.drain();
        final refreshed = await container.read(
          completedWorkoutHistoryProvider.future,
        );
        expect(refreshed.sessions.map((row) => row.uuid), [workout]);
      } finally {
        subscription.close();
        container.dispose();
      }
    },
  );

  testWidgets('authenticated account host starts restore and resumes pull', (
    tester,
  ) async {
    pull.handler = (after, currentEpoch) async =>
        page(nextCursor: 0, changes: const []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          objectBoxStoreProvider.overrideWithValue(store),
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutUploadTransportProvider.overrideWithValue((_) => push),
          workoutRestoreTransportProvider.overrideWithValue((_) => pull),
        ],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: AccountWorkoutUploadHost(child: SizedBox()),
        ),
      ),
    );
    await tester.pump();
    expect(pull.requests, [(0, null, 100)]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(pull.requests, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(pull.requests, [(0, null, 100), (0, epoch, 100)]);
    await tester.pumpWidget(const SizedBox());
  });
}
