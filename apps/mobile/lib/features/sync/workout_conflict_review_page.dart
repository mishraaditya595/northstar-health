import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/page_header.dart';
import 'objectbox_workout_restore_importer.dart';
import 'workout_conflict_resolution.dart';

/// A deliberate, reviewed choice. No automatic last-write-wins policy.
class WorkoutConflictReviewPage extends ConsumerStatefulWidget {
  const WorkoutConflictReviewPage({super.key});

  @override
  ConsumerState<WorkoutConflictReviewPage> createState() =>
      _WorkoutConflictReviewPageState();
}

class _WorkoutConflictReviewPageState
    extends ConsumerState<WorkoutConflictReviewPage> {
  String? workingUuid;

  Future<void> _review(WorkoutConflictCandidate candidate) async {
    if (workingUuid != null) return;
    setState(() => workingUuid = candidate.workoutUuid);
    try {
      final service = ref.read(workoutConflictResolutionProvider);
      final remote = await service.review(candidate.workoutUuid);
      if (!mounted) return;
      final action = await showDialog<WorkoutResolutionAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resolve workout conflict'),
          content: SingleChildScrollView(
            child: Text(
              'This device: ${candidate.deletedLocally
                  ? 'deleted'
                  : candidate.hasLocalWorkout
                  ? 'completed workout'
                  : 'no local copy'}.\n'
              'Cloud: ${remote.change == null
                  ? 'no record'
                  : remote.change!.deleted
                  ? 'deleted'
                  : 'completed workout'}'
              '${remote.change == null ? '' : ' (revision ${remote.change!.serverRevision})'}.\n\n'
              'Choose explicitly. The latest cloud revision will be used '
              'for upload checks. A concurrent change may require another '
              'review. Never discard a pending network request.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            if (remote.change != null)
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext)
                        .pop(WorkoutResolutionAction.useCloud),
                child: Text(
                  remote.change!.deleted
                      ? 'Accept cloud deletion'
                      : 'Use cloud copy',
                ),
              ),
            if (candidate.hasLocalWorkout &&
                !candidate.deletedLocally &&
                remote.change?.deleted != true)
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext)
                        .pop(WorkoutResolutionAction.retryLocal),
                child: const Text('Retry this device'),
              ),
            if (candidate.deletedLocally)
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext)
                        .pop(WorkoutResolutionAction.finishDeletion),
                child: const Text('Complete deletion'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conflict reviewed. Any queued sync will retry.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not resolve this workout safely. '
            'Nothing was overwritten; retry after checking your connection.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => workingUuid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(workoutConflictCandidatesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync conflicts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const PageHeader(title: 'Workout review', eyebrow: 'MANUAL RECOVERY'),
          const SizedBox(height: 12),
          const Text(
            'Your workouts stay on this device until you choose how to '
            'resolve each disagreement. Checking the cloud requires an '
            'active sign-in and connection.',
          ),
          const SizedBox(height: 16),
          if (candidates.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No workouts currently need conflict review.'),
              ),
            ),
          for (final candidate in candidates)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      candidate.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      candidate.deletedLocally
                          ? 'Deleted here; remote deletion needs recovery'
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
      ),
    );
  }
}
