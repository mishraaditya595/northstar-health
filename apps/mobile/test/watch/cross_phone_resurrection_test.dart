import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/sync/workout_upload_coordinator.dart';
import 'package:beyondrep/features/watch/application/watch_workout_inbox.dart';
import 'package:beyondrep/features/watch/data/objectbox_watch_workout_importer.dart';
import 'package:beyondrep/features/watch/data/watch_link.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:beyondrep/features/workouts/data/objectbox_workout_outbox.dart';
import 'package:beyondrep/features/workouts/data/workout_entities.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';

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
}

class _Ids implements UuidFactory {
  @override
  String newId() => '88888888-4444-4444-8444-000000000001';
}

/// The server's answer for a workout it holds a tombstone for: the upsert is
/// not applied (reason deleted), whatever revision the phone expects.
class _TombstoneServer implements WorkoutUploadTransport {
  final expected = <int>[];
  final sent = <String>[];

  @override
  Future<Map<String, dynamic>> send(
    WorkoutSyncOperation operation, {
    required int expectedServerRevision,
  }) async {
    sent.add(operation.operationUuid);
    expected.add(expectedServerRevision);
    return {
      'result': 'conflict',
      'revision': 2,
      'change_seq': 9,
      'replay': false,
      'processing': 'not_applied',
      'reason': 'deleted',
    };
  }
}

CompletedWorkout _fixture(String accountKey) {
  final json = jsonDecode(
    File('../../contracts/watch_link/v1/fixtures/valid/completed_workout.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  json['account_key'] = accountKey;
  return WatchMessage.fromJson(json) as CompletedWorkout;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('watch workout resent to a second phone after deletion ends in a '
      'conflict', () async {
    // Phone B: a fresh account-bound store with no receipt and no session for
    // the workout. Phone A imported it and the user deleted it, so the server
    // holds a tombstone.
    final dir = Directory.systemTemp.createTempSync('beyondrep-cross-phone-');
    final store = Store(getObjectBoxModel(), directory: dir.path);
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    await auth.restore();
    final outbox = ObjectBoxWorkoutOutbox(store);
    final server = _TombstoneServer();
    final uploader = WorkoutUploadCoordinator(
      accountId: accountA,
      auth: auth,
      outbox: outbox,
      transport: server,
      clock: () => DateTime.utc(2026, 10, 25, 15),
    );
    addTearDown(() async {
      uploader.dispose();
      auth.dispose();
      await api.dispose();
      store.close();
      dir.deleteSync(recursive: true);
    });
    final link = _Link();
    final inbox = WatchWorkoutInbox(
      link: link,
      importer: (id) => ObjectBoxWatchWorkoutImporter(
        store,
        accountId: id,
        activeAccountId: () => accountA,
      ),
      signedInUserId: () => accountA,
      ids: _Ids(),
      clock: () => DateTime.utc(2026, 10, 25, 12),
      onStored: () {},
    );
    final resent = _fixture(watchAccountKey(accountA));

    final result = await inbox.handle(resent);

    expect(result, WatchImportResult.stored);
    final ack = WatchMessage.fromJson(
      jsonDecode(link.sent.single) as Map<String, Object?>,
    ) as Ack;
    expect(ack.result, 'stored');

    final workoutUuid = (resent.workout['workout_id']! as String).toLowerCase();
    final entry = store.box<WorkoutSyncOutboxEntity>().getAll().single;
    expect(entry.sessionUuid, workoutUuid);
    expect(entry.state, 'pending');

    await uploader.drain();

    expect(server.expected, [0]);
    final after = store.box<WorkoutSyncOutboxEntity>().getAll().single;
    expect(after.state, 'conflict');
    expect(outbox.pending(), isEmpty);
    expect(store.box<WorkoutRemoteStateEntity>().getAll(), isEmpty);
    expect(outbox.syncFlags()[workoutUuid], WorkoutSyncFlag.needsReview);
    expect(uploader.lastFailureKind, 'revision_conflict');
  });
}
