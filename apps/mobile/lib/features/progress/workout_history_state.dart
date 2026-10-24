import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/objectbox_workout_history_repository.dart';
import 'domain/workout_history_models.dart';

/// Explicit refresh on navigation / after workout completion.
/// No demo values, cloud state, or HealthKit values feed these projections.
final completedWorkoutHistoryProvider =
    Provider.autoDispose<AsyncValue<WorkoutHistorySnapshot>>((ref) {
  try {
    return AsyncData<WorkoutHistorySnapshot>(
      ref.watch(workoutHistoryRepositoryProvider).readCompleted(),
    );
  } catch (error, trace) {
    return AsyncError<WorkoutHistorySnapshot>(error, trace);
  }
});
