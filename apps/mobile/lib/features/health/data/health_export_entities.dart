import 'package:objectbox/objectbox.dart';

/// Presence of a row means the account turned on saving phone workouts to the
/// health store. Lives only in the account-bound ObjectBox store; never synced.
@Entity()
class HealthExportSettingEntity {
  @Id()
  int id = 0;
  @Unique()
  String ownerAccountId;
  int enabledAtMs;

  HealthExportSettingEntity({
    this.id = 0,
    required this.ownerAccountId,
    required this.enabledAtMs,
  });
}

/// What this phone wrote to the health store for one BeyondRep workout.
/// Local only: platform ids never reach the outbox, Supabase, exports or logs.
@Entity()
class HealthExportReceiptEntity {
  @Id()
  int id = 0;

  /// Lowercase BeyondRep workout UUID.
  @Unique()
  String workoutUuid;

  /// `healthkit` or `health_connect`.
  String platform;

  /// A `HealthExportState` wire name.
  String state;

  /// The workout `updatedAtMs` last written; 0 when nothing was written.
  int exportedVersion;

  /// HKWorkout UUID on iOS, the client record id on Android.
  String? platformRecordId;

  int attempts;
  int lastAttemptAtMs;
  int updatedAtMs;

  HealthExportReceiptEntity({
    this.id = 0,
    required this.workoutUuid,
    required this.platform,
    required this.state,
    this.exportedVersion = 0,
    this.platformRecordId,
    this.attempts = 0,
    this.lastAttemptAtMs = 0,
    required this.updatedAtMs,
  });
}
