import 'dart:async';

import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';

class FakeHealthReader implements HealthReader {
  FakeHealthReader({
    this.platform = HealthPlatformKind.appleHealth,
    this.availabilityResult = HealthAvailability.available,
  });

  @override
  final HealthPlatformKind platform;
  HealthAvailability availabilityResult;
  bool throwOnRequestAccess = false;
  Completer<void>? requestAccessGate;
  int requestAccessCalls = 0;
  int openInstallCalls = 0;
  int openSettingsCalls = 0;
  bool throwOnOpenSettings = false;
  List<SleepSegment> sleep = [];
  final Map<HealthSeriesType, List<HealthSample>> series = {};
  final Map<HealthTotalType, List<HealthSample>> totals = {};
  Set<HealthSeriesType> throwOnSeries = {};
  bool throwOnSleep = false;
  bool needsMore = false;
  bool history = true;
  int requestMoreAccessCalls = 0;
  final List<(HealthSeriesType, DateTime, DateTime)> seriesCalls = [];
  final List<(DateTime, DateTime)> sleepCalls = [];
  final List<(HealthTotalType, DateTime, DateTime)> totalsCalls = [];

  /// Non-data results (e.g. [SeriesNeedsAccess]) that win over [series].
  final Map<HealthSeriesType, SeriesResult<List<HealthSample>>> seriesResults =
      {};

  /// Non-data results that win over [totals].
  final Map<HealthTotalType, SeriesResult<List<HealthSample>>> totalsResults =
      {};

  /// When true, [readSeries] yields once before answering, so reads started
  /// together overlap and [maxSeriesInFlight] shows how many ran at once.
  bool overlapSeries = false;
  int _seriesInFlight = 0;
  int maxSeriesInFlight = 0;

  /// When true, [readSeries] answers only samples overlapping [from, to], as
  /// a platform does.
  bool applyWindows = false;

  /// Holds every [readSleep] until completed.
  Completer<void>? sleepGate;

  @override
  Future<HealthAvailability> availability() async => availabilityResult;

  @override
  Future<void> requestAccess() async {
    requestAccessCalls++;
    await requestAccessGate?.future;
    if (throwOnRequestAccess) throw StateError('synthetic permission bug');
  }

  @override
  Future<void> openInstall() async => openInstallCalls++;

  @override
  Future<void> openSettings() async {
    openSettingsCalls++;
    if (throwOnOpenSettings) throw StateError('synthetic settings bug');
  }

  @override
  Future<SeriesResult<List<SleepSegment>>> readSleep(
    DateTime from,
    DateTime to,
  ) async {
    sleepCalls.add((from, to));
    await sleepGate?.future;
    if (throwOnSleep) throw StateError('synthetic sleep bug');
    return SeriesData(sleep);
  }

  @override
  Future<SeriesResult<List<HealthSample>>> readSeries(
    HealthSeriesType type,
    DateTime from,
    DateTime to,
  ) async {
    seriesCalls.add((type, from, to));
    if (overlapSeries) {
      _seriesInFlight++;
      if (_seriesInFlight > maxSeriesInFlight) {
        maxSeriesInFlight = _seriesInFlight;
      }
      await Future<void>.microtask(() {});
      _seriesInFlight--;
    }
    if (throwOnSeries.contains(type)) throw StateError('synthetic series bug');
    final samples = series[type] ?? const <HealthSample>[];
    return seriesResults[type] ??
        SeriesData(
          applyWindows
              ? [
                  for (final s in samples)
                    if (!s.to.isBefore(from) && !s.from.isAfter(to)) s,
                ]
              : samples,
        );
  }

  @override
  Future<SeriesResult<List<HealthSample>>> readHourlyTotals(
    HealthTotalType type,
    DateTime from,
    DateTime to,
  ) async {
    totalsCalls.add((type, from, to));
    return totalsResults[type] ?? SeriesData(totals[type] ?? const []);
  }

  @override
  Future<bool> needsMoreAccess() async => needsMore;

  @override
  Future<void> requestMoreAccess() async => requestMoreAccessCalls++;

  @override
  Future<bool> hasHistoryAccess() async => history;
}
