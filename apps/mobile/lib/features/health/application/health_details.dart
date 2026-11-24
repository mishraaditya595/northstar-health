import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/health_reader.dart';
import '../domain/daily_series.dart';
import '../domain/health_types.dart';
import '../domain/sleep_nights.dart';
import '../domain/sleep_score.dart';
import 'health_overview.dart';
import 'health_summary_controller.dart';

enum SleepRange { lastNight, week, month }

extension SleepRangeLength on SleepRange {
  /// Night dates shown, ending last night.
  int get nights => switch (this) {
    SleepRange.lastNight => 1,
    SleepRange.week => 7,
    SleepRange.month => 30,
  };
}

/// Read fresh for the detail screen and held in memory only.
class SleepNightExtras {
  const SleepNightExtras({
    required this.heartRate,
    required this.respiratoryRate,
    required this.bloodOxygen,
    required this.wristTemp,
    required this.wristTempDeviation,
  });

  /// Samples inside last night's window, ascending.
  final List<HealthSample> heartRate;

  /// Breaths per minute, mean over the night.
  final double? respiratoryRate;

  /// Percent (0-100), mean over the night.
  final double? bloodOxygen;

  /// Last night's wrist (iOS) or skin (Android) temperature, °C.
  final double? wristTemp;

  /// [wristTemp] minus the mean of earlier nights; null with fewer than 7.
  final double? wristTempDeviation;
}

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

double? _mean(Iterable<double> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

bool _during(HealthSample s, SleepNight n) =>
    !s.from.isAfter(n.end) && !s.to.isBefore(n.start);

double? _meanDuring(List<HealthSample> samples, SleepNight n) => _mean([
  for (final s in samples)
    if (_during(s, n)) s.value,
]);

Future<List<HealthSample>> _readSeries(
  HealthReader reader,
  HealthSeriesType type,
  DateTime from,
  DateTime to,
) async {
  try {
    final r = await reader.readSeries(type, from, to);
    return r is SeriesData<List<HealthSample>> ? r.data : const [];
  } catch (_) {
    return const [];
  }
}

/// The overview and its sleep for the signed-in account; null otherwise.
/// Watching the owner as the overview does means an account switch rebuilds
/// every detail read.
Future<(HealthOverview, SleepOverview)?> _sleepOf(Ref ref) async {
  final owner = ref.watch(healthOwnerIdProvider);
  final overview = await ref.watch(healthOverviewProvider.future);
  if (owner == null || overview == null || overview.ownerId != owner) {
    return null;
  }
  return switch (overview.sleep) {
    SectionData(:final value) => (overview, value),
    SectionGap() => null,
  };
}

bool _stillOwner(Ref ref, String owner) =>
    ref.mounted && ref.read(healthOwnerIdProvider) == owner;

/// Heart rate, breathing and blood oxygen inside last night's window, and
/// wrist/skin temperature over the overview's nights for the deviation.
/// Null when last night has no main sleep.
final sleepNightExtrasProvider = FutureProvider.autoDispose<SleepNightExtras?>((
  ref,
) async {
  final sleepOf = await _sleepOf(ref);
  if (sleepOf == null) return null;
  final (overview, sleep) = sleepOf;
  final night = sleep.lastNight;
  if (night.date != _dayOf(overview.readAt)) return null;
  final reader = ref.read(healthReaderProvider);
  final prior = [
    for (final n in sleep.nights)
      if (n.date.isBefore(night.date)) n,
  ];
  Future<List<HealthSample>> read(HealthSeriesType type, DateTime from) =>
      _readSeries(reader, type, from, night.end);
  final hrF = read(HealthSeriesType.heartRate, night.start);
  final breathingF = read(HealthSeriesType.respiratoryRate, night.start);
  final oxygenF = read(HealthSeriesType.bloodOxygen, night.start);
  final tempF = read(
    overview.platform == HealthPlatformKind.appleHealth
        ? HealthSeriesType.sleepingWristTemperature
        : HealthSeriesType.skinTemperature,
    prior.isEmpty ? night.start : prior.first.start,
  );
  final heartRate = [
    for (final s in await hrF)
      if (_during(s, night)) s,
  ]..sort((a, b) => a.from.compareTo(b.from));
  final breathing = await breathingF;
  final oxygen = await oxygenF;
  final temp = await tempF;
  if (!_stillOwner(ref, overview.ownerId)) return null;

  final wristTemp = _meanDuring(temp, night);
  final priorTemps = [for (final n in prior) ?_meanDuring(temp, n)];
  return SleepNightExtras(
    heartRate: heartRate,
    respiratoryRate: _meanDuring(breathing, night),
    bloodOxygen: _meanDuring(oxygen, night),
    wristTemp: wristTemp,
    wristTempDeviation: wristTemp == null || priorTemps.length < 7
        ? null
        : wristTemp - _mean(priorTemps)!,
  );
});

/// Nights for [SleepRange] and the same-length period before it, ascending.
/// The overview's 31 nights cover 7 days and the 7 before; 30 days reads the
/// 60 nights it needs. Null without overview sleep.
final sleepRangeNightsProvider = FutureProvider.autoDispose
    .family<List<SleepNight>?, SleepRange>((ref, range) async {
      final sleepOf = await _sleepOf(ref);
      if (sleepOf == null) return null;
      final (overview, sleep) = sleepOf;
      final today = _dayOf(overview.readAt);
      final first = DateTime(
        today.year,
        today.month,
        today.day - (2 * range.nights - 1),
      );
      List<SleepNight> since(List<SleepNight> nights) => [
        for (final n in nights)
          if (!n.date.isBefore(first)) n,
      ];
      if (!first.isBefore(DateTime(today.year, today.month, today.day - 30))) {
        return since(sleep.nights);
      }
      final reader = ref.read(healthReaderProvider);
      SeriesResult<List<SleepSegment>> result;
      try {
        result = await reader.readSleep(
          DateTime(first.year, first.month, first.day - 1, 18),
          overview.readAt,
        );
      } catch (_) {
        result = const SeriesFailed();
      }
      if (!_stillOwner(ref, overview.ownerId)) return null;
      // A failed longer read still shows the overview's nights.
      return result is SeriesData<List<SleepSegment>>
          ? since(buildNights(result.data))
          : since(sleep.nights);
    });

/// Mean heart rate per night date inside each night's window, from one
/// HEART_RATE read spanning the range's nights.
final sleepRangeHrProvider = FutureProvider.autoDispose
    .family<Map<DateTime, double>, SleepRange>((ref, range) async {
      final sleepOfF = _sleepOf(ref);
      final nightsF = ref.watch(sleepRangeNightsProvider(range).future);
      final sleepOf = await sleepOfF;
      final nights = await nightsF;
      if (sleepOf == null || nights == null) return const {};
      final (overview, _) = sleepOf;
      final firstDate = currentRangeStart(overview.readAt, range);
      final current = [
        for (final n in nights)
          if (!n.date.isBefore(firstDate)) n,
      ];
      if (current.isEmpty) return const {};
      final samples = await _readSeries(
        ref.read(healthReaderProvider),
        HealthSeriesType.heartRate,
        current.first.start,
        current.last.end,
      );
      if (!_stillOwner(ref, overview.ownerId)) return const {};
      return {for (final n in current) n.date: ?_meanDuring(samples, n)};
    });

/// First night date of [range] ending on the date of [readAt].
DateTime currentRangeStart(DateTime readAt, SleepRange range) =>
    DateTime(readAt.year, readAt.month, readAt.day - (range.nights - 1));

/// Minutes after 12:00 local, so evening and after-midnight starts are close.
int _minutesAfterNoon(DateTime t) {
  final l = t.toLocal();
  return (l.hour * 60 + l.minute - 720) % 1440;
}

double _median(List<num> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid].toDouble()
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// How many minutes later (negative: earlier) [night] started than the
/// median of the 14 most recent [priorNights]; null with fewer than 5, as in
/// the sleep score's timing.
int? bedtimeOffset(SleepNight night, List<SleepNight> priorNights) {
  final recent = [...priorNights]..sort((a, b) => b.date.compareTo(a.date));
  final starts = [for (final n in recent.take(14)) _minutesAfterNoon(n.start)];
  if (starts.length < 5) return null;
  return (_minutesAfterNoon(night.start) - _median(starts)).round();
}

/// Median bedtime as minutes after midnight, ± the median absolute
/// deviation; null with fewer than 5 nights.
({int minutes, int spread})? usualBedtime(List<SleepNight> nights) {
  if (nights.length < 5) return null;
  final starts = [for (final n in nights) _minutesAfterNoon(n.start)];
  final median = _median(starts);
  final spread = _median([for (final s in starts) (s - median).abs()]);
  return (minutes: (median.round() + 720) % 1440, spread: spread.round());
}

/// What the 7 and 30 day tabs show, computed in memory.
class SleepRangeStats {
  const SleepRangeStats({
    required this.slots,
    required this.asleep,
    required this.score,
    required this.deep,
    required this.rem,
    required this.sleepHr,
    required this.bedtime,
  });

  /// One per night date of the range, oldest first; null where no night.
  final List<SleepNight?> slots;

  /// Asleep minutes; previousAverage is null when the period before was not
  /// readable or too sparse.
  final PeriodSummary asleep;

  /// Means over the nights that have them.
  final double? score, deep, rem, sleepHr;
  final ({int minutes, int spread})? bedtime;
}

SleepRangeStats sleepRangeStats({
  required List<SleepNight> nights,
  required SleepRange range,
  required DateTime readAt,
  required DateTime? readableFrom,
  required Map<DateTime, double> sleepHr,
  required List<DayValue> restingHr,
}) {
  final firstDate = currentRangeStart(readAt, range);
  final byDate = {for (final n in nights) n.date: n};
  final slots = [
    for (var i = 0; i < range.nights; i++)
      byDate[DateTime(firstDate.year, firstDate.month, firstDate.day + i)],
  ];
  final current = slots.nonNulls.toList();
  final staged = current.where((n) => n.hasStages);
  final scores = [
    for (final n in staged)
      ?scoreSleep(
        n,
        priorNights: [
          for (final p in nights)
            if (p.date.isBefore(n.date)) p,
        ],
        sleepAvgHr: sleepHr[n.date],
        restingHr: restingHr
            .where((d) => !d.day.isAfter(n.date))
            .lastOrNull
            ?.value,
      )?.value.toDouble(),
  ];
  return SleepRangeStats(
    slots: slots,
    asleep: summarizePeriod(
      [
        for (final n in nights)
          (day: n.date, value: n.asleep.inMinutes.toDouble()),
      ],
      lastDay: readAt,
      days: range.nights,
      readableFrom: readableFrom,
    ),
    score: _mean(scores),
    deep: _mean([for (final n in staged) n.deep.inMinutes.toDouble()]),
    rem: _mean([for (final n in staged) n.rem.inMinutes.toDouble()]),
    sleepHr: _mean([for (final n in current) ?sleepHr[n.date]]),
    bedtime: usualBedtime(current),
  );
}
