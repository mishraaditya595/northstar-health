import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_auth_provider.dart';
import '../progress/workout_history_state.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import 'objectbox_workout_restore_importer.dart';
import 'workout_restore_feed.dart';
import 'workout_restore_transport.dart';
import 'workout_upload_coordinator.dart';

/// User-driven only: no automated local/cloud winner and no write while HTTP
/// is pending. The importer owns the optimistic local transaction.
class WorkoutConflictResolutionService {
  WorkoutConflictResolutionService({
    required this.importer,
    required this.transport,
  });
  final ObjectBoxWorkoutRestoreImporter importer;
  final WorkoutConflictTransport transport;

  List<WorkoutConflictCandidate> get candidates =>
      importer.readConflictCandidates();

  WorkoutRestoreCursor get cursor => importer.readCursor();

  bool retryBlockedRestore(WorkoutRestoreCursor observed) =>
      importer.clearBlocked(
        afterSeq: observed.nextCursor,
        requestedEpoch: observed.epoch,
      );

  Future<WorkoutRemoteReview> review(String workoutUuid) =>
      transport.fetchWorkout(workoutUuid);

  void resolve({
    required WorkoutConflictCandidate candidate,
    required WorkoutRemoteReview remote,
    required WorkoutResolutionAction action,
  }) {
    importer.resolveReviewedWorkout(
      workoutUuid: candidate.workoutUuid,
      expectedLocalRevision: candidate.localRevision,
      review: remote,
      action: action,
    );
  }
}

final workoutConflictResolutionProvider =
    Provider<WorkoutConflictResolutionService>((ref) {
      final auth = ref.watch(accountAuthControllerProvider);
      final owner = auth?.userId;
      if (auth == null || owner == null) {
        throw StateError('Conflict review requires an authenticated account');
      }
      return WorkoutConflictResolutionService(
        importer: ref.watch(workoutRestoreImporterProvider)(
          owner,
          () => auth.userId,
        ),
        transport: ref.watch(workoutConflictTransportProvider)(owner),
      );
    });

/// Standalone UI and isolated widget tests have no native Store. The
/// authenticated account scope overrides this with its bound importer.
final workoutRestoreCursorProvider = Provider<WorkoutRestoreCursor?>(
  (ref) => null,
);

final workoutRestoreBlockedCodeProvider = Provider<String?>(
  (ref) => ref.watch(workoutRestoreCursorProvider)?.blockedCode,
);

final workoutConflictCandidatesProvider =
    Provider<List<WorkoutConflictCandidate>>(
      (ref) => ref.watch(workoutConflictResolutionProvider).candidates,
    );

void refreshResolvedWorkout(WidgetRef ref, {required bool uploadQueued}) {
  ref.invalidate(workoutConflictCandidatesProvider);
  ref.invalidate(workoutRestoreCursorProvider);
  ref.invalidate(workoutRestoreBlockedCodeProvider);
  ref.invalidate(completedWorkoutHistoryProvider);
  ref.invalidate(workoutSyncFlagsProvider);
  ref.invalidate(blockedWorkoutCountProvider);
  if (uploadQueued) {
    ref.read(workoutUploadCoordinatorProvider).kick();
  }
}
