import 'package:beyondrep/features/health/domain/trend.dart';
import 'package:flutter_test/flutter_test.dart';

void expectTrend(
  TrendResult r,
  TrendDirection d,
  TrendTone t, [
  double? delta,
]) {
  expect(r.direction, d);
  expect(r.tone, t);
  if (delta != null) expect(r.delta, closeTo(delta, 1e-9));
}

void main() {
  test('restingHr 54 vs 57 is down/better, delta -3', () {
    expectTrend(
      trendOf(TrendMetric.restingHr, 54, 57),
      TrendDirection.down,
      TrendTone.better,
      -3,
    );
  });
  test('restingHr 56.5 vs 57 is flat/same', () {
    expectTrend(
      trendOf(TrendMetric.restingHr, 56.5, 57),
      TrendDirection.flat,
      TrendTone.same,
    );
  });
  test('hrv 52 vs 46 up/better', () {
    expectTrend(
      trendOf(TrendMetric.hrv, 52, 46),
      TrendDirection.up,
      TrendTone.better,
    );
  });
  test('hrv 48 vs 46 flat (band 3)', () {
    expectTrend(
      trendOf(TrendMetric.hrv, 48, 46),
      TrendDirection.flat,
      TrendTone.same,
    );
  });
  test('steps 9000 vs 9400 flat (5% = 470)', () {
    expectTrend(
      trendOf(TrendMetric.steps, 9000, 9400),
      TrendDirection.flat,
      TrendTone.same,
    );
  });
  test('weight 78.4 vs 79.3 down/neutral', () {
    expectTrend(
      trendOf(TrendMetric.weight, 78.4, 79.3),
      TrendDirection.down,
      TrendTone.neutral,
    );
  });
  test('sleepDuration 372 vs 408 down/worse', () {
    expectTrend(
      trendOf(TrendMetric.sleepDuration, 372, 408),
      TrendDirection.down,
      TrendTone.worse,
      -36,
    );
  });
}
