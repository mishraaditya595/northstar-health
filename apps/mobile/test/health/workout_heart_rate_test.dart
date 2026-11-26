import 'package:beyondrep/features/health/application/health_summary_controller.dart';
import 'package:beyondrep/features/health/application/workout_heart_rate.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_reader.dart';

class _Owner extends Notifier<String?> {
  @override
  String? build() => 'owner-a';

  void set(String? owner) => state = owner;
}

final _ownerProvider = NotifierProvider<_Owner, String?>(_Owner.new);

HealthSample _hr(DateTime at, double v) =>
    (from: at, to: at, value: v, source: 'Synthetic watch');

final _start = DateTime.utc(2026, 11, 20, 9);
final WorkoutWindow _window = (
  start: _start,
  end: _start.add(const Duration(minutes: 30)),
);

void main() {
  late FakeHealthReader fake;

  setUp(() => fake = FakeHealthReader());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        healthReaderProvider.overrideWithValue(fake),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(_ownerProvider)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('mean of HR samples in the window', () async {
    fake.series[HealthSeriesType.heartRate] = [
      _hr(_start.add(const Duration(minutes: 5)), 100),
      _hr(_start.add(const Duration(minutes: 10)), 120),
    ];
    final c = container();
    expect(await c.read(workoutAverageHrProvider(_window).future), 110);
    expect(fake.seriesCalls.single.$1, HealthSeriesType.heartRate);
    expect(fake.seriesCalls.single.$2, _window.start);
    expect(fake.seriesCalls.single.$3, _window.end);
  });

  test('null with no samples or not allowed', () async {
    final c = container();
    expect(await c.read(workoutAverageHrProvider(_window).future), isNull);
    fake.seriesResults[HealthSeriesType.heartRate] = const SeriesNotAllowed();
    final other = (start: _start, end: _start.add(const Duration(hours: 1)));
    expect(await c.read(workoutAverageHrProvider(other).future), isNull);
  });

  test('owner change drops the result', () async {
    fake.overlapSeries = true;
    fake.series[HealthSeriesType.heartRate] = [
      _hr(_start.add(const Duration(minutes: 5)), 100),
    ];
    final c = container();
    c.listen(workoutAverageHrProvider(_window), (_, _) {});
    final pending = c.read(workoutAverageHrProvider(_window).future);
    c.read(_ownerProvider.notifier).set(null);
    expect(await pending.catchError((_) => null), isNull);
    expect(await c.read(workoutAverageHrProvider(_window).future), isNull);
  });

  test('a throwing reader gives null', () async {
    fake.throwOnSeries = {HealthSeriesType.heartRate};
    expect(
      await container().read(workoutAverageHrProvider(_window).future),
      isNull,
    );
  });
}
