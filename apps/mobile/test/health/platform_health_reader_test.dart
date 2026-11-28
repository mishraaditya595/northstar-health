import 'dart:io';

import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/data/platform_health_reader.dart';
import 'package:beyondrep/features/health/domain/health_types.dart';
import 'package:beyondrep/features/health/domain/outside_workouts.dart';
import 'package:beyondrep/features/health/domain/own_workout_health.dart';
import 'package:beyondrep/features/health/domain/sleep_nights.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

class _Call {
  _Call(this.types, this.start, this.end, this.limit);
  final List<HealthDataType> types;
  final DateTime start;
  final DateTime end;
  final int? limit;
}

class _IntervalCall {
  _IntervalCall(this.types, this.start, this.end, this.interval);
  final List<HealthDataType> types;
  final DateTime start;
  final DateTime end;
  final int interval;
}

class _FakeHealth extends Fake implements Health {
  int configureCalls = 0;
  Object? dataError;
  bool? permitted = true;
  HealthConnectSdkStatus? sdkStatus = HealthConnectSdkStatus.sdkAvailable;
  List<HealthDataPoint> points = [];
  final calls = <_Call>[];
  int installCalls = 0;
  List<HealthDataType>? requested;
  final permissionChecks = <List<HealthDataType>>[];
  Set<HealthDataType> deniedTypes = {};
  final intervalCalls = <_IntervalCall>[];
  HealthAuthorizationRequestStatus? requestStatus =
      HealthAuthorizationRequestStatus.unnecessary;
  List<HealthDataType>? statusTypes;
  bool historyAvailable = false;
  bool historyAuthorized = false;
  bool skinAvailable = false;

  /// Order of permission prompts: 'types' and 'history'.
  final prompts = <String>[];

  /// Thrown by the next `configure` call only.
  Object? configureError;

  @override
  Future<void> configure() async {
    configureCalls++;
    final error = configureError;
    configureError = null;
    if (error != null) throw error;
  }

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    permissionChecks.add(types);
    if (types.any(deniedTypes.contains)) return false;
    return permitted;
  }

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requested = types;
    prompts.add('types');
    return true;
  }

  @override
  Future<HealthAuthorizationRequestStatus?> getRequestStatusForAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    statusTypes = types;
    return requestStatus;
  }

  @override
  Future<bool> isHealthDataHistoryAvailable() async => historyAvailable;

  @override
  Future<bool> isHealthDataHistoryAuthorized() async => historyAuthorized;

  @override
  Future<bool> requestHealthDataHistoryAuthorization() async {
    prompts.add('history');
    return true;
  }

  @override
  Future<bool> isSkinTemperatureAvailable() async => skinAvailable;

  @override
  Future<List<HealthDataPoint>> getHealthIntervalDataFromTypes({
    required DateTime startDate,
    required DateTime endDate,
    required List<HealthDataType> types,
    required int interval,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    intervalCalls.add(_IntervalCall(types, startDate, endDate, interval));
    if (dataError != null) throw dataError!;
    return points.where((p) => types.contains(p.type)).toList();
  }

  @override
  Future<HealthConnectSdkStatus?> getHealthConnectSdkStatus() async =>
      sdkStatus;

  @override
  Future<void> installHealthConnect() async => installCalls++;

  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
    int? limit,
  }) async {
    calls.add(_Call(types, startTime, endTime, limit));
    if (dataError != null) throw dataError!;
    return points.where((p) => types.contains(p.type)).toList();
  }
}

HealthPlatformException _platformError(String code) => HealthPlatformException(
  HealthDataType.STEPS,
  PlatformException(code: code, message: 'private detail'),
);

HealthDataPoint _point(
  HealthDataType type,
  num value,
  DateTime from,
  DateTime to, {
  String source = 'com.example.unknown',
  String? sourceId,
}) => HealthDataPoint(
  uuid: 'u',
  value: NumericHealthValue(numericValue: value),
  type: type,
  unit: HealthDataUnit.NO_UNIT,
  dateFrom: from,
  dateTo: to,
  sourcePlatform: HealthPlatformType.googleHealthConnect,
  sourceDeviceId: 'd',
  sourceId: sourceId ?? source,
  sourceName: source,
);

HealthDataPoint _workout(
  HealthWorkoutActivityType type, {
  String uuid = 'w1',
  int? kcal = 131,
  int? meters,
  String sourceName = 'Aditi Watch',
  String sourceId = 'com.apple.health.watch',
  DateTime? from,
  DateTime? to,
}) => HealthDataPoint(
  uuid: uuid,
  value: WorkoutHealthValue(
    workoutActivityType: type,
    totalEnergyBurned: kcal,
    totalEnergyBurnedUnit: kcal == null ? null : HealthDataUnit.KILOCALORIE,
    totalDistance: meters,
    totalDistanceUnit: meters == null ? null : HealthDataUnit.METER,
  ),
  type: HealthDataType.WORKOUT,
  unit: HealthDataUnit.NO_UNIT,
  dateFrom: from ?? DateTime.utc(2026, 11, 20, 9),
  dateTo: to ?? DateTime.utc(2026, 11, 20, 9, 30),
  sourcePlatform: HealthPlatformType.appleHealth,
  sourceDeviceId: 'd',
  sourceId: sourceId,
  sourceName: sourceName,
);

const _commonTypes = [
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

const _androidTypes = [
  ..._commonTypes,
  HealthDataType.SLEEP_SESSION,
  HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
];

const _iosTypes = [
  ..._commonTypes,
  HealthDataType.SLEEP_IN_BED,
  HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  HealthDataType.WALKING_HEART_RATE,
  HealthDataType.SLEEP_WRIST_TEMPERATURE,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 24, 9, 30);
  late _FakeHealth health;

  PlatformHealthReader android() =>
      PlatformHealthReader(health, platform: HealthPlatformKind.healthConnect);
  PlatformHealthReader ios() =>
      PlatformHealthReader(health, platform: HealthPlatformKind.appleHealth);

  setUp(() => health = _FakeHealth());

  test('a failed configure is retried by the next call', () async {
    health.configureError = StateError('synthetic');
    final reader = android();
    final from = now.subtract(const Duration(days: 30));
    expect(
      await reader.readSeries(HealthSeriesType.weight, from, now),
      isA<SeriesFailed<List<HealthSample>>>(),
    );
    expect(
      await reader.readSeries(HealthSeriesType.weight, from, now),
      isA<SeriesData<List<HealthSample>>>(),
    );
    expect(health.configureCalls, 2);
  });

  group('openSettings', () {
    const channel = MethodChannel('northstar/health_settings');
    final calls = <String>[];
    Object? failure;
    Object? reply = true;

    setUp(() {
      calls.clear();
      failure = null;
      reply = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (failure != null) throw failure!;
            return reply;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('android opens Health Connect settings over the channel', () async {
      await android().openSettings();
      expect(calls, ['openHealthConnectSettings']);
    });

    test('a channel failure or false reply never throws', () async {
      failure = PlatformException(code: 'x', message: 'private detail');
      await android().openSettings();
      failure = null;
      reply = false;
      await android().openSettings();
      expect(calls.length, 2);
    });

    test('a missing channel handler never throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await android().openSettings();
    });

    test('iOS does nothing', () async {
      await ios().openSettings();
      expect(calls, isEmpty);
    });
  });

  test('availability mapping', () async {
    expect(await ios().availability(), HealthAvailability.available);
    health.sdkStatus = HealthConnectSdkStatus.sdkAvailable;
    expect(await android().availability(), HealthAvailability.available);
    health.sdkStatus =
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired;
    expect(await android().availability(), HealthAvailability.needsInstall);
    health.sdkStatus = HealthConnectSdkStatus.sdkUnavailable;
    expect(await android().availability(), HealthAvailability.unsupported);
  });

  test(
    'requestAccess asks for the full type list once; configure is lazy',
    () async {
      final reader = android();
      expect(health.configureCalls, 0);
      await reader.requestAccess();
      await reader.openInstall();
      expect(health.requested, unorderedEquals(_androidTypes));
      expect(health.installCalls, 1);
      expect(health.configureCalls, 1);
    },
  );

  test('iOS requests its own full type list', () async {
    await ios().requestAccess();
    expect(health.requested, unorderedEquals(_iosTypes));
  });

  test('Android requests skin temperature only when available', () async {
    health.skinAvailable = true;
    await android().requestAccess();
    expect(
      health.requested,
      unorderedEquals([..._androidTypes, HealthDataType.SKIN_TEMPERATURE]),
    );
  });

  test('requestAccess on Android with history available requests history after '
      'the type sheet', () async {
    health.historyAvailable = true;
    await android().requestAccess();
    expect(health.prompts, ['types', 'history']);
  });

  test('requestAccess on Android without history available does not', () async {
    await android().requestAccess();
    expect(health.prompts, ['types']);
  });

  test('history already authorized is not requested again', () async {
    health
      ..historyAvailable = true
      ..historyAuthorized = true;
    await android().requestMoreAccess();
    expect(health.prompts, ['types']);
    expect(health.requested, unorderedEquals(_androidTypes));
  });

  test('iOS never requests history', () async {
    health.historyAvailable = true;
    await ios().requestMoreAccess();
    expect(health.prompts, ['types']);
    expect(health.requested, unorderedEquals(_iosTypes));
  });

  test(
    'hasHistoryAccess is true on iOS and asks Health Connect on Android',
    () async {
      expect(await ios().hasHistoryAccess(), true);
      expect(await android().hasHistoryAccess(), false);
      health.historyAuthorized = true;
      expect(await android().hasHistoryAccess(), true);
    },
  );

  group('needsMoreAccess', () {
    test('is true for a Phase 3 grant', () async {
      health.requestStatus = HealthAuthorizationRequestStatus.shouldRequest;
      expect(await ios().needsMoreAccess(), true);
      expect(health.statusTypes, unorderedEquals(_iosTypes));

      health.deniedTypes = {HealthDataType.HEART_RATE};
      expect(await android().needsMoreAccess(), true);
      expect(health.permissionChecks.last, unorderedEquals(_androidTypes));
    });

    test('is false once everything was requested or granted', () async {
      health.requestStatus = HealthAuthorizationRequestStatus.unnecessary;
      expect(await ios().needsMoreAccess(), false);
      expect(await android().needsMoreAccess(), false);
    });

    test('a failing check never throws', () async {
      health.configureError = StateError('synthetic');
      expect(await ios().needsMoreAccess(), false);
    });
  });

  group('readSeries', () {
    final from = DateTime(2026, 11, 1);
    final to = DateTime(2026, 11, 24);

    test('hrv uses SDNN on iOS and RMSSD on Android', () async {
      await ios().readSeries(HealthSeriesType.hrv, from, to);
      expect(health.calls.last.types, [
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
      ]);
      await android().readSeries(HealthSeriesType.hrv, from, to);
      expect(health.calls.last.types, [
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      ]);
      expect(health.calls.last.start, from);
      expect(health.calls.last.end, to);
    });

    test('maps each series type to its platform type', () async {
      const shared = {
        HealthSeriesType.heartRate: HealthDataType.HEART_RATE,
        HealthSeriesType.restingHeartRate: HealthDataType.RESTING_HEART_RATE,
        HealthSeriesType.respiratoryRate: HealthDataType.RESPIRATORY_RATE,
        HealthSeriesType.bloodOxygen: HealthDataType.BLOOD_OXYGEN,
        HealthSeriesType.vo2Max: HealthDataType.VO2_MAX,
        HealthSeriesType.weight: HealthDataType.WEIGHT,
        HealthSeriesType.bodyFat: HealthDataType.BODY_FAT_PERCENTAGE,
        HealthSeriesType.leanMass: HealthDataType.LEAN_BODY_MASS,
      };
      for (final MapEntry(:key, :value) in shared.entries) {
        await android().readSeries(key, from, to);
        expect(health.calls.last.types, [value], reason: '$key');
      }
      await ios().readSeries(HealthSeriesType.walkingHeartRate, from, to);
      expect(health.calls.last.types, [HealthDataType.WALKING_HEART_RATE]);
      await ios().readSeries(
        HealthSeriesType.sleepingWristTemperature,
        from,
        to,
      );
      expect(health.calls.last.types, [HealthDataType.SLEEP_WRIST_TEMPERATURE]);
    });

    test('walking heart rate is unsupported on Android', () async {
      expect(
        await android().readSeries(HealthSeriesType.walkingHeartRate, from, to),
        isA<SeriesUnsupported<List<HealthSample>>>(),
      );
      expect(
        await android().readSeries(
          HealthSeriesType.sleepingWristTemperature,
          from,
          to,
        ),
        isA<SeriesUnsupported<List<HealthSample>>>(),
      );
      expect(health.calls, isEmpty);
    });

    test('skin temperature is Android-only and needs the feature', () async {
      expect(
        await ios().readSeries(HealthSeriesType.skinTemperature, from, to),
        isA<SeriesUnsupported<List<HealthSample>>>(),
      );
      expect(
        await android().readSeries(HealthSeriesType.skinTemperature, from, to),
        isA<SeriesUnsupported<List<HealthSample>>>(),
      );
      expect(health.calls, isEmpty);
      health.skinAvailable = true;
      await android().readSeries(HealthSeriesType.skinTemperature, from, to);
      expect(health.calls.single.types, [HealthDataType.SKIN_TEMPERATURE]);
    });

    test('returns samples with friendly sources', () async {
      health.points = [
        _point(
          HealthDataType.RESTING_HEART_RATE,
          54,
          DateTime(2026, 11, 2),
          DateTime(2026, 11, 2, 0, 1),
          source: 'com.google.android.apps.fitness',
        ),
      ];
      final r = await android().readSeries(
        HealthSeriesType.restingHeartRate,
        from,
        to,
      );
      final sample = (r as SeriesData<List<HealthSample>>).data.single;
      expect(sample.value, 54);
      expect(sample.from, DateTime(2026, 11, 2));
      expect(sample.to, DateTime(2026, 11, 2, 0, 1));
      expect(sample.source, 'Fit');
    });

    test('body fat is returned on a 0-100 scale on both platforms', () async {
      // HealthKit reads HKUnit.percent() as a fraction (0.22); Health
      // Connect's Percentage is already 0-100 (22).
      health.points = [
        _point(HealthDataType.BODY_FAT_PERCENTAGE, 0.22, from, from),
      ];
      final iosResult = await ios().readSeries(
        HealthSeriesType.bodyFat,
        from,
        to,
      );
      expect(
        (iosResult as SeriesData<List<HealthSample>>).data.single.value,
        closeTo(22, 1e-9),
      );
      health.points = [
        _point(HealthDataType.BODY_FAT_PERCENTAGE, 22, from, from),
      ];
      final androidResult = await android().readSeries(
        HealthSeriesType.bodyFat,
        from,
        to,
      );
      expect(
        (androidResult as SeriesData<List<HealthSample>>).data.single.value,
        22,
      );
    });

    test(
      'blood oxygen is returned on a 0-100 scale on both platforms',
      () async {
        health.points = [_point(HealthDataType.BLOOD_OXYGEN, 0.96, from, from)];
        final iosResult = await ios().readSeries(
          HealthSeriesType.bloodOxygen,
          from,
          to,
        );
        expect(
          (iosResult as SeriesData<List<HealthSample>>).data.single.value,
          closeTo(96, 1e-9),
        );
        health.points = [_point(HealthDataType.BLOOD_OXYGEN, 96, from, from)];
        final androidResult = await android().readSeries(
          HealthSeriesType.bloodOxygen,
          from,
          to,
        );
        expect(
          (androidResult as SeriesData<List<HealthSample>>).data.single.value,
          96,
        );
      },
    );

    test('Android denied series returns SeriesNotAllowed; iOS never-requested '
        'returns SeriesNeedsAccess', () async {
      health.deniedTypes = {HealthDataType.HEART_RATE_VARIABILITY_RMSSD};
      expect(
        await android().readSeries(HealthSeriesType.hrv, from, to),
        isA<SeriesNotAllowed<List<HealthSample>>>(),
      );
      expect(health.calls, isEmpty);
      expect(health.permissionChecks.last, [
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      ]);

      health.dataError = _platformError('PERMISSION_DENIED');
      expect(
        await ios().readSeries(HealthSeriesType.hrv, from, to),
        isA<SeriesNeedsAccess<List<HealthSample>>>(),
      );
      health.deniedTypes = {};
      expect(
        await android().readSeries(HealthSeriesType.hrv, from, to),
        isA<SeriesNotAllowed<List<HealthSample>>>(),
      );
    });

    test('notSupported is unsupported, other errors failed', () async {
      health.dataError = _platformError('NOT_SUPPORTED');
      expect(
        await ios().readSeries(HealthSeriesType.vo2Max, from, to),
        isA<SeriesUnsupported<List<HealthSample>>>(),
      );
      health.dataError = StateError('boom');
      expect(
        await ios().readSeries(HealthSeriesType.vo2Max, from, to),
        isA<SeriesFailed<List<HealthSample>>>(),
      );
    });
  });

  group('readSleep', () {
    final from = DateTime(2026, 11, 23, 18);
    final to = DateTime(2026, 11, 24, 9);

    test('maps stage types and Android sessions to inBed', () async {
      DateTime t(int h) => DateTime(2026, 11, 24, h);
      health.points = [
        _point(HealthDataType.SLEEP_ASLEEP, 0, t(0), t(1)),
        _point(HealthDataType.SLEEP_LIGHT, 0, t(1), t(2)),
        _point(HealthDataType.SLEEP_DEEP, 0, t(2), t(3)),
        _point(HealthDataType.SLEEP_REM, 0, t(3), t(4)),
        _point(
          HealthDataType.SLEEP_AWAKE,
          0,
          t(4),
          t(5),
          source: 'com.google.android.apps.fitness',
        ),
        _point(HealthDataType.SLEEP_SESSION, 0, t(0), t(5)),
        _point(HealthDataType.SLEEP_IN_BED, 0, t(0), t(5)),
      ];
      final r = await android().readSleep(from, to);
      final segments = (r as SeriesData<List<SleepSegment>>).data;
      expect(
        [for (final s in segments) s.stage],
        [
          SleepStage.asleepUnspecified,
          SleepStage.light,
          SleepStage.deep,
          SleepStage.rem,
          SleepStage.awake,
          SleepStage.inBed,
        ],
      );
      expect(segments[4].source, 'Fit');
      expect(segments[4].from, t(4));
      expect(segments[4].to, t(5));
      expect(health.calls.single.start, from);
      expect(health.calls.single.end, to);
      expect(
        health.calls.single.types,
        isNot(contains(HealthDataType.SLEEP_IN_BED)),
      );

      final iosResult = await ios().readSleep(from, to);
      final iosStages = [
        for (final s in (iosResult as SeriesData<List<SleepSegment>>).data)
          s.stage,
      ];
      expect(iosStages.last, SleepStage.inBed);
      expect(iosStages.where((s) => s == SleepStage.inBed).length, 1);
      expect(
        health.calls.last.types,
        isNot(contains(HealthDataType.SLEEP_SESSION)),
      );
    });

    test('Android session without stages is one unstaged night', () async {
      final bed = DateTime(2026, 11, 23, 23);
      final wake = DateTime(2026, 11, 24, 7);
      health.points = [
        _point(
          HealthDataType.SLEEP_SESSION,
          0,
          bed,
          wake,
          source: 'com.example.sleepapp',
        ),
      ];
      final r = await android().readSleep(from, to);
      final n = buildNights((r as SeriesData<List<SleepSegment>>).data).single;
      expect(n.asleep, const Duration(hours: 8));
      expect(n.hasStages, isFalse);
      expect(n.inBed, isNull);

      // iOS in-bed only (e.g. an iPhone bedtime schedule) is still no night.
      health.points = [_point(HealthDataType.SLEEP_IN_BED, 0, bed, wake)];
      final iosResult = await ios().readSleep(from, to);
      expect(
        buildNights((iosResult as SeriesData<List<SleepSegment>>).data),
        isEmpty,
      );
    });

    group('two wearables the same night stay separate sources', () {
      DateTime t(int h, [int m = 0]) => DateTime(2026, 11, 24, h, m);

      // Watch: 7h with 1h30 deep. Ring: 6h with 1h deep, overlapping it.
      List<HealthDataPoint> points({
        required String watch,
        required String ring,
        required String watchId,
        required String ringId,
      }) => [
        _point(
          HealthDataType.SLEEP_LIGHT,
          0,
          t(-1, 30),
          t(1, 30),
          source: watch,
          sourceId: watchId,
        ),
        _point(
          HealthDataType.SLEEP_DEEP,
          0,
          t(1, 30),
          t(3),
          source: watch,
          sourceId: watchId,
        ),
        _point(
          HealthDataType.SLEEP_REM,
          0,
          t(3),
          t(4, 30),
          source: watch,
          sourceId: watchId,
        ),
        _point(
          HealthDataType.SLEEP_LIGHT,
          0,
          t(4, 30),
          t(6, 30),
          source: watch,
          sourceId: watchId,
        ),
        _point(
          HealthDataType.SLEEP_LIGHT,
          0,
          t(0, 30),
          t(3),
          source: ring,
          sourceId: ringId,
        ),
        _point(
          HealthDataType.SLEEP_DEEP,
          0,
          t(3),
          t(4),
          source: ring,
          sourceId: ringId,
        ),
        _point(
          HealthDataType.SLEEP_REM,
          0,
          t(4),
          t(6, 30),
          source: ring,
          sourceId: ringId,
        ),
      ];

      void expectWatchOnly(List<SleepSegment> segments, String caption) {
        expect({for (final s in segments) s.sourceKey}, hasLength(2));
        final n = buildNights(segments).single;
        expect({for (final s in n.segments) s.sourceKey}, hasLength(1));
        expect(n.asleep, const Duration(hours: 7));
        expect(n.deep, const Duration(hours: 1, minutes: 30));
        expect(n.rem, const Duration(hours: 1, minutes: 30));
        expect(n.source, caption);
      }

      test('iOS groups by source id and names the source', () async {
        health.points = points(
          watch: 'Synthetic Watch',
          ring: 'Synthetic Ring',
          watchId: 'com.example.watch',
          ringId: 'com.example.ring',
        );
        final r = await ios().readSleep(from, to);
        expectWatchOnly(
          (r as SeriesData<List<SleepSegment>>).data,
          'Synthetic Watch',
        );
      });

      test('Android groups by package name (no source id)', () async {
        health.points = points(
          watch: 'com.example.watch',
          ring: 'com.example.ring',
          watchId: '',
          ringId: '',
        );
        final r = await android().readSleep(from, to);
        expectWatchOnly(
          (r as SeriesData<List<SleepSegment>>).data,
          'Health Connect',
        );
      });
    });

    test('Android denied sleep is not allowed; errors map', () async {
      health.permitted = false;
      expect(
        await android().readSleep(from, to),
        isA<SeriesNotAllowed<List<SleepSegment>>>(),
      );
      health.dataError = _platformError('PERMISSION_DENIED');
      expect(
        await ios().readSleep(from, to),
        isA<SeriesNeedsAccess<List<SleepSegment>>>(),
      );
      health.dataError = StateError('boom');
      expect(
        await ios().readSleep(from, to),
        isA<SeriesFailed<List<SleepSegment>>>(),
      );
    });
  });

  group('readHourlyTotals', () {
    final from = DateTime(2026, 11, 24);

    test('asks for 3600 s intervals over the given range', () async {
      health.points = [
        _point(
          HealthDataType.STEPS,
          420,
          DateTime(2026, 11, 24, 7),
          DateTime(2026, 11, 24, 8),
        ),
      ];
      final r = await android().readHourlyTotals(
        HealthTotalType.steps,
        from,
        now,
      );
      final sample = (r as SeriesData<List<HealthSample>>).data.single;
      expect(sample.value, 420);
      expect(sample.from, DateTime(2026, 11, 24, 7));
      final call = health.intervalCalls.single;
      expect(call.types, [HealthDataType.STEPS]);
      expect(call.interval, 3600);
      expect(call.start, from);
      expect(call.end, now);

      await ios().readHourlyTotals(HealthTotalType.activeEnergy, from, now);
      expect(health.intervalCalls.last.types, [
        HealthDataType.ACTIVE_ENERGY_BURNED,
      ]);
    });

    test('Android denied totals are not allowed; iOS denial maps', () async {
      health.deniedTypes = {HealthDataType.ACTIVE_ENERGY_BURNED};
      expect(
        await android().readHourlyTotals(
          HealthTotalType.activeEnergy,
          from,
          now,
        ),
        isA<SeriesNotAllowed<List<HealthSample>>>(),
      );
      expect(health.intervalCalls, isEmpty);
      health.dataError = _platformError('PERMISSION_DENIED');
      expect(
        await ios().readHourlyTotals(HealthTotalType.steps, from, now),
        isA<SeriesNeedsAccess<List<HealthSample>>>(),
      );
    });
  });

  test('friendlySource never leaks a raw identifier', () {
    expect(
      friendlySource(
        'com.google.android.apps.fitness',
        HealthPlatformKind.healthConnect,
      ),
      'Fit',
    );
    expect(
      friendlySource('com.vendor.app', HealthPlatformKind.healthConnect),
      'Health Connect',
    );
    expect(
      friendlySource('com.vendor.app', HealthPlatformKind.appleHealth),
      'Apple Health',
    );
  });

  group('readWorkouts', () {
    final from = DateTime(2026, 8, 28);

    test('WORKOUT is in the request list on both platforms', () async {
      await ios().requestAccess();
      expect(health.requested, contains(HealthDataType.WORKOUT));
      await android().requestAccess();
      expect(health.requested, contains(HealthDataType.WORKOUT));
    });

    test('maps a TRADITIONAL_STRENGTH_TRAINING workout to strength with '
        '131 kcal on iOS', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
          meters: 0,
        ),
      ];
      final r = await ios().readWorkouts(from, now);
      final w = (r as SeriesData<List<OutsideWorkout>>).data.single;
      expect(w.kind, OutsideWorkoutKind.strength);
      expect(w.activeKcal, 131);
      expect(w.id, 'w1');
      expect(w.source, 'Aditi Watch');
      expect(w.minutes, 30);
      expect(health.calls.last.types, [HealthDataType.WORKOUT]);
    });

    test('a workout from in.beyondrep.app.watchkitapp is dropped', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
          sourceId: 'in.beyondrep.app.watchkitapp',
          sourceName: 'Aditi Watch',
        ),
        _workout(
          HealthWorkoutActivityType.RUNNING,
          uuid: 'w2',
          sourceId: 'com.apple.health.watch',
          sourceName: 'in.beyondrep.app.watchkitapp',
        ),
        _workout(HealthWorkoutActivityType.RUNNING, uuid: 'w3'),
      ];
      final r = await ios().readWorkouts(from, now);
      expect((r as SeriesData<List<OutsideWorkout>>).data.map((w) => w.id), [
        'w3',
      ]);
    });

    test('a source merely containing beyondrep elsewhere is kept', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.RUNNING,
          sourceId: 'com.example.beyondrep',
          sourceName: 'Example BeyondRep',
        ),
      ];
      final r = await ios().readWorkouts(from, now);
      expect((r as SeriesData<List<OutsideWorkout>>).data, hasLength(1));
    });

    test('zero or negative kcal and distance are null, not 0', () async {
      for (final (kcal, meters) in [(0, 0), (-5, -1)]) {
        health.points = [
          _workout(
            HealthWorkoutActivityType.RUNNING,
            kcal: kcal,
            meters: meters,
          ),
        ];
        final w = ((await ios().readWorkouts(
          from,
          now,
        )) as SeriesData<List<OutsideWorkout>>).data.single;
        expect(w.activeKcal, isNull);
        expect(w.distanceMeters, isNull);
      }
    });

    test('keeps distance and null when absent', () async {
      health.points = [
        _workout(HealthWorkoutActivityType.RUNNING, kcal: null, meters: 5000),
      ];
      final w = ((await ios().readWorkouts(
        from,
        now,
      )) as SeriesData<List<OutsideWorkout>>).data.single;
      expect(w.kind, OutsideWorkoutKind.running);
      expect(w.distanceMeters, 5000);
      expect(w.activeKcal, isNull);
    });

    test('maps activity types to friendly kinds', () async {
      final cases = {
        HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING:
            OutsideWorkoutKind.strength,
        HealthWorkoutActivityType.WEIGHTLIFTING: OutsideWorkoutKind.strength,
        HealthWorkoutActivityType.RUNNING_TREADMILL: OutsideWorkoutKind.running,
        HealthWorkoutActivityType.BIKING_STATIONARY: OutsideWorkoutKind.cycling,
        HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING:
            OutsideWorkoutKind.hiit,
        HealthWorkoutActivityType.SOCIAL_DANCE: OutsideWorkoutKind.dance,
        HealthWorkoutActivityType.SWIMMING_POOL: OutsideWorkoutKind.swimming,
        HealthWorkoutActivityType.YOGA: OutsideWorkoutKind.yoga,
        HealthWorkoutActivityType.OTHER: OutsideWorkoutKind.other,
      };
      for (final e in cases.entries) {
        health.points = [_workout(e.key)];
        final w = ((await ios().readWorkouts(
          from,
          now,
        )) as SeriesData<List<OutsideWorkout>>).data.single;
        expect(w.kind, e.value, reason: e.key.name);
      }
    });

    test('Android kcal is null even when the plugin returns a total', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.RUNNING,
          kcal: 300,
          sourceName: 'com.example.app',
        ),
      ];
      final w = ((await android().readWorkouts(
        from,
        now,
      )) as SeriesData<List<OutsideWorkout>>).data.single;
      expect(w.activeKcal, isNull);
      expect(w.source, 'Health Connect');
    });

    test('an empty uuid falls back to source and start', () async {
      health.points = [
        _workout(HealthWorkoutActivityType.RUNNING, uuid: '', sourceId: 'src'),
      ];
      final w = ((await ios().readWorkouts(
        from,
        now,
      )) as SeriesData<List<OutsideWorkout>>).data.single;
      expect(
        w.id,
        'src-${DateTime.utc(2026, 11, 20, 9).millisecondsSinceEpoch}',
      );
    });

    test('drops workouts from in.beyondrep.app', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.RUNNING,
          uuid: 'own',
          sourceId: 'in.beyondrep.app',
        ),
        _workout(
          HealthWorkoutActivityType.RUNNING,
          uuid: 'own2',
          sourceName: 'in.beyondrep.app',
        ),
        _workout(HealthWorkoutActivityType.RUNNING, uuid: 'other'),
      ];
      final r = await ios().readWorkouts(from, now);
      expect((r as SeriesData<List<OutsideWorkout>>).data.map((w) => w.id), [
        'other',
      ]);
    });

    test('own written workout is not an outside workout', () async {
      // A strength workout as the phone export writes it (Phase 5).
      health.points = [
        _workout(
          HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
          uuid: 'written',
          kcal: null,
          sourceId: 'in.beyondrep.app',
          sourceName: 'BeyondRep',
        ),
      ];
      final r = await ios().readWorkouts(from, now);
      expect((r as SeriesData<List<OutsideWorkout>>).data, isEmpty);
    });

    test('a lookalike source such as in.beyondrep.apple is kept', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.RUNNING,
          uuid: 'look',
          sourceId: 'in.beyondrep.apple',
          sourceName: 'in.beyondrep.apple',
        ),
        _workout(
          HealthWorkoutActivityType.RUNNING,
          uuid: 'child',
          sourceId: 'in.beyondrep.app.child',
        ),
      ];
      final r = await ios().readWorkouts(from, now);
      expect((r as SeriesData<List<OutsideWorkout>>).data.map((w) => w.id), [
        'look',
      ]);
    });

    test('permission denied on Android is SeriesNotAllowed', () async {
      health.deniedTypes = {HealthDataType.WORKOUT};
      expect(
        await android().readWorkouts(from, now),
        isA<SeriesNotAllowed<List<OutsideWorkout>>>(),
      );
    });

    test('the Android manifest asks for exercise, heart rate write and '
        'calories (watch workouts, Wear OS 3b), never distance', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      for (final p in [
        'READ_EXERCISE',
        'WRITE_EXERCISE',
        'READ_HEART_RATE',
        'WRITE_HEART_RATE',
        'READ_TOTAL_CALORIES_BURNED',
        'WRITE_TOTAL_CALORIES_BURNED',
      ]) {
        expect(manifest, contains('android.permission.health.$p"'));
      }
      expect(manifest, isNot(contains('DISTANCE')));
    });

    test('a platform failure never throws', () async {
      health.dataError = StateError('private detail');
      expect(
        await ios().readWorkouts(from, now),
        isA<SeriesFailed<List<OutsideWorkout>>>(),
      );
    });
  });
  group('readOwnWorkout', () {
    final start = DateTime.utc(2026, 11, 20, 9);
    final end = DateTime.utc(2026, 11, 20, 9, 40);
    final workoutStart = start.add(const Duration(minutes: 2));
    final workoutEnd = end.subtract(const Duration(minutes: 3));

    HealthDataPoint hr(num value, int minute, {String uuid = 'h'}) =>
        HealthDataPoint(
          uuid: uuid,
          value: NumericHealthValue(numericValue: value),
          type: HealthDataType.HEART_RATE,
          unit: HealthDataUnit.BEATS_PER_MINUTE,
          dateFrom: start.add(Duration(minutes: minute)),
          dateTo: start.add(Duration(minutes: minute)),
          sourcePlatform: HealthPlatformType.appleHealth,
          sourceDeviceId: 'd',
          sourceId: 'com.apple.health.watch',
          sourceName: 'Synthetic Watch',
        );

    test('matches the uuid ignoring case and reads kcal, average and max '
        'heart rate', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
          uuid: 'AB12-CD',
          kcal: 212,
          from: workoutStart,
          to: workoutEnd,
          sourceId: 'in.beyondrep.app.watchkitapp',
        ),
        hr(100, 5),
        hr(130, 10),
        hr(160, 20),
      ];
      final r = await ios().readOwnWorkout('ab12-cd', start, end);
      final data = (r as SeriesData<OwnWorkoutHealth?>).data!;
      expect(data.activeKcal, 212);
      expect(data.averageBpm, 130);
      expect(data.maxBpm, 160);
      final workoutCall = health.calls.firstWhere(
        (c) => c.types.contains(HealthDataType.WORKOUT),
      );
      expect(workoutCall.start, start.subtract(const Duration(minutes: 5)));
      expect(workoutCall.end, end.add(const Duration(minutes: 5)));
      final hrCall = health.calls.firstWhere(
        (c) => c.types.contains(HealthDataType.HEART_RATE),
      );
      // The requested bounds differ from the workout's own, so this proves
      // heart rate is read over the matched workout's bounds.
      expect(hrCall.start, workoutStart);
      // End-inclusive: a sample stamped at the workout end still counts.
      expect(hrCall.end, workoutEnd.add(const Duration(seconds: 1)));
    });

    test('ignores workouts with another uuid', () async {
      health.points = [
        _workout(HealthWorkoutActivityType.RUNNING, uuid: 'other', kcal: 300),
        hr(120, 5),
      ];
      final r = await ios().readOwnWorkout('mine', start, end);
      expect((r as SeriesData<OwnWorkoutHealth?>).data, isNull);
    });

    test('missing heart rate and energy leave null values, never 0', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.RUNNING,
          uuid: 'mine',
          kcal: 0,
          from: start,
          to: end,
        ),
      ];
      final r = await ios().readOwnWorkout('mine', start, end);
      final data = (r as SeriesData<OwnWorkoutHealth?>).data!;
      expect(data.isEmpty, isTrue);
    });

    HealthDataPoint ownHr(
      num value,
      int minute, {
      String source = 'in.beyondrep.app',
    }) => HealthDataPoint(
      uuid: 'h$minute',
      value: NumericHealthValue(numericValue: value),
      type: HealthDataType.HEART_RATE,
      unit: HealthDataUnit.BEATS_PER_MINUTE,
      dateFrom: start.add(Duration(minutes: minute)),
      dateTo: start.add(Duration(minutes: minute)),
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      sourceDeviceId: 'd',
      sourceId: source,
      sourceName: source,
    );

    test('readOwnWorkoutOnAndroidReturnsAverageMaxAndCalories', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.STRENGTH_TRAINING,
          uuid: 'ab12-cd',
          kcal: 212,
          from: workoutStart,
          to: workoutEnd,
          sourceId: 'in.beyondrep.app',
        ),
        ownHr(100, 5),
        ownHr(130, 10),
        ownHr(160, 20),
      ];
      final r = await android().readOwnWorkout('AB12-CD', start, end);
      final data = (r as SeriesData<OwnWorkoutHealth?>).data!;
      expect(data.activeKcal, 212);
      expect(data.averageBpm, 130);
      expect(data.maxBpm, 160);
    });

    test('readOwnWorkoutIgnoresHeartRateFromOtherApps', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.STRENGTH_TRAINING,
          uuid: 'mine',
          kcal: null,
          from: workoutStart,
          to: workoutEnd,
          sourceId: 'in.beyondrep.app',
        ),
        ownHr(100, 5),
        ownHr(200, 10, source: 'com.other.app'),
        ownHr(60, 15, source: 'in.beyondrep.apple'),
      ];
      final r = await android().readOwnWorkout('mine', start, end);
      final data = (r as SeriesData<OwnWorkoutHealth?>).data!;
      expect(data.averageBpm, 100);
      expect(data.maxBpm, 100);
      expect(data.activeKcal, isNull);
    });

    test('on Android a workout another app saved is not read', () async {
      health.points = [
        _workout(
          HealthWorkoutActivityType.STRENGTH_TRAINING,
          uuid: 'mine',
          sourceId: 'com.other.app',
        ),
      ];
      final r = await android().readOwnWorkout('mine', start, end);
      expect((r as SeriesData<OwnWorkoutHealth?>).data, isNull);
    });

    test('a platform failure never throws', () async {
      health.dataError = StateError('private detail');
      expect(
        await ios().readOwnWorkout('mine', start, end),
        isA<SeriesFailed<OwnWorkoutHealth?>>(),
      );
    });
  });
}
