import 'package:beyondrep/features/health/application/own_workout_health.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_connection_repository.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/own_workout_health.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_reader.dart';

class _Owner extends Notifier<String?> {
  @override
  String? build() => 'owner-a';

  void set(String? owner) => state = owner;
}

final _ownerProvider = NotifierProvider<_Owner, String?>(_Owner.new);

class _Connections implements HealthConnectionRepository {
  _Connections(this.connected);
  final Set<String> connected;

  @override
  bool isConnected(String ownerAccountId) => connected.contains(ownerAccountId);
  @override
  DateTime? connectedAt(String ownerAccountId) => null;
  @override
  void connect(String ownerAccountId, DateTime at) {}
  @override
  void disconnect(String ownerAccountId) => connected.remove(ownerAccountId);
  @override
  int accessScope(String ownerAccountId) => 0;
  @override
  void recordAccessScope(String ownerAccountId, int scope) {}
}

final _start = DateTime.utc(2026, 11, 20, 9);
final _key = (
  workoutUuid: 'workout-1',
  start: _start,
  end: _start.add(const Duration(minutes: 40)),
);

void main() {
  late FakeHealthReader fake;

  setUp(() => fake = FakeHealthReader());

  ProviderContainer container({
    Set<String> connected = const {'owner-a'},
    String? Function(String uuid)? platformId,
  }) {
    final c = ProviderContainer(
      overrides: [
        healthReaderProvider.overrideWithValue(fake),
        healthConnectionRepositoryProvider.overrideWithValue(
          _Connections(connected),
        ),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
        watchWorkoutPlatformIdProvider.overrideWith(
          (ref, uuid) => platformId == null ? 'hk-1' : platformId(uuid),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('returns values for a connected owner with a receipt', () async {
    fake.ownWorkout = const SeriesData(
      OwnWorkoutHealth(averageBpm: 128, maxBpm: 161, activeKcal: 212.4),
    );
    final result = await container().read(
      ownWorkoutHealthProvider(_key).future,
    );
    expect(result?.averageBpm, 128);
    expect(result?.maxBpm, 161);
    expect(result?.activeKcal, 212.4);
    final call = fake.ownWorkoutCalls.single;
    expect(call.$1, 'hk-1');
    expect(call.$2, _key.start);
    expect(call.$3, _key.end);
  });

  test('returns null without a receipt and never calls the reader', () async {
    fake.ownWorkout = const SeriesData(OwnWorkoutHealth(averageBpm: 100));
    final c = container(platformId: (_) => null);
    expect(await c.read(ownWorkoutHealthProvider(_key).future), isNull);
    expect(fake.ownWorkoutCalls, isEmpty);
  });

  test('does not read when health is not connected', () async {
    fake.ownWorkout = const SeriesData(OwnWorkoutHealth(averageBpm: 100));
    final c = container(connected: const {});
    expect(await c.read(ownWorkoutHealthProvider(_key).future), isNull);
    expect(fake.ownWorkoutCalls, isEmpty);
  });

  test('disconnecting health while listened to hides the values', () async {
    fake.ownWorkout = const SeriesData(OwnWorkoutHealth(averageBpm: 100));
    final connections = _Connections({'owner-a'});
    final c = ProviderContainer(
      overrides: [
        healthReaderProvider.overrideWithValue(fake),
        healthConnectionRepositoryProvider.overrideWithValue(connections),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
        watchWorkoutPlatformIdProvider.overrideWith((ref, uuid) => 'hk-1'),
      ],
    );
    addTearDown(c.dispose);
    c.listen(ownWorkoutHealthProvider(_key), (_, _) {});
    expect(
      (await c.read(ownWorkoutHealthProvider(_key).future))?.averageBpm,
      100,
    );

    await c.read(healthSummaryProvider.notifier).disconnect();
    expect(await c.read(ownWorkoutHealthProvider(_key).future), isNull);
  });

  test('returns null when the workout is not found', () async {
    fake.ownWorkout = const SeriesData(null);
    expect(
      await container().read(ownWorkoutHealthProvider(_key).future),
      isNull,
    );
    expect(fake.ownWorkoutCalls, hasLength(1));
  });

  test('returns null for SeriesNotAllowed, SeriesFailed and '
      'SeriesUnsupported', () async {
    for (final r in <SeriesResult<OwnWorkoutHealth?>>[
      const SeriesNotAllowed(),
      const SeriesFailed(),
      const SeriesUnsupported(),
    ]) {
      fake.ownWorkout = r;
      expect(
        await container().read(ownWorkoutHealthProvider(_key).future),
        isNull,
        reason: '$r',
      );
    }
  });

  test('returns null when every value is missing', () async {
    fake.ownWorkout = const SeriesData(OwnWorkoutHealth());
    expect(
      await container().read(ownWorkoutHealthProvider(_key).future),
      isNull,
    );
  });

  test('a throwing reader gives null', () async {
    fake.throwOnOwnWorkout = true;
    expect(
      await container().read(ownWorkoutHealthProvider(_key).future),
      isNull,
    );
  });

  test('keyed by owner', () async {
    fake.ownWorkout = const SeriesData(OwnWorkoutHealth(averageBpm: 90));
    final c = container(connected: const {'owner-a', 'owner-b'});
    c.listen(ownWorkoutHealthProvider(_key), (_, _) {});
    expect(
      (await c.read(ownWorkoutHealthProvider(_key).future))?.averageBpm,
      90,
    );
    expect(fake.ownWorkoutCalls, hasLength(1));
    c.read(_ownerProvider.notifier).set('owner-b');
    await c.read(ownWorkoutHealthProvider(_key).future);
    expect(fake.ownWorkoutCalls, hasLength(2));
    c.read(_ownerProvider.notifier).set(null);
    expect(await c.read(ownWorkoutHealthProvider(_key).future), isNull);
    expect(fake.ownWorkoutCalls, hasLength(2));
  });
}
