import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart' hide HealthValue;

/// One BeyondRep workout summary to save: name, start and end only. No heart
/// rate, calories, distance, sets or reps (ADR-0014).
class HealthWorkoutRecord {
  const HealthWorkoutRecord({
    required this.workoutUuid,
    required this.name,
    required this.start,
    required this.end,
    required this.offsetMinutes,
    required this.version,
  });

  /// Lowercase BeyondRep workout UUID; the platform id for idempotent rewrites.
  final String workoutUuid;
  final String name;
  final DateTime start;
  final DateTime end;
  final int offsetMinutes;

  /// Grows on every edit of the workout; a greater version replaces the entry.
  final int version;
}

sealed class HealthWriteResult {
  const HealthWriteResult();
}

class HealthWriteOk extends HealthWriteResult {
  const HealthWriteOk(this.platformRecordId);
  final String platformRecordId;
}

class HealthWriteDenied extends HealthWriteResult {
  const HealthWriteDenied();
}

class HealthWriteFailed extends HealthWriteResult {
  const HealthWriteFailed();
}

class HealthWriteUnavailable extends HealthWriteResult {
  const HealthWriteUnavailable();
}

/// A workout in the health store written by BeyondRep (phone or watch).
class OwnStoredWorkout {
  const OwnStoredWorkout({
    required this.platformRecordId,
    required this.sourceId,
    required this.start,
    required this.end,
  });
  final String platformRecordId;
  final String sourceId;
  final DateTime start;
  final DateTime end;
}

abstract interface class HealthWorkoutWriter {
  /// `healthkit` or `health_connect`.
  String get platform;
  bool get isIos;

  Future<bool> isAvailable();

  /// Shows the platform permission prompt for workout read and write.
  Future<bool> requestAccess();
  Future<bool> hasWriteAccess();
  Future<HealthWriteResult> write(HealthWorkoutRecord record);
  Future<HealthWriteResult> delete(
    String workoutUuid,
    String? platformRecordId,
  );

  /// Workouts from `in.beyondrep.app` or a child source (the watch app)
  /// overlapping the window; null when the read failed.
  Future<List<OwnStoredWorkout>?> beyondRepWorkoutsIn(
    DateTime start,
    DateTime end,
  );
}

const _ownAppId = 'in.beyondrep.app';

bool _isOwnSource(String source) =>
    source == _ownAppId || source.startsWith('$_ownAppId.');

/// [HealthWorkoutWriter] over the `health` plugin. BeyondRep's own code logs
/// no record ids, times or exception text; the plugin itself prints record
/// ids (no health values) to the device log.
class PlatformHealthWorkoutWriter implements HealthWorkoutWriter {
  PlatformHealthWorkoutWriter(this._health, {bool? isIos})
    : isIos = isIos ?? defaultTargetPlatform == TargetPlatform.iOS;

  final Health _health;

  @override
  final bool isIos;

  @override
  String get platform => isIos ? 'healthkit' : 'health_connect';

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
  Future<bool> requestAccess() async {
    try {
      await _configure();
      return await _health.requestAuthorization(
        [HealthDataType.WORKOUT],
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
        [HealthDataType.WORKOUT],
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
  Future<HealthWriteResult> write(HealthWorkoutRecord record) async {
    try {
      await _configure();
      final offset = Duration(minutes: record.offsetMinutes);
      final id = await _health.writeWorkoutDataUUID(
        activityType: isIos
            ? HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING
            : HealthWorkoutActivityType.STRENGTH_TRAINING,
        start: record.start,
        end: record.end,
        title: isIos ? null : record.name,
        metadata: isIos
            ? WorkoutMetadata(
                workoutBrandName: 'BeyondRep',
                indoorWorkout: true,
                syncIdentifier: record.workoutUuid,
                syncVersion: record.version,
              )
            : null,
        clientRecordId: isIos ? null : record.workoutUuid,
        clientRecordVersion: isIos ? null : record.version.toDouble(),
        startZoneOffset: isIos ? null : offset,
        endZoneOffset: isIos ? null : offset,
      );
      final returned = (id == null || id == 'null') ? '' : id;
      // The plugin turns every native failure into an empty result (Android
      // catches all exceptions), so only a non-empty record id is a success.
      return returned.isNotEmpty
          ? HealthWriteOk(returned)
          : const HealthWriteFailed();
    } catch (e) {
      return _failure(e);
    }
  }

  @override
  Future<HealthWriteResult> delete(
    String workoutUuid,
    String? platformRecordId,
  ) async {
    try {
      await _configure();
      final bool deleted;
      if (isIos) {
        if (platformRecordId == null || platformRecordId.isEmpty) {
          return const HealthWriteOk('');
        }
        deleted = await _health.deleteByUUID(
          uuid: platformRecordId,
          type: HealthDataType.WORKOUT,
        );
      } else {
        deleted = await _health.deleteByClientRecordId(
          dataTypeKey: HealthDataType.WORKOUT,
          clientRecordId: workoutUuid,
        );
      }
      // false is a failed delete (Android) or a failed or not-found delete
      // (iOS); the caller checks the store before treating it as gone.
      return deleted
          ? HealthWriteOk(platformRecordId ?? '')
          : const HealthWriteFailed();
    } catch (e) {
      return _failure(e);
    }
  }

  @override
  Future<List<OwnStoredWorkout>?> beyondRepWorkoutsIn(
    DateTime start,
    DateTime end,
  ) async {
    try {
      await _configure();
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: start,
        endTime: end,
      );
      return [
        for (final p in points)
          if (_isOwnSource(p.sourceId) || _isOwnSource(p.sourceName))
            OwnStoredWorkout(
              platformRecordId: p.uuid,
              sourceId: _isOwnSource(p.sourceId) ? p.sourceId : p.sourceName,
              start: p.dateFrom,
              end: p.dateTo,
            ),
      ];
    } catch (_) {
      return null;
    }
  }
}

final healthWorkoutWriterProvider = Provider<HealthWorkoutWriter>(
  (ref) => PlatformHealthWorkoutWriter(Health()),
);
