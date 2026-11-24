import 'dart:async';

import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';

class FakeHealthReader implements HealthReader {
  FakeHealthReader({
    this.platform = HealthPlatformKind.appleHealth,
    this.availabilityResult = HealthAvailability.available,
    Map<HealthMetric, HealthReading>? readings,
  }) : readings = readings ?? _defaultReadings();

  @override
  final HealthPlatformKind platform;
  HealthAvailability availabilityResult;
  Map<HealthMetric, HealthReading> readings;
  Set<HealthMetric> throwOn = {};
  bool throwOnRequestAccess = false;
  Completer<void>? requestAccessGate;
  int requestAccessCalls = 0;
  int openInstallCalls = 0;
  int openSettingsCalls = 0;
  bool throwOnOpenSettings = false;
  final List<HealthMetric> readCalls = [];
  List<SleepSegment> sleep = [];
  final Map<HealthSeriesType, List<HealthSample>> series = {};
  final Map<HealthTotalType, List<HealthSample>> totals = {};
  Set<HealthSeriesType> throwOnSeries = {};
  bool needsMore = false;
  bool history = true;
  int requestMoreAccessCalls = 0;
  final List<(HealthSeriesType, DateTime, DateTime)> seriesCalls = [];

  static Map<HealthMetric, HealthReading> _defaultReadings() => {
    for (final metric in HealthMetric.values)
      metric: HealthMeasured(
        value: 1,
        measuredAt: DateTime(2026, 11, 24, 7),
        source: 'Fake source',
      ),
  };

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
  Future<HealthReading> read(HealthMetric metric, DateTime now) async {
    readCalls.add(metric);
    if (throwOn.contains(metric)) throw StateError('synthetic reader bug');
    return readings[metric] ?? const HealthNoData();
  }

  @override
  Future<SeriesResult<List<SleepSegment>>> readSleep(
    DateTime from,
    DateTime to,
  ) async => SeriesData(sleep);

  @override
  Future<SeriesResult<List<HealthSample>>> readSeries(
    HealthSeriesType type,
    DateTime from,
    DateTime to,
  ) async {
    seriesCalls.add((type, from, to));
    if (throwOnSeries.contains(type)) throw StateError('synthetic series bug');
    return SeriesData(series[type] ?? const []);
  }

  @override
  Future<SeriesResult<List<HealthSample>>> readHourlyTotals(
    HealthTotalType type,
    DateTime from,
    DateTime to,
  ) async => SeriesData(totals[type] ?? const []);

  @override
  Future<bool> needsMoreAccess() async => needsMore;

  @override
  Future<void> requestMoreAccess() async => requestMoreAccessCalls++;

  @override
  Future<bool> hasHistoryAccess() async => history;
}
