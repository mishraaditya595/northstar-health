import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/features/sync/workout_restore_feed.dart';
import 'package:beyondrep/features/watch/data/objectbox_watch_workout_importer.dart';
import 'package:beyondrep/features/watch/data/watch_workout_receipt_entity.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/features/workouts/domain/workout_models.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

const accountA = '00000000-0000-4000-8000-0000000000a1';
const accountB = '00000000-0000-4000-8000-0000000000b2';
const message1 = '77777777-3333-4333-8333-000000000091';
const message2 = '77777777-3333-4333-8333-000000000092';
const hkUuid = '11111111-2222-4333-8444-5555555555AA';
const fixtureWorkout = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const fixtureSet = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

Map<String, Object?> fixtureWorkoutJson() {
  final file = File(
    '../../contracts/watch_link/v1/fixtures/valid/completed_workout.json',
  );
  final message = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return (message['body']! as Map<String, Object?>)['workout']!
      as Map<String, Object?>;
}

RemoteWorkoutSnapshot snapshotOf(Map<String, Object?> json) =>
    WorkoutRestorePage.parseWorkout(
      json,
      workoutId: json['workout_id']! as String,
      origins: {WorkoutOrigin.watch},
    );

void main() {
  late Directory dir;
  late Store store;
  late String? active;
  late ObjectBoxWatchWorkoutImporter importer;

  ObjectBoxWatchWorkoutImporter bind() => ObjectBoxWatchWorkoutImporter(
    store,
    accountId: accountA,
    activeAccountId: () => active,
    clock: () => DateTime.utc(2026, 10, 23, 12),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('beyondrep-watch-import-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    active = accountA;
    importer = bind();
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  WatchImportResult importIt({
    String messageId = message1,
    Map<String, Object?>? json,
    String? platform = hkUuid,
    ({String planId, String programId, String localDate})? programDay,
  }) => importer.importCompleted(
    messageId: messageId,
    snapshot: snapshotOf(json ?? fixtureWorkoutJson()),
    platformWorkoutUuid: platform,
    programDay: programDay,
  );

  Map<String, int> counts() => {
    'sessions': store.box<WorkoutSessionEntity>().count(),
    'exercises': store.box<WorkoutExerciseEntity>().count(),
    'sets': store.box<WorkoutSetEntity>().count(),
    'receipts': store.box<WatchWorkoutReceiptEntity>().count(),
    'outbox': store.box<WorkoutSyncOutboxEntity>().count(),
  };

  test('stores session, receipt and one pending outbox entry with origin '
      'beyondrep_watch', () {
    expect(importIt(), WatchImportResult.stored);
    final session = store.box<WorkoutSessionEntity>().getAll().single;
    expect(session.uuid, fixtureWorkout);
    expect(session.status, 'completed');
    expect(session.origin, 'beyondrep_watch');
    expect(session.revision, 1);
    final op = store.box<WorkoutSyncOutboxEntity>().getAll().single;
    expect(op.state, 'pending');
    expect(op.action, 'upsert');
    expect(op.localRevision, 1);
    expect((jsonDecode(op.payloadJson) as Map)['origin'], 'beyondrep_watch');
    final receipt = store.box<WatchWorkoutReceiptEntity>().getAll().single;
    expect(receipt.workoutUuid, fixtureWorkout);
    expect(receipt.messageId, message1);
    expect(receipt.platformWorkoutUuid, hkUuid.toLowerCase());
    expect(
      receipt.receivedAtMs,
      DateTime.utc(2026, 10, 23, 12).millisecondsSinceEpoch,
    );
    expect(store.box<WorkoutExerciseEntity>().count(), 2);
    expect(store.box<WorkoutSetEntity>().count(), 3);
  });

  test('same message twice is a duplicate with no writes', () {
    importIt();
    final before = counts();
    expect(importIt(), WatchImportResult.duplicate);
    expect(counts(), before);
  });

  test('redelivery with a new message id is a duplicate', () {
    importIt();
    final before = counts();
    expect(importIt(messageId: message2), WatchImportResult.duplicate);
    expect(counts(), before);
    expect(before['outbox'], 1);
  });

  test('the same message id for another workout is invalid', () {
    importIt();
    final other = fixtureWorkoutJson()
      ..['workout_id'] = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    final before = counts();
    expect(importIt(json: other), WatchImportResult.invalid);
    expect(counts(), before);
  });

  test('a locally deleted workout is not resurrected', () {
    importIt();
    final outbox = ObjectBoxWorkoutOutbox(store);
    outbox.deleteCompletedWorkout(
      sessionUuid: fixtureWorkout,
      expectedLocalRevision: 1,
    );
    final before = counts();
    expect(importIt(messageId: message2), WatchImportResult.duplicate);
    expect(counts(), before);
    final session = store.box<WorkoutSessionEntity>().getAll().single;
    expect(session.deletedAtMs, isNotNull);
    expect(
      store.box<WorkoutSyncOutboxEntity>().getAll().map((o) => o.action),
      containsAll(['upsert', 'delete']),
    );
  });

  test('a locally deleted workout without a receipt is a duplicate', () {
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: fixtureWorkout,
        name: 'Deleted workout',
        status: 'completed',
        origin: 'beyondrep_watch',
        revision: 2,
        startedAtMs: 1,
        completedAtMs: 2,
        originalOffsetMinutes: 0,
        updatedAtMs: 3,
        deletedAtMs: 3,
      ),
    );
    expect(importIt(), WatchImportResult.duplicate);
    expect(store.box<WatchWorkoutReceiptEntity>().count(), 0);
    expect(store.box<WorkoutSyncOutboxEntity>().count(), 0);
  });

  test('a restored watch workout is a duplicate', () {
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: fixtureWorkout,
        name: 'Restored',
        status: 'completed',
        origin: 'beyondrep_watch',
        startedAtMs: 1,
        completedAtMs: 2,
        originalOffsetMinutes: 0,
        updatedAtMs: 2,
      ),
    );
    expect(importIt(), WatchImportResult.duplicate);
    expect(counts()['receipts'], 0);
    expect(counts()['outbox'], 0);
    expect(store.box<WorkoutSessionEntity>().getAll().single.name, 'Restored');
  });

  test('a phone session with the same uuid is invalid', () {
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: fixtureWorkout,
        name: 'Phone',
        status: 'completed',
        startedAtMs: 1,
        completedAtMs: 2,
        originalOffsetMinutes: 0,
        updatedAtMs: 2,
      ),
    );
    expect(importIt(), WatchImportResult.invalid);
    expect(counts()['receipts'], 0);
    expect(counts()['outbox'], 0);
    expect(store.box<WorkoutSessionEntity>().getAll().single.name, 'Phone');
  });

  test('a set uuid used by another workout is invalid and writes nothing', () {
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        name: 'Other',
        status: 'completed',
        startedAtMs: 1,
        completedAtMs: 2,
        originalOffsetMinutes: 0,
        updatedAtMs: 2,
      ),
    );
    store.box<WorkoutExerciseEntity>().put(
      WorkoutExerciseEntity(
        uuid: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        sessionUuid: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        position: 0,
        nameSnapshot: 'Other row',
      ),
    );
    store.box<WorkoutSetEntity>().put(
      WorkoutSetEntity(
        uuid: fixtureSet,
        exerciseUuid: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        position: 0,
        updatedAtMs: 1,
      ),
    );
    final before = counts();
    expect(importIt(), WatchImportResult.invalid);
    expect(counts(), before);
  });

  test('an outbox-invalid snapshot writes nothing', () {
    final json = fixtureWorkoutJson();
    json['exercises'] = [
      for (var i = 0; i < 86; i++)
        {
          'id':
              '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
          'name': '🔥' * 160,
          'position': i,
          'sets': <Object>[],
        },
    ];
    expect(snapshotOf(json).exercises, hasLength(86));
    expect(importIt(json: json), WatchImportResult.invalid);
    expect(counts(), {
      'sessions': 0,
      'exercises': 0,
      'sets': 0,
      'receipts': 0,
      'outbox': 0,
    });
  });

  test('account changed inside the transaction rolls back', () {
    var calls = 0;
    importer = ObjectBoxWatchWorkoutImporter(
      store,
      accountId: accountA,
      activeAccountId: () => ++calls == 1 ? accountA : accountB,
    );
    expect(
      () => importer.importCompleted(
        messageId: message1,
        snapshot: snapshotOf(fixtureWorkoutJson()),
        platformWorkoutUuid: hkUuid,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'account_changed',
        ),
      ),
    );
    expect(counts(), {
      'sessions': 0,
      'exercises': 0,
      'sets': 0,
      'receipts': 0,
      'outbox': 0,
    });
  });

  test('a signed-out store never imports', () {
    active = null;
    expect(
      importIt,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'account_changed',
        ),
      ),
    );
    expect(counts()['sessions'], 0);
  });

  test('after reopening the store a redelivery is a duplicate', () {
    importIt();
    store.close();
    store = Store(getObjectBoxModel(), directory: dir.path);
    importer = bind();
    final before = counts();
    expect(importIt(messageId: message2), WatchImportResult.duplicate);
    expect(counts(), before);
    expect(before['outbox'], 1);
  });

  test('program day is recorded when the plan belongs to the program', () {
    store.box<WorkoutPlanEntity>().put(
      WorkoutPlanEntity(
        uuid: 'plan-synthetic-push',
        name: 'Push',
        createdAtMs: 1,
        updatedAtMs: 1,
        programUuid: 'program-synthetic-ppl',
      ),
    );
    importIt(
      programDay: (
        planId: 'plan-synthetic-push',
        programId: 'program-synthetic-ppl',
        localDate: '2026-10-23',
      ),
    );
    final session = store.box<WorkoutSessionEntity>().getAll().single;
    expect(session.planUuid, 'plan-synthetic-push');
    expect(session.programUuid, 'program-synthetic-ppl');
    expect(session.programDayLocalDate, '2026-10-23');
  });

  test('a plan of another program imports without a program day', () {
    store.box<WorkoutPlanEntity>().put(
      WorkoutPlanEntity(
        uuid: 'plan-synthetic-push',
        name: 'Push',
        createdAtMs: 1,
        updatedAtMs: 1,
        programUuid: 'program-other',
      ),
    );
    expect(
      importIt(
        programDay: (
          planId: 'plan-synthetic-push',
          programId: 'program-synthetic-ppl',
          localDate: '2026-10-23',
        ),
      ),
      WatchImportResult.stored,
    );
    final session = store.box<WorkoutSessionEntity>().getAll().single;
    expect(session.planUuid, isNull);
    expect(session.programUuid, isNull);
    expect(session.programDayLocalDate, isNull);
  });

  test('an unknown plan imports without a program day', () {
    expect(
      importIt(
        programDay: (
          planId: 'plan-missing',
          programId: 'program-synthetic-ppl',
          localDate: '2026-10-23',
        ),
      ),
      WatchImportResult.stored,
    );
    final session = store.box<WorkoutSessionEntity>().getAll().single;
    expect(session.planUuid, isNull);
    expect(session.programUuid, isNull);
    expect(session.programDayLocalDate, isNull);
  });

  test('a workout without a HealthKit uuid stores a receipt without one', () {
    expect(importIt(platform: null), WatchImportResult.stored);
    expect(
      store
          .box<WatchWorkoutReceiptEntity>()
          .getAll()
          .single
          .platformWorkoutUuid,
      isNull,
    );
    expect(importer.platformWorkoutUuids(), isEmpty);
  });

  test('platformWorkoutUuids returns the stored HKWorkout ids lowercase', () {
    importIt();
    expect(importer.platformWorkoutUuids(), {hkUuid.toLowerCase()});
  });

  test('platformWorkoutUuidFor reads the receipt of one workout', () {
    importIt();
    final workoutUuid = store
        .box<WatchWorkoutReceiptEntity>()
        .getAll()
        .single
        .workoutUuid;
    expect(importer.platformWorkoutUuidFor(workoutUuid), hkUuid.toLowerCase());
    expect(importer.platformWorkoutUuidFor('no-such-workout'), isNull);
  });
}
