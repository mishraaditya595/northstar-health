import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../progress/domain/workout_history_models.dart';
import '../progress/workout_history_state.dart';
import '../workouts/domain/workout_models.dart';

/// Completed sets of [definitionUuid] from its most recent completed session,
/// in set order. Empty when the exercise has never been completed.
List<WorkoutSetRecord> previousSetsFor(
  WorkoutHistorySnapshot snapshot,
  String? definitionUuid,
) {
  if (definitionUuid == null) return const [];
  WorkoutSessionRecord? latest;
  WorkoutExerciseRecord? latestExercise;
  for (final session in snapshot.sessions) {
    final finished = session.completedAtUtc;
    if (finished == null) continue;
    final exercise = session.exercises
        .where((e) => e.definitionUuid == definitionUuid)
        .firstOrNull;
    if (exercise == null) continue;
    final hasCompleted = session.sets.any(
      (s) =>
          s.exerciseUuid == exercise.uuid &&
          s.status == WorkoutSetStatus.completed,
    );
    if (!hasCompleted) continue;
    if (latest == null || finished.isAfter(latest.completedAtUtc!)) {
      latest = session;
      latestExercise = exercise;
    }
  }
  if (latest == null) return const [];
  return latest.sets
      .where(
        (s) =>
            s.exerciseUuid == latestExercise!.uuid &&
            s.status == WorkoutSetStatus.completed,
      )
      .toList()
    ..sort((a, b) => a.position.compareTo(b.position));
}

/// Empty while history loads or fails, so the Previous column simply shows a
/// dash and never blocks logging.
final previousSetsProvider = Provider.family<List<WorkoutSetRecord>, String?>((
  ref,
  definitionUuid,
) {
  final history = ref.watch(completedWorkoutHistoryProvider).asData?.value;
  if (history == null) return const [];
  return previousSetsFor(history, definitionUuid);
});
