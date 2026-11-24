import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HealthMetric { sleep, steps, restingHeartRate, weight }

enum HealthPlatformKind { appleHealth, healthConnect }

enum HealthAvailability { available, needsInstall, unsupported }

sealed class HealthReading {
  const HealthReading();
}

/// sleep: minutes asleep; steps: count; restingHeartRate: bpm; weight: kg.
final class HealthMeasured extends HealthReading {
  const HealthMeasured({
    required this.value,
    required this.measuredAt,
    required this.source,
  });

  final double value;
  final DateTime measuredAt;
  final String source;
}

final class HealthNoData extends HealthReading {
  const HealthNoData();
}

final class HealthNotAllowed extends HealthReading {
  const HealthNotAllowed();
}

final class HealthReadFailed extends HealthReading {
  const HealthReadFailed();
}

final class HealthUnsupported extends HealthReading {
  const HealthUnsupported();
}

abstract interface class HealthReader {
  HealthPlatformKind get platform;
  Future<HealthAvailability> availability();

  /// One permission sheet for all four metric types.
  Future<void> requestAccess();

  /// Android: opens the Health Connect install flow.
  Future<void> openInstall();

  /// Never throws; failures map to a [HealthReading] variant.
  Future<HealthReading> read(HealthMetric metric, DateTime now);
}

final healthReaderProvider = Provider<HealthReader>(
  (ref) => throw UnimplementedError('healthReaderProvider is not overridden'),
);
