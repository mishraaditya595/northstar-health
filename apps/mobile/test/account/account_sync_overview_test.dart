import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/features/account/account_sync_overview.dart';
import 'package:northstar_health/features/workouts/data/objectbox_workout_outbox.dart';

void main() {
  test('unique workout flags count once per most severe state', () {
    final overview = AccountSyncOverview.fromState(
      flags: const {
        'w1': WorkoutSyncFlag.notSynced,
        'w2': WorkoutSyncFlag.needsReview,
        'w3': WorkoutSyncFlag.localOnly,
        'w4': WorkoutSyncFlag.needsReview,
      },
      blockedOperations: 3,
      restorePaused: true,
    );
    expect(overview.queued, 1);
    expect(overview.needsReview, 2);
    expect(overview.localOnly, 1);
    expect(overview.blockedOperations, 3);
    expect(overview.requiresReview, true);
    expect(overview.hasUnresolvedLocalChanges, true);
  });

  test('no flags does not imply verified cloud backup', () {
    final overview = AccountSyncOverview.fromState(
      flags: const {},
      blockedOperations: 0,
      restorePaused: false,
    );
    expect(overview.hasIssues, false);
    expect(overview.requiresReview, false);
  });

  test('blocked cursor needs review but is not an unsent local workout', () {
    final overview = AccountSyncOverview.fromState(
      flags: const {},
      blockedOperations: 0,
      restorePaused: true,
    );
    expect(overview.requiresReview, true);
    expect(overview.hasUnresolvedLocalChanges, false);
  });

  test('reject impossible negative operation counts', () {
    expect(
      () => AccountSyncOverview.fromState(
        flags: const {},
        blockedOperations: -1,
        restorePaused: false,
      ),
      throwsArgumentError,
    );
  });
}
