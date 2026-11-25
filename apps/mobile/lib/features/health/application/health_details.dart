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
    required this.heartRateGap,
    required this.respiratoryRate,
    required this.bloodOxygen,
    required this.wristTemp,
    required this.wristTempDeviation,
    required this.skinTempDelta,
  });

  /// Samples inside last night's window, ascending.
  final List<HealthSample> heartRate;

  /// Why heart rate could not be read (not allowed, failed, ...); null when
  /// the read succeeded, even with no samples.
  final MetricGap? heartRateGap;

  /// Breaths per minute, mean over the night.
  final double? respiratoryRate;

  /// Percent (0-100), mean over the night.
  final double? bloodOxygen;

  /// Last night's absolute wrist temperature (iOS), °C.
  final double? wristTemp;

  /// [wristTemp] minus the mean of earlier nights; null with fewer than 7.
  final double? wristTempDeviation;

  /// Last night's skin temperature (Android), °C above or below the
  /// device's own baseline. Health Connect stores only this delta, never an
  /// absolute reading.
  final double? skinTempDelta;
}

double? _mean(Iterable<double> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

bool _during(HealthSample s, SleepNight n) =>
    !s.from.isAfter(n.end) && !s.to.isBefore(n.start);

double? _meanDuring(List<HealthSample> samples, SleepNight n) => _mean([
  for (final s in samples)
    if (_during(s, n)) s.value,
]);

Future<SeriesResult<List<HealthSample>>> _readResult(
  HealthReader reader,
  HealthSeriesType type,
  DateTime from,
  DateTime to,
) async {
  try {
    return await reader.readSeries(type, from, to);
  } catch (_) {
    return const SeriesFailed();
  }
}

List<HealthSample> _samples(SeriesResult<List<HealthSample>> r) =>
    r is SeriesData<List<HealthSample>> ? r.data : const [];

/// Tiles that only show when present treat any gap as absent.
Future<List<HealthSample>> _readSeries(
  HealthReader reader,
  HealthSeriesType type,
  DateTime from,
  DateTime to,
) async => _samples(await _readResult(reader, type, from, to));

/// The overview for the signed-in account; null otherwise. Watching the
/// owner as the overview does means an account switch rebuilds every detail
/// read.
Future<HealthOverview?> _overviewOf(Ref ref) async {
  final owner = ref.watch(healthOwnerIdProvider);
  final overview = await ref.watch(healthOverviewProvider.future);
  if (owner == null || overview == null || overview.ownerId != owner) {
    return null;
  }
  return overview;
}

/// The overview and its sleep for the signed-in account; null otherwise.
Future<(HealthOverview, SleepOverview)?> _sleepOf(Ref ref) async {
  final overview = await _overviewOf(ref);
  if (overview == null) return null;
  return switch (overview.sleep) {
    SectionData(:final value) => (overview, value),
    SectionGap() => null,
  };
}

bool _stillOwner(Ref ref, String owner) =>
    ref.mounted && ref.read(healthOwnerIdProvider) == owner;

DateTime _monthFrom(DateTime readAt) =>
    DateTime(readAt.year, readAt.month, readAt.day - 29);

/// iOS: the latest day's mean walking heart rate in the 30 days ending at the
/// overview's read. Health Connect has no walking heart rate: unsupported,
/// without a read. Null without an overview for the signed-in account.
final walkingHrProvider = FutureProvider.autoDispose<Section<DayValue>?>((
  ref,
) async {
  final overview = await _overviewOf(ref);
  if (overview == null) return null;
  if (overview.platform != HealthPlatformKind.appleHealth) {
    return const SectionGap(MetricGap.unsupported);
  }
  final result = await _readResult(
    ref.read(healthReaderProvider),
    HealthSeriesType.walkingHeartRate,
    _monthFrom(overview.readAt),
    overview.readAt,
  );
  if (!_stillOwner(ref, overview.ownerId)) return null;
  final latest = reduceDaily(_samples(result), DailyReduction.mean).lastOrNull;
  if (latest != null) return SectionData(latest);
  return SectionGap(metricGapOf(result) ?? MetricGap.noData);
});

/// The latest lean body mass in the 30 days ending at the overview's read;
/// null when there is none or it could not be read (the tile only shows when
/// present).
final leanMassProvider = FutureProvider.autoDispose<DayValue?>((ref) async {
  final overview = await _overviewOf(ref);
  if (overview == null) return null;
  final samples = await _readSeries(
    ref.read(healthReaderProvider),
    HealthSeriesType.leanMass,
    _monthFrom(overview.readAt),
    overview.readAt,
  );
  if (!_stillOwner(ref, overview.ownerId)) return null;
  return reduceDaily(samples, DailyReduction.latest).lastOrNull;
});

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
  if (night.date != dayOf(overview.readAt)) return null;
  final reader = ref.read(healthReaderProvider);
  final prior = [
    for (final n in sleep.nights)
      if (n.date.isBefore(night.date)) n,
  ];
  Future<List<HealthSample>> read(HealthSeriesType type, DateTime from) =>
      _readSeries(reader, type, from, night.end);
  final hrF = _readResult(
    reader,
    HealthSeriesType.heartRate,
    night.start,
    night.end,
  );
  final breathingF = read(HealthSeriesType.respiratoryRate, night.start);
  final oxygenF = read(HealthSeriesType.bloodOxygen, night.start);
  final ios = overview.platform == HealthPlatformKind.appleHealth;
  final tempF = ios
      ? read(
          HealthSeriesType.sleepingWristTemperature,
          prior.isEmpty ? night.start : prior.first.start,
        )
      : read(HealthSeriesType.skinTemperature, night.start);
  final hrResult = await hrF;
  final heartRate = [
    for (final s in _samples(hrResult))
      if (_during(s, night)) s,
  ]..sort((a, b) => a.from.compareTo(b.from));
  final breathing = await breathingF;
  final oxygen = await oxygenF;
  final temp = await tempF;
  if (!_stillOwner(ref, overview.ownerId)) return null;

  final nightTemp = _meanDuring(temp, night);
  final wristTemp = ios ? nightTemp : null;
  final priorTemps = [for (final n in prior) ?_meanDuring(temp, n)];
  return SleepNightExtras(
    heartRate: heartRate,
    heartRateGap: metricGapOf(hrResult),
    respiratoryRate: _meanDuring(breathing, night),
    bloodOxygen: _meanDuring(oxygen, night),
    wristTemp: wristTemp,
    wristTempDeviation: wristTemp == null || priorTemps.length < 7
        ? null
        : wristTemp - _mean(priorTemps)!,
    skinTempDelta: ios ? null : nightTemp,
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
      final today = dayOf(overview.readAt);
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

/// Sleep heart rate for a range tab: mean heart rate per night date, each
/// read inside its own night window (never one read across the range or the
/// daytime between), plus why a read failed or was not allowed.
typedef SleepRangeHr = ({Map<DateTime, double> byNight, MetricGap? gap});

/// Night-window heart rate reads in flight at once, so 30 nights never fire
/// 30 platform calls together.
const maxSleepHrReadsInFlight = 5;

final sleepRangeHrProvider = FutureProvider.autoDispose
    .family<SleepRangeHr, SleepRange>((ref, range) async {
      const none = (byNight: <DateTime, double>{}, gap: null);
      final sleepOfF = _sleepOf(ref);
      final nightsF = ref.watch(sleepRangeNightsProvider(range).future);
      final sleepOf = await sleepOfF;
      final nights = await nightsF;
      if (sleepOf == null || nights == null) return none;
      final (overview, _) = sleepOf;
      final firstDate = currentRangeStart(overview.readAt, range);
      final current = [
        for (final n in nights)
          if (!n.date.isBefore(firstDate)) n,
      ];
      final reader = ref.read(healthReaderProvider);
      final results = await _pooled(
        current.length,
        (i) => _readResult(
          reader,
          HealthSeriesType.heartRate,
          current[i].start,
          current[i].end,
        ),
      );
      if (!_stillOwner(ref, overview.ownerId)) return none;
      return (
        byNight: {
          for (final (i, n) in current.indexed)
            n.date: ?_meanDuring(_samples(results[i]), n),
        },
        gap: results.map(metricGapOf).nonNulls.firstOrNull,
      );
    });

/// Runs [read] for 0..[count)-1 with at most [maxSleepHrReadsInFlight] at
/// once; results keep their index order.
Future<List<T>> _pooled<T>(int count, Future<T> Function(int i) read) async {
  final results = List<T?>.filled(count, null);
  var next = 0;
  Future<void> worker() async {
    while (next < count) {
      final i = next++;
      results[i] = await read(i);
    }
  }

  await Future.wait([
    for (var w = 0; w < maxSleepHrReadsInFlight && w < count; w++) worker(),
  ]);
  return results.cast<T>();
}

/// First night date of [range] ending on the date of [readAt].
DateTime currentRangeStart(DateTime readAt, SleepRange range) =>
    DateTime(readAt.year, readAt.month, readAt.day - (range.nights - 1));

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
