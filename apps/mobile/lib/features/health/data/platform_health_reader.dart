import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:health/health.dart' hide HealthValue;

import 'health_reader.dart';
import 'sleep_merge.dart';

const _sleepTypes = [
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_REM,
];

// One entry per metric; sleep's stage types share a single permission.
const _requestTypes = [
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.STEPS,
  HealthDataType.RESTING_HEART_RATE,
  HealthDataType.WEIGHT,
];

const _knownSources = {'com.google.android.apps.fitness': 'Fit'};

/// Display name for a platform source id. Never returns a raw identifier.
String friendlySource(String sourceName, HealthPlatformKind p) =>
    _knownSources[sourceName] ??
    (p == HealthPlatformKind.appleHealth ? 'Apple Health' : 'Health Connect');

/// The only class that talks to the `health` plugin. Values are returned to
/// the caller and never stored or logged here.
class PlatformHealthReader implements HealthReader {
  PlatformHealthReader(this._health, {HealthPlatformKind? platform})
    : platform =
          platform ??
          (defaultTargetPlatform == TargetPlatform.iOS
              ? HealthPlatformKind.appleHealth
              : HealthPlatformKind.healthConnect);

  final Health _health;

  @override
  final HealthPlatformKind platform;

  Future<void>? _configured;

  Future<void> _configure() => _configured ??= _health.configure();

  bool get _isAndroid => platform == HealthPlatformKind.healthConnect;

  @override
  Future<HealthAvailability> availability() async {
    if (!_isAndroid) return HealthAvailability.available;
    try {
      await _configure();
      return switch (await _health.getHealthConnectSdkStatus()) {
        HealthConnectSdkStatus.sdkAvailable => HealthAvailability.available,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
          HealthAvailability.needsInstall,
        _ => HealthAvailability.unsupported,
      };
    } catch (_) {
      return HealthAvailability.unsupported;
    }
  }

  @override
  Future<void> requestAccess() async {
    await _configure();
    await _health.requestAuthorization(_requestTypes);
  }

  @override
  Future<void> openInstall() async {
    await _configure();
    await _health.installHealthConnect();
  }

  @override
  Future<HealthReading> read(HealthMetric metric, DateTime now) async {
    try {
      await _configure();
      return switch (metric) {
        HealthMetric.steps => await _steps(now),
        HealthMetric.sleep => await _sleep(now),
        HealthMetric.restingHeartRate => await _latest(
          HealthDataType.RESTING_HEART_RATE,
          now.subtract(const Duration(days: 7)),
          now,
        ),
        HealthMetric.weight => await _latest(
          HealthDataType.WEIGHT,
          now.subtract(const Duration(days: 30)),
          now,
        ),
      };
    } on HealthPlatformException catch (e) {
      return switch (e.errorCode) {
        HealthErrorCode.permissionDenied =>
          _isAndroid ? const HealthNotAllowed() : const HealthNoData(),
        HealthErrorCode.notSupported => const HealthUnsupported(),
        _ => const HealthReadFailed(),
      };
    } catch (_) {
      return const HealthReadFailed();
    }
  }

  /// Android reports a denied permission explicitly; iOS never reveals it.
  Future<bool> _allowed(HealthDataType type) async =>
      !_isAndroid || await _health.hasPermissions([type]) == true;

  Future<HealthReading> _steps(DateTime now) async {
    if (!await _allowed(HealthDataType.STEPS)) return const HealthNotAllowed();
    final midnight = DateTime(now.year, now.month, now.day);
    final steps = await _health.getTotalStepsInInterval(midnight, now);
    if (steps <= 0) return const HealthNoData();
    return HealthMeasured(
      value: steps.toDouble(),
      measuredAt: now,
      source: friendlySource('', platform),
    );
  }

  Future<HealthReading> _sleep(DateTime now) async {
    if (!await _allowed(HealthDataType.SLEEP_ASLEEP)) {
      return const HealthNotAllowed();
    }
    final points = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: DateTime(now.year, now.month, now.day - 1, 18),
      endTime: now,
    );
    if (points.isEmpty) return const HealthNoData();
    final minutes = mergedSleepMinutes([
      for (final p in points) (from: p.dateFrom, to: p.dateTo),
    ]);
    if (minutes <= 0) return const HealthNoData();
    final sources = <String>{
      for (final p in points) friendlySource(p.sourceName, platform),
    };
    return HealthMeasured(
      value: minutes.toDouble(),
      measuredAt: points
          .map((p) => p.dateTo)
          .reduce((a, b) => a.isAfter(b) ? a : b),
      source: sources.join(', '),
    );
  }

  Future<HealthReading> _latest(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    if (!await _allowed(type)) return const HealthNotAllowed();
    final points = await _health.getHealthDataFromTypes(
      types: [type],
      startTime: start,
      endTime: end,
      limit: 1,
    );
    final numeric = points.where((p) => p.value is NumericHealthValue);
    if (numeric.isEmpty) return const HealthNoData();
    final newest = numeric.reduce((a, b) => a.dateTo.isAfter(b.dateTo) ? a : b);
    return HealthMeasured(
      value: (newest.value as NumericHealthValue).numericValue.toDouble(),
      measuredAt: newest.dateTo,
      source: friendlySource(newest.sourceName, platform),
    );
  }
}
