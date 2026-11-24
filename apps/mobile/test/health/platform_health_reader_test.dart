import 'package:beyondrep/features/health/data/health_reader.dart';
import 'package:beyondrep/features/health/data/platform_health_reader.dart';
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

class _FakeHealth extends Fake implements Health {
  int configureCalls = 0;
  int? steps;
  Object? stepsError;
  Object? dataError;
  bool? permitted = true;
  HealthConnectSdkStatus? sdkStatus = HealthConnectSdkStatus.sdkAvailable;
  List<HealthDataPoint> points = [];
  final calls = <_Call>[];
  DateTime? stepsStart;
  DateTime? stepsEnd;
  int installCalls = 0;
  List<HealthDataType>? requested;

  @override
  Future<void> configure() async => configureCalls++;

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => permitted;

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requested = types;
    return true;
  }

  @override
  Future<HealthConnectSdkStatus?> getHealthConnectSdkStatus() async =>
      sdkStatus;

  @override
  Future<void> installHealthConnect() async => installCalls++;

  @override
  Future<int> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime, {
    bool includeManualEntry = true,
  }) async {
    stepsStart = startTime;
    stepsEnd = endTime;
    if (stepsError != null) throw stepsError!;
    return steps ?? 0;
  }

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
    return points;
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
}) => HealthDataPoint(
  uuid: 'u',
  value: NumericHealthValue(numericValue: value),
  type: type,
  unit: HealthDataUnit.NO_UNIT,
  dateFrom: from,
  dateTo: to,
  sourcePlatform: HealthPlatformType.googleHealthConnect,
  sourceDeviceId: 'd',
  sourceId: source,
  sourceName: source,
);

void main() {
  final now = DateTime(2026, 11, 24, 9, 30);
  late _FakeHealth health;

  PlatformHealthReader android() =>
      PlatformHealthReader(health, platform: HealthPlatformKind.healthConnect);
  PlatformHealthReader ios() =>
      PlatformHealthReader(health, platform: HealthPlatformKind.appleHealth);

  setUp(() => health = _FakeHealth());

  test('steps are measured with the Apple Health source name', () async {
    health.steps = 6420;
    final r = await ios().read(HealthMetric.steps, now);
    expect(r, isA<HealthMeasured>());
    final m = r as HealthMeasured;
    expect(m.value, 6420);
    expect(m.measuredAt, now);
    expect(m.source, 'Apple Health');
    expect(health.stepsStart, DateTime(2026, 11, 24));
    expect(health.stepsEnd, now);
  });

  test('zero steps is no data on both platforms', () async {
    health.steps = 0;
    expect(await ios().read(HealthMetric.steps, now), isA<HealthNoData>());
    expect(await android().read(HealthMetric.steps, now), isA<HealthNoData>());
  });

  test('permissionDenied is not allowed on Android, no data on iOS', () async {
    health.stepsError = _platformError('PERMISSION_DENIED');
    expect(
      await android().read(HealthMetric.steps, now),
      isA<HealthNotAllowed>(),
    );
    expect(await ios().read(HealthMetric.steps, now), isA<HealthNoData>());
  });

  test('Android without read permission skips the data call', () async {
    health.permitted = false;
    final r = await android().read(HealthMetric.weight, now);
    expect(r, isA<HealthNotAllowed>());
    expect(health.calls, isEmpty);
  });

  test('notSupported maps to unsupported, other errors to failed', () async {
    health.stepsError = _platformError('NOT_SUPPORTED');
    expect(
      await android().read(HealthMetric.steps, now),
      isA<HealthUnsupported>(),
    );
    health.stepsError = StateError('boom');
    expect(
      await android().read(HealthMetric.steps, now),
      isA<HealthReadFailed>(),
    );
  });

  test('sleep window, types and merged minutes', () async {
    health.points = [
      _point(
        HealthDataType.SLEEP_LIGHT,
        0,
        DateTime(2026, 11, 23, 23),
        DateTime(2026, 11, 24, 3),
        source: 'com.google.android.apps.fitness',
      ),
      _point(
        HealthDataType.SLEEP_DEEP,
        0,
        DateTime(2026, 11, 24, 2),
        DateTime(2026, 11, 24, 6, 30),
        source: 'com.example.unknown',
      ),
    ];
    final r = await android().read(HealthMetric.sleep, now) as HealthMeasured;
    expect(r.value, 450);
    expect(r.measuredAt, DateTime(2026, 11, 24, 6, 30));
    expect(r.source, 'Fit, Health Connect');
    final call = health.calls.single;
    expect(call.start, DateTime(2026, 11, 23, 18));
    expect(call.end, now);
    expect(call.types, [
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_REM,
    ]);
  });

  test('sleep without points is no data', () async {
    expect(await android().read(HealthMetric.sleep, now), isA<HealthNoData>());
  });

  test('resting heart rate window, limit and newest value', () async {
    health.points = [
      _point(
        HealthDataType.RESTING_HEART_RATE,
        58,
        DateTime(2026, 11, 22),
        DateTime(2026, 11, 22, 0, 1),
      ),
      _point(
        HealthDataType.RESTING_HEART_RATE,
        55,
        DateTime(2026, 11, 23),
        DateTime(2026, 11, 23, 0, 1),
      ),
    ];
    final r = await android().read(
      HealthMetric.restingHeartRate,
      now,
    ) as HealthMeasured;
    expect(r.value, 55);
    expect(r.measuredAt, DateTime(2026, 11, 23, 0, 1));
    final call = health.calls.single;
    expect(call.start, now.subtract(const Duration(days: 7)));
    expect(call.end, now);
    expect(call.limit, 1);
    expect(call.types, [HealthDataType.RESTING_HEART_RATE]);
  });

  test('weight window and limit', () async {
    health.points = [
      _point(
        HealthDataType.WEIGHT,
        72.4,
        DateTime(2026, 11, 20),
        DateTime(2026, 11, 20),
      ),
    ];
    final r = await ios().read(HealthMetric.weight, now) as HealthMeasured;
    expect(r.value, 72.4);
    expect(r.source, 'Apple Health');
    final call = health.calls.single;
    expect(call.start, now.subtract(const Duration(days: 30)));
    expect(call.limit, 1);
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
    'requestAccess asks for all four types once; configure is lazy',
    () async {
      final reader = android();
      expect(health.configureCalls, 0);
      await reader.requestAccess();
      await reader.openInstall();
      expect(health.requested, [
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.STEPS,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.WEIGHT,
      ]);
      expect(health.installCalls, 1);
      expect(health.configureCalls, 1);
    },
  );

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
}
