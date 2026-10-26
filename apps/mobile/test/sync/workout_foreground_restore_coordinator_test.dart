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

  test(
    'account switch during pull never writes old owner data',
    () async {
      final response = Completer<WorkoutRestorePage>();
      pull.handler = (_, _) => response.future;
      final ongoing = worker.drain();
      await Future<void>.delayed(Duration.zero);
      api.emitSession(accountB);
      response.complete(page());
      await ongoing;
      expect(store.box<WorkoutSessionEntity>().count(), 0);
      expect(store.box<WorkoutRestoreCursorEntity>().count(), 0);
    },
  );


  test('blocked or conflicted upload defers restore without poisoning cursor',
      () async {
    for (final status in ['conflict', 'blocked']) {
      final row = WorkoutSyncOutboxEntity(
        operationUuid: operation,
        sessionUuid: workout,
        localRevision: 1,
        action: 'upsert',
        state: status,
        payloadJson: '{}',
        createdAtMs: 10,
      );
      final rowId = store.box<WorkoutSyncOutboxEntity>().put(row);
      pull.handler = (_, _) async => page();
      expect(outbox.hasUnacknowledgedOperations(), true);
      await worker.drain();
      expect(pull.requests, isEmpty);
      expect(importer.readCursor().nextCursor, 0);
      expect(importer.readCursor().blockedCode, isNull);
      expect(worker.lastRestoreFailureKind, 'upload_unresolved');
      // Simulate a future reviewed resolution; no automatic deletion or
      // conflict clearing exists in this milestone.
      store.box<WorkoutSyncOutboxEntity>().remove(rowId);
    }
    expect(outbox.hasUnacknowledgedOperations(), false);
    await worker.drain();
    expect(pull.requests, hasLength(1));
    expect(importer.readCursor().nextCursor, 1);
    expect(importer.readCursor().blockedCode, isNull);
  });

  test('unresolved operation created during fetch defers, even if blocked',
      () async {
    final response = Completer<WorkoutRestorePage>();
    pull.handler = (_, _) => response.future;
    final ongoing = worker.drain();
    await Future<void>.delayed(Duration.zero);
    store.box<WorkoutSyncOutboxEntity>().put(WorkoutSyncOutboxEntity(
      operationUuid: operation,
      sessionUuid: workout,
      localRevision: 1,
      action: 'upsert',
      state: 'conflict',
      payloadJson: '{}',
      createdAtMs: 10,
    ));
    response.complete(page());
    await ongoing;
    expect(importer.readCursor().nextCursor, 0);
    expect(importer.readCursor().blockedCode, isNull);
    expect(store.box<WorkoutSessionEntity>().count(), 0);
    expect(worker.lastRestoreFailureKind, 'upload_unresolved');
  });

  test('token expires in-flight: network response cannot mutate the Store',
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
  });

  test('malformed half-configured upload and restore worker is rejected', () {
    expect(() => WorkoutUploadCoordinator(
      accountId: accountA,
      auth: auth,
      outbox: outbox,
      transport: push,
      restoreTransport: pull,
    ), throwsAssertionError);
    expect(() => WorkoutUploadCoordinator(
      accountId: accountA,
      auth: auth,
      outbox: outbox,
      transport: push,
      restoreImporter: importer,
    ), throwsAssertionError);
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
