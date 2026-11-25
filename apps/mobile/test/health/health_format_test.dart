import 'package:beyondrep/core/design/charts/trend_label.dart';
import 'package:beyondrep/core/design/stats.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/trend.dart';
import 'package:beyondrep/features/health/health_format.dart';
import 'package:flutter_test/flutter_test.dart';

const apple = HealthPlatformKind.appleHealth;
const android = HealthPlatformKind.healthConnect;
final now = DateTime(2026, 11, 24, 18, 20);

void main() {
  test('clock time, date and platform name', () {
    expect(formatClockTime(DateTime(2026, 11, 24, 6, 52)), '6:52 AM');
    expect(formatClockTime(now), '6:20 PM');
    expect(formatClockTime(DateTime(2026, 11, 24, 0, 5)), '12:05 AM');
    expect(formatHealthDate(DateTime(2026, 11, 22, 8)), '22 Nov');
    expect(healthPlatformName(apple), 'Apple Health');
    expect(healthPlatformName(android), 'Health Connect');
  });

  test('counts are grouped by thousands', () {
    expect(formatCount(6420), '6,420');
    expect(formatCount(1234567.4), '1,234,567');
    expect(formatCount(12), '12');
  });

  test('formatDuration pads minutes after hours', () {
    expect(formatDuration(const Duration(minutes: 372)), '6h 12m');
    expect(formatDuration(const Duration(minutes: 63)), '1h 03m');
    expect(formatDuration(const Duration(minutes: 45)), '45m');
    expect(formatDuration(Duration.zero), '0m');
  });

  test('formatTrend gives amount and context without an arrow', () {
    TrendResult r(TrendDirection d, TrendTone t, double delta) =>
        TrendResult(direction: d, tone: t, delta: delta);
    expect(
      formatTrend(
        TrendMetric.sleepDuration,
        r(TrendDirection.down, TrendTone.worse, -36),
      ),
      '36m vs 7-day avg',
    );
    expect(
      formatTrend(
        TrendMetric.restingHr,
        r(TrendDirection.down, TrendTone.better, -3.2),
      ),
      '3 bpm this month · better',
    );
    expect(
      formatTrend(TrendMetric.hrv, r(TrendDirection.up, TrendTone.better, 6)),
      '6 ms vs normal',
    );
    expect(
      formatTrend(
        TrendMetric.weight,
        r(TrendDirection.down, TrendTone.neutral, -0.9),
      ),
      '0.9 kg in 30 days',
    );
    expect(
      formatTrend(
        TrendMetric.weight,
        r(TrendDirection.down, TrendTone.neutral, -0.9),
        since: DateTime(2026, 11, 22),
      ),
      '0.9 kg since 22 Nov',
    );
    expect(
      formatTrend(
        TrendMetric.weight,
        r(TrendDirection.flat, TrendTone.same, 0),
        since: DateTime(2026, 11, 22),
      ),
      'steady since 22 Nov',
    );
    expect(
      formatTrend(
        TrendMetric.sleepDuration,
        r(TrendDirection.flat, TrendTone.same, 4),
      ),
      'same as 7-day avg',
    );
  });

  test('nsTrendOf maps domain direction and tone to the kit', () {
    final t = nsTrendOf(
      const TrendResult(
        direction: TrendDirection.down,
        tone: TrendTone.worse,
        delta: -1,
      ),
    );
    expect(t.direction, NsTrend.down);
    expect(t.tone, NsTrendTone.worse);
    final flat = nsTrendOf(
      const TrendResult(
        direction: TrendDirection.flat,
        tone: TrendTone.same,
        delta: 0,
      ),
    );
    expect(flat.direction, NsTrend.flat);
    expect(flat.tone, NsTrendTone.same);
  });

  test('overview date line names day, platform and read time', () {
    expect(
      formatOverviewDateLine(DateTime(2026, 11, 24, 7, 42), apple),
      'Tue 24 Nov · Apple Health · updated 7:42 AM',
    );
    expect(
      formatOverviewDateLine(DateTime(2026, 11, 22, 19, 5), android),
      'Sun 22 Nov · Health Connect · updated 7:05 PM',
    );
  });
}
