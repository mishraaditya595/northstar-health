import 'dart:async';

import 'package:beyondrep/features/health/data/health_reader.dart';

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
}
