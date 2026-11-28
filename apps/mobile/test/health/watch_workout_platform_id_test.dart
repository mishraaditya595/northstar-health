import 'dart:convert';
import 'dart:io';

import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/core/storage/objectbox_store_provider.dart';
import 'package:beyondrep/features/account/account_auth_provider.dart';
import 'package:beyondrep/features/account/account_gate.dart';
import 'package:beyondrep/features/health/application/own_workout_health.dart';
import 'package:beyondrep/features/health/data/health_export_repository.dart';
import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:beyondrep/features/watch/application/watch_sync_controller.dart';
import 'package:beyondrep/features/watch/application/watch_workout_health_inbox.dart';
import 'package:beyondrep/features/watch/application/watch_workout_inbox.dart';
import 'package:beyondrep/features/watch/data/objectbox_watch_workout_importer.dart';
import 'package:beyondrep/features/watch/data/watch_link.dart';
import 'package:beyondrep/features/watch/domain/watch_account_key.dart';
import 'package:beyondrep/features/watch/domain/watch_message.dart';
import 'package:beyondrep/features/watch/domain/watch_status.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_account_auth.dart';
import '../support/fake_health_workout_writer.dart';

class _Link implements WatchLink {
  @override
  Future<void> transfer(String json) async {}
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
}

class _Ids implements UuidFactory {
  @override
  String newId() => '88888888-4444-4444-8444-000000000001';
}

Map<String, Object?> _fixture(String name) => jsonDecode(
  File('../../contracts/watch_link/v1/fixtures/valid/$name.json')
      .readAsStringSync(),
) as Map<String, Object?>;

const _uuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  test('on Android the platform id appears once the watch health write '
      'confirms the receipt (real account gate resolver)', () async {
    final dir = Directory.systemTemp.createTempSync('beyondrep-platform-id-');
    final store = Store(getObjectBoxModel(), directory: dir.path);
    final api = FakeAuthApi()..sessionId = accountA;
    final auth = controller(api, FakeBoundAccountStore()..saved = accountA);
    await auth.restore();
    final writer = FakeHealthWorkoutWriter(isIos: false);
    final container = ProviderContainer(
      overrides: [
        objectBoxStoreProvider.overrideWithValue(store),
        accountAuthControllerProvider.overrideWithValue(auth),
        healthWorkoutWriterProvider.overrideWithValue(writer),
        watchLinkProvider.overrideWithValue(_Link()),
        watchMessageIdsProvider.overrideWithValue(_Ids()),
        wallClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 23, 12),
        ),
        watchWorkoutPlatformIdProvider.overrideWith(
          resolveWatchWorkoutPlatformId,
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      auth.dispose();
      await api.dispose();
      store.close();
      dir.deleteSync(recursive: true);
    });
    container
        .read(healthExportRepositoryProvider)
        .enable(accountA, DateTime.utc(2026, 10, 1));
    final key = watchAccountKey(accountA);
    final completed = _fixture('completed_workout')..['account_key'] = key;
    expect(
      await WatchWorkoutInbox(
        link: _Link(),
        importer: (id) => ObjectBoxWatchWorkoutImporter(
          store,
          accountId: id,
          activeAccountId: () => accountA,
        ),
        signedInUserId: () => accountA,
        ids: _Ids(),
        clock: () => DateTime.utc(2026, 10, 23, 12),
        onStored: () {},
      ).handle(WatchMessage.fromJson(completed) as CompletedWorkout),
      WatchImportResult.stored,
    );

    // Read (and cache) before the receipt exists: null.
    final sub = container.listen(
      watchWorkoutPlatformIdProvider(_uuid),
      (_, _) {},
    );
    addTearDown(sub.close);
    expect(container.read(watchWorkoutPlatformIdProvider(_uuid)), isNull);

    final health = _fixture('workout_health')..['account_key'] = key;
    final ack = await container
        .read(watchWorkoutHealthInboxProvider)
        .handle(WatchMessage.fromJson(health) as WorkoutHealth);
    expect(ack?.result, 'stored');
    expect(container.read(watchWorkoutPlatformIdProvider(_uuid)), _uuid);
  });
}
