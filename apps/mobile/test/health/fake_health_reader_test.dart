import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_health_reader.dart';

void main() {
  final from = DateTime(2026, 11, 1);
  final to = DateTime(2026, 11, 8);

  test('series returns configured data and records the call', () async {
    final fake = FakeHealthReader();
    final sample = (from: from, to: from, value: 52.0, source: 'Fake source');
    fake.series[HealthSeriesType.restingHeartRate] = [sample];

    final result = await fake.readSeries(
      HealthSeriesType.restingHeartRate,
      from,
      to,
    );

    expect((result as SeriesData).data, [sample]);
    expect(fake.seriesCalls, [(HealthSeriesType.restingHeartRate, from, to)]);
  });

  test('unconfigured type returns empty SeriesData', () async {
    final fake = FakeHealthReader();
    final result = await fake.readSeries(HealthSeriesType.hrv, from, to);
    expect((result as SeriesData).data, isEmpty);
    expect(((await fake.readSleep(from, to)) as SeriesData).data, isEmpty);
    expect(
      ((await fake.readHourlyTotals(
        HealthTotalType.steps,
        from,
        to,
      )) as SeriesData).data,
      isEmpty,
    );
  });

  test('throwOnSeries throws and access flags are settable', () async {
    final fake = FakeHealthReader()
      ..throwOnSeries = {HealthSeriesType.weight}
      ..needsMore = true
      ..history = false;
    await expectLater(
      fake.readSeries(HealthSeriesType.weight, from, to),
      throwsStateError,
    );
    expect(await fake.needsMoreAccess(), true);
    expect(await fake.hasHistoryAccess(), false);
    await fake.requestMoreAccess();
    expect(fake.requestMoreAccessCalls, 1);
  });
}
