import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/health_types.dart';
import '../domain/outside_workouts.dart';
import '../domain/own_workout_health.dart';

export '../domain/health_types.dart' show HealthPlatformKind;

enum HealthAvailability { available, needsInstall, unsupported }

enum HealthSeriesType {
  heartRate,
  restingHeartRate,
  hrv,
  respiratoryRate,
  bloodOxygen,
  vo2Max,
  walkingHeartRate,
  sleepingWristTemperature,
  skinTemperature,
  weight,
  bodyFat,
  leanMass,
}

enum HealthTotalType { steps, activeEnergy }

sealed class SeriesResult<T> {
  const SeriesResult();
}

final class SeriesData<T> extends SeriesResult<T> {
  const SeriesData(this.data);
  final T data;
}

final class SeriesNotAllowed<T> extends SeriesResult<T> {
  const SeriesNotAllowed();
}

/// The type was never requested.
final class SeriesNeedsAccess<T> extends SeriesResult<T> {
  const SeriesNeedsAccess();
}

final class SeriesFailed<T> extends SeriesResult<T> {
  const SeriesFailed();
}

final class SeriesUnsupported<T> extends SeriesResult<T> {
  const SeriesUnsupported();
}

abstract interface class HealthReader {
  HealthPlatformKind get platform;
  Future<HealthAvailability> availability();

  /// One permission sheet for every read type (the Phase 3 metrics plus the
  /// [HealthSeriesType] and [HealthTotalType] reads, plus history where
  /// Health Connect offers it).
  Future<void> requestAccess();

  /// Android: opens the Health Connect install flow.
  Future<void> openInstall();

  /// Android: opens Health Connect's permission settings. No-op on iOS, where
  /// a denied read is indistinguishable from no data.
  Future<void> openSettings();

  /// The range reads below never throw.
  Future<SeriesResult<List<SleepSegment>>> readSleep(
    DateTime from,
    DateTime to,
  );

  Future<SeriesResult<List<HealthSample>>> readSeries(
    HealthSeriesType type,
    DateTime from,
    DateTime to,
  );

  /// Hourly buckets from [from] (a local midnight) to [to].
  Future<SeriesResult<List<HealthSample>>> readHourlyTotals(
    HealthTotalType type,
    DateTime from,
    DateTime to,
  );

  /// Workouts other apps saved to the platform, own-app writes dropped.
  Future<SeriesResult<List<OutsideWorkout>>> readWorkouts(
    DateTime from,
    DateTime to,
  );

  /// Average and maximum heart rate and active energy of the workout whose
  /// platform record id is [platformWorkoutId] (compared ignoring case), read
  /// fresh for [from]..[to]. Data holds null when the record is not found.
  /// Android: only a record BeyondRep wrote itself, with its own heart rate.
  Future<SeriesResult<OwnWorkoutHealth?>> readOwnWorkout(
    String platformWorkoutId,
    DateTime from,
    DateTime to,
  );

  /// Some current types were never requested or are not granted.
  Future<bool> needsMoreAccess();

  /// Requests the full current type list (+ history where available).
  Future<void> requestMoreAccess();

  /// Android: isHealthDataHistoryAuthorized; iOS: true.
  Future<bool> hasHistoryAccess();
}

final healthReaderProvider = Provider<HealthReader>(
  (ref) => throw UnimplementedError('healthReaderProvider is not overridden'),
);
