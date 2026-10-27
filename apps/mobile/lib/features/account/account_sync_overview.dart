import '../workouts/data/objectbox_workout_outbox.dart';

/// Device-local sync *issues*, not a server-confirmed inventory. A workout
/// appears once in the highest-priority state from the durable outbox/skip.
class AccountSyncOverview {
  const AccountSyncOverview({
    required this.queued,
    required this.needsReview,
    required this.localOnly,
    required this.blockedOperations,
    required this.restorePaused,
  });

  factory AccountSyncOverview.fromState({
    required Map<String, WorkoutSyncFlag> flags,
    required int blockedOperations,
    required bool restorePaused,
  }) {
    if (blockedOperations < 0) throw ArgumentError.value(blockedOperations);
    return AccountSyncOverview(
      queued: flags.values.where((f) => f == WorkoutSyncFlag.notSynced).length,
      needsReview:
          flags.values.where((f) => f == WorkoutSyncFlag.needsReview).length,
      localOnly: flags.values.where((f) => f == WorkoutSyncFlag.localOnly).length,
      blockedOperations: blockedOperations,
      restorePaused: restorePaused,
    );
  }

  final int queued;
  final int needsReview;
  final int localOnly;

  /// Count of terminal blocked outbox operations, not distinct workouts.
  final int blockedOperations;
  final bool restorePaused;

  bool get requiresReview =>
      needsReview > 0 || localOnly > 0 || blockedOperations > 0 || restorePaused;
  bool get hasIssues => requiresReview || queued > 0;
  bool get hasUnresolvedLocalChanges =>
      queued > 0 || needsReview > 0 || localOnly > 0 || blockedOperations > 0;
}
