import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/dialogs.dart';
import '../../core/design/page_header.dart';
import '../account/account_auth_provider.dart';
import '../workouts/data/objectbox_workout_outbox.dart';
import 'objectbox_workout_restore_importer.dart';
import 'workout_conflict_resolution.dart';
import 'workout_review_choices.dart';
import 'workout_upload_coordinator.dart';

/// Explicit conflict review. Pending or stale cloud work is never discarded.
class WorkoutConflictReviewPage extends ConsumerStatefulWidget {
  const WorkoutConflictReviewPage({super.key});

  @override
  ConsumerState<WorkoutConflictReviewPage> createState() =>
      _WorkoutConflictReviewPageState();
}

class _WorkoutConflictReviewPageState
    extends ConsumerState<WorkoutConflictReviewPage> {
  String? workingUuid;
  bool retryingRestore = false;

  Future<void> _review(WorkoutConflictCandidate candidate) async {
    if (workingUuid != null) return;
    setState(() => workingUuid = candidate.workoutUuid);
    try {
      final service = ref.read(workoutConflictResolutionProvider);
      final remote = await service.review(candidate.workoutUuid);
      if (!mounted) return;
      final localSummary = candidate.deletedLocally
          ? 'deleted'
          : candidate.hasLocalWorkout
          ? '${candidate.name} (${candidate.exerciseCount} exercises, ${candidate.setCount} sets)'
          : 'no local copy';
      final cloudSnapshot = remote.change?.snapshot;
      final cloudSummary = remote.change == null
          ? 'no cloud record'
          : remote.change!.deleted
          ? 'deleted (revision ${remote.change!.serverRevision})'
          : '${cloudSnapshot!.name} (${cloudSnapshot.exercises.length} exercises, ${cloudSnapshot.sets.length} sets, revision ${remote.change!.serverRevision})';
      final action = await showNsDialog<WorkoutResolutionAction>(
        context: context,
        builder: (dialogContext) => NsDialog(
          title: 'Resolve workout conflict',
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This device: $localSummary.\n'
                  'Cloud: $cloudSummary.\n\n'
                  'Choose which copy to keep. Accepting cloud deletion '
                  'permanently removes the local workout and its sets. '
                  'If another device changes this workout during review, '
                  'you may need to review it again.',
                ),
                WorkoutReviewDeletionHint(candidate: candidate, remote: remote),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            WorkoutReviewChoices(
              candidate: candidate,
              remote: remote,
              onSelect: (choice) => Navigator.of(dialogContext).pop(choice),
            ),
          ],
        ),
      );
      if (!mounted || action == null) return;
      service.resolve(candidate: candidate, remote: remote, action: action);
      refreshResolvedWorkout(
        ref,
        uploadQueued:
            action == WorkoutResolutionAction.retryLocal ||
            (action == WorkoutResolutionAction.finishDeletion &&
                remote.change != null &&
                !remote.change!.deleted),
      );
      if (!mounted) return;
      showNsMessage(
        context,
        action == WorkoutResolutionAction.keepLocalOnly
            ? 'Workout kept on this device only. No cloud upload queued.'
            : action == WorkoutResolutionAction.dismissMissing
            ? 'Unavailable cloud change dismissed. No workouts were deleted.'
            : 'Conflict reviewed. Any queued sync will retry.',
      );
    } catch (error) {
      if (!mounted) return;
      showNsMessage(context, workoutReviewFailureMessage(error));
    } finally {
      if (mounted) setState(() => workingUuid = null);
    }
  }

  Future<void> _retryRestore(WorkoutRestoreCursor cursor) async {
    if (retryingRestore || workingUuid != null) return;
    final confirmed = await showNsConfirm(
      context,
      title: 'Retry cloud restore?',
      message:
          'The last restore stopped because its data could not be safely '
          'reconciled. This retries the same position without skipping '
          'workouts. If the issue still exists, restore will pause again. '
          'Your local workouts will be kept.',
      confirmLabel: 'Retry restore',
    );
    if (!confirmed || !mounted) return;
    setState(() => retryingRestore = true);
    try {
      final service = ref.read(workoutConflictResolutionProvider);
      if (!service.retryBlockedRestore(cursor)) {
        throw const RestoreImportException('resolution_local_changed');
      }
      ref.invalidate(workoutRestoreBlockedCodeProvider);
      ref.invalidate(workoutConflictCandidatesProvider);
      ref.read(workoutUploadKickProvider)?.call();
      if (!mounted) return;
      showNsMessage(context, 'Restore retry requested at the saved position.');
    } catch (error) {
      if (!mounted) return;
      showNsMessage(context, workoutReviewFailureMessage(error));
    } finally {
      if (mounted) setState(() => retryingRestore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(accountAuthControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync conflicts')),
      body: auth == null
          ? const Center(child: Text('Sign in to review workout conflicts.'))
          : ListenableBuilder(
              listenable: auth,
              builder: (context, _) => auth.userId == null
                  ? const Center(
                      child: Text(
                        'Signed out. Sign in to review your workouts.',
                      ),
                    )
                  : Consumer(
                      builder: (context, ref, _) {
                        // Refresh candidates whenever the foreground worker
                        // reports a change; the explicit refresh button covers
                        // statuses changed while the page remains open.
                        ref.listen(workoutSyncFlagsProvider, (_, _) {
                          ref.invalidate(workoutConflictCandidatesProvider);
                        });
                        ref.listen(blockedWorkoutCountProvider, (_, _) {
                          ref.invalidate(workoutConflictCandidatesProvider);
                        });
                        final candidates = ref.watch(
                          workoutConflictCandidatesProvider,
                        );
                        final cursor = ref.watch(workoutRestoreCursorProvider);
                        final block = cursor?.blockedCode;
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            const PageHeader(
                              title: 'Workout review',
                              eyebrow: 'MANUAL RECOVERY',
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Your workouts stay on this device until you choose '
                              'how to resolve each disagreement. Cloud review '
                              'requires an active sign-in and connection.',
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  ref.invalidate(
                                    workoutConflictCandidatesProvider,
                                  );
                                  ref.invalidate(
                                    workoutRestoreBlockedCodeProvider,
                                  );
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Refresh status'),
                              ),
                            ),
                            if (block != null && cursor != null)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Cloud restore paused',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'A cloud change could not be safely '
                                        'reconciled. Local workouts are intact. '
                                        'Review conflicts below, or explicitly '
                                        'retry the saved restore position.',
                                      ),
                                      const SizedBox(height: 8),
                                      OutlinedButton(
                                        onPressed: retryingRestore
                                            ? null
                                            : () => _retryRestore(cursor),
                                        child: const Text('Retry restore'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            if (candidates.isEmpty)
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(18),
                                  child: Text(
                                    'No workouts currently need conflict review.',
                                  ),
                                ),
                              ),
                            for (final candidate in candidates)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        candidate.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        candidate.deletedLocally
                                            ? 'Deleted here; cloud deletion needs review'
                                            : candidate.canKeepLocalOnly
                                            ? 'Could not be backed up. Keep it on this device.'
                                            : candidate.hasLocalWorkout
                                            ? 'Local copy protected until review'
                                            : 'Remote change was skipped',
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: OutlinedButton(
                                          onPressed: workingUuid == null
                                              ? () => _review(candidate)
                                              : null,
                                          child: Text(
                                            workingUuid == candidate.workoutUuid
                                                ? 'Checking…'
                                                : 'Review',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
    );
  }
}
