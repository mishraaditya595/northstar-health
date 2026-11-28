import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/health/data/health_export_entities.dart';
import 'package:beyondrep/features/health/data/health_export_repository.dart';
import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:beyondrep/features/health/data/watch_workout_lookup.dart';
import 'package:beyondrep/features/health/domain/health_export_state.dart';
import 'package:beyondrep/features/watch/application/watch_workout_health_inbox.dart';
import 'package:beyondrep/features/watch/application/watch_workout_inbox.dart';
import 'package:beyondrep/features/watch/data/objectbox_watch_workout_importer.dart';
import 'package:beyondrep/features/watch/data/watch_link.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';
import '../support/fake_health_workout_writer.dart';

class _Link implements WatchLink {
  final sent = <String>[];

  @override
  Future<void> transfer(String json) async => sent.add(json);

  @override
  Future<bool> isReachableForUpdates() async => true;
  @override
  Future<void> updateContext(Map<String, String> latestByType) async {}
  @override
  Stream<void> get watchStateChanges => const Stream.empty();
  @override
  Stream<void> get watchReachabilityChanges => const Stream.empty();
  @override
  Future<WatchDeviceStatus> status() async => WatchDeviceStatus.unsupported;
  @override
  Stream<String> get messages => const Stream.empty();
  @override
  Future<void> startMessages() async {}

  Ack ackAt(int i) =>
      WatchMessage.fromJson(jsonDecode(sent[i]) as Map<String, Object?>) as Ack;
}

class _Ids implements UuidFactory {
  @override
  String newId() => '88888888-4444-4444-8444-000000000001';
}

Map<String, Object?> _fixtureJson(String name) => jsonDecode(
  File('../../contracts/watch_link/v1/fixtures/valid/$name.json')
      .readAsStringSync(),
) as Map<String, Object?>;

const _workoutUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

WorkoutHealth _health({
  String? accountKey,
  Object? kcal,
  List<Map<String, Object?>>? heartRate,
}) {
  final json = _fixtureJson('workout_health');
  json['account_key'] = accountKey ?? watchAccountKey(accountA);
  final body = json['body']! as Map<String, Object?>;
  if (kcal != null) body['total_kcal'] = kcal;
  if (heartRate != null) body['heart_rate'] = heartRate;
  return WatchMessage.fromJson(json) as WorkoutHealth;
}

void main() {
  late Directory dir;
  late Store store;
  late _Link link;
  late String? user;
  late FakeHealthWorkoutWriter writer;
  late ObjectBoxHealthExportRepository repository;
  late int written;
  late DateTime now;
  late WatchWorkoutHealthInbox inbox;

  WorkoutSessionEntity workout() => store
      .box<WorkoutSessionEntity>()
      .query(WorkoutSessionEntity_.uuid.equals(_workoutUuid))
      .build()
      .findFirst()!;

  Future<void> importWorkout() async {
    final json = _fixtureJson('completed_workout');
    json['account_key'] = watchAccountKey(accountA);
    final imported = WatchWorkoutInbox(
      link: _Link(),
      importer: (id) => ObjectBoxWatchWorkoutImporter(
        store,
        accountId: id,
        activeAccountId: () => user,
      ),
      signedInUserId: () => user,
      ids: _Ids(),
      clock: () => DateTime.utc(2026, 10, 23, 12),
      onStored: () {},
    );
    expect(
      await imported.handle(WatchMessage.fromJson(json) as CompletedWorkout),
      WatchImportResult.stored,
    );
  }

  WatchWorkoutHealthInbox build({WatchWorkoutLookup? lookup}) =>
      WatchWorkoutHealthInbox(
        link: link,
        signedInUserId: () => user,
        ids: _Ids(),
        clock: () => now,
        workout: lookup ?? (uuid) => watchWorkoutCandidate(store, uuid),
        repository: repository,
        writer: writer,
        onWritten: (_) => written++,
      );

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('beyondrep-whealth-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    link = _Link();
    user = accountA;
    writer = FakeHealthWorkoutWriter(isIos: false);
    repository = ObjectBoxHealthExportRepository(store);
    repository.enable(accountA, DateTime.utc(2026, 10, 1));
    written = 0;
    now = DateTime.utc(2026, 10, 23, 12);
    inbox = build();
    await importWorkout();
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  test('writes the workout with heart rate and calories, records a receipt '
      'and acks stored', () async {
    final message = _health();
    final ack = await inbox.handle(message);
    expect(ack?.result, 'stored');
    expect(ack?.reason, isNull);
    expect(ack?.ackedMessageId, message.messageId);
    expect(link.sent, hasLength(1));
    expect(link.ackAt(0).accountKey, watchAccountKey(accountA));

    final record = writer.writes.single;
    expect(record.workoutUuid, _workoutUuid);
    expect(record.name, 'Synthetic push day');
    expect(record.start, DateTime.utc(2026, 10, 23, 11));
    expect(record.end, DateTime.utc(2026, 10, 23, 11, 40));
    // The Health Connect version is the workout version times 1000 plus the
    // attempt, so a retry is never ignored as not newer.
    expect(record.version, workout().updatedAtMs * 1000 + 1);
    expect(record.totalKcal, 312.5);
    expect(record.heartRate.map((p) => p.bpm), [71, 84, 96]);
    expect(record.heartRate.first.at, DateTime.utc(2026, 10, 23, 11));
    expect(record.heartRate.last.at, DateTime.utc(2026, 10, 23, 11, 39));

    final receipt = repository.receipt(_workoutUuid)!;
    expect(receipt.platform, 'health_connect');
    expect(receipt.state, HealthExportState.confirmed.wire);
    expect(receipt.exportedVersion, workout().updatedAtMs);
    expect(receipt.platformRecordId, _workoutUuid);
    expect(written, 1);
  });

  test('a message with no heart rate and no calories still writes the '
      'workout it is about', () async {
    final json = _fixtureJson('workout_health_minimal');
    json['account_key'] = watchAccountKey(accountA);
    final ack = await inbox.handle(
      WatchMessage.fromJson(json) as WorkoutHealth,
    );
    expect(ack?.result, 'stored');
    expect(writer.writes.single.totalKcal, isNull);
    expect(writer.writes.single.heartRate, isEmpty);
  });

  test('a message for another account is rejected wrong_account and writes '
      'nothing', () async {
    final ack = await inbox.handle(
      _health(accountKey: watchAccountKey(accountB)),
    );
    expect(ack?.result, 'rejected');
    expect(ack?.reason, 'wrong_account');
    expect(writer.writes, isEmpty);
    expect(repository.receipt(_workoutUuid), isNull);
  });

  test('signed out: no ack and no write', () async {
    user = null;
    expect(await inbox.handle(_health()), isNull);
    expect(link.sent, isEmpty);
    expect(writer.writes, isEmpty);
  });

  test('a workout the phone has not imported yet gets no ack, so the watch '
      'resends after the import', () async {
    // The Data Layer delivered the health message before the workout: the
    // phone does not hold the workout yet.
    final early = build(lookup: (_) => null);
    final message = _health();
    expect(await early.handle(message), isNull);
    expect(link.sent, isEmpty);
    expect(writer.writes, isEmpty);
    expect(repository.receipt(_workoutUuid), isNull);
    expect((await inbox.handle(message))?.result, 'stored');
    expect(writer.writes, hasLength(1));
  });

  test(
    'a workout that is not completed, or not a watch workout, gets no ack',
    () async {
      final box = store.box<WorkoutSessionEntity>();
      final row = workout()..status = 'inProgress';
      box.put(row);
      expect(await inbox.handle(_health()), isNull);
      row
        ..status = 'completed'
        ..origin = 'northstar_phone';
      box.put(row);
      expect(await inbox.handle(_health()), isNull);
      expect(link.sent, isEmpty);
      expect(writer.writes, isEmpty);
    },
  );

  test(
    'a workout deleted on the phone is not written: rejected not_written',
    () async {
      store.box<WorkoutSessionEntity>().put(
        workout()
          ..deletedAtMs = DateTime.utc(2026, 10, 24).millisecondsSinceEpoch,
      );
      final ack = await inbox.handle(_health());
      expect(ack?.result, 'rejected');
      expect(ack?.reason, 'not_written');
      expect(writer.writes, isEmpty);
      expect(repository.receipt(_workoutUuid), isNull);
    },
  );

  group('rejected not_written, nothing written', () {
    Future<void> expectNotWritten() async {
      final ack = await inbox.handle(_health());
      expect(ack?.result, 'rejected');
      expect(ack?.reason, 'not_written');
      expect(link.sent, hasLength(1));
      expect(writer.writes, isEmpty);
      expect(repository.receipt(_workoutUuid), isNull);
      expect(written, 0);
    }

    test('on iOS', () async {
      writer = FakeHealthWorkoutWriter(isIos: true);
      inbox = build();
      await expectNotWritten();
    });

    test('Health Connect is not installed', () async {
      writer.available = false;
      await expectNotWritten();
    });

    test('the save-workouts switch is off', () async {
      repository.disable(accountA);
      await expectNotWritten();
    });
  });

  group('switch on but access missing: no ack, the watch keeps the series', () {
    test('heart rate or calories write access is missing', () async {
      writer.watchHealthAccess = false;
      expect(await inbox.handle(_health()), isNull);
      expect(link.sent, isEmpty);
      expect(writer.writes, isEmpty);
      expect(repository.receipt(_workoutUuid), isNull);
      expect(written, 0);
      // The user allows access; the watch resends and it is written.
      writer.watchHealthAccess = true;
      expect((await inbox.handle(_health()))?.result, 'stored');
      expect(writer.writes, hasLength(1));
    });

    test('Health Connect reports unavailable during the write', () async {
      writer.writeResults.add(const HealthWriteUnavailable());
      expect(await inbox.handle(_health()), isNull);
      expect(link.sent, isEmpty);
    });
  });

  test('a receipt that already says exported is acked duplicate with no '
      'second write', () async {
    expect((await inbox.handle(_health()))?.result, 'stored');
    final again = _health();
    final ack = await inbox.handle(again);
    expect(ack?.result, 'duplicate');
    expect(ack?.ackedMessageId, again.messageId);
    expect(writer.writes, hasLength(1));
    expect(written, 1);
  });

  test('two copies arriving together write once', () async {
    final gate = Completer<void>();
    writer.writeGate = gate.future;
    final first = inbox.handle(_health());
    final second = inbox.handle(_health());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate.complete();
    final results = [(await first)?.result, (await second)?.result];
    expect(results, ['stored', 'duplicate']);
    expect(writer.writes, hasLength(1));
  });

  test('a workout edited after the write is written again with the newer '
      'version', () async {
    await inbox.handle(_health());
    final row = workout();
    store.box<WorkoutSessionEntity>().put(row..updatedAtMs += 1000);
    final ack = await inbox.handle(_health());
    expect(ack?.result, 'stored');
    expect(writer.writes, hasLength(2));
    expect(writer.writes.last.version, row.updatedAtMs * 1000 + 1);
    expect(
      writer.writes.last.version,
      greaterThan(writer.writes.first.version),
    );
  });

  test('a failed write sends no ack and leaves a retryable receipt', () async {
    writer.writeResults.add(const HealthWriteFailed());
    expect(await inbox.handle(_health()), isNull);
    expect(link.sent, isEmpty);
    expect(
      repository.receipt(_workoutUuid)!.state,
      HealthExportState.failedRetryable.wire,
    );
    expect(written, 0);
    // The watch resends and this time it works.
    now = now.add(const Duration(minutes: 2));
    expect((await inbox.handle(_health()))?.result, 'stored');
  });

  test(
    'a retry after a failure uses a greater Health Connect version',
    () async {
      final base = workout().updatedAtMs * 1000;
      writer.writeResults.add(const HealthWriteFailed());
      await inbox.handle(_health());
      now = now.add(const Duration(minutes: 2));
      writer.writeResults.add(const HealthWriteFailed());
      await inbox.handle(_health());
      now = now.add(const Duration(minutes: 10));
      await inbox.handle(_health());
      expect(writer.writes.map((w) => w.version), [
        base + 1,
        base + 2,
        base + 3,
      ]);
      // Confirmed: the attempt counter starts again for the next edit.
      expect(repository.receipt(_workoutUuid)!.attempts, 0);
    },
  );

  test('a resend inside the receipt backoff is not written again', () async {
    writer.writeResults.add(const HealthWriteFailed());
    expect(await inbox.handle(_health()), isNull);
    now = now.add(const Duration(seconds: 30));
    expect(await inbox.handle(_health()), isNull);
    expect(writer.writes, hasLength(1));
    expect(link.sent, isEmpty);
    now = now.add(const Duration(seconds: 31));
    expect((await inbox.handle(_health()))?.result, 'stored');
    expect(writer.writes, hasLength(2));
  });

  test('a denied write sends no ack, blocks the receipt and is retried at '
      'once when the watch resends', () async {
    writer.writeResults.add(const HealthWriteDenied());
    expect(await inbox.handle(_health()), isNull);
    expect(link.sent, isEmpty);
    expect(
      repository.receipt(_workoutUuid)!.state,
      HealthExportState.blocked.wire,
    );
    expect((await inbox.handle(_health()))?.result, 'stored');
  });

  test('a message whose times differ from the workout by more than two '
      'seconds is ignored: no ack, no write', () async {
    Future<Ack?> withStart(String start, {String? end}) {
      final json = _fixtureJson('workout_health');
      json['account_key'] = watchAccountKey(accountA);
      final body = json['body']! as Map<String, Object?>;
      body['start_utc'] = start;
      body['heart_rate'] = <Object?>[];
      if (end != null) body['end_utc'] = end;
      return inbox.handle(WatchMessage.fromJson(json) as WorkoutHealth);
    }

    expect(await withStart('2026-10-23T11:00:03Z'), isNull);
    expect(
      await withStart('2026-10-23T11:00:00Z', end: '2026-10-23T11:41:00Z'),
      isNull,
    );
    expect(link.sent, isEmpty);
    expect(writer.writes, isEmpty);
    expect(repository.receipt(_workoutUuid), isNull);
    expect((await withStart('2026-10-23T11:00:02Z'))?.result, 'stored');
  });

  test('the receipt says writing while the platform call runs', () async {
    final gate = Completer<void>();
    writer.writeGate = gate.future;
    final pending = inbox.handle(_health());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      repository.receipt(_workoutUuid)!.state,
      HealthExportState.writing.wire,
    );
    gate.complete();
    await pending;
  });

  test('an account change during the write sends no ack and confirms '
      'nothing', () async {
    writer.onWrite = () => user = accountB;
    expect(await inbox.handle(_health()), isNull);
    expect(link.sent, isEmpty);
    expect(written, 0);
  });

  test('the values are never stored: only a receipt is added and no entity '
      'has a heart rate or calories property', () async {
    final before = store.box<HealthExportReceiptEntity>().count();
    final message = _health(
      kcal: 987,
      heartRate: [
        {'at_utc': '2026-10-23T11:00:00Z', 'bpm': 173},
      ],
    );
    await inbox.handle(message);
    expect(writer.writes.single.totalKcal, 987);
    expect(writer.writes.single.heartRate.single.bpm, 173);
    expect(store.box<HealthExportReceiptEntity>().count(), before + 1);
    final receipt = repository.receipt(_workoutUuid)!;
    final fields = [
      receipt.workoutUuid,
      receipt.platform,
      receipt.state,
      receipt.platformRecordId,
      '${receipt.exportedVersion}',
      '${receipt.attempts}',
    ].join(' ');
    expect(fields, isNot(contains('173')));
    expect(fields, isNot(contains('987')));
    final model = jsonDecode(
      File('lib/objectbox-model.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final names = [
      for (final e in model['entities']! as List)
        for (final p in (e as Map)['properties'] as List)
          '${e['name']}.${(p as Map)['name']}',
    ];
    expect(
      names.where(
        (n) =>
            RegExp(r'heart|bpm|kcal|calor', caseSensitive: false).hasMatch(n),
      ),
      isEmpty,
    );
  });
}
