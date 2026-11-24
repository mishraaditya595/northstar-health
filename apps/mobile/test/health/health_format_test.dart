import 'package:beyondrep/core/design/charts/trend_label.dart';
import 'package:beyondrep/core/design/stats.dart';
import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/trend.dart';
import 'package:beyondrep/features/health/health_format.dart';
import 'package:flutter_test/flutter_test.dart';

const apple = HealthPlatformKind.appleHealth;
const android = HealthPlatformKind.healthConnect;
final now = DateTime(2026, 11, 24, 18, 20);

HealthMeasured measured(double value, DateTime at, String source) =>
    HealthMeasured(value: value, measuredAt: at, source: source);

void main() {
  test('sleep value and caption', () {
    final r = measured(378, DateTime(2026, 11, 24, 6, 52), 'Apple Watch');
    expect(formatHealthValue(HealthMetric.sleep, r), '6h 18m');
    expect(
      formatHealthCaption(HealthMetric.sleep, r, apple, now),
      'Apple Watch · ended 6:52 AM',
    );
  });

  test('steps value and platform caption use read time', () {
    final r = measured(6420, DateTime(2026, 11, 24), 'ignored');
    expect(formatHealthValue(HealthMetric.steps, r), '6,420');
    expect(
      formatHealthCaption(HealthMetric.steps, r, apple, now),
      'Apple Health · as of 6:20 PM',
    );
    expect(
      formatHealthCaption(HealthMetric.steps, r, android, now),
      'Health Connect · as of 6:20 PM',
    );
  });

  test('resting heart rate caption is today-aware', () {
    final today = measured(58, DateTime(2026, 11, 24, 7, 10), 'Apple Watch');
    final older = measured(58, DateTime(2026, 11, 21, 7, 10), 'Apple Watch');
    expect(formatHealthValue(HealthMetric.restingHeartRate, today), '58 bpm');
    expect(
      formatHealthCaption(HealthMetric.restingHeartRate, today, apple, now),
      'Apple Watch · today 7:10 AM',
    );
    expect(
      formatHealthCaption(HealthMetric.restingHeartRate, older, apple, now),
      'Apple Watch · 21 Nov',
    );
  });

  test('weight value and caption', () {
    final r = measured(74.2, DateTime(2026, 11, 22, 8), 'Withings');
    expect(formatHealthValue(HealthMetric.weight, r), '74.2 kg');
    expect(
      formatHealthCaption(HealthMetric.weight, r, apple, now),
      'Withings · 22 Nov',
    );
  });

  test('no data shows a dash and a per-metric caption', () {
    const none = HealthNoData();
    expect(formatHealthValue(HealthMetric.sleep, none), '—');
    expect(
      formatHealthCaption(HealthMetric.sleep, none, apple, now),
      'No sleep recorded last night',
    );
    expect(
      formatHealthCaption(HealthMetric.steps, none, apple, now),
      'No steps yet today',
    );
    expect(
      formatHealthCaption(HealthMetric.restingHeartRate, none, apple, now),
      'None in the last 7 days',
    );
    expect(
      formatHealthCaption(HealthMetric.weight, none, apple, now),
      'None in the last 30 days',
    );
  });

  test('not allowed, failed and unsupported', () {
    for (final reading in const [
      HealthNotAllowed(),
      HealthReadFailed(),
      HealthUnsupported(),
    ]) {
      expect(formatHealthValue(HealthMetric.weight, reading), '—');
    }
    expect(
      formatHealthCaption(
        HealthMetric.weight,
        const HealthNotAllowed(),
        android,
        now,
      ),
      'Not allowed · Manage',
    );
    expect(
      formatHealthCaption(
        HealthMetric.weight,
        const HealthReadFailed(),
        android,
        now,
      ),
      "Couldn't read · Try again",
    );
    expect(
      formatHealthCaption(
        HealthMetric.weight,
        const HealthUnsupported(),
        android,
        now,
      ),
      'Not available on this device',
    );
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
