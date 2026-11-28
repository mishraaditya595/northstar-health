import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart' hide HealthValue;

import '../../../core/ids/uuid_factory.dart';
import 'health_workout_writer.dart';

/// Identifies one weight sample BeyondRep wrote, so it can be deleted again.
class SavedWeight {
  const SavedWeight({
    required this.platformRecordId,
    required this.clientRecordId,
  });

  /// HealthKit sample UUID (iOS) or Health Connect record id (Android).
  final String platformRecordId;

  /// Idempotency id BeyondRep chose; Android deletes by it.
  final String clientRecordId;
}

class HealthWeightWriteOk extends HealthWriteOk {
  const HealthWeightWriteOk(super.platformRecordId, this.clientRecordId);
  final String clientRecordId;
}

abstract interface class HealthWeightWriter {
  bool get isIos;

  /// False on Android when Health Connect is missing or needs an update.
  Future<bool> isAvailable();

  Future<bool> hasWriteAccess();

  /// Shows the platform permission prompt for weight write.
  Future<bool> requestAccess();

  /// Writes one manual weight sample at [at]; [HealthWeightWriteOk] on success.
  Future<HealthWriteResult> write(double kg, DateTime at);

  /// True when the plugin reports the sample deleted; false on any failure.
  Future<bool> delete(SavedWeight saved);
}

/// [HealthWeightWriter] over the `health` plugin. On Android the write goes
/// through `WeightWriter.kt` instead, because the plugin logs every written
/// value to logcat (ADR-0016). BeyondRep's own code logs no record ids, values
/// or exception text.
class PlatformHealthWeightWriter implements HealthWeightWriter {
  PlatformHealthWeightWriter(this._health, {bool? isIos, UuidFactory? ids})
    : isIos = isIos ?? defaultTargetPlatform == TargetPlatform.iOS,
      _ids = ids ?? SecureUuidFactory();

  final Health _health;
  final UuidFactory _ids;

  static const _androidWeight = MethodChannel('beyondrep/health_weight');

  @override
  final bool isIos;

  Future<void>? _configured;

  Future<void> _configure() async {
    try {
      await (_configured ??= _health.configure());
    } catch (_) {
      _configured = null;
      rethrow;
    }
  }

  @override
  Future<bool> requestAccess() async {
    try {
      await _configure();
      return await _health.requestAuthorization(
        [HealthDataType.WEIGHT],
        permissions: [HealthDataAccess.WRITE],
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (isIos) return true;
    try {
      await _configure();
      return await _health.getHealthConnectSdkStatus() ==
          HealthConnectSdkStatus.sdkAvailable;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasWriteAccess() async {
    try {
      if (!await isAvailable()) return false;
      await _configure();
      final granted = await _health.hasPermissions(
        [HealthDataType.WEIGHT],
        permissions: [HealthDataAccess.WRITE],
      );
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  HealthWriteResult _failure(Object error) {
    if (error is HealthException &&
        error.errorCode == HealthErrorCode.permissionDenied) {
      return const HealthWriteDenied();
    }
    if (error is UnsupportedError) return const HealthWriteUnavailable();
    return const HealthWriteFailed();
  }

  @override
  Future<HealthWriteResult> write(double kg, DateTime at) async {
    try {
      await _configure();
      if (!isIos &&
          await _health.getHealthConnectSdkStatus() !=
              HealthConnectSdkStatus.sdkAvailable) {
        return const HealthWriteUnavailable();
      }
      final clientRecordId = _ids.newId();
      if (!isIos) return await _writeAndroid(kg, at, clientRecordId);
      final id = await _health.writeHealthDataUUID(
        value: kg,
        unit: HealthDataUnit.KILOGRAM,
        type: HealthDataType.WEIGHT,
        startTime: at,
        endTime: at,
        recordingMethod: RecordingMethod.manual,
        clientRecordId: clientRecordId,
        clientRecordVersion: 1,
      );
      // The plugin turns native failures into an empty result, so only a
      // non-empty record id is a success.
      return (id == null || id.isEmpty || id == 'null')
          ? const HealthWriteFailed()
          : HealthWeightWriteOk(id, clientRecordId);
    } catch (e) {
      return _failure(e);
    }
  }

  /// One manual `WeightRecord` with client record id [clientRecordId] at
  /// version 1, written natively so no value reaches logcat.
  Future<HealthWriteResult> _writeAndroid(
    double kg,
    DateTime at,
    String clientRecordId,
  ) async {
    try {
      final id = await _androidWeight.invokeMethod<String>('write', {
        'clientRecordId': clientRecordId,
        'kg': kg,
        'atMs': at.millisecondsSinceEpoch,
        'offsetSeconds': at.timeZoneOffset.inSeconds,
      });
      return (id == null || id.isEmpty)
          ? const HealthWriteFailed()
          : HealthWeightWriteOk(id, clientRecordId);
    } on PlatformException catch (e) {
      return switch (e.code) {
        'permission_denied' => const HealthWriteDenied(),
        'unavailable' => const HealthWriteUnavailable(),
        _ => const HealthWriteFailed(),
      };
    } catch (_) {
      return const HealthWriteFailed();
    }
  }

  @override
  Future<bool> delete(SavedWeight saved) async {
    try {
      await _configure();
      return isIos
          ? await _health.deleteByUUID(
              uuid: saved.platformRecordId,
              type: HealthDataType.WEIGHT,
            )
          : await _health.deleteByClientRecordId(
              dataTypeKey: HealthDataType.WEIGHT,
              clientRecordId: saved.clientRecordId,
            );
    } catch (_) {
      return false;
    }
  }
}

final healthWeightWriterProvider = Provider<HealthWeightWriter>(
  (ref) => PlatformHealthWeightWriter(Health()),
);
