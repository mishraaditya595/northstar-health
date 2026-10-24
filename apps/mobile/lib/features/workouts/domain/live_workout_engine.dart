import 'workout_models.dart';

/// Crash-recoverable phone-only workout lifecycle. Commands mutate exactly
/// one local ObjectBox transaction and do not imply cloud backup.
abstract interface class LiveWorkoutEngine {
  /// Starts a quick empty workout or atomically copies a saved plan's exercises
  /// and planned sets. A repeated session UUID with identical start arguments
  /// returns the already committed session, never duplicate children.
  WorkoutSessionRecord startWorkout({
    required String sessionUuid,
    String? planUuid,
    String? quickName,
    required DateTime startedAtUtc,
    required int originalOffsetMinutes,
  });

  /// Returns an in-progress or paused session after fresh app startup.
  /// Unknown/ambiguous active states fail closed rather than being discarded.
  WorkoutSessionRecord? recoverActiveWorkout();

  WorkoutRecoveryCheckpoint? readCheckpoint(String sessionUuid);

  /// Starts a wall-clock rest countdown, independent of frame updates.
  /// Timer writes use checkpoint CAS so a delayed skip cannot cancel a
  /// newer timer. The session revision does not change for timer-only edits.
  WorkoutRecoveryCheckpoint startRestTimer(
    String sessionUuid, {
    required int expectedRevision,
    required int expectedCheckpointSavedAtMs,
    required int seconds,
  });

  WorkoutRecoveryCheckpoint clearRestTimer(
    String sessionUuid, {
    required int expectedRevision,
    required int expectedCheckpointSavedAtMs,
  });

  WorkoutSessionRecord pauseWorkout(
    String sessionUuid, {
    required int expectedRevision,
  });

  WorkoutSessionRecord resumeWorkout(
    String sessionUuid, {
    required int expectedRevision,
  });

  WorkoutSessionRecord finishWorkout(
    String sessionUuid, {
    required int expectedRevision,
    required DateTime finishedAtUtc,
  });

  /// Preserves a discarded session record for audit/reconciliation, but
  /// removes the active checkpoint. History UI must filter to completed only.
  WorkoutSessionRecord discardWorkout(
    String sessionUuid, {
    required int expectedRevision,
  });
}

class WorkoutRecoveryCheckpoint {
  const WorkoutRecoveryCheckpoint({
    required this.sessionUuid,
    required this.checkpointRevision,
    this.selectedExerciseUuid,
    this.selectedSetUuid,
    this.restState = 'idle',
    this.restDeadlineUtcMs,
    this.restRemainingMsWhenPaused,
    this.savedAtMs = 0,
  });

  final String restState;
  final int? restDeadlineUtcMs;
  final int? restRemainingMsWhenPaused;
  /// Monotonic checkpoint write token for timer-only compare-and-set.
  final int savedAtMs;
  final String sessionUuid;
  final int checkpointRevision;
  final String? selectedExerciseUuid;
  final String? selectedSetUuid;
}
