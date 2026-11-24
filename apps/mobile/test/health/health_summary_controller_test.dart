import 'dart:io';

import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/data/health_connection_repository.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/objectbox.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_reader.dart';

const _ownerA = 'owner-a';
const _ownerB = 'owner-b';

void main() {
  late Directory root;
  late Store store;
  late HealthConnectionRepository repo;
  late FakeHealthReader fake;

  setUp(() {
    root = Directory.systemTemp.createTempSync('beyondrep-health-summary-');
    store = Store(getObjectBoxModel(), directory: '${root.path}/db');
    repo = ObjectBoxHealthConnectionRepository(store);
    fake = FakeHealthReader();
  });
  tearDown(() {
    store.close();
    root.deleteSync(recursive: true);
  });

  ProviderContainer containerFor(String? owner) {
    final container = ProviderContainer(
      overrides: [
        healthReaderProvider.overrideWithValue(fake),
        healthConnectionRepositoryProvider.overrideWithValue(repo),
        healthOwnerIdProvider.overrideWithValue(owner),
        healthClockProvider.overrideWithValue(
          () => DateTime(2026, 11, 24, 18, 20),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('not connected by default', () async {
    final container = containerFor(_ownerA);
    final state = await container.read(healthSummaryProvider.future);
    expect(state, isA<HealthNotConnected>());
    expect(fake.readCalls, isEmpty);
  });

  test('connect requests access, stores flag, reads four metrics', () async {
    final container = containerFor(_ownerA);
    await container.read(healthSummaryProvider.future);
    await container.read(healthSummaryProvider.notifier).connect();
    final state = await container.read(healthSummaryProvider.future);
    expect(fake.requestAccessCalls, 1);
    expect(repo.isConnected(_ownerA), true);
    expect(state, isA<HealthConnected>());
    expect((state as HealthConnected).readings.keys, HealthMetric.values);
  });

  test('connect swallows a permission failure, records nothing', () async {
    fake.throwOnRequestAccess = true;
    final container = containerFor(_ownerA);
    await container.read(healthSummaryProvider.future);
    final ok = await container.read(healthSummaryProvider.notifier).connect();
    expect(ok, false);
    expect(repo.isConnected(_ownerA), false);
    expect(
      await container.read(healthSummaryProvider.future),
      isA<HealthNotConnected>(),
    );
  });

  test('connect reports true when it completes', () async {
    final container = containerFor(_ownerA);
    await container.read(healthSummaryProvider.future);
    expect(
      await container.read(healthSummaryProvider.notifier).connect(),
      true,
    );
  });

  test('one failing metric does not blank others', () async {
    repo.connect(_ownerA, DateTime(2026, 11, 24));
    fake.throwOn = {HealthMetric.steps};
    final container = containerFor(_ownerA);
    final state =
        await container.read(healthSummaryProvider.future) as HealthConnected;
    expect(state.readings[HealthMetric.steps], isA<HealthReadFailed>());
    expect(state.readings[HealthMetric.sleep], isA<HealthMeasured>());
  });

  test('disconnect clears flag and stops reading', () async {
    repo.connect(_ownerA, DateTime(2026, 11, 24));
    final container = containerFor(_ownerA);
    await container.read(healthSummaryProvider.future);
    fake.readCalls.clear();
    await container.read(healthSummaryProvider.notifier).disconnect();
    final state = await container.read(healthSummaryProvider.future);
    expect(state, isA<HealthNotConnected>());
    expect(repo.isConnected(_ownerA), false);
    expect(fake.readCalls, isEmpty);
  });

  test('different account sees not connected', () async {
    final a = containerFor(_ownerA);
    await a.read(healthSummaryProvider.future);
    await a.read(healthSummaryProvider.notifier).connect();
    expect(await a.read(healthSummaryProvider.future), isA<HealthConnected>());
    final b = containerFor(_ownerB);
    expect(
      await b.read(healthSummaryProvider.future),
      isA<HealthNotConnected>(),
    );
  });

  test('needsInstall is surfaced', () async {
    fake.availabilityResult = HealthAvailability.needsInstall;
    final container = containerFor(_ownerA);
    final state = await container.read(healthSummaryProvider.future);
    expect(
      (state as HealthNotConnected).availability,
      HealthAvailability.needsInstall,
    );
    await container.read(healthSummaryProvider.notifier).connect();
    expect(fake.openInstallCalls, 1);
    expect(fake.requestAccessCalls, 0);
    expect(repo.isConnected(_ownerA), false);
  });

  test('no owner means not connected and connect is a no-op', () async {
    final container = containerFor(null);
    expect(
      await container.read(healthSummaryProvider.future),
      isA<HealthNotConnected>(),
    );
    await container.read(healthSummaryProvider.notifier).connect();
    expect(fake.requestAccessCalls, 0);
  });
}
