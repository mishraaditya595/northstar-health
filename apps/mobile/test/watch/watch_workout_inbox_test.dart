import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/account/account_auth_controller.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/health/application/workout_health_export_controller.dart';
import 'package:beyondrep/features/watch/application/watch_workout_inbox.dart';
import 'package:beyondrep/features/watch/application/watch_sync_controller.dart';
import 'package:beyondrep/features/watch/data/objectbox_watch_workout_importer.dart';
import 'package:beyondrep/features/watch/data/watch_link.dart';
import 'package:beyondrep/features/watch/data/watch_workout_receipt_entity.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';

const accountA = '00000000-0000-4000-8000-0000000000a1';
const accountB = '00000000-0000-4000-8000-0000000000b2';

class _Link implements WatchLink {
  final sent = <String>[];
  final log = <String>[];

  @override
  Future<void> transfer(String json) async {
    sent.add(json);
    log.add('transfer');
  }

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

CompletedWorkout _fixture({
  String name = 'completed_workout.json',
  void Function(Map<String, Object?> workout)? edit,
  String? accountKey,
}) {
  final json = jsonDecode(
    File('../../contracts/watch_link/v1/fixtures/valid/$name')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  final body = json['body']! as Map<String, Object?>;
  if (edit != null) edit(body['workout']! as Map<String, Object?>);
  if (accountKey != null) json['account_key'] = accountKey;
  return WatchMessage.fromJson(json) as CompletedWorkout;
}

void main() {
  late Directory dir;
  late Store store;
  late _Link link;
  late String? user;
  late int stored;
  late List<DateTime> imported;
  late List<String> order;
  late int linked;
  late WatchWorkoutInbox inbox;

  WatchWorkoutInbox build({
    ObjectBoxWatchWorkoutImporter Function(String accountId)? importer,
  }) => WatchWorkoutInbox(
    link: link,
    importer:
        importer ??
        (id) => ObjectBoxWatchWorkoutImporter(
          store,
          accountId: id,
          activeAccountId: () => user,
        ),
    signedInUserId: () => user,
    ids: _Ids(),
    clock: () => DateTime.utc(2026, 10, 23, 12),
    onStored: () {
      stored++;
      order.add('onStored');
    },
    onImported: imported.add,
    onLinked: () => linked++,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('beyondrep-inbox-');
    store = Store(getObjectBoxModel(), directory: dir.path);
    link = _Link();
    user = accountA;
    stored = 0;
    imported = [];
    order = [];
    linked = 0;
    inbox = build();
  });

  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  test('a Wear completed_workout without healthkit_workout_uuid imports and acks stored', () async {
    final json = jsonDecode(
      File(
        '../../contracts/watch_link/v1/fixtures/valid/completed_workout.json',
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    json['account_key'] = watchAccountKey(accountA);
    (json['body']! as Map<String, Object?>).remove('healthkit_workout_uuid');
    final message = WatchMessage.fromJson(json) as CompletedWorkout;
    expect(message.healthkitWorkoutUuid, isNull);
    expect(await inbox.handle(message), WatchImportResult.stored);
    expect(store.box<WorkoutSessionEntity>().count(), 1);
    expect(link.ackAt(0).result, 'stored');
    expect(link.ackAt(0).ackedMessageId, message.messageId);
  });

  test(
    'stores and acks stored with the signed-in key and the message id',
    () async {
      final message = _fixture(accountKey: watchAccountKey(accountA));
      expect(await inbox.handle(message), WatchImportResult.stored);
      expect(store.box<WorkoutSessionEntity>().count(), 1);
      expect(link.sent, hasLength(1));
      final ack = link.ackAt(0);
      expect(ack.result, 'stored');
      expect(ack.reason, isNull);
      expect(ack.ackedMessageId, message.messageId);
      expect(ack.accountKey, watchAccountKey(accountA));
    },
  );

  test('reports the start of an imported workout, also for a duplicate, never for an ignored one', () async {
    final message = _fixture(accountKey: watchAccountKey(accountA));
    await inbox.handle(message);
    expect(imported, [DateTime.utc(2026, 10, 23, 11)]);
    await inbox.handle(message);
    expect(imported, hasLength(2));
    imported.clear();
    await inbox.handle(_fixture(accountKey: watchAccountKey(accountB)));
    expect(imported, isEmpty);
  });

  test('an upper-case workout id is stored and acked stored', () async {
    final message = _fixture(
      accountKey: watchAccountKey(accountA),
      edit: (w) => w['workout_id'] = (w['workout_id']! as String).toUpperCase(),
    );
    expect(await inbox.handle(message), WatchImportResult.stored);
    expect(link.ackAt(0).result, 'stored');
    expect(store.box<WorkoutSessionEntity>().count(), 1);
  });

  test('ack is sent only after the import returned', () async {
    final events = <String>[];
    final recording = _RecordingLink(events);
    inbox = WatchWorkoutInbox(
      link: recording,
      importer: (id) => _OrderedImporter(
        store,
        id,
        () => user,
        onImport: () => events.add('import'),
      ),
      signedInUserId: () => user,
      ids: _Ids(),
      clock: () => DateTime.utc(2026, 10, 23, 12),
      onStored: () => events.add('onStored'),
    );
    await inbox.handle(_fixture(accountKey: watchAccountKey(accountA)));
    expect(events, ['import', 'onStored', 'transfer']);
    expect(store.box<WorkoutSessionEntity>().count(), 1);
  });

  test('a duplicate acks duplicate', () async {
    final message = _fixture(accountKey: watchAccountKey(accountA));
    await inbox.handle(message);
    expect(await inbox.handle(message), WatchImportResult.duplicate);
    expect(link.ackAt(1).result, 'duplicate');
    expect(store.box<WorkoutSessionEntity>().count(), 1);
    expect(stored, 1, reason: 'onStored runs only for stored');
  });

  test('an invalid payload acks rejected invalid and stores nothing', () async {
    final message = _fixture(
      accountKey: watchAccountKey(accountA),
      edit: (w) {
        final set =
            ((w['exercises']! as List).first as Map)['sets'].first as Map;
        set
          ..remove('reps')
          ..remove('load_grams');
      },
    );
    expect(await inbox.handle(message), WatchImportResult.invalid);
    final ack = link.ackAt(0);
    expect(ack.result, 'rejected');
    expect(ack.reason, 'invalid');
    expect(ack.ackedMessageId, message.messageId);
    expect(store.box<WorkoutSessionEntity>().count(), 0);
    expect(store.box<WatchWorkoutReceiptEntity>().count(), 0);
    expect(stored, 0);
  });

  test("another account's workout is ignored without an ack", () async {
    final message = _fixture(accountKey: watchAccountKey(accountB));
    expect(await inbox.handle(message), isNull);
    expect(link.sent, isEmpty);
    expect(store.box<WorkoutSessionEntity>().count(), 0);
  });

  test('signed out ignores the message', () async {
    user = null;
    final message = _fixture(accountKey: watchAccountKey(accountA));
    expect(await inbox.handle(message), isNull);
    expect(link.sent, isEmpty);
    expect(store.box<WorkoutSessionEntity>().count(), 0);
  });

  test('an account change during the import sends no ack', () async {
    var calls = 0;
    inbox = build(
      importer: (id) => ObjectBoxWatchWorkoutImporter(
        store,
        accountId: id,
        activeAccountId: () => ++calls == 1 ? accountA : accountB,
      ),
    );
    final message = _fixture(accountKey: watchAccountKey(accountA));
    expect(await inbox.handle(message), isNull);
    expect(link.sent, isEmpty);
    expect(store.box<WorkoutSessionEntity>().count(), 0);
  });

  test('onStored runs only for stored', () async {
    final message = _fixture(accountKey: watchAccountKey(accountA));
    await inbox.handle(message);
    expect(stored, 1);
    await inbox.handle(message);
    expect(stored, 1);
  });

  test(
    'the program day and HealthKit receipt are passed to the importer',
    () async {
      final message = _fixture(
        name: 'completed_workout_program_day.json',
        accountKey: watchAccountKey(accountA),
      );
      expect(await inbox.handle(message), WatchImportResult.stored);
      expect(
        store
            .box<WatchWorkoutReceiptEntity>()
            .getAll()
            .single
            .platformWorkoutUuid,
        '11111111-2222-4333-8444-555555555555',
      );
    },
  );

  group('health export kick (provider wiring)', () {
    late FakeAuthApi api;
    late AccountAuthController auth;
    late ProviderContainer container;
    late int kicks;

    setUp(() async {
      api = FakeAuthApi()..sessionId = accountA;
      auth = controller(api, FakeBoundAccountStore()..saved = accountA);
      await auth.restore();
      kicks = 0;
      container = ProviderContainer(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          objectBoxStoreProvider.overrideWithValue(store),
          watchLinkProvider.overrideWithValue(link),
          watchMessageIdsProvider.overrideWithValue(_Ids()),
          wallClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 10, 23, 12),
          ),
          healthExportKickProvider.overrideWithValue(() => kicks++),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      auth.dispose();
      await api.dispose();
    });

    test('a stored watch workout kicks the export', () async {
      final result = await container
          .read(watchWorkoutInboxProvider)
          .handle(_fixture(accountKey: watchAccountKey(accountA)));
      expect(result, WatchImportResult.stored);
      expect(kicks, 1);
    });

    test('onLinked kicks the export', () async {
      _putPhoneWorkout(store);
      final result = await container
          .read(watchWorkoutInboxProvider)
          .handleLink(_link(accountKey: watchAccountKey(accountA)));
      expect(result, WatchLinkResult.stored);
      expect(kicks, 1);
    });
  });

  group('workout_link', () {
    test('a completed phone workout gets a receipt, then an ack', () async {
      _putPhoneWorkout(store);
      final message = _link(accountKey: watchAccountKey(accountA));
      expect(await inbox.handleLink(message), WatchLinkResult.stored);
      expect(store.box<WatchWorkoutReceiptEntity>().count(), 1);
      final ack = link.ackAt(0);
      expect(ack.result, 'stored');
      expect(ack.ackedMessageId, message.messageId);
      expect(ack.accountKey, watchAccountKey(accountA));
      expect(linked, 1);
    });

    test('a duplicate link keeps one receipt and is acked again', () async {
      _putPhoneWorkout(store);
      final message = _link(accountKey: watchAccountKey(accountA));
      await inbox.handleLink(message);
      expect(await inbox.handleLink(message), WatchLinkResult.duplicate);
      expect(store.box<WatchWorkoutReceiptEntity>().count(), 1);
      expect(link.ackAt(1).result, 'duplicate');
      expect(linked, 1, reason: 'only a new receipt refreshes the hidden ids');
    });

    test('an unknown or unfinished workout gets no ack', () async {
      final message = _link(accountKey: watchAccountKey(accountA));
      expect(await inbox.handleLink(message), WatchLinkResult.unknown);
      _putPhoneWorkout(store, status: 'inProgress');
      expect(await inbox.handleLink(message), WatchLinkResult.unknown);
      expect(link.sent, isEmpty);
      expect(store.box<WatchWorkoutReceiptEntity>().count(), 0);
    });

    test('another account or signed out is ignored without an ack', () async {
      _putPhoneWorkout(store);
      expect(
        await inbox.handleLink(_link(accountKey: watchAccountKey(accountB))),
        isNull,
      );
      user = null;
      expect(
        await inbox.handleLink(_link(accountKey: watchAccountKey(accountA))),
        isNull,
      );
      expect(link.sent, isEmpty);
      expect(store.box<WatchWorkoutReceiptEntity>().count(), 0);
    });

    test('a deleted workout is acked rejected', () async {
      store.box<WorkoutSessionEntity>().put(
        WorkoutSessionEntity(
          uuid: _phoneWorkout,
          name: 'Gone',
          status: 'completed',
          startedAtMs: 1,
          completedAtMs: 2,
          originalOffsetMinutes: 0,
          updatedAtMs: 2,
          deletedAtMs: 3,
        ),
      );
      final message = _link(accountKey: watchAccountKey(accountA));
      expect(await inbox.handleLink(message), WatchLinkResult.invalid);
      expect(link.ackAt(0).result, 'rejected');
      expect(link.ackAt(0).reason, 'invalid');
    });
  });
}

const _phoneWorkout = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

WorkoutLink _link({String? accountKey}) {
  final json = jsonDecode(
    File('../../contracts/watch_link/v1/fixtures/valid/workout_link.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  if (accountKey != null) json['account_key'] = accountKey;
  return WatchMessage.fromJson(json) as WorkoutLink;
}

void _putPhoneWorkout(Store store, {String status = 'completed'}) =>
    store.box<WorkoutSessionEntity>().put(
      WorkoutSessionEntity(
        uuid: _phoneWorkout,
        name: 'Phone workout',
        status: status,
        startedAtMs: 1,
        completedAtMs: status == 'completed' ? 2 : null,
        originalOffsetMinutes: 0,
        updatedAtMs: 2,
      ),
    );

class _OrderedImporter extends ObjectBoxWatchWorkoutImporter {
  _OrderedImporter(
    super.store,
    String accountId,
    String? Function() active, {
    required this.onImport,
  }) : super(accountId: accountId, activeAccountId: active);

  final void Function() onImport;

  @override
  WatchImportResult importCompleted({
    required String messageId,
    required snapshot,
    String? platformWorkoutUuid,
    ({String planId, String programId, String localDate})? programDay,
  }) {
    final result = super.importCompleted(
      messageId: messageId,
      snapshot: snapshot,
      platformWorkoutUuid: platformWorkoutUuid,
      programDay: programDay,
    );
    onImport();
    return result;
  }
}

class _RecordingLink extends _Link {
  _RecordingLink(this.events);
  final List<String> events;

  @override
  Future<void> transfer(String json) async {
    events.add('transfer');
    await super.transfer(json);
  }
}
