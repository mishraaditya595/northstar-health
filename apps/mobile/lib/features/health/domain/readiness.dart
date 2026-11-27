import 'dart:math';

import 'daily_series.dart';
import 'health_types.dart';
import 'sleep_nights.dart';
import 'sleep_score.dart';
import 'training_load.dart';

const _baselineWindowDays = 30;
const _baselineMinDays = 14;

/// Days of history the readiness score needs before it uses a baseline.
const readinessBaselineMinDays = 3;

class Baseline {
  const Baseline({required this.mean, required this.sd, required this.days});

  final double mean;

  /// Already floored.
  final double sd;
  final int days;
}

double hrvSdFloor(double mean) => max(0.05 * mean, 2.0);
double rhrSdFloor(double mean) => 1.5;

DateTime _daysBefore(DateTime day, int n) =>
    DateTime(day.year, day.month, day.day - n);

List<double> _baselineValues(List<DayValue> daily, DateTime today) {
  final end = dayOf(today);
  final start = _daysBefore(end, _baselineWindowDays);
  return [
    for (final d in daily)
      if (_usable(d.value) &&
          !dayOf(d.day).isBefore(start) &&
          dayOf(d.day).isBefore(end))
        d.value,
  ];
}

/// Mean and population sd of the values on the 30 local days before [today]
/// (today excluded); null with fewer than [minDays] such days.
Baseline? baselineOf(
  List<DayValue> daily,
  DateTime today, {
  required double Function(double mean) sdFloor,
  int minDays = _baselineMinDays,
}) {
  final values = _baselineValues(daily, today);
  if (values.length < minDays) return null;
  final mean = values.fold(0.0, (a, b) => a + b) / values.length;
  final variance =
      values.fold(0.0, (a, v) => a + (v - mean) * (v - mean)) / values.length;
  return Baseline(
    mean: mean,
    sd: max(sqrt(variance), sdFloor(mean)),
    days: values.length,
  );
}

enum ReadinessBand { good, fair, low }

ReadinessBand readinessBandOf(int value) => value >= 70
    ? ReadinessBand.good
    : value >= 50
    ? ReadinessBand.fair
    : ReadinessBand.low;

enum ReadinessInput { hrv, restingHr, sleep, sleepDebt, trainingLoad }

class ReadinessPart {
  const ReadinessPart({
    required this.input,
    required this.score,
    required this.weight,
    this.z,
  });

  final ReadinessInput input;

  /// 0..100.
  final double score;

  /// Rescaled over the parts present; all weights sum to 1.
  final double weight;
  final double? z;
}

class Readiness {
  const Readiness({
    required this.value,
    required this.band,
    required this.parts,
    this.loadRatio,
    this.baselineDays,
  });

  final int value;
  final ReadinessBand band;
  final List<ReadinessPart> parts;

  /// 7-day against 28-day training load; set with the training load part.
  final double? loadRatio;

  /// The larger day count of the HRV and resting HR baselines in the score;
  /// null when neither part is present.
  final int? baselineDays;
}

sealed class ReadinessResult {
  const ReadinessResult();
}

final class ReadinessReady extends ReadinessResult {
  const ReadinessReady(this.readiness);

  final Readiness readiness;
}

final class ReadinessNotReady extends ReadinessResult {
  const ReadinessNotReady({
    this.noSleep = false,
    this.noHrvOrRhrToday = false,
    this.daysUntilBaseline,
  });

  /// No main sleep last night.
  final bool noSleep;

  /// Neither measure has a value today.
  final bool noHrvOrRhrToday;

  /// Set when a measure has a value today but none has a baseline yet.
  final int? daysUntilBaseline;
}

const _baseWeights = {
  ReadinessInput.hrv: 0.40,
  ReadinessInput.restingHr: 0.25,
  ReadinessInput.sleep: 0.25,
  ReadinessInput.sleepDebt: 0.10,
  ReadinessInput.trainingLoad: 0.15,
};

double _clamp100(double v) => v.clamp(0.0, 100.0).toDouble();

/// NaN would clamp to 100 and a zero reading is a sensor gap, not a value.
bool _usable(double v) => v.isFinite && v > 0;

double? _todayValue(List<DayValue> daily, DateTime today) {
  for (final d in daily) {
    if (dayOf(d.day) == today && _usable(d.value)) return d.value;
  }
  return null;
}

ReadinessResult scoreReadiness({
  required DateTime today,
  required SleepNight? lastNight,
  required SleepScore? sleepScore,
  required List<SleepNight> priorNights,
  required List<DayValue> hrvDaily,
  required List<DayValue> restingHrDaily,
  List<LoadSession> loadSessions = const [],
}) {
  final day = dayOf(today);
  final night = lastNight != null && dayOf(lastNight.date) == day
      ? lastNight
      : null;
  final hrvToday = _todayValue(hrvDaily, day);
  final rhrToday = _todayValue(restingHrDaily, day);
  final hrvBase = hrvToday == null
      ? null
      : baselineOf(
          hrvDaily,
          day,
          sdFloor: hrvSdFloor,
          minDays: readinessBaselineMinDays,
        );
  final rhrBase = rhrToday == null
      ? null
      : baselineOf(
          restingHrDaily,
          day,
          sdFloor: rhrSdFloor,
          minDays: readinessBaselineMinDays,
        );
  final noMeasureToday = hrvToday == null && rhrToday == null;
  final noBaseline = !noMeasureToday && hrvBase == null && rhrBase == null;
  if (night == null || noMeasureToday || noBaseline) {
    var most = 0;
    if (hrvToday != null) {
      most = max(most, _baselineValues(hrvDaily, day).length);
    }
    if (rhrToday != null) {
      most = max(most, _baselineValues(restingHrDaily, day).length);
    }
    return ReadinessNotReady(
      noSleep: night == null,
      noHrvOrRhrToday: noMeasureToday,
      daysUntilBaseline: noBaseline ? readinessBaselineMinDays - most : null,
    );
  }

  final scores = <ReadinessInput, ({double score, double? z})>{};
  if (hrvBase != null) {
    final z = (hrvToday! - hrvBase.mean) / hrvBase.sd;
    scores[ReadinessInput.hrv] = (score: _clamp100(70 + 15 * z), z: z);
  }
  if (rhrBase != null) {
    final z = (rhrToday! - rhrBase.mean) / rhrBase.sd;
    scores[ReadinessInput.restingHr] = (score: _clamp100(70 - 15 * z), z: z);
  }
  scores[ReadinessInput.sleep] = (
    score:
        sleepScore?.value.toDouble() ??
        _clamp100(100 * night.asleep.inMinutes / 450),
    z: null,
  );
  final windowStart = _daysBefore(dayOf(night.date), 7);
  final week = [
    for (final n in priorNights)
      if (!dayOf(n.date).isBefore(windowStart) &&
          dayOf(n.date).isBefore(dayOf(night.date)))
        n.asleep.inMinutes,
  ];
  final mean = week.isEmpty ? 0.0 : week.fold(0, (a, b) => a + b) / week.length;
  if (week.length >= 3 && mean > 0) {
    final r = night.asleep.inMinutes / mean;
    scores[ReadinessInput.sleepDebt] = (
      score: _clamp100((r - 0.7) / 0.3 * 100),
      z: null,
    );
  }

  final load = trainingLoadOf(loadSessions, day);
  if (load != null) {
    scores[ReadinessInput.trainingLoad] = (score: load.score, z: null);
  }

  final total = scores.keys.fold(0.0, (a, k) => a + _baseWeights[k]!);
  final parts = [
    for (final input in ReadinessInput.values)
      if (scores.containsKey(input))
        ReadinessPart(
          input: input,
          score: scores[input]!.score,
          weight: _baseWeights[input]! / total,
          z: scores[input]!.z,
        ),
  ];
  final value = parts.fold(0.0, (a, p) => a + p.score * p.weight).round();
  return ReadinessReady(
    Readiness(
      value: value,
      band: readinessBandOf(value),
      parts: parts,
      loadRatio: load?.ratio,
      baselineDays: [
        ?hrvBase?.days,
        ?rhrBase?.days,
      ].fold<int?>(null, (a, b) => a == null ? b : max(a, b)),
    ),
  );
}
