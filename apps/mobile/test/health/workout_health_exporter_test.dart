import 'dart:io';

import 'package:beyondrep/features/health/data/health_export_entities.dart';
import 'package:beyondrep/features/health/data/health_export_repository.dart';
import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:beyondrep/features/health/data/workout_health_exporter.dart';
import 'package:beyondrep/features/health/domain/health_export_state.dart';
import 'package:beyondrep/features/watch/data/watch_workout_receipt_entity.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_workout_writer.dart';

const _account = '11111111-1111-4111-8111-111111111111';
final _now = DateTime.utc(2026, 11, 27, 12);

String _uuid(int i) =>
    '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}';

void main() {
  late Directory dir;
  late Store store;
  late ObjectBoxHealthExportRepository repo;
  late FakeHealthWorkoutWriter writer;
  late bool current;
  late bool watchPaired;
  late DateTime now;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('beyondrep-hexporter-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    repo = ObjectBoxHealthExportRepository(store);
    writer = FakeHealthWorkoutWriter();
    current = true;
    watchPaired = false;
    now = _now;
    repo.enable(_account, _now);
  });
  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  WorkoutHealthExporter exporter() => WorkoutHealthExporter(
    store: store,
    accountId: _account,
    repository: repo,
    writer: writer,
    stillCurrent: () => current,
    watchPaired: () => watchPaired,
    clock: () => now,
  );

  DateTime ago(Duration d) => _now.subtract(d);

  WorkoutSessionEntity session(
    int i, {
    Duration finishedAgo = const Duration(days: 1),
    String origin = 'northstar_phone',
    String status = 'completed',
    bool deleted = false,
    int updatedAtMs = 1000,
  }) {
    final end = ago(finishedAgo);
    final s = WorkoutSessionEntity(
      uuid: _uuid(i),
      name: 'Workout $i',
      status: status,
      origin: origin,
      startedAtMs: end
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
      completedAtMs: end.millisecondsSinceEpoch,
      originalOffsetMinutes: 60,
      updatedAtMs: updatedAtMs,
      deletedAtMs: deleted ? end.millisecondsSinceEpoch : null,
    );
    store.box<WorkoutSessionEntity>().put(s);
    return s;
  }

  HealthExportReceiptEntity? receipt(int i) => repo.receipt(_uuid(i));

  void putReceipt(
    int i,
    HealthExportState state, {
    int version = 0,
    String? id,
    int attempts = 0,
    DateTime? lastAttempt,
  }) => repo.putReceipt(
    HealthExportReceiptEntity(
      workoutUuid: _uuid(i),
      platform: writer.platform,
      state: state.wire,
      exportedVersion: version,
      platformRecordId: id,
      attempts: attempts,
      lastAttemptAtMs: (lastAttempt ?? _now).millisecondsSinceEpoch,
      updatedAtMs: 1,
    ),
  );

  test('saves a completed phone workout and confirms the receipt', () async {
    final s = session(1);
    final result = await exporter().runPass();
    expect(writer.writes, hasLength(1));
    final w = writer.writes.single;
    expect(w.workoutUuid, _uuid(1));
    expect(w.name, 'Workout 1');
    expect(w.offsetMinutes, 60);
    expect(w.version, 1000);
    expect(w.start.millisecondsSinceEpoch, s.startedAtMs);
    expect(w.end.millisecondsSinceEpoch, s.completedAtMs);
    final r = receipt(1)!;
    expect(r.state, 'confirmed');
    expect(r.exportedVersion, 1000);
    expect(r.platformRecordId, 'hk-0');
    expect(r.platform, 'healthkit');
    expect((result.saved, result.waiting, result.blocked), (1, 0, false));
  });

  test('never writes watch-origin, active or other states', () async {
    session(1, origin: 'beyondrep_watch');
    session(2, status: 'inProgress');
    await exporter().runPass();
    expect(writer.writes, isEmpty);
  });

  test('theExporterNeverWritesAWatchWorkout', () async {
    writer = FakeHealthWorkoutWriter(isIos: false);
    session(1, origin: 'beyondrep_watch');
    final result = await exporter().runPass();
    expect(writer.writes, isEmpty);
    expect(writer.deletes, isEmpty);
    expect(receipt(1), isNull);
    expect((result.saved, result.waiting), (0, 0));
  });

  test('deleting a watch workout deletes its Health Connect copy', () async {
    writer = FakeHealthWorkoutWriter(isIos: false);
    final s = session(1, origin: 'beyondrep_watch', deleted: true);
    putReceipt(1, HealthExportState.confirmed, version: 1000, id: _uuid(1));
    await exporter().runPass();
    expect(writer.deletes, [
      (workoutUuid: _uuid(1), platformRecordId: _uuid(1)),
    ]);
    expect(
      writer.deleteWindows.single.start?.millisecondsSinceEpoch,
      s.startedAtMs,
    );
    expect(
      writer.deleteWindows.single.end?.millisecondsSinceEpoch,
      s.completedAtMs,
    );
    expect(receipt(1)!.state, 'deleted');
  });

  test('on iOS a deleted watch workout is never touched by the exporter '
      '(the watch owns its HealthKit entry)', () async {
    session(1, origin: 'beyondrep_watch', deleted: true);
    putReceipt(1, HealthExportState.confirmed, version: 1000, id: 'hk-1');
    await exporter().runPass();
    expect(writer.deletes, isEmpty);
    expect(receipt(1)!.state, 'confirmed');
  });

  test('a watch workout that is not deleted keeps its copy', () async {
    writer = FakeHealthWorkoutWriter(isIos: false);
    session(1, origin: 'beyondrep_watch');
    putReceipt(1, HealthExportState.confirmed, version: 1000, id: _uuid(1));
    await exporter().runPass();
    expect(writer.deletes, isEmpty);
    expect(receipt(1)!.state, 'confirmed');
  });

  test('a phone workout delete sends no window', () async {
    writer = FakeHealthWorkoutWriter(isIos: false);
    session(1, deleted: true);
    putReceipt(1, HealthExportState.confirmed, version: 1000, id: _uuid(1));
    await exporter().runPass();
    expect(writer.deleteWindows.single.start, isNull);
  });

  test('saves all past workouts in two passes when there are 60', () async {
    for (var i = 0; i < 60; i++) {
      session(i + 1, finishedAgo: Duration(days: i + 1));
    }
    final first = await exporter().runPass();
    expect(writer.writes, hasLength(50));
    expect((first.saved, first.waiting), (50, 10));
    final second = await exporter().runPass();
    expect(writer.writes, hasLength(60));
    expect(writer.writes.map((w) => w.workoutUuid).toSet(), hasLength(60));
    expect((second.saved, second.waiting), (60, 0));
  });

  test('does nothing when the switch is off', () async {
    repo.disable(_account);
    session(1);
    final result = await exporter().runPass();
    expect(writer.writes, isEmpty);
    expect(repo.allReceipts(), isEmpty);
    expect((result.saved, result.waiting), (0, 0));
  });

  test('does nothing when the store is unavailable', () async {
    writer.available = false;
    session(1);
    await exporter().runPass();
    expect(writer.writes, isEmpty);
    expect(repo.allReceipts(), isEmpty);
  });

  test(
    'marks blocked without write access and writes after access is granted',
    () async {
      writer.writeAccess = false;
      session(1);
      final first = await exporter().runPass();
      expect(writer.writes, isEmpty);
      expect(receipt(1)!.state, 'blocked');
      expect(first.blocked, isTrue);
      writer.writeAccess = true;
      final second = await exporter().runPass();
      expect(writer.writes, hasLength(1));
      expect(receipt(1)!.state, 'confirmed');
      expect(second.blocked, isFalse);
    },
  );

  test('a write that is denied marks the receipt blocked', () async {
    session(1);
    writer.writeResults.add(const HealthWriteDenied());
    final result = await exporter().runPass();
    expect(receipt(1)!.state, 'blocked');
    expect(result.blocked, isTrue);
  });

  test('resumes a writing receipt by adopting the own copy on iOS', () async {
    final s = session(1);
    putReceipt(1, HealthExportState.writing, attempts: 1);
    writer.store.add(
      OwnStoredWorkout(
        platformRecordId: 'hk-existing',
        sourceId: 'in.beyondrep.app',
        start: DateTime.fromMillisecondsSinceEpoch(s.startedAtMs, isUtc: true),
        end: DateTime.fromMillisecondsSinceEpoch(s.completedAtMs!, isUtc: true),
      ),
    );
    await exporter().runPass();
    expect(writer.writes, isEmpty);
    final r = receipt(1)!;
    expect(r.state, 'confirmed');
    expect(r.platformRecordId, 'hk-existing');
    expect(r.exportedVersion, 1000);
  });

  test('rewrites with the same id on Android after a crash', () async {
    writer = FakeHealthWorkoutWriter(isIos: false);
    session(1);
    putReceipt(1, HealthExportState.writing, attempts: 1);
    await exporter().runPass();
    expect(writer.lookups, isEmpty);
    expect(writer.writes.single.workoutUuid, _uuid(1));
    expect(receipt(1)!.state, 'confirmed');
    expect(receipt(1)!.platformRecordId, _uuid(1));
    expect(receipt(1)!.platform, 'health_connect');
  });

  test('skips when the watch already saved an overlapping workout', () async {
    final s = session(1);
    writer.store.add(
      OwnStoredWorkout(
        platformRecordId: 'hk-watch',
        sourceId: 'in.beyondrep.app.watchkitapp',
        start: DateTime.fromMillisecondsSinceEpoch(
          s.startedAtMs + 60000,
          isUtc: true,
        ),
        end: DateTime.fromMillisecondsSinceEpoch(
          s.completedAtMs! - 60000,
          isUtc: true,
        ),
      ),
    );
    final result = await exporter().runPass();
    expect(writer.writes, isEmpty);
    expect(receipt(1)!.state, 'skippedWatch');
    expect((result.saved, result.waiting), (0, 0));
    await exporter().runPass();
    expect(writer.writes, isEmpty);
  });

  test('a failed read of the store still writes', () async {
    session(1);
    writer.readFails = true;
    await exporter().runPass();
    expect(writer.writes, hasLength(1));
  });

  test('link after confirm deletes our copy and marks supersededByWatch, and a later pass writes nothing', () async {
    session(1);
    await exporter().runPass();
    expect(receipt(1)!.state, 'confirmed');
    store.box<WatchWorkoutReceiptEntity>().put(
      WatchWorkoutReceiptEntity(
        workoutUuid: _uuid(1),
        messageId: 'm1',
        platformWorkoutUuid: 'watch-hk',
        receivedAtMs: 1,
      ),
    );
    await exporter().runPass();
    expect(writer.deletes.single.platformRecordId, 'hk-0');
    expect(receipt(1)!.state, 'supersededByWatch');
    await exporter().runPass();
    expect(writer.writes, hasLength(1));
    expect(writer.deletes, hasLength(1));
  });

  test('deleting a confirmed workout deletes the platform copy and keeps a deleted receipt', () async {
    final s = session(1);
    await exporter().runPass();
    store.box<WorkoutSessionEntity>().put(
      s..deletedAtMs = _now.millisecondsSinceEpoch,
    );
    await exporter().runPass();
    expect(writer.deletes.single.platformRecordId, 'hk-0');
    expect(receipt(1)!.state, 'deleted');
    expect(writer.store, isEmpty);
  });

  test('delete denied keeps the receipt blocked', () async {
    final s = session(1);
    await exporter().runPass();
    store.box<WorkoutSessionEntity>().put(
      s..deletedAtMs = _now.millisecondsSinceEpoch,
    );
    writer.deleteResult = const HealthWriteDenied();
    final result = await exporter().runPass();
    expect(receipt(1)!.state, 'blocked');
    expect(result.blocked, isTrue);
    writer.deleteResult = const HealthWriteOk('');
    await exporter().runPass();
    expect(receipt(1)!.state, 'deleted');
  });

  test(
    'a delete that fails stays deleting, backs off and is retried',
    () async {
      final s = session(1);
      await exporter().runPass();
      store.box<WorkoutSessionEntity>().put(
        s..deletedAtMs = _now.millisecondsSinceEpoch,
      );
      writer.deleteResult = const HealthWriteFailed();
      await exporter().runPass();
      expect(receipt(1)!.state, 'deleting');
      expect(receipt(1)!.attempts, 1);
      expect(writer.deletes, hasLength(1));
      now = _now.add(const Duration(seconds: 30));
      await exporter().runPass();
      expect(writer.deletes, hasLength(1), reason: 'inside the backoff');
      writer.deleteResult = const HealthWriteOk('');
      now = _now.add(const Duration(minutes: 2));
      await exporter().runPass();
      expect(writer.deletes, hasLength(2));
      expect(receipt(1)!.state, 'deleted');
    },
  );

  test(
    'iOS: a failed delete of a copy that is no longer there counts as gone',
    () async {
      final s = session(1);
      await exporter().runPass();
      writer.store.clear();
      store.box<WorkoutSessionEntity>().put(
        s..deletedAtMs = _now.millisecondsSinceEpoch,
      );
      writer.deleteResult = const HealthWriteFailed();
      await exporter().runPass();
      expect(receipt(1)!.state, 'deleted');
    },
  );

  test(
    'iOS: a failed delete with the copy still there stays deleting',
    () async {
      final s = session(1);
      await exporter().runPass();
      store.box<WorkoutSessionEntity>().put(
        s..deletedAtMs = _now.millisecondsSinceEpoch,
      );
      writer.deleteResult = const HealthWriteFailed();
      await exporter().runPass();
      expect(receipt(1)!.state, 'deleting');
    },
  );

  test('iOS: a failed delete whose lookup read fails stays deleting', () async {
    final s = session(1);
    await exporter().runPass();
    store.box<WorkoutSessionEntity>().put(
      s..deletedAtMs = _now.millisecondsSinceEpoch,
    );
    writer.deleteResult = const HealthWriteFailed();
    writer.readFails = true;
    await exporter().runPass();
    expect(receipt(1)!.state, 'deleting');
  });

  test('Android: a failed delete stays deleting', () async {
    writer = FakeHealthWorkoutWriter(isIos: false);
    final s = session(1);
    await exporter().runPass();
    store.box<WorkoutSessionEntity>().put(
      s..deletedAtMs = _now.millisecondsSinceEpoch,
    );
    writer.deleteResult = const HealthWriteFailed();
    await exporter().runPass();
    expect(receipt(1)!.state, 'deleting');
    expect(writer.lookups, isEmpty);
  });

  test(
    'supersede with no platform id on iOS deletes our exact copy first',
    () async {
      final s = session(1);
      putReceipt(1, HealthExportState.writing, attempts: 1);
      writer.store.add(
        OwnStoredWorkout(
          platformRecordId: 'hk-orphan',
          sourceId: 'in.beyondrep.app',
          start: DateTime.fromMillisecondsSinceEpoch(
            s.startedAtMs,
            isUtc: true,
          ),
          end: DateTime.fromMillisecondsSinceEpoch(
            s.completedAtMs!,
            isUtc: true,
          ),
        ),
      );
      store.box<WatchWorkoutReceiptEntity>().put(
        WatchWorkoutReceiptEntity(
          workoutUuid: _uuid(1),
          messageId: 'm1',
          platformWorkoutUuid: 'watch-hk',
          receivedAtMs: 1,
        ),
      );
      await exporter().runPass();
      expect(writer.deletes.single.platformRecordId, 'hk-orphan');
      expect(receipt(1)!.state, 'supersededByWatch');
    },
  );

  test('supersede with no platform id and no copy marks superseded; a failed lookup retries', () async {
    session(1);
    putReceipt(1, HealthExportState.writing, attempts: 1);
    store.box<WatchWorkoutReceiptEntity>().put(
      WatchWorkoutReceiptEntity(
        workoutUuid: _uuid(1),
        messageId: 'm1',
        platformWorkoutUuid: 'watch-hk',
        receivedAtMs: 1,
      ),
    );
    writer.readFails = true;
    await exporter().runPass();
    expect(receipt(1)!.state, 'writing');
    writer.readFails = false;
    await exporter().runPass();
    expect(writer.deletes, isEmpty);
    expect(receipt(1)!.state, 'supersededByWatch');
  });

  test('turning the switch off stops a running backfill', () async {
    session(1, finishedAgo: const Duration(days: 2));
    session(2, finishedAgo: const Duration(days: 1));
    writer.onWrite = () => repo.disable(_account);
    await exporter().runPass();
    expect(writer.writes, hasLength(1));
    expect(receipt(2), isNull);
  });

  test('iOS restored tombstone with an own copy deletes it', () async {
    final s = session(1, deleted: true);
    writer.store.add(
      OwnStoredWorkout(
        platformRecordId: 'hk-other-phone',
        sourceId: 'in.beyondrep.app',
        start: DateTime.fromMillisecondsSinceEpoch(s.startedAtMs, isUtc: true),
        end: DateTime.fromMillisecondsSinceEpoch(s.completedAtMs!, isUtc: true),
      ),
    );
    await exporter().runPass();
    expect(writer.deletes.single.platformRecordId, 'hk-other-phone');
    expect(receipt(1)!.state, 'deleted');
    expect(writer.writes, isEmpty);
    final lookups = writer.lookups.length;
    await exporter().runPass();
    expect(writer.lookups, hasLength(lookups));
  });

  test('iOS tombstone with no copy is looked up once, then a deleted receipt stands', () async {
    session(1, deleted: true);
    await exporter().runPass();
    expect(writer.lookups, hasLength(1));
    expect(receipt(1)!.state, 'deleted');
    await exporter().runPass();
    expect(writer.lookups, hasLength(1));
  });

  test('iOS tombstone whose lookup read fails is retried next pass', () async {
    session(1, deleted: true);
    writer.readFails = true;
    await exporter().runPass();
    expect(receipt(1), isNull);
    writer.readFails = false;
    await exporter().runPass();
    expect(receipt(1)!.state, 'deleted');
  });

  test('failure marks failedRetryable and the next pass within the backoff writes nothing', () async {
    session(1);
    writer.writeResults.add(const HealthWriteFailed());
    await exporter().runPass();
    expect(receipt(1)!.state, 'failedRetryable');
    expect(receipt(1)!.attempts, 1);
    now = _now.add(const Duration(seconds: 30));
    await exporter().runPass();
    expect(writer.writes, hasLength(1));
    now = _now.add(const Duration(minutes: 2));
    await exporter().runPass();
    expect(writer.writes, hasLength(2));
    expect(receipt(1)!.state, 'confirmed');
  });

  test('stops when the account changes mid-pass', () async {
    session(1, finishedAgo: const Duration(days: 2));
    session(2, finishedAgo: const Duration(days: 1));
    writer.onWrite = () => current = false;
    await exporter().runPass();
    expect(writer.writes, hasLength(1));
    expect(receipt(2), isNull);
    expect(receipt(1)!.state, 'writing');
  });

  test('stops when the account changed before the pass starts', () async {
    session(1);
    current = false;
    await exporter().runPass();
    expect(writer.writes, isEmpty);
    expect(repo.allReceipts(), isEmpty);
  });

  test('waits 10 minutes on iOS with a paired watch', () async {
    watchPaired = true;
    session(1, finishedAgo: const Duration(minutes: 5));
    final result = await exporter().runPass();
    expect(writer.writes, isEmpty);
    expect(result.waiting, 1);
    now = _now.add(const Duration(minutes: 6));
    await exporter().runPass();
    expect(writer.writes, hasLength(1));
  });

  test(
    'a version bump on a confirmed workout writes again with the new version',
    () async {
      final s = session(1);
      await exporter().runPass();
      store.box<WorkoutSessionEntity>().put(s..updatedAtMs = 2000);
      await exporter().runPass();
      expect(writer.writes, hasLength(2));
      expect(writer.writes.last.version, 2000);
      expect(receipt(1)!.exportedVersion, 2000);
      expect(
        writer.lookups,
        hasLength(1),
        reason: 'adopt check only on first write',
      );
    },
  );

  test('a failed rewrite keeps the earlier id and version', () async {
    final s = session(1);
    await exporter().runPass();
    store.box<WorkoutSessionEntity>().put(s..updatedAtMs = 2000);
    writer.writeResults.add(const HealthWriteFailed());
    await exporter().runPass();
    final r = receipt(1)!;
    expect(r.state, 'failedRetryable');
    expect(r.exportedVersion, 1000);
    expect(r.platformRecordId, 'hk-0');
  });

  test('a second runPass while running shares the running pass', () async {
    session(1);
    final e = exporter();
    final a = e.runPass();
    final b = e.runPass();
    await Future.wait([a, b]);
    expect(writer.writes, hasLength(1));
  });
}
