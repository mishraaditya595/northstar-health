import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_health/core/design/northstar_theme.dart';
import 'package:northstar_health/features/account/account_auth_provider.dart';
import 'package:northstar_health/features/sync/objectbox_workout_restore_importer.dart';
import 'package:northstar_health/features/sync/workout_conflict_resolution.dart';
import 'package:northstar_health/features/sync/workout_conflict_review_page.dart';
import 'package:northstar_health/features/sync/workout_restore_feed.dart';
import 'package:northstar_health/features/sync/workout_review_choices.dart';

import '../support/fake_account_auth.dart';

const workout = '00000000-0000-4000-8000-000000006701';
const epoch = '00000000-0000-4000-8000-000000006702';

WorkoutConflictCandidate candidate({
  bool localOnly = false,
  bool deleted = false,
  bool orphaned = false,
  bool skippedDeletion = false,
}) => WorkoutConflictCandidate(
  workoutUuid: workout,
  name: deleted ? 'Deleted workout' : 'Row',
  localRevision: 1,
  deletedLocally: deleted,
  hasLocalWorkout: !orphaned,
  exerciseCount: deleted ? 0 : 1,
  setCount: deleted ? 0 : 2,
  canKeepLocalOnly: localOnly,
  canDismissMissing: orphaned,
  skippedDeletion: skippedDeletion,
);

WorkoutRemoteReview review({bool present = false, bool deleted = false}) =>
    WorkoutRemoteReview(
      cursorEpoch: epoch,
      change: !present
          ? null
          : RemoteWorkoutChange(
              workoutId: workout,
              serverRevision: 2,
              changeSeq: 3,
              deleted: deleted,
              snapshot: deleted
                  ? null
                  : RemoteWorkoutSnapshot(
                      uuid: workout,
                      name: 'Cloud row',
                      startedAtUtc: DateTime.utc(2026, 10, 20),
                      completedAtUtc: DateTime.utc(2026, 10, 20, 1),
                      originalOffsetMinutes: 330,
                      exercises: const [],
                      sets: const [],
                    ),
            ),
    );

void main() {
  Future<List<WorkoutResolutionAction>> showChoices(
    WidgetTester tester, {
    required WorkoutConflictCandidate local,
    required WorkoutRemoteReview cloud,
  }) async {
    final picked = <WorkoutResolutionAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutReviewChoices(
            candidate: local,
            remote: cloud,
            onSelect: picked.add,
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('never-sent blocked workout offers local-only, not retry', (
    tester,
  ) async {
    final picked = await showChoices(
      tester,
      local: candidate(localOnly: true),
      cloud: review(),
    );
    expect(find.text('Keep on this device only'), findsOneWidget);
    expect(find.text('Retry this device'), findsNothing);
    expect(find.text('Use cloud copy'), findsNothing);
    await tester.tap(find.text('Keep on this device only'));
    expect(picked, [WorkoutResolutionAction.keepLocalOnly]);
  });

  testWidgets('skipped cloud deletion warns before reuploading a missing row', (
    tester,
  ) async {
    final local = candidate(skippedDeletion: true);
    final missing = review();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              WorkoutReviewDeletionHint(candidate: local, remote: missing),
              WorkoutReviewChoices(
                candidate: local,
                remote: missing,
                onSelect: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.textContaining('previously deleted in the cloud'),
      findsOneWidget,
    );
    expect(find.text('Retry this device'), findsOneWidget);
  });

  testWidgets('deletion hint hidden if no skipped tombstone or cloud exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              WorkoutReviewDeletionHint(
                candidate: candidate(),
                remote: review(),
              ),
              WorkoutReviewDeletionHint(
                candidate: candidate(skippedDeletion: true),
                remote: review(present: true),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.textContaining('previously deleted in the cloud'),
      findsNothing,
    );
  });

  testWidgets('review with live cloud copy offers explicit winner', (
    tester,
  ) async {
    await showChoices(tester, local: candidate(), cloud: review(present: true));
    expect(find.text('Use cloud copy'), findsOneWidget);
    expect(find.text('Retry this device'), findsOneWidget);
    expect(find.text('Keep on this device only'), findsNothing);
  });

  testWidgets('cloud deletion is permanent and cannot be retried locally', (
    tester,
  ) async {
    await showChoices(
      tester,
      local: candidate(),
      cloud: review(present: true, deleted: true),
    );
    expect(find.text('Accept permanent cloud deletion'), findsOneWidget);
    expect(find.text('Retry this device'), findsNothing);
  });

  testWidgets('local tombstone never offers cloud resurrection', (
    tester,
  ) async {
    await showChoices(
      tester,
      local: candidate(deleted: true),
      cloud: review(present: true),
    );
    expect(find.text('Use cloud copy'), findsNothing);
    expect(find.text('Complete deletion'), findsOneWidget);
  });

  testWidgets('orphaned skipped workout can be dismissed after lookup', (
    tester,
  ) async {
    final picked = await showChoices(
      tester,
      local: candidate(orphaned: true),
      cloud: review(),
    );
    expect(find.text('Dismiss unavailable workout'), findsOneWidget);
    expect(find.text('Retry this device'), findsNothing);
    expect(find.text('Keep on this device only'), findsNothing);
    await tester.tap(find.text('Dismiss unavailable workout'));
    expect(picked, [WorkoutResolutionAction.dismissMissing]);
  });

  testWidgets('orphan dismissal disappears when cloud workout is present', (
    tester,
  ) async {
    await showChoices(
      tester,
      local: candidate(orphaned: true),
      cloud: review(present: true),
    );
    expect(find.text('Dismiss unavailable workout'), findsNothing);
    expect(find.text('Use cloud copy'), findsOneWidget);
  });

  test('contract failures have actionable explanations', () {
    expect(
      workoutReviewFailureMessage(
        const RestoreImportException('resolution_upload_pending'),
      ),
      contains('pending'),
    );
    expect(
      workoutReviewFailureMessage(
        const RestoreImportException('resolution_stale_skip'),
      ),
      contains('changed'),
    );
    expect(
      workoutReviewFailureMessage(
        const RestoreImportException('resolution_invalid_snapshot'),
      ),
      contains('cannot be uploaded'),
    );
    expect(
      workoutReviewFailureMessage(
        const RestoreImportException('resolution_epoch_changed'),
      ),
      contains('restore version'),
    );
  });

  testWidgets('review page survives sign-out without reading account store', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutConflictCandidatesProvider.overrideWithValue(const []),
          workoutRestoreCursorProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const WorkoutConflictReviewPage(),
        ),
      ),
    );
    expect(
      find.text('No workouts currently need conflict review.'),
      findsOneWidget,
    );
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.textContaining('Signed out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review page exposes blocked restore and no false clear', (
    tester,
  ) async {
    final api = FakeAuthApi()..sessionId = accountA;
    final bound = FakeBoundAccountStore()..saved = accountA;
    final auth = controller(api, bound);
    addTearDown(auth.dispose);
    addTearDown(api.dispose);
    await auth.restore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountAuthControllerProvider.overrideWithValue(auth),
          workoutConflictCandidatesProvider.overrideWithValue(const []),
          workoutRestoreCursorProvider.overrideWithValue(
            const WorkoutRestoreCursor(
              epoch: epoch,
              nextCursor: 3,
              blockedCode: 'duplicate_remote_sequence',
            ),
          ),
        ],
        child: MaterialApp(
          theme: NorthstarTheme.build(Brightness.light),
          home: const WorkoutConflictReviewPage(),
        ),
      ),
    );
    expect(find.text('Cloud restore paused'), findsOneWidget);
    expect(find.text('Retry restore'), findsOneWidget);
  });
}
