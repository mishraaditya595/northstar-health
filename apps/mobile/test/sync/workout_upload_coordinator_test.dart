import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/ids/uuid_factory.dart';
import 'package:northstar_health/core/storage/objectbox_store_provider.dart';
import 'package:northstar_health/features/account/account_auth_controller.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';
import 'package:northstar_health/features/sync/cloud_session_guard.dart';
import 'package:northstar_health/features/sync/workout_upload_coordinator.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:northstar_health/features/workouts/data/workout_entities.dart';
import 'package:northstar_health/objectbox.g.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_account_auth.dart';

const workoutId = '00000000-0000-4000-8000-000000000101';
const operationId = '00000000-0000-4000-8000-000000000201';

String completedPayload([String id = workoutId]) => jsonEncode({
  'schema_version': 1,
  'workout_id': id,
  'status': 'completed',
  'origin': 'northstar_phone',
  'name': 'Rows',
  'started_at_utc': '2026-10-25T09:00:00Z',
  'completed_at_utc': '2026-10-25T10:00:00Z',
  'original_offset_minutes': 330,
  'exercises': <Object>[],
});

class FakeTransport implements WorkoutUploadTransport {
  final sent = <String>[];
  final expected = <int>[];
  Future<Map<String, dynamic>> Function(
    WorkoutSyncOperation operation,
    int expectedRevision,
  )?
  handler;

  @override
  Future<Map<String, dynamic>> send(
    WorkoutSyncOperation operation, {
    required int expectedServerRevision,
  }) async {
    sent.add(operation.operationUuid);
    expected.add(expectedServerRevision);
    final impl = handler;
    if (impl != null) return impl(operation, expectedServerRevision);
    return {
      'result': 'applied',
      'revision': expectedServerRevision + 1,
      'change_seq': expectedServerRevision + 1,
      'replay': false,
      'processing': 'processed',
    };
  }
}

class MalformedFirstOperationId implements UuidFactory {
  var calls = 0;
  @override
  String newId() {
    calls++;
    if (calls == 1) return 'not-a-uuid';
    return '00000000-0000-4000-8000-0000000000b2';
  }
}

class BrokenBackfillOutbox extends ObjectBoxWorkoutOutbox {
  BrokenBackfillOutbox(super.store);

  int calls = 0;
  @override
  int backfillCompleted() {
    calls++;
    throw StateError('synthetic historical scan failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Store store;
  late ObjectBoxWorkoutOutbox outbox;
  late FakeAuthApi api;
  late FakeBoundAccountStore bound;
  late AccountAuthController auth;
  late FakeTransport transport;
  late DateTime now;
  late WorkoutUploadCoordinator uploader;

  // Use the real ObjectBox native engine, not a mock list or in-memory fake.
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('northstar-sync-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    outbox = ObjectBoxWorkoutOutbox(store);
    api = FakeAuthApi()..sessionId = accountA;
    bound = FakeBoundAccountStore()..saved = accountA;
    auth = controller(api, bound);
    await auth.restore();
    transport = FakeTransport();
    now = DateTime.utc(2026, 10, 25, 15);
    uploader = WorkoutUploadCoordinator(
      accountId: accountA,
      auth: auth,
      outbox: outbox,
      transport: transport,
      clock: () => now,
    );
  });
  tearDown(() async {
    uploader.dispose();
    auth.dispose();
    await api.dispose();
    store.close();
    dir.deleteSync(recursive: true);
  });

  WorkoutSyncOutboxEntity queued({
    String opId = operationId,
    String sessionId = workoutId,
    int revision = 1,
    int createdAtMs = 1000,
    String? payload,
  }) {
    final op = WorkoutSyncOutboxEntity(
      operationUuid: opId,
      sessionUuid: sessionId,
      localRevision: revision,
      action: 'upsert',
      payloadJson: payload ?? completedPayload(sessionId),
      createdAtMs: createdAtMs,
    );
    store.box<WorkoutSyncOutboxEntity>().put(op);
    return op;
  }

  test(
    'authenticated upload uses CAS revision zero and persists ACK',
    () async {
      queued();
      await uploader.drain();
      expect(transport.sent, [operationId]);
      expect(transport.expected, [0]);
      final entity = store.box<WorkoutSyncOutboxEntity>().getAll().single;
      expect(entity.state, 'acknowledged');
      expect(entity.serverRevision, 1);
      expect(entity.serverChangeSeq, 1);
      expect(outbox.pending(), isEmpty);
    },
  );

  test('lost acknowledgement reuses UUID and same expected revision', () async {
    queued();
    var first = true;
    transport.handler = (op, rev) async {
      if (first) {
        first = false;
        throw TimeoutException('lost HTTP response');
      }
      return {
        'result': 'applied',
        'revision': 1,
        'change_seq': 12,
        'replay': true,
        'processing': 'processed',
      };
    };
    await uploader.drain();
    expect(outbox.pending(), hasLength(1));
    expect(store.box<WorkoutSyncOutboxEntity>().getAll().single.attempts, 1);
    await uploader.drain();
    expect(transport.sent, [operationId]); // durable 5-second cooldown
    now = now.add(const Duration(seconds: 5));
    await uploader.drain();
    expect(transport.sent, [operationId, operationId]);
    expect(transport.expected, [0, 0]);
    expect(outbox.pending(), isEmpty);
    expect(
      store.box<WorkoutSyncOutboxEntity>().getAll().single.serverRevision,
      1,
    );
  });

  test('two revisions upload in order with previous server ACK', () async {
    queued();
    queued(
      opId: '00000000-0000-4000-8000-000000000202',
      revision: 2,
      createdAtMs: 1001,
    );
    await uploader.drain();
    expect(transport.expected, [0, 1]);
    expect(outbox.pending(), isEmpty);
  });

  test('a conflict stays local and blocks dependent revisions', () async {
    queued();
    queued(
      opId: '00000000-0000-4000-8000-000000000202',
      revision: 2,
      createdAtMs: 1001,
    );
    transport.handler = (_, _) async => {
      'result': 'conflict',
      'revision': 7,
      'change_seq': 8,
      'replay': false,
      'processing': 'not_applied',
    };
    await uploader.drain();
    expect(transport.sent, [operationId]);
    expect(
      store.box<WorkoutSyncOutboxEntity>().getAll().first.state,
      'conflict',
    );
    expect(outbox.pending().map((o) => o.localRevision), [2]);
    await uploader.drain();
    expect(transport.sent, [operationId]);
  });

  test(
    'terminal server validation blocks without dropping local snapshot',
    () async {
      queued();
      transport.handler = (_, _) async =>
          throw const PostgrestException(message: 'invalid', code: '22023');
      await uploader.drain();
      expect(outbox.pending(), isEmpty);
      expect(outbox.blockedCount(), 1);
      expect(
        store.box<WorkoutSyncOutboxEntity>().getAll().single.payloadJson,
        completedPayload(),
      );
    },
  );

  test(
    'expired session pauses RPC and resumes without changing local owner',
    () async {
      queued();
      api.emitSession(accountA, isExpired: true);
      await uploader.drain();
      expect(transport.sent, isEmpty);
      expect(outbox.pending(), hasLength(1));
      api.emitSession(accountA);
      await uploader.drain();
      expect(transport.sent, [operationId]);
    },
  );

  test(
    'switch accounts while RPC is in flight never ACKs prior owner',
    () async {
      queued();
      final response = Completer<Map<String, dynamic>>();
      transport.handler = (_, _) => response.future;
      final ongoing = uploader.drain();
      await Future<void>.delayed(Duration.zero);
      expect(transport.sent, [operationId]);
      api.emitSession(accountB);
      response.complete({
        'result': 'applied',
        'revision': 1,
        'change_seq': 1,
        'replay': false,
        'processing': 'processed',
      });
      await ongoing;
      expect(outbox.pending(), hasLength(1));
      expect(
        store.box<WorkoutSyncOutboxEntity>().getAll().single.serverRevision,
        isNull,
      );
    },
  );

  test(
    'malformed response cannot turn an uncertain write into success',
    () async {
      queued();
      transport.handler = (_, _) async => {
        'result': 'applied',
        'revision': 1,
        'change_seq': 0,
      };
      await uploader.drain();
      expect(outbox.pending(), hasLength(1));
      expect(store.box<WorkoutSyncOutboxEntity>().getAll().single.attempts, 1);
    },
  );

  test('backfill completed account-bound workouts only once', () async {
    final when = DateTime.utc(2026, 10, 25, 9).millisecondsSinceEpoch;
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: workoutId,
        name: 'Historical completed rows',
        status: 'completed',
        origin: 'northstar_phone',
        startedAtMs: when,
        completedAtMs: when + 3600000,
        originalOffsetMinutes: 330,
        updatedAtMs: when,
      ),
    );
    await uploader.drain();
    expect(transport.sent, hasLength(1));
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 1);
    await uploader.drain();
    expect(transport.sent, hasLength(1));
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 1);
  });

  test('persistent exponential cooldown survives reopening the Store', () {
    queued();
    expect(outbox.reserveNext(nowMs: 1000), isNotNull);
    expect(outbox.reserveNext(nowMs: 1001), isNull);
    store.close();
    store = Store(getObjectBoxModel(), directory: dir.path);
    outbox = ObjectBoxWorkoutOutbox(store);
    expect(outbox.reserveNext(nowMs: 5999), isNull);
    expect(outbox.reserveNext(nowMs: 6000), isNotNull);
    expect(store.box<WorkoutSyncOutboxEntity>().getAll().single.attempts, 2);
  });

  test(
    'bad legacy completion timestamps cannot starve pending uploads',
    () async {
      final at = DateTime.utc(2026, 10, 25, 9).millisecondsSinceEpoch;
      final sessions = store.box<WorkoutSessionEntity>();
      final variations = <(String, String, String, int?, int?)>[
        (
          '00000000-0000-4000-8000-000000000301',
          'completed',
          'northstar_phone',
          null,
          null,
        ),
        (
          '00000000-0000-4000-8000-000000000302',
          'inProgress',
          'northstar_phone',
          null,
          null,
        ),
        (
          '00000000-0000-4000-8000-000000000303',
          'discarded',
          'northstar_phone',
          null,
          null,
        ),
        (
          '00000000-0000-4000-8000-000000000304',
          'completed',
          'northstar_phone',
          at + 3600000,
          at + 7200000,
        ),
        (
          '00000000-0000-4000-8000-000000000305',
          'completed',
          'watch_import',
          at + 3600000,
          null,
        ),
        (
          '00000000-0000-4000-8000-000000000306',
          'completed',
          'northstar_phone',
          at + 3600000,
          null,
        ),
      ];
      for (final (id, status, origin, completion, deleted) in variations) {
        sessions.put(
          WorkoutSessionEntity(
            uuid: id,
            name: 'Existing local log',
            status: status,
            origin: origin,
            startedAtMs: at,
            completedAtMs: completion,
            deletedAtMs: deleted,
            updatedAtMs: at,
            originalOffsetMinutes: 330,
          ),
        );
      }
      queued(); // A current completed workout already awaiting network upload.
      await uploader.drain();
      expect(transport.sent, hasLength(2)); // Existing + valid history only.
      expect(store.box<WorkoutSyncOutboxEntity>().count(), 2);
      expect(
        store
            .box<WorkoutSyncOutboxEntity>()
            .getAll()
            .map((op) => op.sessionUuid)
            .toSet(),
        {workoutId, '00000000-0000-4000-8000-000000000306'},
      );
      expect(uploader.lastFailureKind, isNull);
    },
  );

  test('per-session backfill failures do not roll back other sessions', () {
    final at = DateTime.utc(2026, 10, 25, 9).millisecondsSinceEpoch;
    final sessions = store.box<WorkoutSessionEntity>();
    for (final id in [
      '00000000-0000-4000-8000-000000000341',
      '00000000-0000-4000-8000-000000000342',
    ]) {
      sessions.put(
        WorkoutSessionEntity(
          uuid: id,
          name: 'Historical workout',
          status: 'completed',
          origin: 'northstar_phone',
          startedAtMs: at,
          completedAtMs: at + 3600000,
          originalOffsetMinutes: 330,
          updatedAtMs: at,
        ),
      );
    }
    final outboxWithBadFirstId = ObjectBoxWorkoutOutbox(
      store,
      uuidFactory: MalformedFirstOperationId(),
    );
    expect(outboxWithBadFirstId.backfillCompleted(), 1);
    expect(outboxWithBadFirstId.pending(), hasLength(1));
  });

  test(
    'failed whole backfill is checked once and cannot block the queue',
    () async {
      queued();
      uploader.dispose();
      final faulty = BrokenBackfillOutbox(store);
      uploader = WorkoutUploadCoordinator(
        accountId: accountA,
        auth: auth,
        outbox: faulty,
        transport: transport,
        clock: () => now,
      );
      await uploader.drain();
      expect(faulty.calls, 1);
      expect(transport.sent, [operationId]);
      expect(uploader.lastFailureKind, 'backfill_failed');
      await uploader.drain();
      expect(faulty.calls, 1);
    },
  );

  test('future-dated attempts retry after device clock is corrected', () {
    final op = queued();
    op.attemptedAtMs = 500000000;
    op.attempts = 7;
    store.box<WorkoutSyncOutboxEntity>().put(op);
    final reserved = outbox.reserveNext(nowMs: 500000);
    expect(reserved, isNotNull);
    expect(store.box<WorkoutSyncOutboxEntity>().getAll().single.attempts, 8);
  });

  test('retry backoff doubles and caps at ten minutes', () {
    expect(ObjectBoxWorkoutOutbox.retryDelayMs(0), 0);
    expect(ObjectBoxWorkoutOutbox.retryDelayMs(1), 5000);
    expect(ObjectBoxWorkoutOutbox.retryDelayMs(2), 10000);
    expect(ObjectBoxWorkoutOutbox.retryDelayMs(3), 20000);
    expect(ObjectBoxWorkoutOutbox.retryDelayMs(1000), 600000);
  });

  test('drain makes at most 25 uploads without a later kick', () async {
    for (var i = 1; i <= 30; i++) {
      final tail = i.toRadixString(16).padLeft(12, '0');
      queued(
        opId: '00000000-0000-4000-8000-$tail',
        sessionId: '00000000-0000-4000-9000-$tail',
        createdAtMs: i,
      );
    }
    await uploader.drain();
    expect(transport.sent.length, 25);
    expect(outbox.pending(), hasLength(5));
    await uploader.drain();
    expect(transport.sent.length, 30);
  });

  test('kick during in-flight RPC guarantees a further drain', () async {
    for (var i = 1; i <= 26; i++) {
      final tail = i.toRadixString(16).padLeft(12, '0');
      queued(
        opId: '00000000-0000-4000-a000-$tail',
        sessionId: '00000000-0000-4000-b000-$tail',
        createdAtMs: i,
      );
    }
    final response = Completer<Map<String, dynamic>>();
    var first = true;
    transport.handler = (_, revision) {
      if (first) {
        first = false;
        return response.future;
      }
      return Future.value({
        'result': 'applied',
        'revision': revision + 1,
        'change_seq': revision + 1,
        'processing': 'processed',
        'replay': false,
      });
    };
    final draining = uploader.drain();
    await Future<void>.delayed(Duration.zero);
    expect(uploader.isUploading, true);
    uploader.kick();
    response.complete({
      'result': 'applied',
      'revision': 1,
      'change_seq': 1,
      'replay': false,
      'processing': 'processed',
    });
    await draining;
    expect(transport.sent.length, 26);
    expect(outbox.pending(), isEmpty);
  });

  test(
    'missing replay alone cannot acknowledge a successful-looking reply',
    () async {
      queued();
      transport.handler = (_, _) async => {
        'result': 'applied',
        'revision': 1,
        'change_seq': 1,
        'processing': 'processed',
      };
      await uploader.drain();
      expect(outbox.pending(), hasLength(1));
      expect(uploader.lastFailureKind, 'invalid_server_ack');
    },
  );

  test(
    'corrupt reserved row updates blocked count after transaction',
    () async {
      final row = queued();
      row.action = 'unsupported';
      store.box<WorkoutSyncOutboxEntity>().put(row);
      var updates = 0;
      uploader.dispose();
      uploader = WorkoutUploadCoordinator(
        accountId: accountA,
        auth: auth,
        outbox: outbox,
        transport: transport,
        clock: () => now,
        onQueueChanged: () => updates++,
      );
      await uploader.drain();
      expect(updates, 1);
      expect(outbox.blockedCount(), 1);
      expect(transport.sent, isEmpty);
    },
  );

  test('transport checks session owner, expiry and anonymous status', () async {
    final seconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    bool allowed(String? id, bool anon, int? exp) => matchesCloudWorkoutSession(
      sessionUserId: id,
      anonymous: anon,
      expiresAtSeconds: exp,
      accountId: accountA,
      nowSeconds: seconds,
    );
    expect(allowed(accountA, false, seconds + 300), true);
    expect(allowed(accountB, false, seconds + 300), false);
    expect(allowed(accountA, true, seconds + 300), false);
    expect(allowed(accountA, false, seconds), false);
    expect(allowed(accountA, false, null), false);
    expect(allowed(null, false, seconds + 300), false);

    final client = SupabaseClient(
      'https://localhost.supabase.co',
      'sb_publishable_test',
    );
    final rpc = SupabaseWorkoutUploadTransport(client, accountA);
    final op = queued();
    final operation = WorkoutSyncOperation(
      operationUuid: op.operationUuid,
      sessionUuid: op.sessionUuid,
      localRevision: op.localRevision,
      action: op.action,
      payloadJson: op.payloadJson,
      createdAtMs: op.createdAtMs,
    );
    await expectLater(
      rpc.send(operation, expectedServerRevision: 0),
      throwsA(isA<AuthException>()),
    );
  });

  test('app resume wakes a previously paused uploader', () async {
    queued();
    uploader.didChangeAppLifecycleState(AppLifecycleState.paused);
    await uploader.drain();
    expect(transport.sent, isEmpty);
    uploader.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(transport.sent, [operationId]);
  });

  testWidgets('account upload host starts after mount and wakes on sign-in', (
    tester,
  ) async {
    queued();
    api.emitSession(accountA, isExpired: true);
    final container = ProviderContainer(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(store),
        accountAuthControllerProvider.overrideWithValue(auth),
        workoutUploadTransportProvider.overrideWithValue((_) => transport),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: AccountWorkoutUploadHost(child: Text('Workout logger')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Workout logger'), findsOneWidget);
    expect(transport.sent, isEmpty);
    api.emitSession(accountA);
    await tester.pump();
    await tester.pump();
    expect(transport.sent, [operationId]);
    await tester.pumpWidget(const SizedBox.shrink());
    // An UncontrolledProviderScope does not own its ProviderContainer. Dispose
    // it explicitly before Flutter verifies there are no periodic timers.
    container.dispose();
    await tester.pump();
  });

  test('malformed snapshot stays blocked rather than sent', () async {
    queued(payload: '{"status":"paused"}');
    await uploader.drain();
    expect(transport.sent, isEmpty);
    expect(outbox.blockedCount(), 1);
  });
}
