import 'package:beyondrep/core/ids/uuid_factory.dart';
import 'package:beyondrep/features/health/data/health_weight_writer.dart';
import 'package:beyondrep/features/health/data/health_workout_writer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

class _FakeHealth extends Fake implements Health {
  final writeCalls = <Map<String, Object?>>[];
  final deleteUuidCalls = <({String uuid, HealthDataType? type})>[];
  final deleteClientCalls = <({HealthDataType type, String clientRecordId})>[];
  Object? writeError;
  Object? deleteError;
  String? writeResult = 'new-uuid';
  bool deleteResult = true;
  bool? permitted = true;
  HealthConnectSdkStatus? sdk = HealthConnectSdkStatus.sdkAvailable;
  List<HealthDataType>? requestedTypes;
  List<HealthDataAccess>? requestedAccess;
  List<HealthDataType>? checkedTypes;
  List<HealthDataAccess>? checkedAccess;
  int configureCalls = 0;

  @override
  Future<void> configure() async {
    configureCalls++;
  }

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
    checkedTypes = types;
    checkedAccess = permissions;
    return permitted;
  }

  @override
  Future<String?> writeHealthDataUUID({
    required double value,
    HealthDataUnit? unit,
    required HealthDataType type,
    required DateTime startTime,
    String? clientRecordId,
    double? clientRecordVersion,
    DateTime? endTime,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    if (writeError != null) throw writeError!;
    writeCalls.add({
      'value': value,
      'unit': unit,
      'type': type,
      'startTime': startTime,
      'endTime': endTime,
      'clientRecordId': clientRecordId,
      'recordingMethod': recordingMethod,
    });
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
}

class _FixedIds implements UuidFactory {
  @override
  String newId() => 'fixed-id';
}

void main() {
  final at = DateTime.utc(2026, 11, 28, 7, 30);
  final v4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  PlatformHealthWeightWriter writer(_FakeHealth h, {bool ios = true}) =>
      PlatformHealthWeightWriter(h, isIos: ios);

  test('write sends kg, WEIGHT, manual, start == end == at, a v4 id', () async {
    final h = _FakeHealth();
    final result = await writer(h).write(72.4, at);
    expect(result, isA<HealthWeightWriteOk>());
    final ok = result as HealthWeightWriteOk;
    expect(ok.platformRecordId, 'new-uuid');
    expect(ok.clientRecordId, matches(v4));
    final args = h.writeCalls.single;
    expect(args['value'], 72.4);
    expect(args['unit'], HealthDataUnit.KILOGRAM);
    expect(args['type'], HealthDataType.WEIGHT);
    expect(args['recordingMethod'], RecordingMethod.manual);
    expect(args['startTime'], at);
    expect(args['endTime'], at);
    expect(args['clientRecordId'], ok.clientRecordId);
  });

  test('the injected UuidFactory supplies the clientRecordId', () async {
    final h = _FakeHealth();
    final result = await PlatformHealthWeightWriter(
      h,
      isIos: true,
      ids: _FixedIds(),
    ).write(70, at);
    expect((result as HealthWeightWriteOk).clientRecordId, 'fixed-id');
  });

  test('configure runs once across calls', () async {
    final h = _FakeHealth();
    final w = writer(h);
    await w.write(70, at);
    await w.write(71, at);
    expect(h.configureCalls, 1);
  });

  test('empty or "null" id is a failure', () async {
    for (final id in ['', 'null', null]) {
      final h = _FakeHealth()..writeResult = id;
      expect(await writer(h).write(70, at), isA<HealthWriteFailed>());
    }
  });

  test(
    'Android without Health Connect is unavailable and writes nothing',
    () async {
      final h = _FakeHealth()..sdk = HealthConnectSdkStatus.sdkUnavailable;
      expect(
        await writer(h, ios: false).write(70, at),
        isA<HealthWriteUnavailable>(),
      );
      expect(h.writeCalls, isEmpty);
    },
  );

  test(
    'permission is denied, UnsupportedError unavailable, else failed',
    () async {
      final denied = _FakeHealth()
        ..writeError = HealthException(
          HealthDataType.WEIGHT,
          'x',
          errorCode: HealthErrorCode.permissionDenied,
        );
      expect(await writer(denied).write(70, at), isA<HealthWriteDenied>());
      final unsupported = _FakeHealth()..writeError = UnsupportedError('x');
      expect(
        await writer(unsupported).write(70, at),
        isA<HealthWriteUnavailable>(),
      );
      final other = _FakeHealth()..writeError = PlatformException(code: 'x');
      expect(await writer(other).write(70, at), isA<HealthWriteFailed>());
    },
  );

  test('requestAccess asks WEIGHT with READ_WRITE', () async {
    final h = _FakeHealth();
    expect(await writer(h).requestAccess(), isTrue);
    expect(h.requestedTypes, [HealthDataType.WEIGHT]);
    expect(h.requestedAccess, [HealthDataAccess.READ_WRITE]);
  });

  test('hasWriteAccess checks WRITE on iOS, READ_WRITE on Android', () async {
    final ios = _FakeHealth();
    expect(await writer(ios).hasWriteAccess(), isTrue);
    expect(ios.checkedTypes, [HealthDataType.WEIGHT]);
    expect(ios.checkedAccess, [HealthDataAccess.WRITE]);
    final android = _FakeHealth()..permitted = null;
    expect(await writer(android, ios: false).hasWriteAccess(), isFalse);
    expect(android.checkedAccess, [HealthDataAccess.READ_WRITE]);
  });

  const saved = SavedWeight(platformRecordId: 'p-1', clientRecordId: 'c-1');

  test('delete on iOS uses deleteByUUID with type WEIGHT', () async {
    final h = _FakeHealth();
    expect(await writer(h).delete(saved), isTrue);
    expect(h.deleteUuidCalls.single.uuid, 'p-1');
    expect(h.deleteUuidCalls.single.type, HealthDataType.WEIGHT);
    expect(h.deleteClientCalls, isEmpty);
  });

  test('delete on Android uses deleteByClientRecordId', () async {
    final h = _FakeHealth();
    expect(await writer(h, ios: false).delete(saved), isTrue);
    expect(h.deleteClientCalls.single.type, HealthDataType.WEIGHT);
    expect(h.deleteClientCalls.single.clientRecordId, 'c-1');
    expect(h.deleteUuidCalls, isEmpty);
  });

  test('delete returns the plugin bool and false on a thrown error', () async {
    final no = _FakeHealth()..deleteResult = false;
    expect(await writer(no).delete(saved), isFalse);
    final boom = _FakeHealth()..deleteError = StateError('x');
    expect(await writer(boom).delete(saved), isFalse);
  });
}
