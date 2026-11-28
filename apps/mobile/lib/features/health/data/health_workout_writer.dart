import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart' hide HealthValue;

/// One minute of a watch workout: the average heart rate of the minute that
/// starts at [at]. Held in memory for the write only.
class HeartRateMinute {
  const HeartRateMinute({required this.at, required this.bpm});

  final DateTime at;
  final int bpm;
}

/// One BeyondRep workout summary to save: name, start and end. A phone
/// workout carries nothing else: no heart rate, calories, distance, sets or
/// reps (ADR-0014). A watch workout on Android (Wear OS stage 3b, ADR-0015)
/// also carries its total calories and per-minute heart rate, which live only
/// in memory during the write.
class HealthWorkoutRecord {
  const HealthWorkoutRecord({
    required this.workoutUuid,
    required this.name,
    required this.start,
    required this.end,
    required this.offsetMinutes,
    required this.version,
    this.totalKcal,
    this.heartRate = const [],
  });

  /// Lowercase BeyondRep workout UUID; the platform id for idempotent rewrites.
  final String workoutUuid;
  final String name;
  final DateTime start;
  final DateTime end;
  final int offsetMinutes;

  /// Grows on every edit of the workout; a greater version replaces the entry.
  final int version;

  /// Total calories of a watch workout; null when the watch measured none.
  final double? totalKcal;

  /// One average per minute, oldest first; empty for a phone workout.
  final List<HeartRateMinute> heartRate;
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

  /// Shows the platform permission prompt for workout read and write. With
  /// [watchHealth] (Android) it also asks to write heart rate and total
  /// calories, which only a watch workout needs.
  Future<bool> requestAccess({bool watchHealth = false});
  Future<bool> hasWriteAccess();

  /// Android: exercise, heart rate and total calories write are all granted.
  /// False on iOS, where the Apple Watch saves its own workout.
  Future<bool> hasWatchHealthWriteAccess();
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
  Future<bool> requestAccess({bool watchHealth = false}) async {
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

  @override
  Future<bool> hasWatchHealthWriteAccess() async => false;

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
