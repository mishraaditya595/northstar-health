import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

class _WriteCall {
  _WriteCall(this.args);
  final Map<String, Object?> args;
}

class _FakeHealth extends Fake implements Health {
  final writeCalls = <_WriteCall>[];
  final deleteUuidCalls = <({String uuid, HealthDataType? type})>[];
  final deleteClientCalls = <({HealthDataType type, String clientRecordId})>[];
  final permissionChecks = <List<HealthAccessLabel>>[];
  List<HealthDataPoint> points = [];
  Object? writeError;
  Object? deleteError;
  String? writeResult = 'new-uuid';
  bool deleteResult = true;
  bool? permitted = true;
  HealthConnectSdkStatus? sdk = HealthConnectSdkStatus.sdkAvailable;
  List<HealthDataType>? requestedTypes;
  List<HealthDataAccess>? requestedAccess;
  final reads = <({DateTime start, DateTime end})>[];
  Object? readError;

  @override
  Future<void> configure() async {}

  @override
  Future<HealthConnectSdkStatus?> getHealthConnectSdkStatus() async => sdk;

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requestedTypes = types;
    requestedAccess = permissions;
    return true;
  }

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requestedTypes = types;
    requestedAccess = permissions;
    return permitted;
  }

  @override
  Future<String?> writeWorkoutDataUUID({
    required HealthWorkoutActivityType activityType,
    required DateTime start,
    required DateTime end,
    int? totalEnergyBurned,
    HealthDataUnit totalEnergyBurnedUnit = HealthDataUnit.KILOCALORIE,
    int? totalDistance,
    HealthDataUnit totalDistanceUnit = HealthDataUnit.METER,
    String? title,
    WorkoutMetadata? metadata,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
    String? clientRecordId,
    double? clientRecordVersion,
    Duration? startZoneOffset,
    Duration? endZoneOffset,
    SwimmingDetails? swimming,
    int? totalSwimmingStrokeCount,
  }) async {
    if (writeError != null) throw writeError!;
    writeCalls.add(
      _WriteCall({
        'activityType': activityType,
        'start': start,
        'end': end,
        'totalEnergyBurned': totalEnergyBurned,
        'totalDistance': totalDistance,
        'title': title,
        'metadata': metadata,
        'clientRecordId': clientRecordId,
        'clientRecordVersion': clientRecordVersion,
        'startZoneOffset': startZoneOffset,
        'endZoneOffset': endZoneOffset,
      }),
    );
    return writeResult;
  }

  @override
  Future<bool> deleteByUUID({
    required String uuid,
    HealthDataType? type,
  }) async {
    if (deleteError != null) throw deleteError!;
    deleteUuidCalls.add((uuid: uuid, type: type));
    return deleteResult;
  }

  @override
  Future<bool> deleteByClientRecordId({
    required HealthDataType dataTypeKey,
    required String clientRecordId,
    String? recordId,
  }) async {
    if (deleteError != null) throw deleteError!;
    deleteClientCalls.add((type: dataTypeKey, clientRecordId: clientRecordId));
    return deleteResult;
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
    reads.add((start: startTime, end: endTime));
    if (readError != null) throw readError!;
    return points;
  }
}

typedef HealthAccessLabel = String;

HealthDataPoint _workoutPoint(
  String uuid,
  String source,
  DateTime a,
  DateTime b,
) => HealthDataPoint(
  uuid: uuid,
  value: WorkoutHealthValue(
    workoutActivityType:
        HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
  ),
  type: HealthDataType.WORKOUT,
  unit: HealthDataUnit.NO_UNIT,
  dateFrom: a,
  dateTo: b,
  sourcePlatform: HealthPlatformType.appleHealth,
  sourceDeviceId: 'd',
  sourceId: source,
  sourceName: 'n',
);

final _start = DateTime.utc(2026, 11, 20, 9);
final _end = DateTime.utc(2026, 11, 20, 10);

HealthWorkoutRecord _record({int offset = 330}) => HealthWorkoutRecord(
  workoutUuid: 'abcdef00-0000-4000-8000-000000000001',
  name: 'Push day',
  start: _start,
  end: _end,
  offsetMinutes: offset,
  version: 1700000000000,
);

void main() {
  late _FakeHealth health;
  setUp(() => health = _FakeHealth());

  PlatformHealthWorkoutWriter ios() =>
      PlatformHealthWorkoutWriter(health, isIos: true);
  PlatformHealthWorkoutWriter android() =>
      PlatformHealthWorkoutWriter(health, isIos: false);

  test('write sends strength training, brand BeyondRep, syncIdentifier and syncVersion on iOS', () async {
    final result = await ios().write(_record());
    expect(result, isA<HealthWriteOk>());
    expect((result as HealthWriteOk).platformRecordId, 'new-uuid');
    final a = health.writeCalls.single.args;
    expect(
      a['activityType'],
      HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
    );
    expect(a['start'], _start);
    expect(a['end'], _end);
    expect(
      a['metadata'],
      const WorkoutMetadata(
        workoutBrandName: 'BeyondRep',
        indoorWorkout: true,
        syncIdentifier: 'abcdef00-0000-4000-8000-000000000001',
        syncVersion: 1700000000000,
      ),
    );
    expect(a['clientRecordId'], isNull);
  });

  test('write sends clientRecordId, clientRecordVersion, title and zone offsets on Android', () async {
    final result = await android().write(_record());
    expect(result, isA<HealthWriteOk>());
    final a = health.writeCalls.single.args;
    expect(a['activityType'], HealthWorkoutActivityType.STRENGTH_TRAINING);
    expect(a['clientRecordId'], 'abcdef00-0000-4000-8000-000000000001');
    expect(a['clientRecordVersion'], 1700000000000.0);
    expect(a['title'], 'Push day');
    expect(a['startZoneOffset'], const Duration(minutes: 330));
    expect(a['endZoneOffset'], const Duration(minutes: 330));
    expect(a['metadata'], isNull);
  });

  test('no energy or distance argument is sent', () async {
    await ios().write(_record());
    await android().write(_record());
    for (final c in health.writeCalls) {
      expect(c.args['totalEnergyBurned'], isNull);
      expect(c.args['totalDistance'], isNull);
    }
  });

  test(
    'an empty result is a failure on iOS and the client id on Android',
    () async {
      health.writeResult = '';
      expect(await ios().write(_record()), isA<HealthWriteFailed>());
      final ok = await android().write(_record());
      expect(
        (ok as HealthWriteOk).platformRecordId,
        'abcdef00-0000-4000-8000-000000000001',
      );
    },
  );

  test('permission error maps to HealthWriteDenied', () async {
    health.writeError = HealthException(
      HealthDataType.WORKOUT,
      'private detail',
      errorCode: HealthErrorCode.permissionDenied,
    );
    expect(await ios().write(_record()), isA<HealthWriteDenied>());
  });

  test('other errors map to HealthWriteFailed and Health Connect missing to Unavailable', () async {
    health.writeError = StateError('private detail');
    expect(await ios().write(_record()), isA<HealthWriteFailed>());
    health.writeError = UnsupportedError('Health Connect is not installed');
    expect(await android().write(_record()), isA<HealthWriteUnavailable>());
  });

  test('delete uses deleteByUUID with WORKOUT on iOS and deleteByClientRecordId on Android', () async {
    expect(await ios().delete('wk', 'hk-1'), isA<HealthWriteOk>());
    expect(health.deleteUuidCalls.single, (
      uuid: 'hk-1',
      type: HealthDataType.WORKOUT,
    ));
    expect(await android().delete('wk', 'wk'), isA<HealthWriteOk>());
    expect(health.deleteClientCalls.single, (
      type: HealthDataType.WORKOUT,
      clientRecordId: 'wk',
    ));
  });

  test('a record that is already gone counts as deleted; errors map', () async {
    health.deleteResult = false;
    expect(await ios().delete('wk', 'hk-1'), isA<HealthWriteOk>());
    health.deleteError = HealthException(
      HealthDataType.WORKOUT,
      'x',
      errorCode: HealthErrorCode.permissionDenied,
    );
    expect(await ios().delete('wk', 'hk-1'), isA<HealthWriteDenied>());
  });

  test('iOS delete without a platform id has nothing to delete', () async {
    expect(await ios().delete('wk', null), isA<HealthWriteOk>());
    expect(health.deleteUuidCalls, isEmpty);
  });

  test('requestAccess asks for READ_WRITE on WORKOUT', () async {
    await ios().requestAccess();
    expect(health.requestedTypes, [HealthDataType.WORKOUT]);
    expect(health.requestedAccess, [HealthDataAccess.READ_WRITE]);
  });

  test(
    'hasWriteAccess checks WRITE on iOS and READ_WRITE on Android',
    () async {
      expect(await ios().hasWriteAccess(), isTrue);
      expect(health.requestedAccess, [HealthDataAccess.WRITE]);
      health.permitted = null;
      expect(await android().hasWriteAccess(), isFalse);
      expect(health.requestedAccess, [HealthDataAccess.READ_WRITE]);
    },
  );

  test('isAvailable follows the Health Connect status on Android', () async {
    expect(await ios().isAvailable(), isTrue);
    expect(await android().isAvailable(), isTrue);
    health.sdk = HealthConnectSdkStatus.sdkUnavailable;
    expect(await android().isAvailable(), isFalse);
  });

  test('beyondRepWorkoutsIn keeps in.beyondrep.app and in.beyondrep.app.watchkitapp, drops in.beyondrep.apple and other apps', () async {
    health.points = [
      _workoutPoint('a', 'in.beyondrep.app', _start, _end),
      _workoutPoint('b', 'in.beyondrep.app.watchkitapp', _start, _end),
      _workoutPoint('c', 'in.beyondrep.apple', _start, _end),
      _workoutPoint('d', 'com.example.other', _start, _end),
    ];
    final found = (await ios().beyondRepWorkoutsIn(_start, _end))!;
    expect(found.map((w) => w.platformRecordId), ['a', 'b']);
    expect(found.first.sourceId, 'in.beyondrep.app');
    expect(found.first.start, _start);
  });

  test('beyondRepWorkoutsIn returns null when the read fails', () async {
    health.readError = StateError('private detail');
    expect(await ios().beyondRepWorkoutsIn(_start, _end), isNull);
  });

  test('PlatformException from the channel maps like a failure', () async {
    health.writeError = PlatformException(code: 'x', message: 'private');
    expect(await ios().write(_record()), isA<HealthWriteFailed>());
  });
}
