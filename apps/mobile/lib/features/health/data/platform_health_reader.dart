import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:health/health.dart' hide HealthValue;

import '../domain/health_types.dart';
import '../domain/outside_workouts.dart';
import '../domain/own_workout_health.dart';
import '../domain/sleep_nights.dart';
import 'health_reader.dart';

// Read types requested on both platforms. Sleep stages share one permission
// on Android but are separate HealthKit types.
const _commonRequestTypes = [
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.STEPS,
  HealthDataType.RESTING_HEART_RATE,
  HealthDataType.WEIGHT,
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_REM,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.HEART_RATE,
  HealthDataType.RESPIRATORY_RATE,
  HealthDataType.BLOOD_OXYGEN,
  HealthDataType.VO2_MAX,
  HealthDataType.ACTIVE_ENERGY_BURNED,
  HealthDataType.BODY_FAT_PERCENTAGE,
  HealthDataType.LEAN_BODY_MASS,
  HealthDataType.WORKOUT,
];

const _iosRequestTypes = [
  ..._commonRequestTypes,
  HealthDataType.SLEEP_IN_BED,
  HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  HealthDataType.WALKING_HEART_RATE,
  HealthDataType.SLEEP_WRIST_TEMPERATURE,
];

const _androidRequestTypes = [
  ..._commonRequestTypes,
  HealthDataType.SLEEP_SESSION,
  HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
];

const _sleepStages = {
  HealthDataType.SLEEP_ASLEEP: SleepStage.asleepUnspecified,
  HealthDataType.SLEEP_LIGHT: SleepStage.light,
  HealthDataType.SLEEP_DEEP: SleepStage.deep,
  HealthDataType.SLEEP_REM: SleepStage.rem,
  HealthDataType.SLEEP_AWAKE: SleepStage.awake,
  HealthDataType.SLEEP_IN_BED: SleepStage.inBed,
  HealthDataType.SLEEP_SESSION: SleepStage.inBed,
};

/// HealthKit reads these in `HKUnit.percent()`, a 0-1 fraction; Health
/// Connect's `Percentage` is already 0-100.
const _iosFractionTypes = {
  HealthDataType.BODY_FAT_PERCENTAGE,
  HealthDataType.BLOOD_OXYGEN,
};

/// Workouts BeyondRep itself saves, never read back as another app's.
const _ownAppId = 'in.beyondrep.app';

/// The app itself or one of its children (the watch app), never a lookalike
/// such as `in.beyondrep.apple`.
bool _isOwnSource(String source) =>
    source == _ownAppId || source.startsWith('$_ownAppId.');

OutsideWorkoutKind _kindOf(HealthWorkoutActivityType type) {
  final name = type.name;
  if (name.contains('DANCE')) return OutsideWorkoutKind.dance;
  return switch (type) {
    HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING ||
    HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING ||
    HealthWorkoutActivityType.STRENGTH_TRAINING ||
    HealthWorkoutActivityType.WEIGHTLIFTING => OutsideWorkoutKind.strength,
    HealthWorkoutActivityType.RUNNING ||
    HealthWorkoutActivityType.RUNNING_TREADMILL => OutsideWorkoutKind.running,
    HealthWorkoutActivityType.WALKING ||
    HealthWorkoutActivityType.WALKING_TREADMILL => OutsideWorkoutKind.walking,
    HealthWorkoutActivityType.BIKING ||
    HealthWorkoutActivityType.BIKING_STATIONARY ||
    HealthWorkoutActivityType.HAND_CYCLING => OutsideWorkoutKind.cycling,
    HealthWorkoutActivityType.SWIMMING ||
    HealthWorkoutActivityType.SWIMMING_OPEN_WATER ||
    HealthWorkoutActivityType.SWIMMING_POOL => OutsideWorkoutKind.swimming,
    HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING =>
      OutsideWorkoutKind.hiit,
    HealthWorkoutActivityType.YOGA => OutsideWorkoutKind.yoga,
    HealthWorkoutActivityType.PILATES => OutsideWorkoutKind.pilates,
    HealthWorkoutActivityType.ROWING ||
    HealthWorkoutActivityType.ROWING_MACHINE => OutsideWorkoutKind.rowing,
    HealthWorkoutActivityType.ELLIPTICAL => OutsideWorkoutKind.elliptical,
    HealthWorkoutActivityType.HIKING => OutsideWorkoutKind.hiking,
    _ => OutsideWorkoutKind.other,
  };
}

/// Kilocalories, or null for a missing, zero or unknown value.
double? _kcalOf(int? value, HealthDataUnit? unit) {
  if (value == null) return null;
  final kcal = switch (unit) {
    null || HealthDataUnit.KILOCALORIE => value.toDouble(),
    HealthDataUnit.JOULE => value / 4184,
    _ => null,
  };
  return kcal != null && kcal > 0 ? kcal : null;
}

/// Metres, or null for a missing, zero or unknown value.
double? _metersOf(int? value, HealthDataUnit? unit) {
  if (value == null) return null;
  final meters = switch (unit) {
    null || HealthDataUnit.METER => value.toDouble(),
    HealthDataUnit.CENTIMETER => value / 100,
    HealthDataUnit.MILE => value * 1609.344,
    _ => null,
  };
  return meters != null && meters > 0 ? meters : null;
}

const _settingsChannel = MethodChannel('northstar/health_settings');

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

  /// The production reader. Keeps `Health()` construction in this file, the
  /// only importer of the plugin.
  factory PlatformHealthReader.system() => PlatformHealthReader(Health());

  final Health _health;

  @override
  final HealthPlatformKind platform;

  Future<void>? _configured;

  /// A failed configure is not cached; the next call retries it.
  Future<void> _configure() async {
    try {
      await (_configured ??= _health.configure());
    } catch (_) {
      _configured = null;
      rethrow;
    }
  }

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

  /// Skin temperature is requested only where Health Connect has it.
  Future<List<HealthDataType>> _requestTypes() async {
    if (!_isAndroid) return _iosRequestTypes;
    return [
      ..._androidRequestTypes,
      if (await _health.isSkinTemperatureAvailable())
        HealthDataType.SKIN_TEMPERATURE,
    ];
  }

  @override
  Future<void> requestAccess() async {
    await _configure();
    await _health.requestAuthorization(await _requestTypes());
    if (_isAndroid &&
        await _health.isHealthDataHistoryAvailable() &&
        !await _health.isHealthDataHistoryAuthorized()) {
      await _health.requestHealthDataHistoryAuthorization();
    }
  }

  @override
  Future<void> openInstall() async {
    await _configure();
    await _health.installHealthConnect();
  }

  @override
  Future<void> openSettings() async {
    if (!_isAndroid) return;
    try {
      await _settingsChannel.invokeMethod<bool>('openHealthConnectSettings');
    } catch (_) {
      // The resume refresh still re-reads; nothing to report to the user.
    }
  }

  @override
  Future<SeriesResult<List<SleepSegment>>> readSleep(
    DateTime from,
    DateTime to,
  ) => _guard(() async {
    final types = [
      ..._sleepStages.keys.where(
        (t) => _isAndroid
            ? t != HealthDataType.SLEEP_IN_BED
            : t != HealthDataType.SLEEP_SESSION,
      ),
    ];
    if (!await _allowedAll(types)) return const SeriesNotAllowed();
    final points = await _health.getHealthDataFromTypes(
      types: types,
      startTime: from,
      endTime: to,
    );
    final segments = <SleepSegment>[
      for (final p in points)
        if (_sleepStages[p.type] case final stage?)
          (
            from: p.dateFrom,
            to: p.dateTo,
            stage: stage,
            source: _sleepSourceName(p),
            sourceKey: p.sourceId.isEmpty ? p.sourceName : p.sourceId,
          ),
    ];
    // Health Connect apps may write sessions without stages. iOS in-bed
    // alone (e.g. an iPhone bedtime schedule) is not sleep and stays as is.
    return SeriesData(
      _isAndroid ? sessionsWithoutStagesAsSleep(segments) : segments,
    );
  });

  /// HealthKit's source name is the app or device name the Health app shows
  /// (e.g. "Oura"); Health Connect only gives a package name, which is never
  /// shown.
  String _sleepSourceName(HealthDataPoint p) =>
      !_isAndroid && p.sourceName.isNotEmpty
      ? p.sourceName
      : friendlySource(p.sourceName, platform);

  @override
  Future<SeriesResult<List<HealthSample>>> readSeries(
    HealthSeriesType type,
    DateTime from,
    DateTime to,
  ) => _guard(() async {
    final dataType = await _seriesType(type);
    if (dataType == null) return const SeriesUnsupported();
    if (!await _allowed(dataType)) return const SeriesNotAllowed();
    final points = await _health.getHealthDataFromTypes(
      types: [dataType],
      startTime: from,
      endTime: to,
    );
    final scale = !_isAndroid && _iosFractionTypes.contains(dataType) ? 100 : 1;
    return SeriesData(_samples(points, scale));
  });

  @override
  Future<SeriesResult<List<HealthSample>>> readHourlyTotals(
    HealthTotalType type,
    DateTime from,
    DateTime to,
  ) => _guard(() async {
    final dataType = switch (type) {
      HealthTotalType.steps => HealthDataType.STEPS,
      HealthTotalType.activeEnergy => HealthDataType.ACTIVE_ENERGY_BURNED,
    };
    if (!await _allowed(dataType)) return const SeriesNotAllowed();
    final points = await _health.getHealthIntervalDataFromTypes(
      startDate: from,
      endDate: to,
      types: [dataType],
      interval: 3600,
    );
    return SeriesData(_samples(points, 1));
  });

  @override
  Future<SeriesResult<List<OutsideWorkout>>> readWorkouts(
    DateTime from,
    DateTime to,
  ) => _guard(() async {
    if (!await _allowed(HealthDataType.WORKOUT)) {
      return const SeriesNotAllowed();
    }
    final points = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT],
      startTime: from,
      endTime: to,
    );
    return SeriesData([
      for (final p in points)
        if (p.value case final WorkoutHealthValue w)
          if (!_isOwnSource(p.sourceId) && !_isOwnSource(p.sourceName))
            OutsideWorkout(
              id: p.uuid.isEmpty
                  ? '${p.sourceId}-${p.dateFrom.millisecondsSinceEpoch}'
                  : p.uuid,
              kind: _kindOf(w.workoutActivityType),
              start: p.dateFrom.toUtc(),
              end: p.dateTo.toUtc(),
              // Health Connect needs a separate calories permission that
              // BeyondRep does not request.
              activeKcal: _isAndroid
                  ? null
                  : _kcalOf(w.totalEnergyBurned, w.totalEnergyBurnedUnit),
              distanceMeters: _metersOf(w.totalDistance, w.totalDistanceUnit),
              source: _sleepSourceName(p),
            ),
    ]);
  });

  @override
  Future<SeriesResult<OwnWorkoutHealth?>> readOwnWorkout(
    String platformWorkoutId,
    DateTime from,
    DateTime to,
  ) => _guard(() async {
    if (!await _allowed(HealthDataType.WORKOUT)) {
      return const SeriesNotAllowed();
    }
    const margin = Duration(minutes: 5);
    final points = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT],
      startTime: from.subtract(margin),
      endTime: to.add(margin),
    );
    final wanted = platformWorkoutId.toLowerCase();
    HealthDataPoint? match;
    for (final p in points) {
      // On Android the uuid is a Health Connect record id other apps can
      // see, so only a record BeyondRep itself wrote counts.
      if (p.uuid.toLowerCase() == wanted &&
          p.value is WorkoutHealthValue &&
          (!_isAndroid ||
              _isOwnSource(p.sourceId) ||
              _isOwnSource(p.sourceName))) {
        match = p;
        break;
      }
    }
    if (match == null) return const SeriesData(null);
    final workout = match.value as WorkoutHealthValue;
    int? average;
    int? max;
    if (await _allowed(HealthDataType.HEART_RATE)) {
      final beats = [
        for (final p in await _health.getHealthDataFromTypes(
          types: [HealthDataType.HEART_RATE],
          startTime: match.dateFrom,
          // End-inclusive: a sample stamped at the workout end counts.
          endTime: match.dateTo.add(const Duration(seconds: 1)),
        ))
          // Android: other apps' heart rate in the window is not this
          // workout's.
          if (!_isAndroid ||
              _isOwnSource(p.sourceId) ||
              _isOwnSource(p.sourceName))
            if (p.value case NumericHealthValue(:final numericValue))
              numericValue.toDouble(),
      ];
      if (beats.isNotEmpty) {
        average = (beats.reduce((a, b) => a + b) / beats.length).round();
        max = beats.reduce((a, b) => a > b ? a : b).round();
      }
    }
    return SeriesData(
      OwnWorkoutHealth(
        averageBpm: average,
        maxBpm: max,
        activeKcal: _kcalOf(
          workout.totalEnergyBurned,
          workout.totalEnergyBurnedUnit,
        ),
      ),
    );
  });

  @override
  Future<bool> needsMoreAccess() async {
    try {
      await _configure();
      final types = await _requestTypes();
      if (_isAndroid) return await _health.hasPermissions(types) != true;
      return await _health.getRequestStatusForAuthorization(types) ==
          HealthAuthorizationRequestStatus.shouldRequest;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> requestMoreAccess() => requestAccess();

  @override
  Future<bool> hasHistoryAccess() async {
    if (!_isAndroid) return true;
    try {
      await _configure();
      return await _health.isHealthDataHistoryAuthorized();
    } catch (_) {
      return false;
    }
  }

  /// Null when [type] does not exist on this platform or device.
  Future<HealthDataType?> _seriesType(HealthSeriesType type) async =>
      switch (type) {
        HealthSeriesType.heartRate => HealthDataType.HEART_RATE,
        HealthSeriesType.restingHeartRate => HealthDataType.RESTING_HEART_RATE,
        HealthSeriesType.hrv =>
          _isAndroid
              ? HealthDataType.HEART_RATE_VARIABILITY_RMSSD
              : HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        HealthSeriesType.respiratoryRate => HealthDataType.RESPIRATORY_RATE,
        HealthSeriesType.bloodOxygen => HealthDataType.BLOOD_OXYGEN,
        HealthSeriesType.vo2Max => HealthDataType.VO2_MAX,
        HealthSeriesType.walkingHeartRate =>
          _isAndroid ? null : HealthDataType.WALKING_HEART_RATE,
        HealthSeriesType.sleepingWristTemperature =>
          _isAndroid ? null : HealthDataType.SLEEP_WRIST_TEMPERATURE,
        HealthSeriesType.skinTemperature =>
          _isAndroid && await _health.isSkinTemperatureAvailable()
              ? HealthDataType.SKIN_TEMPERATURE
              : null,
        HealthSeriesType.weight => HealthDataType.WEIGHT,
        HealthSeriesType.bodyFat => HealthDataType.BODY_FAT_PERCENTAGE,
        HealthSeriesType.leanMass => HealthDataType.LEAN_BODY_MASS,
      };

  List<HealthSample> _samples(List<HealthDataPoint> points, num scale) => [
    for (final p in points)
      if (p.value case NumericHealthValue(:final numericValue))
        (
          from: p.dateFrom,
          to: p.dateTo,
          value: numericValue.toDouble() * scale,
          source: friendlySource(p.sourceName, platform),
        ),
  ];

  /// Configures, runs [read] and maps platform failures. Never throws.
  Future<SeriesResult<T>> _guard<T>(
    Future<SeriesResult<T>> Function() read,
  ) async {
    try {
      await _configure();
      return await read();
    } on HealthException catch (e) {
      return switch (e.errorCode) {
        HealthErrorCode.permissionDenied =>
          _isAndroid ? SeriesNotAllowed<T>() : SeriesNeedsAccess<T>(),
        HealthErrorCode.notSupported => SeriesUnsupported<T>(),
        _ => SeriesFailed<T>(),
      };
    } catch (_) {
      return SeriesFailed<T>();
    }
  }

  Future<bool> _allowedAll(List<HealthDataType> types) async =>
      !_isAndroid || await _health.hasPermissions(types) == true;

  /// Android reports a denied permission explicitly; iOS never reveals it.
  Future<bool> _allowed(HealthDataType type) async =>
      !_isAndroid || await _health.hasPermissions([type]) == true;
}
