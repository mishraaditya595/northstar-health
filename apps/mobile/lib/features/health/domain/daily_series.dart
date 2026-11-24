import 'health_types.dart';

enum DailyReduction { latest, mean, sum }

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

List<DayValue> _sorted(Map<DateTime, double> byDay) => [
  for (final day in byDay.keys.toList()..sort()) (day: day, value: byDay[day]!),
];

List<DayValue> reduceDaily(List<HealthSample> samples, DailyReduction how) {
  final groups = <DateTime, List<HealthSample>>{};
  for (final s in samples) {
    groups.putIfAbsent(_dayOf(s.to), () => []).add(s);
  }
  return _sorted({
    for (final e in groups.entries)
      e.key: switch (how) {
        DailyReduction.latest =>
          e.value.reduce((a, b) => b.to.isAfter(a.to) ? b : a).value,
        DailyReduction.mean =>
          e.value.fold(0.0, (a, s) => a + s.value) / e.value.length,
        DailyReduction.sum => e.value.fold(0.0, (a, s) => a + s.value),
      },
  });
}

/// Sums hourly buckets by the local date of `from`; DST days sum 23 or 25.
List<DayValue> hourlyToDaily(List<HealthSample> hourly) {
  final byDay = <DateTime, double>{};
  for (final s in hourly) {
    byDay.update(_dayOf(s.from), (v) => v + s.value, ifAbsent: () => s.value);
  }
  return _sorted(byDay);
}

class PeriodSummary {
  const PeriodSummary({
    required this.average,
    required this.daysWithData,
    required this.previousAverage,
  });

  final double? average;
  final int daysWithData;
  final double? previousAverage;
}

PeriodSummary summarizePeriod(
  List<DayValue> series, {
  required DateTime lastDay,
  required int days,
  DateTime? readableFrom,
}) {
  final last = _dayOf(lastDay);
  final currentStart = DateTime(last.year, last.month, last.day - (days - 1));
  final previousStart = DateTime(
    last.year,
    last.month,
    last.day - (2 * days - 1),
  );

  List<double> window(DateTime start, DateTime end) => [
    for (final d in series)
      if (!_dayOf(d.day).isBefore(start) && !_dayOf(d.day).isAfter(end))
        d.value,
  ];
  double? mean(List<double> v) =>
      v.isEmpty ? null : v.fold(0.0, (a, b) => a + b) / v.length;

  final current = window(currentStart, last);
  final previous = window(
    previousStart,
    DateTime(last.year, last.month, last.day - days),
  );
  final comparable =
      (readableFrom == null || !previousStart.isBefore(readableFrom)) &&
      previous.length >= days ~/ 2;
  return PeriodSummary(
    average: mean(current),
    daysWithData: current.length,
    previousAverage: comparable ? mean(previous) : null,
  );
}
