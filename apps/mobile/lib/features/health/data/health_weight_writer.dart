import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
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

  Future<bool> hasWriteAccess();

  /// Shows the platform permission prompt for weight read and write.
  Future<bool> requestAccess();

  /// Writes one manual weight sample at [at]; [HealthWeightWriteOk] on success.
  Future<HealthWriteResult> write(double kg, DateTime at);

  /// True when the plugin reports the sample deleted; false on any failure.
  Future<bool> delete(SavedWeight saved);
}

/// [HealthWeightWriter] over the `health` plugin. BeyondRep's own code logs no
/// record ids, values or exception text.
class PlatformHealthWeightWriter implements HealthWeightWriter {
  PlatformHealthWeightWriter(this._health, {bool? isIos, UuidFactory? ids})
    : isIos = isIos ?? defaultTargetPlatform == TargetPlatform.iOS,
      _ids = ids ?? SecureUuidFactory();

  final Health _health;
  final UuidFactory _ids;

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
        permissions: [HealthDataAccess.READ_WRITE],
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasWriteAccess() async {
    try {
      await _configure();
      // HealthKit reports write status truthfully but never read status.
      final granted = await _health.hasPermissions(
        [HealthDataType.WEIGHT],
        permissions: [
          isIos ? HealthDataAccess.WRITE : HealthDataAccess.READ_WRITE,
        ],
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
      final id = await _health.writeHealthDataUUID(
        value: kg,
        unit: HealthDataUnit.KILOGRAM,
        type: HealthDataType.WEIGHT,
        startTime: at,
        endTime: at,
        recordingMethod: RecordingMethod.manual,
        clientRecordId: clientRecordId,
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
