import 'package:beyondrep/core/clock.dart';
import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/application/weight_logger.dart';
import 'package:beyondrep/features/health/data/health_weight_writer.dart';
import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_overview.dart';
import '../support/fake_health_weight_writer.dart';

class _Owner extends Notifier<String?> {
  @override
  String? build() => 'user-1';
  void set(String? v) => state = v;
}

final _ownerProvider = NotifierProvider<_Owner, String?>(_Owner.new);

void main() {
  final fixedNow = DateTime(2026, 11, 28, 9, 30);
  late FakeHealthWeightWriter writer;
  late FakeHealthOverviewController overview;
  late ProviderContainer container;

  setUp(() {
    writer = FakeHealthWeightWriter();
    overview = FakeHealthOverviewController(null);
    container = ProviderContainer(
      overrides: [
        healthWeightWriterProvider.overrideWithValue(writer),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
        wallClockProvider.overrideWithValue(() => fixedNow),
        fakeHealthOverview(overview),
      ],
    );
    addTearDown(container.dispose);
  });

  WeightLogger logger() => container.read(weightLoggerProvider);

  test('invalid input never touches the writer', () async {
    expect(await logger().save('abc'), isA<WeightInvalid>());
    expect(writer.writes, isEmpty);
    expect(writer.requestAccessCalls, 0);
  });

  test('with access: writes kg at now and refreshes once', () async {
    final result = await logger().save('72,4');
    expect(result, isA<WeightSaved>());
    expect((result as WeightSaved).saved.platformRecordId, 'hk-0');
    expect(result.saved.clientRecordId, 'client-0');
    expect(writer.writes, [(kg: 72.4, at: fixedNow)]);
    expect(overview.refreshCalls, 1);
    expect(writer.requestAccessCalls, 0);
  });

  test('without access: requests, then writes when granted', () async {
    writer.writeAccess = false;
    expect(await logger().save('70'), isA<WeightSaved>());
    expect(writer.requestAccessCalls, 1);
    expect(writer.writes, hasLength(1));
  });

  test('without access: WeightDenied when still denied, no write', () async {
    writer.writeAccess = false;
    writer.accessGrantedByRequest = false;
    expect(await logger().save('70'), isA<WeightDenied>());
    expect(writer.requestAccessCalls, 1);
    expect(writer.writes, isEmpty);
    expect(overview.refreshCalls, 0);
  });

  test('writer HealthWriteDenied gives WeightDenied', () async {
    writer.writeResults.add(const HealthWriteDenied());
    expect(await logger().save('70'), isA<WeightDenied>());
    expect(overview.refreshCalls, 0);
  });

  test('failed or unavailable gives WeightSaveFailed, no refresh', () async {
    writer.writeResults.addAll(const [
      HealthWriteFailed(),
      HealthWriteUnavailable(),
    ]);
    expect(await logger().save('70'), isA<WeightSaveFailed>());
    expect(await logger().save('70'), isA<WeightSaveFailed>());
    expect(overview.refreshCalls, 0);
  });

  test('no signed-in account gives WeightSaveFailed, no write', () async {
    container.read(_ownerProvider.notifier).set(null);
    expect(await logger().save('70'), isA<WeightSaveFailed>());
    expect(writer.writes, isEmpty);
  });

  test('account changes during the access prompt: no write', () async {
    writer.writeAccess = false;
    writer.onRequestAccess = () =>
        container.read(_ownerProvider.notifier).set('user-2');
    expect(await logger().save('70'), isA<WeightSaveFailed>());
    expect(writer.writes, isEmpty);
    expect(overview.refreshCalls, 0);
  });

  test('undo deletes once and refreshes', () async {
    final saved = (await logger().save('70') as WeightSaved).saved;
    expect(await logger().undo(saved), isTrue);
    expect(writer.deletes, [saved]);
    expect(overview.refreshCalls, 2);
  });

  test(
    'a second undo of the same weight does nothing and returns true',
    () async {
      final saved = (await logger().save('70') as WeightSaved).saved;
      await logger().undo(saved);
      expect(await logger().undo(saved), isTrue);
      expect(writer.deletes, hasLength(1));
      expect(overview.refreshCalls, 2);
    },
  );

  test('undo returns false when delete fails, and may be retried', () async {
    final saved = (await logger().save('70') as WeightSaved).saved;
    writer.deleteResult = false;
    expect(await logger().undo(saved), isFalse);
    expect(overview.refreshCalls, 1);
    writer.deleteResult = true;
    expect(await logger().undo(saved), isTrue);
    expect(writer.deletes, hasLength(2));
  });

  test('undo still works after the widget that saved it is gone', () async {
    final sub = container.listen(weightLoggerProvider, (_, _) {});
    final saved = (await logger().save('70') as WeightSaved).saved;
    sub.close();
    await Future<void>.delayed(Duration.zero);
    expect(await container.read(weightLoggerProvider).undo(saved), isTrue);
    expect(writer.deletes, [saved]);
  });
}
