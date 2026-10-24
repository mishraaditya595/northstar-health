import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/objectbox_workout_history_repository.dart';
import 'domain/workout_history_models.dart';

/// Retained across tabs. Invalidated after a finish/discard or user refresh.
/// ObjectBox executes this read transaction in its own background isolate.
final completedWorkoutHistoryProvider = FutureProvider<WorkoutHistorySnapshot>(
  (ref) => ref.watch(workoutHistoryRepositoryProvider).readCompletedAsync(),
);

/// Injectable clock sampled once per Progress visit, not cached with the
/// completed history. Disposes after the last listener leaves the page.
final progressNowProvider = Provider.autoDispose<DateTime>(
  (ref) => DateTime.now().toUtc(),
);
