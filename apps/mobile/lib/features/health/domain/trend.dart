import 'dart:math' as math;

enum TrendMetric {
  sleepDuration,
  sleepScore,
  deep,
  rem,
  restingHr,
  sleepHr,
  hrv,
  vo2Max,
  steps,
  activeEnergy,
  weight,
  bodyFat,
}

enum TrendDirection { up, down, flat }

enum TrendTone { better, worse, neutral, same }

class TrendResult {
  const TrendResult({
    required this.direction,
    required this.tone,
    required this.delta,
  });

  final TrendDirection direction;
  final TrendTone tone;
  final double delta;
}

/// `delta` is current minus reference; |delta| within the dead band is flat.
TrendResult trendOf(TrendMetric m, double current, double reference) {
  final delta = current - reference;
  final band = switch (m) {
    TrendMetric.sleepDuration => 10.0,
    TrendMetric.sleepScore => 3.0,
    TrendMetric.deep || TrendMetric.rem => 5.0,
    TrendMetric.restingHr || TrendMetric.sleepHr => 1.0,
    TrendMetric.hrv => math.max(3.0, 0.05 * reference),
    TrendMetric.vo2Max => 0.5,
    TrendMetric.steps || TrendMetric.activeEnergy => 0.05 * reference,
    TrendMetric.weight => 0.2,
    TrendMetric.bodyFat => 0.3,
  };
  if (delta.abs() <= band) {
    return TrendResult(
      direction: TrendDirection.flat,
      tone: TrendTone.same,
      delta: delta,
    );
  }
  final up = delta > 0;
  final tone = switch (m) {
    TrendMetric.weight || TrendMetric.bodyFat => TrendTone.neutral,
    TrendMetric.restingHr ||
    TrendMetric.sleepHr => up ? TrendTone.worse : TrendTone.better,
    _ => up ? TrendTone.better : TrendTone.worse,
  };
  return TrendResult(
    direction: up ? TrendDirection.up : TrendDirection.down,
    tone: tone,
    delta: delta,
  );
}
