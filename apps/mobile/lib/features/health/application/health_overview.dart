import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/health_connection_repository.dart';
import '../data/health_reader.dart';
import '../domain/daily_series.dart';
import '../domain/health_types.dart';
import '../domain/readiness.dart';
import '../domain/sleep_nights.dart';
import '../domain/sleep_score.dart';
import '../domain/trend.dart';
import 'health_summary_controller.dart';

enum MetricGap { noData, notAllowed, needsAccess, failed, unsupported }

sealed class Section<T> {
  const Section();
}

final class SectionData<T> extends Section<T> {
  const SectionData(this.value);
  final T value;
}

final class SectionGap<T> extends Section<T> {
  const SectionGap(this.gap);
  final MetricGap gap;
}

class SleepOverview {
  const SleepOverview({
    required this.lastNight,
    required this.score,
    required this.sleepAvgHr,
    required this.nights,
    required this.vsWeek,
    this.sleepHrGap,
  });

  /// The most recent night in the window.
  final SleepNight lastNight;

  /// Null when the night has no stages.
  final SleepScore? score;

  /// Mean heart rate inside [lastNight]'s window, bpm.
  final double? sleepAvgHr;

  /// Up to 31 nights, ascending by date.
  final List<SleepNight> nights;

  /// Last night's asleep minutes vs the mean of the nights in the 7 dates
  /// before it; null with fewer than 3 such nights.
  final TrendResult? vsWeek;

  /// Why heart rate inside [lastNight] could not be read; null when the read
  /// succeeded, even with no samples.
  final MetricGap? sleepHrGap;
}

class HeartOverview {
  const HeartOverview({
    required this.restingHr,
    required this.restingHrDaily,
    required this.hrv,
    required this.hrvDaily,
    required this.vo2Max,
    required this.vo2MaxDaily,
    required this.restingHrVsMonth,
    required this.hrvVsNormal,
    required this.hrvIsSdnn,
    this.restingHrGap,
    this.hrvGap,
    this.vo2Gap,
  });

  final DayValue? restingHr;
  final List<DayValue> restingHrDaily;
  final DayValue? hrv;
  final List<DayValue> hrvDaily;
  final DayValue? vo2Max;

  /// Latest per day over 90 days, for the change since a month earlier.
  final List<DayValue> vo2MaxDaily;

  /// Latest vs the mean of the earlier days in the window (needs ≥7).
  final TrendResult? restingHrVsMonth;
  final TrendResult? hrvVsNormal;

  /// Apple Health reports SDNN; Health Connect reports RMSSD.
  final bool hrvIsSdnn;

  /// Why a metric could not be read while the section has other data; null
  /// when its read succeeded (even with no samples).
  final MetricGap? restingHrGap, hrvGap, vo2Gap;
}

class ActivityOverview {
  const ActivityOverview({
    required this.stepsToday,
    required this.stepsDaily,
    required this.activeEnergyToday,
    required this.activeEnergyDaily,
    required this.stepsWeekAverage,
    this.stepsGap,
    this.energyGap,
  });

  final double? stepsToday;
  final List<DayValue> stepsDaily;
  final double? activeEnergyToday;
  final List<DayValue> activeEnergyDaily;

  /// Mean of the days with data among the 7 days before today.
  final double? stepsWeekAverage;

  /// As on [HeartOverview]: why a metric could not be read.
  final MetricGap? stepsGap, energyGap;
}

class BodyOverview {
  const BodyOverview({
    required this.weight,
    required this.weightDaily,
    required this.bodyFat,
    required this.weightVsMonth,
    this.weightSince,
    this.weightGap,
    this.bodyFatGap,
  });

  final DayValue? weight;
  final List<DayValue> weightDaily;
  final DayValue? bodyFat;

  /// Latest vs the earliest weight in the window (needs ≥2 days).
  final TrendResult? weightVsMonth;

  /// The earliest weight's day when it is under 21 days before the latest,
  /// so the change is labelled "since 22 Nov" rather than "in 30 days".
  final DateTime? weightSince;

  /// As on [HeartOverview]: why a metric could not be read.
  final MetricGap? weightGap, bodyFatGap;
}

/// Derived from the sleep and heart data already read; held in memory only.
class ReadinessOverview {
  const ReadinessOverview({
    required this.result,
    required this.hasHrv,
    required this.hasRestingHr,
    required this.hasSleep,
    required this.hrvVsNormal,
    required this.restingHrVsNormal,
    required this.hrvBaseline,
    required this.restingHrBaseline,
    required this.hrvIsSdnn,
  });

  final ReadinessResult result;

  /// Today's inputs are present, for the "what's missing" chips.
  final bool hasHrv, hasRestingHr, hasSleep;

  /// Today against the baseline mean; null without a value today or baseline.
  final TrendResult? hrvVsNormal, restingHrVsNormal;
  final Baseline? hrvBaseline, restingHrBaseline;
  final bool hrvIsSdnn;
}

/// Read fresh and held in memory only; never written anywhere.
class HealthOverview {
  const HealthOverview({
    required this.ownerId,
    required this.readAt,
    required this.platform,
    required this.readableFrom,
    required this.needsMoreAccess,
    required this.sleep,
    required this.heart,
    required this.activity,
    required this.body,
    required this.readiness,
  });

  /// The account this was read for; never shown under another account.
  final String ownerId;
  final DateTime readAt;
  final HealthPlatformKind platform;

  /// Android without history access: the earliest readable instant.
  final DateTime? readableFrom;
  final bool needsMoreAccess;
  final Section<SleepOverview> sleep;
  final Section<HeartOverview> heart;
  final Section<ActivityOverview> activity;
  final Section<BodyOverview> body;
  final Section<ReadinessOverview> readiness;
}

/// Readiness only means something on the day it was read: the same-owner
/// value survives a re-read, so an overview read yesterday must not score
/// today. Null for an overview from another day or a readiness gap.
ReadinessOverview? todaysReadiness(HealthOverview o, DateTime now) {
  if (dayOf(o.readAt) != dayOf(now)) return null;
  return switch (o.readiness) {
    SectionData(:final value) => value,
    SectionGap() => null,
  };
}

/// True when [o] still holds a readiness score from an earlier day, which
/// must not be shown as today's.
bool hasStaleReadiness(HealthOverview o, DateTime now) =>
    todaysReadiness(o, now) == null && o.readiness is SectionData;

const _staleAfter = Duration(minutes: 5);

class HealthOverviewController extends AsyncNotifier<HealthOverview?> {
  @override
  Future<HealthOverview?> build() async {
    final owner = ref.watch(healthOwnerIdProvider);
    // Riverpod keeps the previous value while a rebuild loads, and a plain
    // AsyncLoading copies it too. Replacing it with null first, then loading
    // again, means another account's overview is never exposed while this
    // account's read runs.
    if (state.value case final previous? when previous.ownerId != owner) {
      state = const AsyncData(null);
      state = const AsyncLoading();
    }
    // Rebuilds only when the connection flips, not on every summary reload.
    final connected = await ref.watch(
      healthSummaryProvider.selectAsync((s) => s is HealthConnected),
    );
    if (owner == null || !connected || !ref.mounted) return null;
    final reader = ref.read(healthReaderProvider);
    final repository = ref.read(healthConnectionRepositoryProvider);
    final overview = await _read(
      owner,
      reader,
      ref.read(healthClockProvider)(),
      repository.connectedAt(owner),
      repository.accessScope(owner),
    );
    // An account switch or disconnect while reading discards the result.
    if (!ref.mounted || ref.read(healthOwnerIdProvider) != owner) return null;
    return overview;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Re-reads after an error, after the user went to the permission
  /// settings (Manage), or when the overview is older than 5 minutes.
  Future<void> refreshIfStale() async {
    final reread = ref.read(healthRereadOnResumeProvider.notifier);
    if (ref.read(healthRereadOnResumeProvider)) {
      reread.set(false);
    } else if (!state.hasError) {
      final readAt = state.value?.readAt;
      if (readAt == null) return;
      final now = ref.read(healthClockProvider)();
      if (dayOf(now) == dayOf(readAt) &&
          now.difference(readAt) <= _staleAfter) {
        return;
      }
    }
    await refresh();
  }

  /// Never throws; re-reads afterwards. Once the sheet was shown, granted or
  /// not, the current scope is recorded so Android stops offering it.
  Future<void> requestMoreAccess() async {
    final owner = ref.read(healthOwnerIdProvider);
    final repository = ref.read(healthConnectionRepositoryProvider);
    try {
      await ref.read(healthReaderProvider).requestMoreAccess();
      // Not after an account switch: the store may be another account's.
      if (owner != null &&
          ref.mounted &&
          ref.read(healthOwnerIdProvider) == owner) {
        repository.recordAccessScope(owner, currentHealthAccessScope);
      }
    } catch (_) {}
    if (ref.mounted) await refresh();
  }
}

final healthOverviewProvider =
    AsyncNotifierProvider<HealthOverviewController, HealthOverview?>(
      HealthOverviewController.new,
    );

Future<SeriesResult<T>> _guard<T>(
  Future<SeriesResult<T>> Function() read,
) async {
  try {
    return await read();
  } catch (_) {
    return SeriesFailed<T>();
  }
}

Future<bool> _flag(Future<bool> Function() read, bool onError) async {
  try {
    return await read();
  } catch (_) {
    return onError;
  }
}

List<T> _list<T>(SeriesResult<List<T>> r) =>
    r is SeriesData<List<T>> ? r.data : const [];

/// Why a read gave no data; null when it succeeded, even with no samples.
MetricGap? metricGapOf(SeriesResult<Object?> r) => switch (r) {
  SeriesData() => null,
  SeriesNotAllowed() => MetricGap.notAllowed,
  SeriesNeedsAccess() => MetricGap.needsAccess,
  SeriesFailed() => MetricGap.failed,
  SeriesUnsupported() => MetricGap.unsupported,
};

Section<T> _section<T>(
  List<SeriesResult<Object?>> results,
  T? Function() build,
) {
  final value = build();
  if (value != null) return SectionData(value);
  final gaps = {for (final r in results) ?metricGapOf(r)};
  return SectionGap(
    _gapRank.firstWhere(gaps.contains, orElse: () => MetricGap.noData),
  );
}

/// needsAccess first so "Allow more data" is never hidden by another gap.
const _gapRank = [
  MetricGap.needsAccess,
  MetricGap.notAllowed,
  MetricGap.failed,
  MetricGap.unsupported,
];

double? _mean(Iterable<double> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

double? _valueOn(List<DayValue> daily, DateTime day) {
  for (final d in daily) {
    if (d.day == day) return d.value;
  }
  return null;
}

/// Latest vs the mean of the earlier days; null with fewer than [min] of them.
TrendResult? _vsPrior(TrendMetric metric, List<DayValue> daily, int min) {
  if (daily.length - 1 < min) return null;
  final prior = daily.sublist(0, daily.length - 1).map((d) => d.value);
  return trendOf(metric, daily.last.value, _mean(prior)!);
}

/// Per day the mean of samples inside that day's night, else the mean of the
/// day's samples outside any night.
List<DayValue> hrvDailyOf(List<HealthSample> samples, List<SleepNight> nights) {
  final overnight = <HealthSample>[];
  final daytime = <HealthSample>[];
  outer:
  for (final s in samples) {
    for (final n in nights) {
      if (!s.from.isBefore(n.start) && !s.to.isAfter(n.end)) {
        overnight.add((
          from: s.from,
          to: n.end,
          value: s.value,
          source: s.source,
        ));
        continue outer;
      }
    }
    daytime.add(s);
  }
  final byDay = {
    for (final d in reduceDaily(daytime, DailyReduction.mean)) d.day: d.value,
    for (final d in reduceDaily(overnight, DailyReduction.mean)) d.day: d.value,
  };
  return [
    for (final day in byDay.keys.toList()..sort())
      (day: day, value: byDay[day]!),
  ];
}

/// A gapped section counts as absent inputs; only two gaps for the same
/// reason make the whole readiness a gap.
/// [hrvDaily] and [rhrDaily] cover the 30 days before today, one more than
/// the heart section shows, so the baseline sees all of them.
Section<ReadinessOverview> _readiness(
  Section<SleepOverview> sleepSection,
  Section<HeartOverview> heartSection,
  List<DayValue> hrvDaily,
  List<DayValue> rhrDaily,
  DateTime today,
  HealthPlatformKind platform, {
  required bool inputFailed,
}) {
  // A read that failed is not a missing wearable; ask to try again.
  if (inputFailed) return const SectionGap(MetricGap.failed);
  if (sleepSection is SectionGap<SleepOverview> &&
      heartSection is SectionGap<HeartOverview> &&
      sleepSection.gap == heartSection.gap) {
    return SectionGap(sleepSection.gap);
  }
  // Sleep is required for a score: without permission, say so.
  if (sleepSection case SectionGap(gap: MetricGap.notAllowed)) {
    return const SectionGap(MetricGap.notAllowed);
  }
  final sleep = switch (sleepSection) {
    SectionData(:final value) => value,
    SectionGap() => null,
  };
  final hrvToday = _valueOn(hrvDaily, today);
  final rhrToday = _valueOn(rhrDaily, today);
  final hrvBaseline = baselineOf(hrvDaily, today, sdFloor: hrvSdFloor);
  final rhrBaseline = baselineOf(rhrDaily, today, sdFloor: rhrSdFloor);
  final night = sleep?.lastNight;
  return SectionData(
    ReadinessOverview(
      result: scoreReadiness(
        today: today,
        lastNight: night,
        sleepScore: sleep?.score,
        priorNights: sleep == null
            ? const []
            : sleep.nights.sublist(0, sleep.nights.length - 1),
        hrvDaily: hrvDaily,
        restingHrDaily: rhrDaily,
      ),
      hasHrv: hrvToday != null,
      hasRestingHr: rhrToday != null,
      hasSleep: night != null && dayOf(night.date) == today,
      hrvVsNormal: hrvToday == null || hrvBaseline == null
          ? null
          : trendOf(TrendMetric.hrv, hrvToday, hrvBaseline.mean),
      restingHrVsNormal: rhrToday == null || rhrBaseline == null
          ? null
          : trendOf(TrendMetric.restingHr, rhrToday, rhrBaseline.mean),
      hrvBaseline: hrvBaseline,
      restingHrBaseline: rhrBaseline,
      hrvIsSdnn: platform == HealthPlatformKind.appleHealth,
    ),
  );
}

Future<HealthOverview> _read(
  String ownerId,
  HealthReader reader,
  DateTime now,
  DateTime? connectedAt,
  int accessScope,
) async {
  final platform = reader.platform;
  final today = dayOf(now);
  DateTime daysAgo(int n, [int hour = 0]) =>
      DateTime(today.year, today.month, today.day - n, hour);
  final monthFrom = daysAgo(29);

  Future<SeriesResult<List<HealthSample>>> series(
    HealthSeriesType type,
    DateTime from,
  ) => _guard(() => reader.readSeries(type, from, now));
  Future<SeriesResult<List<HealthSample>>> totals(HealthTotalType type) =>
      _guard(() => reader.readHourlyTotals(type, monthFrom, now));

  final sleepFrom = daysAgo(31, 18);
  final sleepF = _guard(() => reader.readSleep(sleepFrom, now));
  // Readiness baselines use the 30 days before today. HRV starts with the
  // sleep read so day -30 holds its whole night, as the detail history does.
  final rhrF = series(HealthSeriesType.restingHeartRate, daysAgo(30));
  final hrvF = series(HealthSeriesType.hrv, sleepFrom);
  final weightF = series(HealthSeriesType.weight, monthFrom);
  final bodyFatF = series(HealthSeriesType.bodyFat, monthFrom);
  final vo2F = series(HealthSeriesType.vo2Max, daysAgo(89));
  final stepsF = totals(HealthTotalType.steps);
  final energyF = totals(HealthTotalType.activeEnergy);
  // Health Connect keeps reporting a declined type, so Android asks only
  // until the current scope was requested once. iOS reports only types never
  // requested.
  final needsMoreF =
      platform == HealthPlatformKind.healthConnect &&
          accessScope >= currentHealthAccessScope
      ? Future.value(false)
      : _flag(reader.needsMoreAccess, false);
  final historyF = platform == HealthPlatformKind.healthConnect
      ? _flag(reader.hasHistoryAccess, false)
      : Future.value(true);

  final sleepResult = await sleepF;
  final firstNight = daysAgo(30);
  final nights = [
    for (final n in buildNights(_list(sleepResult)))
      if (!n.date.isBefore(firstNight)) n,
  ];
  final lastNight = nights.isEmpty ? null : nights.last;
  final heartRate = lastNight == null
      ? null
      : await _guard(
          () => reader.readSeries(
            HealthSeriesType.heartRate,
            lastNight.start,
            lastNight.end,
          ),
        );

  final rhrResult = await rhrF;
  final hrvResult = await hrvF;
  final weightResult = await weightF;
  final bodyFatResult = await bodyFatF;
  final vo2Result = await vo2F;
  final stepsResult = await stepsF;
  final energyResult = await energyF;

  final rhrAll = reduceDaily(_list(rhrResult), DailyReduction.latest);
  final hrvAll = hrvDailyOf(_list(hrvResult), nights);
  List<DayValue> since(DateTime day, List<DayValue> all) => [
    for (final d in all)
      if (!d.day.isBefore(day)) d,
  ];
  final rhrDaily = since(monthFrom, rhrAll);
  final hrvDaily = since(monthFrom, hrvAll);

  final sleep = _section<SleepOverview>([sleepResult], () {
    if (lastNight == null) return null;
    final sleepAvgHr = _mean(_list(heartRate!).map((s) => s.value));
    final restingHr = rhrDaily
        .where((d) => !d.day.isAfter(lastNight.date))
        .lastOrNull
        ?.value;
    final d = lastNight.date;
    final weekFrom = DateTime(d.year, d.month, d.day - 7);
    final week = [
      for (final n in nights)
        if (!n.date.isBefore(weekFrom) && n.date.isBefore(d))
          n.asleep.inMinutes.toDouble(),
    ];
    return SleepOverview(
      lastNight: lastNight,
      score: scoreSleep(
        lastNight,
        priorNights: nights.sublist(0, nights.length - 1),
        sleepAvgHr: sleepAvgHr,
        restingHr: restingHr,
      ),
      sleepAvgHr: sleepAvgHr,
      nights: nights,
      vsWeek: week.length < 3
          ? null
          : trendOf(
              TrendMetric.sleepDuration,
              lastNight.asleep.inMinutes.toDouble(),
              _mean(week)!,
            ),
      sleepHrGap: metricGapOf(heartRate),
    );
  });

  final vo2Daily = reduceDaily(_list(vo2Result), DailyReduction.latest);
  final heart = _section<HeartOverview>([rhrResult, hrvResult, vo2Result], () {
    if (rhrDaily.isEmpty && hrvDaily.isEmpty && vo2Daily.isEmpty) return null;
    return HeartOverview(
      restingHr: rhrDaily.lastOrNull,
      restingHrDaily: rhrDaily,
      hrv: hrvDaily.lastOrNull,
      hrvDaily: hrvDaily,
      vo2Max: vo2Daily.lastOrNull,
      vo2MaxDaily: vo2Daily,
      restingHrVsMonth: _vsPrior(TrendMetric.restingHr, rhrDaily, 7),
      hrvVsNormal: _vsPrior(TrendMetric.hrv, hrvDaily, 7),
      hrvIsSdnn: platform == HealthPlatformKind.appleHealth,
      restingHrGap: metricGapOf(rhrResult),
      hrvGap: metricGapOf(hrvResult),
      vo2Gap: metricGapOf(vo2Result),
    );
  });

  final activity = _section<ActivityOverview>([stepsResult, energyResult], () {
    final steps = hourlyToDaily(_list(stepsResult));
    final energy = hourlyToDaily(_list(energyResult));
    if (steps.isEmpty && energy.isEmpty) return null;
    final stepsToday = _valueOn(steps, today);
    return ActivityOverview(
      // iOS reports no steps as 0; Phase 3 shows that as no data.
      stepsToday: platform == HealthPlatformKind.appleHealth && stepsToday == 0
          ? null
          : stepsToday,
      stepsDaily: steps,
      activeEnergyToday: _valueOn(energy, today),
      activeEnergyDaily: energy,
      stepsWeekAverage: summarizePeriod(
        steps,
        lastDay: daysAgo(1),
        days: 7,
      ).average,
      stepsGap: metricGapOf(stepsResult),
      energyGap: metricGapOf(energyResult),
    );
  });

  final body = _section<BodyOverview>([weightResult, bodyFatResult], () {
    final weight = reduceDaily(_list(weightResult), DailyReduction.latest);
    final bodyFat = reduceDaily(
      _list(bodyFatResult),
      DailyReduction.latest,
    ).lastOrNull;
    if (weight.isEmpty && bodyFat == null) return null;
    return BodyOverview(
      weight: weight.lastOrNull,
      weightDaily: weight,
      bodyFat: bodyFat,
      weightVsMonth: weight.length < 2
          ? null
          : trendOf(TrendMetric.weight, weight.last.value, weight.first.value),
      weightSince:
          weight.length >= 2 &&
              weight.last.day.difference(weight.first.day).inDays < 21
          ? weight.first.day
          : null,
      weightGap: metricGapOf(weightResult),
      bodyFatGap: metricGapOf(bodyFatResult),
    );
  });

  final readiness = _readiness(
    sleep,
    heart,
    since(daysAgo(30), hrvAll),
    rhrAll,
    today,
    platform,
    inputFailed:
        metricGapOf(sleepResult) == MetricGap.failed ||
        (metricGapOf(rhrResult) == MetricGap.failed &&
            metricGapOf(hrvResult) == MetricGap.failed),
  );

  return HealthOverview(
    ownerId: ownerId,
    readAt: now,
    platform: platform,
    readableFrom: !await historyF && connectedAt != null
        ? connectedAt.subtract(const Duration(days: 30))
        : null,
    needsMoreAccess: await needsMoreF,
    sleep: sleep,
    heart: heart,
    activity: activity,
    body: body,
    readiness: readiness,
  );
}
