import 'package:flutter/material.dart';

import 'objectbox_workout_restore_importer.dart';
import 'workout_restore_feed.dart';

/// Shared, testable button visibility rules for reviewed conflict choices.
/// An unsent locally-invalid snapshot must never present blind upload retry.
class WorkoutReviewChoices extends StatelessWidget {
  const WorkoutReviewChoices({
    required this.candidate,
    required this.remote,
    required this.onSelect,
    super.key,
  });

  final WorkoutConflictCandidate candidate;
  final WorkoutRemoteReview remote;
  final ValueChanged<WorkoutResolutionAction> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: 8,
    runSpacing: 8,
    children: [
      if (remote.change != null &&
          (!candidate.deletedLocally || remote.change!.deleted))
        TextButton(
          onPressed: () => onSelect(WorkoutResolutionAction.useCloud),
          child: Text(
            remote.change!.deleted
                ? 'Accept permanent cloud deletion'
                : 'Use cloud copy',
          ),
        ),
      if (candidate.hasLocalWorkout &&
          !candidate.deletedLocally &&
          !candidate.canKeepLocalOnly &&
          remote.change?.deleted != true)
        TextButton(
          onPressed: () => onSelect(WorkoutResolutionAction.retryLocal),
          child: const Text('Retry this device'),
        ),
      if (candidate.hasLocalWorkout &&
          candidate.canKeepLocalOnly &&
          !candidate.deletedLocally &&
          remote.change == null)
        TextButton(
          onPressed: () => onSelect(WorkoutResolutionAction.keepLocalOnly),
          child: const Text('Keep on this device only'),
        ),
      if (candidate.deletedLocally)
        TextButton(
          onPressed: () => onSelect(WorkoutResolutionAction.finishDeletion),
          child: const Text('Complete deletion'),
        ),
    ],
  );
}

/// User-facing failure messages. Contract failures are NOT network errors.
String workoutReviewFailureMessage(Object error) {
  if (error is RestoreImportException) {
    return switch (error.code) {
      'resolution_invalid_snapshot' || 'resolution_cannot_upload' => 'This workout cannot be uploaded as saved. Keep it on this device or correct its data before syncing.',
      'resolution_upload_pending' => 'An earlier upload is still pending. Sync it before reviewing this workout again.',
      'resolution_stale_skip' ||
      'resolution_stale_server' ||
      'resolution_local_changed' => 'This workout changed while you were reviewing it. Open Review again for the latest version.',
      'resolution_epoch_changed' => 'The cloud restore version changed. Refresh your workout review before choosing.',
      'resolution_cannot_keep_local' => 'This workout might already exist in the cloud. It cannot be marked local-only safely.',
      'resolution_already_handled' =>
        'This workout no longer needs review. Refresh the list.',
      'account_changed' || 'owner_store_mismatch' => 'The signed-in account changed. Open your workouts from the current account.',
      'resolution_cloud_missing' =>
        'There is no cloud workout to restore. Refresh the review.',
      'local_tombstone_sticky' => 'A workout deleted on this device cannot be restored through conflict review.',
      'resolution_not_deleted' =>
        'This workout is not deleted locally. Refresh before choosing.',
      _ => 'This conflict could not be resolved safely. Your workout was not changed.',
    };
  }
  if (error is RestoreContractException) {
    return 'The cloud response was invalid. Your local workout is unchanged.';
  }
  return 'Could not verify the cloud workout. No changes were made; check your sign-in and connection.';
}
