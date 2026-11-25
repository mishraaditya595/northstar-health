import 'dart:math' as math;

import 'health_types.dart';

/// "Your normal": mean ± one standard deviation of [values]; null with fewer
/// than [minValues].
({double low, double high})? normalBand(
  List<double> values, {
  int minValues = 7,
}) {
  if (values.length < minValues) return null;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance =
      values.fold(0.0, (a, v) => a + (v - mean) * (v - mean)) / values.length;
  final sd = math.sqrt(variance);
  return (low: mean - sd, high: mean + sd);
}

/// For each slot, the mean of the values present in the [window] slots
/// ending there; null where there are none.
List<double?> rollingMean(List<double?> slots, int window) => [
  for (var i = 0; i < slots.length; i++)
    () {
      final present = slots
          .sublist(math.max(0, i - window + 1), i + 1)
          .whereType<double>();
      return present.isEmpty
          ? null
          : present.reduce((a, b) => a + b) / present.length;
    }(),
];

int _dayIndex(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// Least-squares slope of [points] per day, times 7; null with fewer than
/// [minPoints] days with data.
double? weeklyChange(List<DayValue> points, {int minPoints = 4}) {
  if (points.length < minPoints) return null;
  final xs = [for (final p in points) _dayIndex(p.day).toDouble()];
  final ys = [for (final p in points) p.value];
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  var sxy = 0.0;
  var sxx = 0.0;
  for (var i = 0; i < xs.length; i++) {
    sxy += (xs[i] - mx) * (ys[i] - my);
    sxx += (xs[i] - mx) * (xs[i] - mx);
  }
  if (sxx == 0) return null;
  return sxy / sxx * 7;
}

/// The latest of [daily] (ascending) dated at least [days] days before its
/// last reading; null when none is that old.
DayValue? earlierReading(List<DayValue> daily, int days) {
  if (daily.isEmpty) return null;
  final cutoff = _dayIndex(daily.last.day) - days;
  return daily.where((d) => _dayIndex(d.day) <= cutoff).lastOrNull;
}
